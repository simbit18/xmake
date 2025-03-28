--!A cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Copyright (C) 2015-present, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        target_utils.lua
--

-- imports
import("core.base.option")
import("core.base.hashset")
import("core.project.rule")
import("core.project.config")
import("core.project.project")
import("async.runjobs", {alias = "async_runjobs"})
import("async.jobgraph", {alias = "async_jobgraph"})
import("private.utils.batchcmds")
import("builtin.prepare_files")

-- get rule
-- @note we need to get rule from target first, because we maybe will inject and replace builtin rule in target
function _get_rule(target, rulename)
    local ruleinst = assert(target:rule(rulename) or project.rule(rulename, {namespace = target:namespace()}) or
        rule.rule(rulename), "unknown rule: %s", rulename)
    return ruleinst
end

-- clean target for rebuilding
function _clean_target(target)
    if target:targetfile() then
        os.tryrm(target:symbolfile())
        os.tryrm(target:targetfile())
    end
end

-- add target jobs for the builtin script
function _add_targetjobs_for_builtin_script(jobgraph, target, job_kind)
    if target:is_static() or target:is_binary() or target:is_shared() or target:is_object() or target:is_moduleonly() then
        if job_kind == "prepare" then
            prepare_files(jobgraph, target)
        else
            local script = import("builtin.build_" .. target:kind(), {anonymous = true})
            if script then
                script(jobgraph, target)
            end
        end
    end
end

-- add target jobs for the given script
function _add_targetjobs_for_script(jobgraph, instance, opt)
    opt = opt or {}
    local has_script = false
    local script_name = opt.script_name
    local script = instance:script(script_name)
    if script then
        -- call custom script with jobgraph
        -- e.g.
        --
        -- target("test")
        --     on_build(function (target, jobgraph, opt)
        --     end, {jobgraph = true})
        if instance:extraconf(script_name, "jobgraph") then
            script(target, jobgraph)
        elseif instance:extraconf(script_name, "batch") then
            wprint("%s.%s: the batch mode is deprecated, please use jobgraph mode instead of it, or disable `build.jobgraph` policy to use it.", instance:fullname(), script_name)
        else
            -- call custom script directly
            -- e.g.
            --
            -- target("test")
            --     on_build(function (target, opt)
            --     end)
            local jobname = string.format("%s/%s/%s", instance == target and "target" or "rule", instance:fullname(), script_name)
            jobgraph:add(jobname, function (index, total, opt)
                script(target, {progress = opt.progress})
            end)
        end
        has_script = true
    else
        -- call command script
        -- e.g.
        --
        -- target("test")
        --     on_buildcmd(function (target, batchcmds, opt)
        --     end)
        local scriptcmd_name = opt.scriptcmd_name
        local scriptcmd = instance:script(scriptcmd_name)
        if scriptcmd then
            local jobname = string.format("%s/%s/%s", instance == target and "target" or "rule", instance:fullname(), scriptcmd_name)
            jobgraph:add(jobname, function (index, total, opt)
                local batchcmds_ = batchcmds.new({target = target})
                scriptcmd(target, batchcmds_, {progress = opt.progress})
                batchcmds_:runcmds({changed = target:is_rebuilt(), dryrun = option.get("dry-run")})
            end)
            has_script = true
        end
    end
    return has_script
end

-- add target jobs with the given stage
-- stage: before, after or ""
function _add_targetjobs_with_stage(jobgraph, target, stage, opt)
    opt = opt or {}
    local job_kind = opt.job_kind

    -- the group name, e.g. foo/after_prepare, bar/before_build
    local group_name = string.format("%s/%s_%s", target:fullname(), stage, job_kind)

    -- the script name, e.g. before/after_prepare, before/after_build
    local script_name = stage ~= "" and (job_kind .. "_" .. stage) or job_kind

    -- the command script name, e.g. before/after_preparecmd, before/after_buildcmd
    local scriptcmd_name = stage ~= "" and (job_kind .. "cmd_" .. stage) or (job_kind .. "cmd")

    -- TODO sort rules and jobs
    local instances = {target}
    for _, r in ipairs(target:orderules()) do
        table.insert(instances, r)
    end

    -- call target and rules script
    local jobsize = jobgraph:size()
    jobgraph:group(group_name, function ()
        local has_script = false
        local script_opt = {
            script_name = script_name,
            scriptcmd_name = scriptcmd_name
        }
        for _, instance in ipairs(instances) do
            if _add_targetjobs_for_script(jobgraph, instance, script_opt) then
                has_script = true
            end
        end

        -- call builtin script, e.g. on_prepare, on_build, ...
        if not has_script and stage == "" then
            _add_targetjobs_for_builtin_script(jobgraph, target, job_kind)
        end
    end)

    if jobgraph:size() > jobsize then
        return group_name
    end
end

-- add target jobs for the given target
function _add_targetjobs(jobgraph, target, opt)
    opt = opt or {}
    if not target:is_enabled() then
        return
    end

    local pkgenvs = _g.pkgenvs
    if pkgenvs == nil then
        pkgenvs = {}
        _g.pkgenvs = pkgenvs
    end

    local job_kind = opt.job_kind
    local job_begin = string.format("target/%s/begin_%s", target:fullname(), job_kind)
    local job_end = string.format("target/%s/end_%s", target:fullname(), job_kind)
    jobgraph:add(job_begin, function (index, total, opt)
        -- enter package environments
        -- https://github.com/xmake-io/xmake/issues/4033
        --
        -- maybe mixing envs isn't a great solution,
        -- but it's the most efficient compromise compared to setting envs in every on_build_file.
        --
        if target:pkgenvs() then
            pkgenvs.oldenvs = pkgenvs.oldenvs or os.getenvs()
            pkgenvs.newenvs = pkgenvs.newenvs or {}
            pkgenvs.newenvs[target] = target:pkgenvs()
            local newenvs = pkgenvs.oldenvs
            for _, envs in pairs(pkgenvs.newenvs) do
                newenvs = os.joinenvs(envs, newenvs)
            end
            os.setenvs(newenvs)
        end

        -- clean target first if rebuild
        if job_kind == "prepare" and target:is_rebuilt() and not option.get("dry-run") then
            _clean_target(target)
        end
    end)

    jobgraph:add(job_end, function (index, total, opt)
        -- restore environments
        if target:pkgenvs() then
            pkgenvs.oldenvs = pkgenvs.oldenvs or os.getenvs()
            pkgenvs.newenvs = pkgenvs.newenvs or {}
            pkgenvs.newenvs[target] = nil
            local newenvs = pkgenvs.oldenvs
            for _, envs in pairs(pkgenvs.newenvs) do
                newenvs = os.joinenvs(envs, newenvs)
            end
            os.setenvs(newenvs)
        end
    end)

    -- add jobs with target stage, e.g. begin -> before_xxx -> on_xxx -> after_xxx
    local group        = _add_targetjobs_with_stage(jobgraph, target, "", opt)
    local group_before = _add_targetjobs_with_stage(jobgraph, target, "before", opt)
    local group_after  = _add_targetjobs_with_stage(jobgraph, target, "after", opt)
    jobgraph:add_orders(job_begin, group_before, group, group_after, job_end)
end

-- add target jobs for the given target and deps
function _add_targetjobs_and_deps(jobgraph, target, targetrefs, opt)
    local targetname = target:fullname()
    if not targetrefs[targetname] then
        targetrefs[targetname] = target
        _add_targetjobs(jobgraph, target, opt)
        for _, depname in ipairs(target:get("deps")) do
            local dep = project.target(depname, {namespace = target:namespace()})
            _add_targetjobs_and_deps(jobgraph, dep, targetrefs, opt)
        end
    end
end

-- get target jobs
function _get_targetjobs(targets_root, opt)
    local jobgraph = async_jobgraph.new()
    local targetrefs = {}
    for _, target in ipairs(targets_root) do
        _add_targetjobs_and_deps(jobgraph, target, targetrefs, opt)
    end
    return jobgraph
end

-- match source files
function _match_sourcefiles(sourcefile, filepatterns)
    for _, filepattern in ipairs(filepatterns) do
        if sourcefile:match(filepattern.pattern) == sourcefile then
            if filepattern.excludes then
                if filepattern.rootdir and sourcefile:startswith(filepattern.rootdir) then
                    sourcefile = sourcefile:sub(#filepattern.rootdir + 2)
                end
                for _, exclude in ipairs(filepattern.excludes) do
                    if sourcefile:match(exclude) == sourcefile then
                        return false
                    end
                end
            end
            return true
        end
    end
end

-- match sourcebatches
function _match_sourcebatches(target, filepatterns)
    local newbatches = {}
    local sourcecount = 0
    for rulename, sourcebatch in pairs(target:sourcebatches()) do
        local objectfiles = sourcebatch.objectfiles
        local dependfiles = sourcebatch.dependfiles
        local sourcekind  = sourcebatch.sourcekind
        for idx, sourcefile in ipairs(sourcebatch.sourcefiles) do
            if _match_sourcefiles(sourcefile, filepatterns) then
                local newbatch = newbatches[rulename]
                if not newbatch then
                    newbatch             = {}
                    newbatch.sourcekind  = sourcekind
                    newbatch.rulename    = rulename
                    newbatch.sourcefiles = {}
                end
                table.insert(newbatch.sourcefiles, sourcefile)
                if objectfiles then
                    newbatch.objectfiles = newbatch.objectfiles or {}
                    table.insert(newbatch.objectfiles, objectfiles[idx])
                end
                if dependfiles then
                    newbatch.dependfiles = newbatch.dependfiles or {}
                    table.insert(newbatch.dependfiles, dependfiles[idx])
                end
                newbatches[rulename] = newbatch
                sourcecount = sourcecount + 1
            end
        end
    end
    if sourcecount > 0 then
        return newbatches
    end
end

-- add file jobs for the builtin script
function _add_filejobs_for_builtin_script(jobgraph, target, sourcebatch, job_kind)
end

-- add file jobs for the given script, TODO on single file
function _add_filejobs_for_script(jobgraph, instance, sourcebatch, opt)
    opt = opt or {}
    local has_script = false
    local script_file_name = opt.script_file_name
    local script_files_name = opt.script_files_name
    local script = instance:script(script_files_name)
    if script then
        -- call custom script with jobgraph
        -- e.g.
        --
        -- target("test")
        --     on_build_files(function (target, jobgraph, sourcebatch, opt)
        --     end, {jobgraph = true})
        if instance:extraconf(script_files_name, "jobgraph") then
            script(target, jobgraph, sourcebatch)
        elseif instance:extraconf(script_files_name, "batch") then
            wprint("%s.%s: the batch mode is deprecated, please use jobgraph mode instead of it, or disable `build.jobgraph` policy to use it.",
                instance:fullname(), script_files_name)
        else
            -- call custom script directly
            -- e.g.
            --
            -- target("test")
            --     on_build_files(function (target, sourcebatch, opt)
            --     end)
            local jobname = string.format("%s/%s/%s", instance == target and "target" or "rule", instance:fullname(), script_files_name)
            jobgraph:add(jobname, function (index, total, opt)
                script(target, sourcebatch, {progress = opt.progress})
            end)
        end
        has_script = true
    else
        -- call command script
        -- e.g.
        --
        -- target("test")
        --     on_buildcmd(function (target, batchcmds, sourcebatch, opt)
        --     end)
        local scriptcmd_file_name = opt.scriptcmd_file_name
        local scriptcmd_files_name = opt.scriptcmd_files_name
        local scriptcmd = instance:script(scriptcmd_files_name)
        if scriptcmd then
            local jobname = string.format("%s/%s/%s", instance == target and "target" or "rule", instance:fullname(), scriptcmd_files_name)
            jobgraph:add(jobname, function (index, total, opt)
                local batchcmds_ = batchcmds.new({target = target})
                scriptcmd(target, batchcmds_, sourcebatch, {progress = opt.progress})
                batchcmds_:runcmds({changed = target:is_rebuilt(), dryrun = option.get("dry-run")})
            end)
            has_script = true
        end
    end
    return has_script
end

-- add file jobs with the given stage
-- stage: before, after or ""
--
function _add_filejobs_with_stage(jobgraph, target, sourcebatches, stage, opt)
    opt = opt or {}
    local job_kind = opt.job_kind
    local job_kind_file = job_kind .. "_file"
    local job_kind_files = job_kind .. "_files"

    -- the group name, e.g. foo/after_prepare_files, bar/before_build_files
    local group_name = string.format("%s/%s_%s_files", target:fullname(), stage, job_kind)

    -- the script name, e.g. before/after_prepare_files, before/after_build_files
    local script_file_name = stage ~= "" and (job_kind_file .. "_" .. stage) or job_kind_file
    local script_files_name = stage ~= "" and (job_kind_files .. "_" .. stage) or job_kind_files

    -- the command script name, e.g. before/after_preparecmd_files, before/after_buildcmd_files
    local scriptcmd_file_name = stage ~= "" and (job_kind_file .. "cmd_" .. stage) or (job_kind_file .. "cmd")
    local scriptcmd_files_name = stage ~= "" and (job_kind_files .. "cmd_" .. stage) or (job_kind_files .. "cmd")

    -- build sourcebatches map
    local sourcebatches_map = {}
    for _, sourcebatch in ipairs(sourcebatches) do
        local rulename = assert(sourcebatch.rulename, "unknown rule for sourcebatch!")
        local ruleinst = _get_rule(target, rulename)
        sourcebatches_map[ruleinst] = sourcebatch
    end

    -- TODO sort rules and jobs
    local instances = {target}
    for _, r in ipairs(target:orderules()) do
        table.insert(instances, r)
    end

    -- call target and rules script
    local jobsize = jobgraph:size()
    jobgraph:group(group_name, function ()
        local has_script = false
        local script_opt = {
            script_file_name = script_file_name,
            script_files_name = script_files_name,
            scriptcmd_file_name = scriptcmd_file_name,
            scriptcmd_files_name = scriptcmd_files_name
        }
        for _, instance in ipairs(instances) do
            if instance == target then
                for _, sourcebatch in ipairs(sourcebatches) do
                    if _add_filejobs_for_script(jobgraph, instance, sourcebatch, script_opt) then
                        has_script = true
                    end
                end
            else -- rule
                local sourcebatch = sourcebatches_map[instance]
                if sourcebatch and _add_filejobs_for_script(jobgraph, instance, sourcebatch, script_opt) then
                    has_script = true
                end
            end
        end

        -- call builtin script, e.g. on_prepare_files, on_build_files, ...
        if not has_script and stage == "" then
            for _, sourcebatch in ipairs(sourcebatches) do
                _add_filejobs_for_builtin_script(jobgraph, target, sourcebatch, job_kind)
            end
        end
    end)

    if jobgraph:size() > jobsize then
        return group_name
    end
end

-- add file jobs for the given target
function _add_filejobs(jobgraph, target, opt)
    opt = opt or {}
    if not target:is_enabled() then
        return
    end

    -- get sourcebatches
    local filepatterns = opt.filepatterns
    local sourcebatches = filepatterns and _match_sourcebatches(target, filepatterns) or target:sourcebatches()

    -- we just build sourcebatch with on_build_files scripts
    --
    -- for example, c++.build and c++.build.modules.builder rules have same sourcefiles,
    -- but we just build it for c++.build
    --
    -- @see https://github.com/xmake-io/xmake/issues/3171
    --
    local sourcebatches_result = {}
    for _, sourcebatch in pairs(sourcebatches) do
        local rulename = sourcebatch.rulename
        if rulename then
            local ruleinst = _get_rule(target, rulename)
            if ruleinst:script("build_file") or ruleinst:script("build_files") then
                table.insert(sourcebatches_result, sourcebatch)
            end
        else
            table.insert(sourcebatches_result, sourcebatch)
        end
    end
    if #sourcebatches_result == 0 then
        return
    end

    -- add file jobs with target stage, e.g. before_xxx_files -> on_xxx_files -> after_xxx_files
    local group        = _add_filejobs_with_stage(jobgraph, target, sourcebatches_result, "", opt)
    local group_before = _add_filejobs_with_stage(jobgraph, target, sourcebatches_result, "before", opt)
    local group_after  = _add_filejobs_with_stage(jobgraph, target, sourcebatches_result, "after", opt)
    jobgraph:add_orders(group_before, group, group_after)
end

-- add file jobs for the given target and deps
function _add_filejobs_and_deps(jobgraph, target, targetrefs, opt)
    local targetname = target:fullname()
    if not targetrefs[targetname] then
        targetrefs[targetname] = target
        _add_filejobs(jobgraph, target, opt)
        for _, depname in ipairs(target:get("deps")) do
            local dep = project.target(depname, {namespace = target:namespace()})
            _add_filejobs_and_deps(jobgraph, dep, targetrefs, opt)
        end
    end
end

-- get files jobs
function _get_filejobs(targets_root, opt)
    local jobgraph = async_jobgraph.new()
    local targetrefs = {}
    for _, target in ipairs(targets_root) do
        _add_filejobs_and_deps(jobgraph, target, targetrefs, opt)
    end
    return jobgraph
end

-- get all root targets
function get_root_targets(targetnames, opt)
    opt = opt or {}

    -- get root targets
    local targets_root = {}
    if targetnames then
        for _, targetname in ipairs(table.wrap(targetnames)) do
            local target = project.target(targetname)
            if target then
                table.insert(targets_root, target)
                if option.get("rebuild") then
                    target:data_set("rebuilt", true)
                    if not option.get("shallow") then
                        for _, dep in ipairs(target:orderdeps()) do
                            dep:data_set("rebuilt", true)
                        end
                    end
                end
            end
        end
    else
        local group_pattern = opt.group_pattern
        local depset = hashset.new()
        local targets = {}
        for _, target in ipairs(project.ordertargets()) do
            if target:is_enabled() then
                local group = target:get("group")
                if (target:is_default() and not group_pattern) or option.get("all") or (group_pattern and group and group:match(group_pattern)) then
                    for _, depname in ipairs(target:get("deps")) do
                        depset:insert(depname)
                    end
                    table.insert(targets, target)
                end
            end
        end
        for _, target in ipairs(targets) do
            if not depset:has(target:name()) then
                table.insert(targets_root, target)
            end
            if option.get("rebuild") then
                target:data_set("rebuilt", true)
            end
        end
    end
    return targets_root
end

-- run target-level jobs, e.g. on_prepare, on_build, ...
function run_targetjobs(targets_root, opt)
    opt = opt or {}
    local job_kind = opt.job_kind
    local jobgraph = _get_targetjobs(targets_root, opt)
    if jobgraph and not jobgraph:empty() then
        local curdir = os.curdir()
        async_runjobs(job_kind, jobgraph, {on_exit = function (errors)
            import("utils.progress")
            if errors and progress.showing_without_scroll() then
                print("")
            end
        end, comax = option.get("jobs") or 1, curdir = curdir, distcc = opt.distcc})
        os.cd(curdir)
        return true
    end
end

-- run files-level jobs, e.g. on_prepare_files, on_build_files, ...
function run_filejobs(targets_root, opt)
    opt = opt or {}
    local job_kind = opt.job_kind
    local jobgraph = _get_filejobs(targets_root, opt)
    if jobgraph and not jobgraph:empty() then
        local curdir = os.curdir()
        async_runjobs(job_kind, jobgraph, {on_exit = function (errors)
            import("utils.progress")
            if errors and progress.showing_without_scroll() then
                print("")
            end
        end, comax = option.get("jobs") or 1, curdir = curdir, distcc = opt.distcc})
        os.cd(curdir)
        return true
    end
end

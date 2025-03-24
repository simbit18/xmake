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
-- @file        prepare.lua
--

-- imports
import("core.base.option")
import("core.project.config")
import("async.runjobs")
import("async.jobgraph", {alias = "async_jobgraph"})

-- get prepare jobs
function _get_prepare_jobs(targetnames, opt)
    local jobgraph = async_jobgraph.new()
    return jobgraph

    -- get root targets
    --[[
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

    -- generate batch jobs for default or all targets
    local jobrefs = {}
    local jobrefs_before = {}
    local jobgraph = jobpool.new()
    for _, target in ipairs(targets_root) do
        _add_jobgraph_for_target_and_deps(jobgraph, jobgraph:rootjob(), target, jobrefs, jobrefs_before)
    end

    -- add fence jobs, @see https://github.com/xmake-io/xmake/issues/5003
    for _, target in ipairs(project.ordertargets()) do
        local target_job_before = jobrefs_before[target:name()]
        if target_job_before then
            for _, dep in ipairs(target:orderdeps()) do
                if dep:policy("build.fence") then
                    local fence_job = jobrefs[dep:name()]
                    if fence_job then
                        jobgraph:add(fence_job, target_job_before)
                    end
                end
            end
        end
    end

    return jobgraph]]
end

function main(targetnames, opt)
    local jobgraph = _get_prepare_jobs(targetnames, opt)
    if jobgraph and not jobgraph:empty() then
        local curdir = os.curdir()
        runjobs("prepare", jobgraph, {on_exit = function (errors)
            import("utils.progress")
            if errors and progress.showing_without_scroll() then
                print("")
            end
        end, comax = option.get("jobs") or 1, curdir = curdir})
        os.cd(curdir)
    end
end

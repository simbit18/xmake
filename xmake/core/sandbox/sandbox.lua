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
-- Copyright (C) 2015-present, Xmake Open Source Community.
--
-- @author      ruki
-- @file        sandbox.lua
--

-- define module
local sandbox = sandbox or {}

-- load modules
local os        = require("base/os")
local path      = require("base/path")
local table     = require("base/table")
local utils     = require("base/utils")
local string    = require("base/string")
local option    = require("base/option")

-- traceback
function sandbox._traceback(errors)

    -- no diagnosis info?
    if not option.get("diagnosis") then
        if errors then
            -- remove the prefix info
            local _, pos = errors:find(":%d+: ")
            if pos then
                errors = errors:sub(pos + 1)
            end
        end
        return errors
    end

    -- traceback exists?
    if errors and errors:find("stack traceback:", 1, true) then
        return errors
    end

    -- init results
    local results = ""
    if errors then
        results = errors .. "\n"
    end
    results = results .. "stack traceback:\n"

    -- make results
    local level = 2
    while true do

        -- get debug info
        local info = debug.getinfo(level, "Sln")

        -- end?
        if not info then
            break
        end

        -- function?
        if info.what == "C" then
            results = results .. string.format("    [C]: in function '%s'\n", info.name)
        elseif info.name then
            results = results .. string.format("    [%s:%d]: in function '%s'\n", info.short_src, info.currentline, info.name)
        elseif info.what == "main" then
            results = results .. string.format("    [%s:%d]: in main chunk\n", info.short_src, info.currentline)
            break
        else
            results = results .. string.format("    [%s:%d]:\n", info.short_src, info.currentline)
        end
        level = level + 1
    end
    return results
end

-- register api for builtin
function sandbox._api_register_builtin(self, name, func)
    assert(self and self._PUBLIC and func)
    self._PUBLIC[name] = func
end

-- new a sandbox instance
function sandbox._new()

    -- init an sandbox instance
    local instance = {_PUBLIC = {}, _PRIVATE = {}}

    -- inherit the interfaces of sandbox
    table.inherit2(instance, sandbox)

    -- register the builtin modules
    instance:_api_register_builtin("_g", {})
    for module_name, module in pairs(sandbox.builtin_modules()) do
        instance:_api_register_builtin(module_name, module)
    end

    -- bind instance to the public script envirnoment
    instance:bind(instance._PUBLIC)
    return instance
end

-- new a sandbox instance with the given script
function sandbox.new(script, opt)
    opt = opt or {}

    -- new instance
    local self = sandbox._new()
    assert(self and self._PUBLIC and self._PRIVATE)

    self._PRIVATE._FILTER = opt.filter
    self._PRIVATE._ROOTDIR = opt.rootdir
    self._PRIVATE._NAMESPACE = opt.namespace

    -- invalid script?
    if type(script) ~= "function" then
        return nil, "invalid script!"
    end

    -- bind public scope
    setfenv(script, self._PUBLIC)

    -- save script
    self._PRIVATE._SCRIPT = script
    return self
end

-- load script in the sandbox
function sandbox.load(script, ...)
    return utils.trycall(script, sandbox._traceback, ...)
end

-- bind self instance to the given script or envirnoment
function sandbox:bind(script_or_env)

    -- get envirnoment
    local env = script_or_env
    if type(script_or_env) == "function" then
        env = getfenv(script_or_env)
    end

    -- bind instance to the script envirnoment
    setmetatable(env, {     __index = function (tbl, key)
                                if type(key) == "string" and key == "_SANDBOX" and rawget(tbl, "_SANDBOX_READABLE") then
                                    return self
                                end
                                return rawget(tbl, key)
                            end
                        ,   __newindex = function (tbl, key, val)
                                if type(key) == "string" and (key == "_SANDBOX" or key == "_SANDBOX_READABLE") then
                                    return
                                end
                                rawset(tbl, key, val)
                            end})

    -- ok
    return script_or_env
end

-- fork a new sandbox from the self sandbox
function sandbox:fork(script, rootdir)

    -- invalid script?
    if script ~= nil and type(script) ~= "function" then
        return nil, "invalid script!"
    end

    -- init a new sandbox instance
    local instance = sandbox._new()
    assert(instance and instance._PUBLIC and instance._PRIVATE)

    instance._PRIVATE._FILTER = self:filter()
    instance._PRIVATE._ROOTDIR = rootdir or self:rootdir()
    instance._PRIVATE._NAMESPACE = self:namespace()

    -- bind public scope
    if script then
        setfenv(script, instance._PUBLIC)
        instance._PRIVATE._SCRIPT = script
    end
    return instance
end

-- load script and module
function sandbox:module()

    -- this module has been loaded?
    if self._PRIVATE._MODULE then
        return self._PRIVATE._MODULE
    end

    -- backup the scope variables first
    local scope_public = getfenv(self:script())
    local scope_backup = {}
    table.copy2(scope_backup, scope_public)

    -- load module with sandbox
    local ok, errors = sandbox.load(self:script())
    if not ok then
        return nil, errors
    end

    -- only export new public functions
    local module = {}
    for k, v in pairs(scope_public) do
        if type(v) == "function" and not k:startswith("_") and scope_backup[k] == nil then
            module[k] = v
        end
    end
    self._PRIVATE._MODULE = module
    return module
end

-- get script from the given sandbox
function sandbox:script()
    assert(self and self._PRIVATE)
    return self._PRIVATE._SCRIPT
end

-- get filter from the given sandbox
function sandbox:filter()
    assert(self and self._PRIVATE)
    return self._PRIVATE._FILTER
end

-- get root directory from the given sandbox
function sandbox:rootdir()
    assert(self and self._PRIVATE)
    return self._PRIVATE._ROOTDIR
end

-- get current namespace
function sandbox:namespace()
    assert(self and self._PRIVATE)
    return self._PRIVATE._NAMESPACE
end

-- get current instance in the sandbox modules
function sandbox.instance(script)

    -- get the sandbox instance from the given script
    local instance = nil
    if script then
        local scope = getfenv(script)
        if scope then

            -- enable to read _SANDBOX
            rawset(scope, "_SANDBOX_READABLE", true)

            -- attempt to get it
            instance = scope._SANDBOX

            -- disable to read _SANDBOX
            rawset(scope, "_SANDBOX_READABLE", nil)
        end
        if instance then return instance end
    end

    -- find self instance for the current sandbox
    local level = 2
    while level < 32 do

        -- get scope
        local ok, scope = pcall(getfenv, level)
        if not ok then
            break;
        end
        if scope then

            -- enable to read _SANDBOX
            rawset(scope, "_SANDBOX_READABLE", true)

            -- attempt to get it
            instance = scope._SANDBOX

            -- disable to read _SANDBOX
            rawset(scope, "_SANDBOX_READABLE", nil)
        end

        -- found?
        if instance then
            break
        end

        -- next
        level = level + 1
    end
    return instance
end

-- get builtin modules
function sandbox.builtin_modules()
    local builtin_modules = sandbox._BUILTIN_MODULES
    if builtin_modules == nil then
        builtin_modules = {}
        local builtin_module_files = os.files(path.join(os.programdir(), "core/sandbox/modules/*.lua"))
        if builtin_module_files then
            for _, builtin_module_file in ipairs(builtin_module_files) do
                local module_name = path.basename(builtin_module_file)
                assert(module_name)

                local script, errors = loadfile(builtin_module_file)
                if script then
                    local ok, results = utils.trycall(script)
                    if not ok then
                        os.raise(results)
                    end
                    builtin_modules[module_name] = results
                else
                    os.raise(errors)
                end
            end
        end
        sandbox._BUILTIN_MODULES = builtin_modules
    end
    return builtin_modules
end


-- return module
return sandbox

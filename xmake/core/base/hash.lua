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
-- @file        hash.lua
--

-- define module: hash
local hash  = hash or {}

-- load modules
local io    = require("base/io")
local utils = require("base/utils")
local bytes = require("base/bytes")

-- save metatable and builtin functions
hash._md5 = hash._md5 or hash.md5
hash._sha = hash._sha or hash.sha
hash._xxhash = hash._xxhash or hash.xxhash

-- generate md5 from the given file or data
function hash.md5(file_or_data)
    local hashstr, errors
    if bytes.instance_of(file_or_data) then
        local datasize = file_or_data:size()
        local dataaddr = file_or_data:caddr()
        hashstr, errors = hash._md5(dataaddr, datasize)
    else
        hashstr, errors = hash._md5(file_or_data)
    end
    return hashstr, errors
end

-- generate sha1 from the given file or data
function hash.sha1(file_or_data)
    local hashstr, errors
    if bytes.instance_of(file_or_data) then
        local datasize = file_or_data:size()
        local dataaddr = file_or_data:caddr()
        hashstr, errors = hash._sha(160, dataaddr, datasize)
    else
        hashstr, errors = hash._sha(160, file_or_data)
    end
    return hashstr, errors
end

-- generate sha256 from the given file or data
function hash.sha256(file_or_data)
    local hashstr, errors
    if bytes.instance_of(file_or_data) then
        local datasize = file_or_data:size()
        local dataaddr = file_or_data:caddr()
        hashstr, errors = hash._sha(256, dataaddr, datasize)
    else
        hashstr, errors = hash._sha(256, file_or_data)
    end
    return hashstr, errors
end

-- generate xxhash64 from the given file or data
function hash.xxhash64(file_or_data)
    local hashstr, errors
    if bytes.instance_of(file_or_data) then
        local datasize = file_or_data:size()
        local dataaddr = file_or_data:caddr()
        hashstr, errors = hash._xxhash(64, dataaddr, datasize)
    else
        hashstr, errors = hash._xxhash(64, file_or_data)
    end
    return hashstr, errors
end

-- generate xxhash128 from the given file or data
function hash.xxhash128(file_or_data)
    local hashstr, errors
    if bytes.instance_of(file_or_data) then
        local datasize = file_or_data:size()
        local dataaddr = file_or_data:caddr()
        hashstr, errors = hash._xxhash(128, dataaddr, datasize)
    else
        hashstr, errors = hash._xxhash(128, file_or_data)
    end
    return hashstr, errors
end

-- generate uuid, e.g "91E8ECF1-417F-4EDF-A574-E22D7D8D204A"
function hash.uuid(str)
    return hash.uuid4(str)
end

-- TODO, we should optimize it
-- generate hash32 from string, e.g. "91e8ecf1"
function hash.strhash32(str)
    return hash.uuid4(str):split("-", {plain = true})[1]:lower()
end

-- generate hash128 from string, e.g. "91e8ecf1417f4edfa574e22d7d8d204a"
function hash.strhash128(str)
    return hash.uuid4(str):replace("-", "", {plain = true}):lower()
end

-- return module: hash
return hash

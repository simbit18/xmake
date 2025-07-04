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
-- @file        xmake.lua
--

-- define rule: protobuf.cpp
rule("protobuf.cpp")
    add_deps("c++")
    set_extensions(".proto")
    after_load(function(target)
        import("proto").load(target, "cxx")
    end)
    -- generate build commands
    before_buildcmd_file(function(target, batchcmds, sourcefile_proto, opt)
        import("proto").buildcmd_pfile(target, batchcmds, sourcefile_proto, "cxx", opt)
    end)
    on_buildcmd_file(function(target, batchcmds, sourcefile_proto, opt)
        import("proto").buildcmd_cxfile(target, batchcmds, sourcefile_proto, "cxx", opt)
    end)


-- define rule: protobuf.c
rule("protobuf.c")
    add_deps("c++")
    set_extensions(".proto")
    after_load(function(target)
        import("proto").load(target, "cc")
    end)
    before_buildcmd_file(function(target, batchcmds, sourcefile_proto, opt)
        import("proto").buildcmd_pfile(target, batchcmds, sourcefile_proto, "cc", opt)
    end)
    on_buildcmd_file(function(target, batchcmds, sourcefile_proto, opt)
        import("proto").buildcmd_cxfile(target, batchcmds, sourcefile_proto, "cc", opt)
    end)

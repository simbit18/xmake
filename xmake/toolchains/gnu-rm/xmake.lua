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

toolchain("gnu-rm")
    set_homepage("https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm")
    set_description("GNU Arm Embedded Toolchain")
    set_kind("cross")

    on_load(function (toolchain)
        toolchain:load_cross_toolchain()

        toolchain:add("ldflags", "--specs=nosys.specs", "--specs=nano.specs", {force = true})
        toolchain:add("shflags", "--specs=nosys.specs", "--specs=nano.specs", {force = true})
        toolchain:add("syslinks", "c", "m")
    end)

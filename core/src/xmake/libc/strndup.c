/*!A cross-platform build utility based on Lua
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright (C) 2015-present, Xmake Open Source Community.
 *
 * @author      ruki
 * @file        strndup.c
 *
 */

/* //////////////////////////////////////////////////////////////////////////////////////
 * trace
 */
#define TB_TRACE_MODULE_NAME    "strndup"
#define TB_TRACE_MODULE_DEBUG   (0)

/* //////////////////////////////////////////////////////////////////////////////////////
 * includes
 */
#include "prefix.h"

/* //////////////////////////////////////////////////////////////////////////////////////
 * implementation
 */
tb_int_t xm_libc_strndup(lua_State* lua)
{
    // check
    tb_assert_and_check_return_val(lua, 0);

    // do strndup
    tb_char_t const* s = tb_null;
    if (lua_isnumber(lua, 1))
        s = (tb_char_t const*)(tb_size_t)lua_tointeger(lua, 1);
    else if (lua_isstring(lua, 2))
        s = lua_tostring(lua, 2);
    else xm_libc_return_error(lua, "libc.strndup(invalid args)!");
    tb_int_t n = (tb_int_t)lua_tointeger(lua, 2);
    if (s && n >= 0)
        lua_pushlstring(lua, s, n);
    else lua_pushliteral(lua, "");
    return 1;
}


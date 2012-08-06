#include "skynet.h"

#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>

static int 
traceback (lua_State *L) {
  const char *msg = lua_tostring(L, 1);
  if (msg)
    luaL_traceback(L, L, msg, 1);
  else if (!lua_isnoneornil(L, 1)) {  /* is there an error object? */
    if (!luaL_callmeta(L, 1, "__tostring"))  /* try its 'tostring' metamethod */
      lua_pushliteral(L, "(no error message)");
  }
  return 1;
}

static void
_cb(struct skynet_context * context, void * ud, int session, const char * addr, const void * msg, size_t sz) {
	lua_State *L = ud;
	lua_pushcfunction(L, traceback);
	lua_rawgetp(L, LUA_REGISTRYINDEX, _cb);
	int r;
	if (msg == NULL) {
		lua_pushinteger(L, session);
		r = lua_pcall(L, 1, 0 , -3);
	} else {
		lua_pushinteger(L, session);
		lua_pushstring(L, addr);
		lua_pushlstring(L, msg, sz);
		r = lua_pcall(L, 3, 0 , -5);
	}
	if (r == LUA_OK) 
		return;
	skynet_error(context, "lua error %s", lua_tostring(L,-1));
}

static int
_callback(lua_State *L) {
	struct skynet_context * context = lua_touserdata(L, lua_upvalueindex(1));
	if (context == NULL) {
		return luaL_error(L, "Init skynet context first");
	}

	luaL_checktype(L,1,LUA_TFUNCTION);
	lua_settop(L,1);
	lua_rawsetp(L, LUA_REGISTRYINDEX, _cb);
	lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
	lua_State *gL = lua_tothread(L,-1);

	skynet_callback(context, gL, _cb);

	return 0;
}

static int
_command(lua_State *L) {
	struct skynet_context * context = lua_touserdata(L, lua_upvalueindex(1));
	const char * cmd = luaL_checkstring(L,1);
	const char * parm = NULL;
	int session = 0;
	const char * result;
	int top = lua_gettop(L);
	if (top == 2) {
		if (lua_type(L,2) == LUA_TNUMBER) {
			session = lua_tointeger(L,2);
		} else {
			parm = luaL_checkstring(L,2);
		}
	} else if (top == 3) {
		session = lua_tointeger(L,2);
		parm = luaL_checkstring(L,3);
	} else if (top != 1) {
		luaL_error(L, "skynet.command support only 3 parms (%d)",top);
	}

	result = skynet_command(context, cmd, session, parm);
	if (result) {
		lua_pushstring(L, result);
		return 1;
	}
	return 0;
}

static int
_send(lua_State *L) {
	struct skynet_context * context = lua_touserdata(L, lua_upvalueindex(1));
	int session = -1;
	int index = 0;
	const char * dest = luaL_checkstring(L,1);

	if (lua_type(L,2) == LUA_TNUMBER) {
		session = lua_tointeger(L,2);
		++index;
	}
	if (lua_gettop(L) == index + 1) {
		session = skynet_send(context, dest, session , NULL, 0);
	} else {
		int type = lua_type(L,index+2);
		if (type == LUA_TSTRING) {
			size_t len = 0;
			void * msg = (void *)lua_tolstring(L,index+2,&len);
			void * message = malloc(len);
			memcpy(message, msg, len);
			session = skynet_send(context, dest, session , message, len);
		} else if (type == LUA_TNIL) {
			session = skynet_send(context, dest, session , NULL, 0);
		} else {
			void * msg = lua_touserdata(L,index+2);
			if (msg == NULL) {
				return luaL_error(L, "skynet.send need userdata or string (%s)", lua_typename(L,type));
			}
			int size = luaL_checkinteger(L,index+3);
			session = skynet_send(context, dest, session, msg, size);
		}
	}
	if (session < 0) {
		return luaL_error(L, "skynet.send drop the message to %s", dest);
	}
	lua_pushinteger(L,session);
	return 1;
}

static int
_error(lua_State *L) {
	struct skynet_context * context = lua_touserdata(L, lua_upvalueindex(1));
	skynet_error(context, "%s", luaL_checkstring(L,1));
	return 0;
}

int
luaopen_skynet_c(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "send" , _send },
		{ "command" , _command },
		{ "callback" , _callback },
		{ "error", _error },
		{ NULL, NULL },
	};

	luaL_newlibtable(L,l);

	lua_getfield(L, LUA_REGISTRYINDEX, "skynet_context");
	struct skynet_context * ctx = lua_touserdata(L,-1);
	if (ctx == NULL) {
		return luaL_error(L, "Init skynet context first");
	}

	luaL_setfuncs(L,l,1);

	return 1;
}

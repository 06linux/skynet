local c = require "skynet.c"
local tostring = tostring
local tonumber = tonumber
local coroutine = coroutine
local assert = assert

local skynet = {}
local session_id_coroutine = {}
local session_coroutine_id = {}
local session_coroutine_address = {}

local function create_coroutine(f)
	return coroutine.create(function(...)
		assert(xpcall(f,debug.traceback,...))
	end)
end

local function suspend(co, result, command, param, size)
	assert(result, command)
	if command == "CALL" or command == "SLEEP" then
		session_id_coroutine[param] = co
	elseif command == "RETURN" then
		local co_session = session_coroutine_id[co]
		local co_address = session_coroutine_address[co]
		c.send(co_address, co_session, param, size)
		return suspend(co, coroutine.resume(co))
	elseif command == nil then
		session_coroutine_id[co] = nil
		session_coroutine_address[co] = nil
	else
		error("Unknown command : " .. command)
	end
end

function skynet.timeout(ti, func, ...)
	local session = c.command("TIMEOUT",tostring(ti))
	assert(session)
	session = tonumber(session)
	local co
	if select("#",...) == 0 then
		co = create_coroutine(func)
	else
		local args = { ... }
		co = create_coroutine(function()
			func(unpack(args))
		end)
	end
	assert(session_id_coroutine[session] == nil)
	session_id_coroutine[session] = co
end

function skynet.fork(func,...)
	skynet.timeout("0", func, ...)
end

function skynet.sleep(ti)
	local session = c.command("TIMEOUT",tostring(ti))
	assert(session)
	coroutine.yield("SLEEP", tonumber(session))
end

function skynet.yield()
	local session = c.command("TIMEOUT","0")
	assert(session)
	coroutine.yield("SLEEP", tonumber(session))
end

function skynet.register(name)
	return c.command("REG", name)
end

function skynet.name(name, handle)
	c.command("NAME", name .. " " .. handle)
end

function skynet.self()
	return c.command("REG")
end

function skynet.launch(...)
	return c.command("LAUNCH", table.concat({...}," "))
end

function skynet.now()
	return tonumber(c.command("NOW"))
end

function skynet.starttime()
	return tonumber(c.command("STARTTIME"))
end

function skynet.exit()
	c.command("EXIT")
end

function skynet.kill(name)
	c.command("KILL",name)
end

function skynet.getenv(key)
	return c.command("GETENV",key)
end

function skynet.setenv(key, value)
	c.command("SETENV",key .. " " ..value)
end

skynet.send = assert(c.send)
skynet.genid = assert(c.genid)
skynet.redirect = assert(c.redirect)
skynet.pack = assert(c.pack)
skynet.tostring = assert(c.tostring)
skynet.unpack = assert(c.unpack)

function skynet.call(addr, deseri , ...)
	if deseri == nil then
		local session = c.send(addr, -1, ...)
		return coroutine.yield("CALL", session)
	end
	local t = type(deseri)
	if t == "function" then
		local session = c.send(addr, -1, ...)
		return deseri(coroutine.yield("CALL", session))
	else
		assert(t=="string")
		local session = c.send(addr, -1, deseri)
		return c.tostring(coroutine.yield("CALL", session))
	end
end

function skynet.ret(...)
	coroutine.yield("RETURN", ...)
end

local function default_dispatch(f)
	return function(session, address , msg, sz)
		if session == nil then
			return
		end
		if session <= 0 then
			session = - session
			co = create_coroutine(f)
			session_coroutine_id[co] = session
			session_coroutine_address[co] = address
			suspend(co, coroutine.resume(co, msg, sz, session, address))
		else
			local co = session_id_coroutine[session]
			assert(co, session)
			session_id_coroutine[session] = nil
			suspend(co, coroutine.resume(co, msg, sz))
		end
	end
end

function skynet.dispatch(f)
	c.callback(default_dispatch(f))
end

function skynet.filter(filter, f)
	local func = default_dispatch(f)
	c.callback(function (...)
		func(filter(...))
	end)
end

function skynet.start(f)
	local session = c.command("TIMEOUT","0")
	local co = create_coroutine(
		function(...)
			f(...)
			skynet.send(".launcher",0)
		end
	)
	session_id_coroutine[tonumber(session)] = co
end

return skynet

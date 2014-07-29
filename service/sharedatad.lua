local skynet = require "skynet"
local sharedata = require "sharedata.corelib"
local table = table

local NORET = {}
local pool = {}
local objmap = {}

local function newobj(name, tbl)
	assert(pool[name] == nil)
	local cobj = sharedata.host.new(tbl)
	sharedata.host.incref(cobj)
	local v = { value = tbl , obj = cobj, watch = {} }
	objmap[cobj] = v
	pool[name] = v
end

local function collectobj()
	while true do
		skynet.sleep(600 * 100)	-- sleep 10 min
		collectgarbage()
		for obj, v in pairs(objmap) do
			if v == true then
				if sharedata.host.getref(obj) <= 0  then
					objmap[obj] = nil
					print("collect", obj)
					sharedata.host.delete(obj)
				end
			end
		end
	end
end

local CMD = {}

function CMD.new(name, t)
	local dt = type(t)
	local value
	if dt == "table" then
		value = t
	elseif dt == "string" then
		value = {}
		local f = load(t, "=" .. name, "t", env)
		f()
	elseif dt == "nil" then
		value = {}
	else
		error ("Unknown data type " .. dt)
	end
	newobj(name, value)
end

function CMD.delete(name)
	local v = assert(pool[name])
	pool[name] = nil
	assert(objmap[v.obj])
	objmap[v.obj] = true
	sharedata.host.decref(v.obj)
end

function CMD.query(name)
	local v = assert(pool[name])
	local obj = v.obj
	sharedata.host.incref(obj)
	return v.obj
end

function CMD.confirm(cobj)
	if objmap[cobj] then
		sharedata.host.decref(cobj)
	end
	return NORET
end

function CMD.update(name, t)
	local v = pool[name]
	local watch, oldcobj
	if v then
		watch = v.watch
		oldcobj = v.obj
		CMD.delete(name)
	end
	CMD.new(name, t)
	local newobj = pool[name].obj
	if watch then
		sharedata.host.markdirty(oldcobj)
		for _,v in ipairs(watch) do
			local session = v[1]
			local address = v[2]
			skynet.redirect(address, 0, "response", session, skynet.pack(newobj))
		end
	end
end

function CMD.monitor(session, address, name, obj)
	local v = assert(pool[name])
	if obj ~= v.obj then
		return v.obj
	end

	table.insert(v.watch, { session, address })

	return NORET
end

skynet.start(function()
	skynet.fork(collectobj)
	skynet.dispatch("lua", function (session, source ,cmd, ...)
		local f = assert(CMD[cmd])
		local r
		if cmd == "monitor" then
			r = f(session, source, ...)
		else
			r = f(...)
		end
		if r ~= NORET then
			skynet.ret(skynet.pack(r))
		end
	end)
end)


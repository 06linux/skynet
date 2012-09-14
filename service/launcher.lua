local skynet = require "skynet"
local string = string

local services = {}

local command = {}

function command.LIST()
	local list = {}
	for k,v in pairs(services) do
		list[skynet.address(k)] = v
	end
	skynet.ret(skynet.pack(list))
end

function command.STAT()
	local list = {}
	for k,v in pairs(services) do
		local stat = skynet.call(k,"debug","STAT")
		local result = {}
		for k,v in pairs(stat) do
			table.insert(result, string.format("%s = %s", k, tostring(v)))
		end
		list[skynet.address(k)] = table.concat(result,",") .. " (" .. v .. ")"
	end
	skynet.ret(skynet.pack(list))
end

function command.KILL(handle)
	skynet.kill(handle)
	skynet.ret( skynet.pack({ [handle] = tostring(services[handle]) }))
	services[handle] = nil
end

function command.MEM()
	local list = {}
	for k,v in pairs(services) do
		local kb, bytes = skynet.call(k,"debug","MEM")
		list[skynet.address(k)] = string.format("%d Kb (%s)",kb,v)
	end
	skynet.ret(skynet.pack(list))
end

function command.GC()
	for k,v in pairs(services) do
		skynet.send(k,"debug","GC")
	end
	command.MEM()
end

function command.REMOVE(handle)
	services[handle] = nil
end

local instance = {}

skynet.register(".launcher")

skynet.start(function()
	skynet.dispatch("text" , function(session, address , cmd)
		if cmd == "" then
			-- init notice
			local reply = instance[address]
			if reply then
				skynet.redirect(reply.address , 0, "response", reply.session, skynet.address(address))
				instance[address] = nil
			end
		else
			-- launch request
			local service, param = string.match(cmd,"([^ ]+) (.*)")
			local inst = skynet.launch(service, param)
			if inst then
				services[inst] = cmd
				instance[inst] = { session = session, address = address }
			else
				skynet.ret("")
			end
		end
	end)
	skynet.dispatch("lua", function(session, address, cmd , ...)
		cmd = string.upper(cmd)
		command[cmd](...)
	end)
end)

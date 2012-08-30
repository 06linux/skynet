local skynet = require "skynet"

local port, max_agent, buffer = ...
local command = {}
local agent_all = {}
local gate

function command:open(parm)
	local fd,addr = string.match(parm,"(%d+) ([^%s]+)")
	fd = tonumber(fd)
	print("agent open",self,string.format("%d %d %s",self,fd,addr))
	local client = skynet.launch("client",fd)
	local agent = skynet.launch("snlua","agent",skynet.address(client))
	if agent then
		agent_all[self] = { agent , client }
		skynet.send(gate, "forward ".. self .. " " .. skynet.address(agent) .. " " .. skynet.address(client))
	end
end

function command:close()
	print("agent close",self,string.format("close %d",self))
	local agent = agent_all[self]
	agent_all[self] = nil
	skynet.kill(agent[1])
	skynet.kill(agent[2])
end

function command:data(data, session)
	local agent = agent_all[self]
	if agent then
		-- 0x7fffffff means it's a client
		skynet.redirect(agent[1], agent[2], 0x7fffffff, data)
	else
		skynet.error(string.format("agent data drop %d size=%d",self,#data))
	end
end

skynet.dispatch(function(msg, sz, session, address)
	local message = skynet.tostring(msg,sz)
	local id, cmd , parm = string.match(message, "(%d+) (%w+) ?(.*)")
	id = tonumber(id)
	local f = command[cmd]
	if f then
		f(id,parm,session)
	else
		skynet.error(string.format("[watchdog] Unknown command : %s",message))
	end
end)

skynet.start(function()
	gate = skynet.launch("gate" , skynet.address(skynet.self()), port, max_agent, buffer)
	skynet.send(gate,"start")
	skynet.register(".watchdog")
end)

local skynet = require "skynet"

-- register a dummy callback function
skynet.dispatch()

local connection = skynet.launch("connection","16")
print("connection",connection)

skynet.start(function()
	local fd = skynet.call(".connection","CONNECT 127.0.0.1:8000")
	if fd == nil then
		print("Connect failed")
		skynet.exit()
		return
	end
	print("connect to ",fd)
	skynet.send(".connection","WRITE "..fd.." Welcome\n")
	local four = skynet.call(".connection","READ "..fd .." 4")
	print("READ 4", four)
	local line = skynet.call(".connection","READLINE "..fd .." \n")
	skynet.send(".connection","WRITE "..fd.." "..line.."\n")
	skynet.send(".connection","CLOSE "..fd)

	skynet.exit()
end)

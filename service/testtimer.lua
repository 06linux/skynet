local skynet = require "skynet"

-- register a dummy callback function
skynet.dispatch()

local function timeout(t)
	print(t)
end

local function wakeup(co)
	for i=1,5 do
		skynet.sleep(50)
		skynet.wakeup(co)
	end
end

skynet.start(function()
	skynet.fork(wakeup, coroutine.running())
	skynet.timeout(300, timeout, "Hello World")
	for i = 1, 10 do
		print(i, skynet.now())
		print(skynet.sleep(100))
	end
	skynet.exit()
	print("Test timer exit")
end)

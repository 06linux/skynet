local skynet = require "skynet"
local id = ...

skynet.dispatch(function (msg,sz)
	print(id, skynet.tostring(msg,sz))
end
)

skynet.start(function()
	print("start",id)
end)

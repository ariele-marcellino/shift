--!strict
-- Minimal server/client-local signal. Connect returns a connection with :Disconnect().
local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} :: { [any]: (...any) -> () } }, Signal)
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local key = {}
	self._handlers[key] = fn
	local handlers = self._handlers
	return {
		Disconnect = function()
			handlers[key] = nil
		end,
	} :: any
end

function Signal:Fire(...: any)
	for _, fn in self._handlers do
		task.spawn(fn, ...)
	end
end

return Signal

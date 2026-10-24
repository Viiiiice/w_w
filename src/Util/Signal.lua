local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self._handlers
	handlers[fn] = true
	return {
		Disconnect = function()
			handlers[fn] = nil
		end,
	}
end

function Signal:Fire(...)
	for fn in pairs(self._handlers) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn(err)
		end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal

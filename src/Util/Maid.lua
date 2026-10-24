local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give(item)
	table.insert(self._tasks, item)
	return item
end

function Maid:Clean()
	for _, item in ipairs(self._tasks) do
		pcall(function()
			if type(item) == "function" then
				item()
			elseif typeof(item) == "RBXScriptConnection" or (type(item) == "table" and item.Disconnect) then
				item:Disconnect()
			elseif typeof(item) == "Instance" then
				item:Destroy()
			end
		end)
	end
	table.clear(self._tasks)
end

return Maid

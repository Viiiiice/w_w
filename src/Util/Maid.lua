local Maid = {}
Maid.__index = Maid

local function cleanup(item, method)
	if method then
		item[method](item)
	elseif type(item) == "function" then
		item()
	elseif type(item) == "thread" then
		if coroutine.status(item) ~= "dead" then
			task.cancel(item)
		end
	elseif typeof(item) == "RBXScriptConnection" then
		item:Disconnect()
	elseif typeof(item) == "Instance" then
		item:Destroy()
	elseif type(item) == "table" then
		if item.Destroy then
			item:Destroy()
		elseif item.Clean then
			item:Clean()
		elseif item.Disconnect then
			item:Disconnect()
		end
	end
end

function Maid.new()
	return setmetatable({ _tasks = {}, _keyed = {}, _cleaning = false }, Maid)
end

function Maid.is(value)
	return getmetatable(value) == Maid
end

function Maid:Give(item, method)
	if self._cleaning then
		task.defer(cleanup, item, method)
		return item
	end
	table.insert(self._tasks, { item, method })
	return item
end

Maid.Add = Maid.Give

function Maid:Connect(signal, handler)
	return self:Give(signal:Connect(handler))
end

function Maid:Once(signal, handler)
	return self:Give(signal:Once(handler))
end

function Maid:BindToRenderStep(name, priority, handler)
	local RunService = game:GetService("RunService")
	RunService:BindToRenderStep(name, priority, handler)
	self:Give(function()
		RunService:UnbindFromRenderStep(name)
	end)
end

function Maid:Spawn(fn, ...)
	return self:Give(task.spawn(fn, ...))
end

function Maid:Delay(seconds, fn, ...)
	return self:Give(task.delay(seconds, fn, ...))
end

function Maid:Extend()
	return self:Give(Maid.new())
end

function Maid:Set(key, item, method)
	local old = self._keyed[key]
	self._keyed[key] = nil
	if old then
		pcall(cleanup, old[1], old[2])
	end
	if item ~= nil then
		if self._cleaning then
			task.defer(cleanup, item, method)
		else
			self._keyed[key] = { item, method }
		end
	end
	return item
end

function Maid:Get(key)
	local entry = self._keyed[key]
	return entry and entry[1]
end

function Maid:Remove(item, keep)
	for i = #self._tasks, 1, -1 do
		local entry = self._tasks[i]
		if entry[1] == item then
			table.remove(self._tasks, i)
			if not keep then
				pcall(cleanup, entry[1], entry[2])
			end
			return true
		end
	end
	return false
end

function Maid:AttachToInstance(instance)
	return self:Give(instance.Destroying:Connect(function()
		self:Clean()
	end))
end

function Maid:Count()
	local count = #self._tasks
	for _ in pairs(self._keyed) do
		count += 1
	end
	return count
end

function Maid:Clean()
	if self._cleaning then
		return
	end
	self._cleaning = true

	local keyed = self._keyed
	self._keyed = {}
	for _, entry in pairs(keyed) do
		local ok, err = pcall(cleanup, entry[1], entry[2])
		if not ok then
			warn("[w_w] maid cleanup failed:", err)
		end
	end

	local tasks = self._tasks
	self._tasks = {}
	for i = #tasks, 1, -1 do
		local ok, err = pcall(cleanup, tasks[i][1], tasks[i][2])
		if not ok then
			warn("[w_w] maid cleanup failed:", err)
		end
	end

	self._cleaning = false
end

Maid.Destroy = Maid.Clean
Maid.DoCleaning = Maid.Clean

return Maid

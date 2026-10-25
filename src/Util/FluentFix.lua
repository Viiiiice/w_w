local FluentFix = {}

local creator

local function isCreator(t)
	return type(t) == "table"
		and type(rawget(t, "Registry")) == "table"
		and type(rawget(t, "Signals")) == "table"
		and type(rawget(t, "UpdateTheme")) == "function"
		and type(rawget(t, "AddThemeObject")) == "function"
end

function FluentFix.find()
	if creator then
		return creator
	end
	if not getgc then
		return nil
	end
	local ok, objects = pcall(getgc, true)
	if not ok then
		return nil
	end
	for _, t in ipairs(objects) do
		if isCreator(t) then
			creator = t
			break
		end
	end
	return creator
end

function FluentFix.prune()
	local c = FluentFix.find()
	if not c then
		return 0
	end
	local removed = 0
	for object in pairs(c.Registry) do
		if typeof(object) == "Instance" and object.Parent == nil then
			c.Registry[object] = nil
			removed += 1
		end
	end
	local signals = c.Signals
	for i = #signals, 1, -1 do
		local connection = signals[i]
		if typeof(connection) == "RBXScriptConnection" and not connection.Connected then
			table.remove(signals, i)
		end
	end
	return removed
end

function FluentFix.setValues(dropdown, values)
	dropdown:SetValues(values)
	task.defer(FluentFix.prune)
end

return FluentFix

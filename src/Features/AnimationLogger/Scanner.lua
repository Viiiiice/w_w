local Logger = require("Features/AnimationLogger/Logger")

local Scanner = {}

function Scanner.scan()
	local seen = {}
	local found = 0

	local function check(inst)
		if seen[inst] or typeof(inst) ~= "Instance" or not inst:IsA("Animation") then
			return
		end
		seen[inst] = true
		local where = inst.Parent and inst.Parent.Name or "nil"
		local _, isNew = Logger.log(inst.AnimationId, inst.Name, "scan:" .. where)
		if isNew then
			found += 1
		end
	end

	local function sweep(list)
		for i, inst in ipairs(list) do
			pcall(check, inst)
			if i % 5000 == 0 then
				task.wait()
			end
		end
	end

	sweep(game:GetDescendants())
	if getinstances then
		sweep(getinstances())
	end

	if getnilinstances then
		sweep(getnilinstances())
	end

	return found
end

return Scanner

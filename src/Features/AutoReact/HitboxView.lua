local Services = require("Util/Services")

local RunService = Services.RunService
local LocalPlayer = Services.Players.LocalPlayer

local HitboxView = {
	enabled = false,
}

local COLORS = {
	inside = Color3.fromRGB(255, 60, 60),
	outside = Color3.fromRGB(255, 200, 60),
	mine = Color3.fromRGB(80, 220, 120),
}

local folder
local pool = {}
local active = {}
local connection

local function rootOf(model)
	return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end

local function getBox()
	local box = table.remove(pool)
	if box and box.Parent then
		return box
	end
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "w_wHitboxes"
		folder.Parent = workspace.CurrentCamera
	end
	box = Instance.new("Part")
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Material = Enum.Material.ForceField
	box.Transparency = 0.2
	box.Parent = folder
	return box
end

local function release(entry)
	entry.box.CFrame = CFrame.new(0, -10000, 0)
	table.insert(pool, entry.box)
end

local function inside(cf, size, position, padding)
	local p = cf:PointToObjectSpace(position)
	return math.abs(p.X) <= size.X / 2 + padding
		and math.abs(p.Y) <= size.Y / 2 + padding + 2
		and math.abs(p.Z) <= size.Z / 2 + padding
end

local function step()
	local now = os.clock()
	local mine = rootOf(LocalPlayer.Character)
	for i = #active, 1, -1 do
		local entry = active[i]
		local root = rootOf(entry.model)
		if now >= entry.expires or not root then
			table.remove(active, i)
			release(entry)
		else
			local cf = root.CFrame * CFrame.new(entry.offset)
			entry.box.CFrame = cf
			if entry.color then
				entry.box.Color = entry.color
			else
				local hit = mine and inside(cf, entry.size, mine.Position, entry.padding)
				entry.box.Color = hit and COLORS.inside or COLORS.outside
			end
		end
	end
	if #active == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

function HitboxView.show(model, hit, duration, padding, mine)
	if not HitboxView.enabled then
		return
	end
	local box = getBox()
	local size = Vector3.new(hit.size[1], hit.size[2], hit.size[3])
	box.Size = size
	table.insert(active, {
		model = model,
		box = box,
		size = size,
		offset = Vector3.new(hit.offset[1], hit.offset[2], hit.offset[3]),
		expires = os.clock() + duration,
		padding = padding or 0,
		color = mine and COLORS.mine or nil,
	})
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
	step()
end

function HitboxView.clear()
	for i = #active, 1, -1 do
		release(table.remove(active, i))
	end
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(pool)
end

return HitboxView

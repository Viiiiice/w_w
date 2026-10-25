local Services = require("Util/Services")
local Config = require("Config")

local Players = Services.Players
local LocalPlayer = Players.LocalPlayer

local Rig = {}

local STRIP = {"LuaSourceContainer", "Sound", "ForceField", "BillboardGui", "ParticleEmitter", "Trail"}

local function shouldStrip(inst)
	for _, class in ipairs(STRIP) do
		if inst:IsA(class) then
			return true
		end
	end
	return false
end


function Rig.findSource(kind, ownerName)
	if kind == "Owner" and ownerName and not ownerName:find("^scan:") then
		local player = Players:FindFirstChild(ownerName)
		if player and player:IsA("Player") and player.Character then
			return player.Character
		end

		local folder = workspace:FindFirstChild(Config.AnimationLogger.ScanFolder)
		local model = folder and folder:FindFirstChild(ownerName)
		if model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
			return model
		end
	end

	return LocalPlayer.Character
end

function Rig.build(source)
	if not source then
		return nil, "No character to copy"
	end

	local wasArchivable = source.Archivable
	source.Archivable = true

	local ok, rig = pcall(source.Clone, source)
	source.Archivable = wasArchivable

	if not ok or not rig then
		return nil, "Couldn't copy the character"
	end

	for _, inst in ipairs(rig:GetDescendants()) do
		if shouldStrip(inst) then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = false
		end
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
	if not humanoid or not root then
		rig:Destroy()
		return nil, "That character has no Humanoid/root part"
	end

	root.Anchored = true
	root.Transparency = 1
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	rig.PrimaryPart = root
	rig:PivotTo(CFrame.new())
	
	return rig, animator, root
end

return Rig

local Services = require("Util/Services")
local Logger = require("Features/AnimationLogger/Logger")

local Players = Services.Players

local Tracker = {}

local hooked = {}

local function ownerOf(animator)
	local model = animator:FindFirstAncestorOfClass("Model")
	if not model then
		return "?"
	end

	local player = Players:GetPlayerFromCharacter(model)

	return player and player.Name or model.Name
end

local function nameOf(track)
	local name = track.Name
	if (name == "" or name == "Animation") and track.Animation then
		name = track.Animation.Name
	end

	return name
end

local function onTrack(animator, track)
	local anim = track.Animation
	if anim then
		Logger.log(anim.AnimationId, nameOf(track), ownerOf(animator))
	end
end

local function hookAnimator(animator, maid)
	if hooked[animator] then
		return
	end
	local played, ancestry
	played = animator.AnimationPlayed:Connect(function(track)
		onTrack(animator, track)
	end)
	ancestry = animator.AncestryChanged:Connect(function()
		if not animator:IsDescendantOf(workspace) then
			played:Disconnect()
			ancestry:Disconnect()
			hooked[animator] = nil
		end
	end)
	hooked[animator] = { played, ancestry }

	local ok, playing = pcall(animator.GetPlayingAnimationTracks, animator)
	if ok then
		for _, track in ipairs(playing) do
			onTrack(animator, track)
		end
	end
end

local function tryHook(inst, maid)
	if inst:IsA("Animator") then
		hookAnimator(inst, maid)
	end
end

function Tracker.start(maid)
	for _, inst in ipairs(workspace:GetDescendants()) do
		tryHook(inst, maid)
	end

	maid:Give(workspace.DescendantAdded:Connect(function(inst)
		tryHook(inst, maid)
	end))

	maid:Give(function()
		for _, connections in pairs(hooked) do
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
		table.clear(hooked)
	end)
end

return Tracker

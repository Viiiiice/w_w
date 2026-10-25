local Services = require("Util/Services")
local Config = require("Config")
local Maid = require("Util/Maid")
local Signal = require("Util/Signal")
local Logger = require("Features/AnimationLogger/Logger")

local Players = Services.Players

local Tracker = {
	Played = Signal.new(),
}

local characters = {}
local folderMaid

local function ownerOf(model)
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

local function onTrack(model, track)
	local anim = track.Animation
	if anim then
		Logger.log(anim.AnimationId, nameOf(track), ownerOf(model))
		Tracker.Played:Fire(model, track, anim.AnimationId)
	end
end

local function hookAnimator(model, charMaid, animators, animator)
	if animators[animator] then
		return
	end

	local animMaid = charMaid:Extend()
	animators[animator] = animMaid

	animMaid:Connect(animator.AnimationPlayed, function(track)
		onTrack(model, track)
	end)
	animMaid:Connect(animator.AncestryChanged, function()
		if not animator:IsDescendantOf(model) then
			animators[animator] = nil
			charMaid:Remove(animMaid)
		end
	end)

	local ok, playing = pcall(animator.GetPlayingAnimationTracks, animator)
	if ok then
		for _, track in ipairs(playing) do
			onTrack(model, track)
		end
	end
end

local function unhookCharacter(model)
	local charMaid = characters[model]
	if charMaid then
		characters[model] = nil
		charMaid:Clean()
	end
end

local function hookCharacter(model)
	if characters[model] or not model:IsA("Model") then
		return
	end

	local charMaid = Maid.new()
	local animators = {}
	characters[model] = charMaid
	charMaid:Give(function()
		table.clear(animators)
	end)

	charMaid:Connect(model.DescendantAdded, function(inst)
		if inst:IsA("Animator") then
			hookAnimator(model, charMaid, animators, inst)
		end
	end)

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("Animator") then
			hookAnimator(model, charMaid, animators, inst)
		end
	end
end

local function unhookAll()
	for model in pairs(characters) do
		unhookCharacter(model)
	end
end

local function watchFolder(folder)
	if folderMaid then
		folderMaid:Clean()
	end
	unhookAll()
	folderMaid = Maid.new()

	folderMaid:Connect(folder.ChildAdded, hookCharacter)
	folderMaid:Connect(folder.ChildRemoved, unhookCharacter)
	folderMaid:Connect(folder.AncestryChanged, function()
		if folder.Parent ~= workspace then
			folderMaid:Clean()
			unhookAll()
		end
	end)

	for _, model in ipairs(folder:GetChildren()) do
		hookCharacter(model)
	end
end

function Tracker.folder()
	return workspace:FindFirstChild(Config.AnimationLogger.ScanFolder)
end

function Tracker.start(maid)
	local name = Config.AnimationLogger.ScanFolder

	maid:Give(workspace.ChildAdded:Connect(function(child)
		if child.Name == name then
			watchFolder(child)
		end
	end))

	local folder = Tracker.folder()
	if folder then
		watchFolder(folder)
	end

	maid:Give(function()
		if folderMaid then
			folderMaid:Clean()
			folderMaid = nil
		end
		unhookAll()
	end)
end

return Tracker

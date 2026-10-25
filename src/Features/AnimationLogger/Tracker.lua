local Services = require("Util/Services")
local Config = require("Config")
local Maid = require("Util/Maid")
local Signal = require("Util/Signal")
local Logger = require("Features/AnimationLogger/Logger")

local Players = Services.Players
local LocalPlayer = Players.LocalPlayer

local Tracker = {
	Played = Signal.new(),
	damagedAt = {},
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
		Tracker.damagedAt[model] = nil
		charMaid:Clean()
	end
end

local function hookHumanoid(model, charMaid, humanoid)
	local last = humanoid.Health
	charMaid:Connect(humanoid.HealthChanged, function(health)
		if health < last - 0.01 then
			local list = Tracker.damagedAt[model]
			if not list then
				list = {}
				Tracker.damagedAt[model] = list
			end
			table.insert(list, os.clock())
			if #list > 4 then
				table.remove(list, 1)
			end
		end
		last = health
	end)
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

	local function check(inst)
		if inst:IsA("Animator") then
			hookAnimator(model, charMaid, animators, inst)
		elseif inst:IsA("Humanoid") and inst.Parent == model then
			hookHumanoid(model, charMaid, inst)
		end
	end

	charMaid:Connect(model.DescendantAdded, check)
	for _, inst in ipairs(model:GetDescendants()) do
		check(inst)
	end
end

local function unhookAll()
	for model in pairs(characters) do
		unhookCharacter(model)
	end
end

local function isCharacter(model)
	return model:IsA("Model")
		and (
			Players:GetPlayerFromCharacter(model) ~= nil
			or model:FindFirstChildOfClass("Humanoid") ~= nil
			or model:FindFirstChildOfClass("AnimationController") ~= nil
		)
end

local function tryHookChild(folder, model)
	if folder ~= workspace or isCharacter(model) then
		hookCharacter(model)
	end
end

local function watchFolder(folder)
	if folder == Tracker.current then
		return
	end
	if folderMaid then
		folderMaid:Clean()
	end
	unhookAll()
	Tracker.current = folder
	folderMaid = Maid.new()
	if not folder then
		return
	end

	folderMaid:Connect(folder.ChildAdded, function(model)
		if folder == workspace then
			task.defer(tryHookChild, folder, model)
		else
			hookCharacter(model)
		end
	end)
	folderMaid:Connect(folder.ChildRemoved, unhookCharacter)
	folderMaid:Connect(folder.AncestryChanged, function()
		if not folder:IsDescendantOf(game) then
			watchFolder(nil)
		end
	end)

	for _, model in ipairs(folder:GetChildren()) do
		tryHookChild(folder, model)
	end
end

local function findFolder()
	local name = Config.AnimationLogger.ScanFolder
	if name and name ~= "" and name ~= "Auto" then
		return workspace:FindFirstChild(name)
	end
	local character = LocalPlayer.Character
	local parent = character and character.Parent
	if parent and parent:IsDescendantOf(workspace) or parent == workspace then
		return parent
	end
end

function Tracker.folder()
	return Tracker.current or findFolder()
end

function Tracker.start(maid)
	local function update()
		local folder = findFolder()
		if folder then
			watchFolder(folder)
		end
	end

	local charMaid = maid:Extend()
	local function onCharacter(character)
		charMaid:Clean()
		if character then
			charMaid:Connect(character.AncestryChanged, function()
				task.defer(update)
			end)
		end
		task.defer(update)
	end

	maid:Connect(LocalPlayer.CharacterAdded, onCharacter)
	maid:Connect(workspace.ChildAdded, function(child)
		if not Tracker.current then
			task.defer(update)
		elseif child.Name == Config.AnimationLogger.ScanFolder then
			task.defer(update)
		end
	end)
	onCharacter(LocalPlayer.Character)
	update()

	maid:Give(function()
		watchFolder(nil)
		if folderMaid then
			folderMaid:Clean()
			folderMaid = nil
		end
		Tracker.current = nil
	end)
end

return Tracker

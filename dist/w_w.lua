-- w_w - bundled build, do not edit by hand.
-- Source lives in src/; rebuild with: python build.py
local __modules, __cache = {}, {}
local function require(name)
	local cached = __cache[name]
	if cached ~= nil then
		return cached
	end
	local loader = __modules[name]
	if not loader then
		error("module not found: " .. tostring(name), 2)
	end
	local result = loader()
	if result == nil then
		result = true
	end
	__cache[name] = result
	return result
end

__modules["Config"] = function()
-- Tweak these without touching the rest of the code.
return {
	Title = "w_w",
	Version = "0.1.0",
	ToggleKey = Enum.KeyCode.RightControl,
	WindowSize = UDim2.fromOffset(600, 480),
	Theme = "Dark",

	-- inside the executor's workspace directory
	RootFolder = "w_w",
	ConfigFolder = "w_w/config",

	Fluent = {
		Library = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua",
		SaveManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
		InterfaceManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",
	},

	AnimationLogger = {
		SaveFolder = "w_w/animations",
		-- the dropdown rebuilds its whole list on change, so cap it and throttle it
		MaxDropdownItems = 200,
		RefreshInterval = 0.5,
	},
}
end

__modules["Features/AnimationLogger/Exporter"] = function()
-- Turns entries into text and writes them to the executor's workspace folder.
local Config = require("Config")

local Exporter = {}

function Exporter.toText(entries)
	local lines = {}
	for _, e in ipairs(entries) do
		table.insert(
			lines,
			string.format("%s | rbxassetid://%s | %s", e.name, e.id, table.concat(e.ownerList, ", "))
		)
	end
	return table.concat(lines, "\n")
end

-- Returns ok, pathOrError
function Exporter.save(entries)
	if not writefile then
		return false, "writefile is not available"
	end
	local folder = Config.AnimationLogger.SaveFolder
	if makefolder and not (isfolder and isfolder(folder)) then
		pcall(makefolder, folder)
	end
	local path = string.format("%s/%d_%s.txt", folder, game.PlaceId, os.date("%Y%m%d_%H%M%S"))
	local ok, err = pcall(writefile, path, Exporter.toText(entries))
	if not ok then
		return false, tostring(err)
	end
	return true, path
end

return Exporter
end

__modules["Features/AnimationLogger/Logger"] = function()
-- Central store of every animation seen. Everything else reads from here.
local Signal = require("Util/Signal")

local Logger = {
	paused = false,
	entries = {}, -- [id] = Entry
	count = 0,

	Added = Signal.new(), -- (entry) first time an id is seen
	Updated = Signal.new(), -- (entry) seen again / new owner
	Cleared = Signal.new(),
}

--[[ Entry:
	id        string   numeric asset id
	name      string   best name we've found
	owners    {[name]=true}
	ownerList {string}
	plays     number
	lastSeen  number   os.clock() of last play
]]

local GENERIC_NAMES = { [""] = true, Animation = true, AnimationTrack = true }

local function cleanId(raw)
	return tostring(raw):match("%d+")
end

function Logger.log(rawId, name, owner)
	if Logger.paused then
		return nil, false
	end
	local id = cleanId(rawId)
	if not id or id == "0" then
		return nil, false
	end
	owner = owner or "?"

	local entry = Logger.entries[id]
	local isNew = entry == nil
	if isNew then
		entry = { id = id, name = name or "Animation", owners = {}, ownerList = {}, plays = 0 }
		Logger.entries[id] = entry
		Logger.count += 1
	elseif GENERIC_NAMES[entry.name] and name and not GENERIC_NAMES[name] then
		entry.name = name
	end

	if not entry.owners[owner] then
		entry.owners[owner] = true
		table.insert(entry.ownerList, owner)
	end
	entry.plays += 1
	entry.lastSeen = os.clock()

	if isNew then
		Logger.Added:Fire(entry)
	else
		Logger.Updated:Fire(entry)
	end
	return entry, isNew
end

function Logger.get(id)
	return Logger.entries[id]
end

-- filter = { text = "lowercase search", onlyOwner = "PlayerName" | nil }
-- Returns entries sorted most-recently-played first.
function Logger.list(filter)
	filter = filter or {}
	local text = filter.text or ""
	local out = {}
	for _, e in pairs(Logger.entries) do
		local ok = true
		if filter.onlyOwner and not e.owners[filter.onlyOwner] then
			ok = false
		end
		if ok and text ~= "" then
			local hay = (e.name .. " " .. e.id .. " " .. table.concat(e.ownerList, " ")):lower()
			ok = hay:find(text, 1, true) ~= nil
		end
		if ok then
			table.insert(out, e)
		end
	end
	table.sort(out, function(a, b)
		return a.lastSeen > b.lastSeen
	end)
	return out
end

function Logger.clear()
	table.clear(Logger.entries)
	Logger.count = 0
	Logger.Cleared:Fire()
end

return Logger
end

__modules["Features/AnimationLogger/Preview"] = function()
-- Plays a logged animation on the local character.
local Services = require("Util/Services")

local LocalPlayer = Services.Players.LocalPlayer

local Preview = {}

local current

function Preview.stop()
	if current then
		pcall(current.Stop, current)
		current = nil
	end
end

-- Returns ok, errorMessage
function Preview.play(id)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "No character"
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid

	Preview.stop()

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok or not track then
		return false, "Could not load (it may be owned by another game/group)"
	end
	current = track
	track:Play()
	return true
end

return Preview
end

__modules["Features/AnimationLogger/PreviewWindow"] = function()
-- Pop-out window that plays an animation on a rig inside a ViewportFrame.
-- Fluent only supports one window, so this is a small standalone GUI styled to match.
local Services = require("Util/Services")
local Maid = require("Util/Maid")
local Rig = require("Features/AnimationLogger/Rig")

local UserInputService = Services.UserInputService
local RunService = Services.RunService

local PreviewWindow = {}

local THEME = {
	bg = Color3.fromRGB(28, 28, 32),
	bar = Color3.fromRGB(38, 38, 44),
	button = Color3.fromRGB(50, 50, 58),
	accent = Color3.fromRGB(96, 165, 250),
	text = Color3.fromRGB(240, 240, 240),
	sub = Color3.fromRGB(160, 160, 170),
	viewport = Color3.fromRGB(20, 20, 24),
}

local SPEEDS = { 0.25, 0.5, 1, 1.5, 2 }

local gui -- built once, then shown/hidden
local ui = {}
local uiMaid = Maid.new() -- global input connections made by build()
local state = {
	entry = nil,
	rigKind = "Me",
	rig = nil,
	track = nil,
	playing = true,
	looped = true,
	speedIndex = 3,
	yaw = math.pi, -- start looking at the rig's face
	pitch = 0.15,
	zoom = 8,
	defaultZoom = 8,
	height = 0,
}

------------------------------------------------------------ ui helpers
local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 6) })
end

local function button(text, width, parent)
	return new("TextButton", {
		Size = UDim2.fromOffset(width, 26),
		BackgroundColor3 = THEME.button,
		Text = text,
		TextColor3 = THEME.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		AutoButtonColor = true,
		Parent = parent,
	}, { corner(5) })
end

local function setStatus(text)
	ui.status.Text = text or ""
end

------------------------------------------------------------ playback
local function speed()
	return SPEEDS[state.speedIndex]
end

local function applySpeed()
	if state.track then
		state.track:AdjustSpeed(state.playing and speed() or 0)
	end
	ui.speed.Text = string.format("%gx", speed())
	ui.play.Text = state.playing and "Pause" or "Play"
end

local function stopTrack()
	if state.track then
		pcall(state.track.Stop, state.track, 0)
		pcall(state.track.Destroy, state.track)
		state.track = nil
	end
end

local function loadTrack(animator)
	stopTrack()
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. state.entry.id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok or not track then
		setStatus("Couldn't load this animation (it may belong to another game/group).")
		return
	end
	track.Looped = state.looped
	track:Play(0)
	state.track = track
	applySpeed()
end

local function resetCamera()
	state.yaw, state.pitch, state.zoom = math.pi, 0.15, state.defaultZoom
end

local function rebuildRig()
	stopTrack()
	if state.rig then
		state.rig:Destroy()
		state.rig = nil
	end
	if not state.entry then
		return
	end
	setStatus("")

	local owner = state.entry.ownerList[1]
	local rig, animator = Rig.build(Rig.findSource(state.rigKind, owner))
	if not rig then
		setStatus(animator) -- error message
		return
	end
	rig.Parent = ui.world
	state.rig = rig

	-- frame the camera around the rig's size
	local size = rig:GetExtentsSize()
	state.height = 0
	state.defaultZoom = math.max(size.Y, size.X) * 1.6 + 2
	resetCamera()

	loadTrack(animator)
end

------------------------------------------------------------ build
local function build()
	gui = new("ScreenGui", {
		Name = "w_wPreview",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})

	local main = new("Frame", {
		Size = UDim2.fromOffset(320, 400),
		Position = UDim2.new(1, -340, 0.5, -200),
		BackgroundColor3 = THEME.bg,
		BorderSizePixel = 0,
		Parent = gui,
	}, { corner(8), new("UIStroke", { Color = THEME.bar, Thickness = 1 }) })

	-- title bar (drag handle)
	local bar = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = THEME.bar,
		BorderSizePixel = 0,
		Parent = main,
	}, { corner(8) })
	ui.title = new("TextLabel", {
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = "Preview",
		TextColor3 = THEME.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	local close = button("X", 24, bar)
	close.Size = UDim2.fromOffset(24, 22)
	close.Position = UDim2.new(1, -30, 0, 5)
	close.MouseButton1Click:Connect(PreviewWindow.close)

	do
		local dragging, start, startPos
		bar.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging, start, startPos = true, input.Position, main.Position
			end
		end)
		uiMaid:Give(UserInputService.InputChanged:Connect(function(input)
			if
				dragging
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				local d = input.Position - start
				main.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + d.X,
					startPos.Y.Scale,
					startPos.Y.Offset + d.Y
				)
			end
		end))
		uiMaid:Give(UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
			end
		end))
	end

	-- 3D view
	ui.viewport = new("ViewportFrame", {
		Size = UDim2.new(1, -16, 0, 250),
		Position = UDim2.fromOffset(8, 40),
		BackgroundColor3 = THEME.viewport,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = main,
	}, { corner(6) })
	ui.world = new("WorldModel", { Parent = ui.viewport })
	ui.camera = new("Camera", { FieldOfView = 40, Parent = ui.viewport })
	ui.viewport.CurrentCamera = ui.camera
	new("TextLabel", {
		Size = UDim2.new(1, -8, 0, 14),
		Position = UDim2.new(0, 4, 1, -16),
		BackgroundTransparency = 1,
		Text = "drag to rotate • scroll to zoom",
		TextColor3 = THEME.sub,
		TextTransparency = 0.3,
		Font = Enum.Font.Gotham,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.viewport,
	})

	-- orbit + zoom
	do
		local orbiting = false
		ui.viewport.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				orbiting = true
			end
		end)
		ui.viewport.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				state.zoom = math.clamp(state.zoom - input.Position.Z * 0.8, 2, 40)
			end
		end)
		uiMaid:Give(UserInputService.InputChanged:Connect(function(input)
			if
				orbiting
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				state.yaw -= input.Delta.X * 0.01
				state.pitch = math.clamp(state.pitch + input.Delta.Y * 0.01, -1.2, 1.2)
			end
		end))
		uiMaid:Give(UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				orbiting = false
			end
		end))
	end

	-- timeline (click to seek)
	ui.timeline = new("TextButton", {
		Size = UDim2.new(1, -16, 0, 8),
		Position = UDim2.fromOffset(8, 298),
		BackgroundColor3 = THEME.button,
		Text = "",
		AutoButtonColor = false,
		Parent = main,
	}, { corner(4) })
	ui.progress = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.accent,
		BorderSizePixel = 0,
		Parent = ui.timeline,
	}, { corner(4) })
	ui.timeline.MouseButton1Down:Connect(function(x)
		local track = state.track
		if track and track.Length > 0 then
			local frac = math.clamp((x - ui.timeline.AbsolutePosition.X) / ui.timeline.AbsoluteSize.X, 0, 1)
			track.TimePosition = frac * track.Length
		end
	end)

	-- controls row 1: playback
	local row1 = new("Frame", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 314),
		BackgroundTransparency = 1,
		Parent = main,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	ui.play = button("Pause", 58, row1)
	ui.play.MouseButton1Click:Connect(function()
		state.playing = not state.playing
		if state.playing and state.track and not state.track.IsPlaying then
			state.track:Play(0)
		end
		applySpeed()
	end)

	local restart = button("Restart", 58, row1)
	restart.MouseButton1Click:Connect(function()
		if state.track then
			state.playing = true
			state.track:Play(0)
			state.track.TimePosition = 0
			applySpeed()
		end
	end)

	local slower = button("-", 26, row1)
	ui.speed = new("TextLabel", {
		Size = UDim2.fromOffset(40, 26),
		BackgroundTransparency = 1,
		Text = "1x",
		TextColor3 = THEME.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		Parent = row1,
	})
	local faster = button("+", 26, row1)
	slower.MouseButton1Click:Connect(function()
		state.speedIndex = math.max(1, state.speedIndex - 1)
		applySpeed()
	end)
	faster.MouseButton1Click:Connect(function()
		state.speedIndex = math.min(#SPEEDS, state.speedIndex + 1)
		applySpeed()
	end)

	local loop = button("Loop: on", 62, row1)
	loop.MouseButton1Click:Connect(function()
		state.looped = not state.looped
		loop.Text = state.looped and "Loop: on" or "Loop: off"
		if state.track then
			state.track.Looped = state.looped
		end
	end)

	-- controls row 2: rig + camera
	local row2 = new("Frame", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 346),
		BackgroundTransparency = 1,
		Parent = main,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	local rigButton = button("Rig: my character", 150, row2)
	rigButton.MouseButton1Click:Connect(function()
		state.rigKind = state.rigKind == "Me" and "Owner" or "Me"
		rigButton.Text = state.rigKind == "Me" and "Rig: my character" or "Rig: who played it"
		rebuildRig()
	end)

	local camButton = button("Reset camera", 96, row2)
	camButton.MouseButton1Click:Connect(resetCamera)

	ui.status = new("TextLabel", {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 376),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(250, 160, 120),
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = main,
	})

	gui.Parent = (gethui and gethui()) or Services.CoreGui
end

------------------------------------------------------------ per-frame
local function step()
	local cam = ui.camera
	local center = Vector3.new(0, state.height, 0)
	cam.CFrame = CFrame.new(center)
		* CFrame.Angles(0, state.yaw, 0)
		* CFrame.Angles(-state.pitch, 0, 0)
		* CFrame.new(0, 0, state.zoom)

	local track = state.track
	if track and track.Length > 0 then
		ui.progress.Size = UDim2.fromScale(math.clamp(track.TimePosition / track.Length, 0, 1), 1)
	else
		ui.progress.Size = UDim2.fromScale(0, 1)
	end
end

------------------------------------------------------------ public
function PreviewWindow.isOpen()
	return gui ~= nil and gui.Enabled
end

-- Opens the window (or switches it) to this logger entry.
function PreviewWindow.show(entry)
	if not gui then
		build()
		state.render = RunService.RenderStepped:Connect(step)
	end
	state.entry = entry
	ui.title.Text = string.format("%s  [%s]", entry.name, entry.id)
	gui.Enabled = true
	state.playing = true
	rebuildRig()
end

function PreviewWindow.close()
	if not gui then
		return
	end
	gui.Enabled = false
	stopTrack()
	if state.rig then
		state.rig:Destroy()
		state.rig = nil
	end
end

-- Full teardown, used when the script unloads.
function PreviewWindow.destroy()
	PreviewWindow.close()
	uiMaid:Clean()
	if state.render then
		state.render:Disconnect()
		state.render = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
end

return PreviewWindow
end

__modules["Features/AnimationLogger/Rig"] = function()
-- Builds a clean, script-free copy of a character to animate inside a ViewportFrame.
local Services = require("Util/Services")

local Players = Services.Players
local LocalPlayer = Players.LocalPlayer

local Rig = {}

-- Junk that shouldn't come along (scripts would run, sounds would play).
local STRIP = { "LuaSourceContainer", "Sound", "ForceField", "BillboardGui", "ParticleEmitter", "Trail" }

local function shouldStrip(inst)
	for _, class in ipairs(STRIP) do
		if inst:IsA(class) then
			return true
		end
	end
	return false
end

-- Finds the model to copy. kind is "Me" or "Owner".
function Rig.findSource(kind, ownerName)
	if kind == "Owner" and ownerName and not ownerName:find("^scan:") then
		local player = Players:FindFirstChild(ownerName)
		if player and player:IsA("Player") and player.Character then
			return player.Character
		end
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst:IsA("Model") and inst.Name == ownerName and inst:FindFirstChildOfClass("Humanoid") then
				return inst
			end
		end
	end
	return LocalPlayer.Character
end

-- Returns rig, animator, root  (or nil, errorMessage)
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

	-- the root stays put; Motor6Ds move everything else
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
end

__modules["Features/AnimationLogger/Scanner"] = function()
-- One-shot scan for Animation objects that exist but aren't necessarily playing.
local Logger = require("Features/AnimationLogger/Logger")

local Scanner = {}

-- Returns how many new ids were found.
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
		for _, inst in ipairs(list) do
			pcall(check, inst)
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
end

__modules["Features/AnimationLogger/Tracker"] = function()
-- Hooks every Animator in workspace and feeds played tracks into the Logger.
local Services = require("Util/Services")
local Logger = require("Features/AnimationLogger/Logger")

local Players = Services.Players

local Tracker = {}

local hooked = setmetatable({}, { __mode = "k" })

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
	hooked[animator] = true

	maid:Give(animator.AnimationPlayed:Connect(function(track)
		onTrack(animator, track)
	end))

	-- catch whatever was already playing
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
		table.clear(hooked)
	end)
end

return Tracker
end

__modules["Features/AnimationLogger"] = function()
-- Animation Logger feature: live log, selected-animation actions, tools, 3D preview.
local Services = require("Util/Services")
local Clipboard = require("Util/Clipboard")
local Config = require("Config")
local Logger = require("Features/AnimationLogger/Logger")
local Scanner = require("Features/AnimationLogger/Scanner")
local Preview = require("Features/AnimationLogger/Preview")
local Exporter = require("Features/AnimationLogger/Exporter")
local Tracker = require("Features/AnimationLogger/Tracker")
local PreviewWindow = require("Features/AnimationLogger/PreviewWindow")

local LocalPlayer = Services.Players.LocalPlayer

local AnimationLogger = {
	Title = "Animations",
	Icon = "activity",
	-- options SaveManager shouldn't save
	IgnoreOptions = { "Search", "AnimList" },
}

local function label(entry)
	-- the id keeps labels unique even when names repeat
	return string.format("%s  [%s]", entry.name, entry.id)
end

function AnimationLogger.build(Tab, ctx)
	local Window, Fluent, maid = ctx.Window, ctx.Fluent, ctx.maid
	local Options = Fluent.Options

	local state = {
		search = "",
		onlyMe = false,
		notify = false,
		selectedId = nil,
		labelToId = {},
		dirty = true,
	}

	local function notify(title, content)
		Fluent:Notify({ Title = title, Content = content, Duration = 3 })
	end

	local function currentList()
		return Logger.list({
			text = state.search,
			onlyOwner = state.onlyMe and LocalPlayer.Name or nil,
		})
	end

	local function selected()
		return state.selectedId and Logger.get(state.selectedId)
	end

	------------------------------------------------------------ filters
	local Filters = Tab:AddSection("Filters")

	Filters:AddInput("Search", {
		Title = "Search",
		Placeholder = "name, id or player...",
		Default = "",
		Numeric = false,
		Finished = false,
		Callback = function(text)
			state.search = text:lower()
			state.dirty = true
		end,
	})

	Filters:AddToggle("OnlyMe", { Title = "Only my animations", Default = false })
	Options.OnlyMe:OnChanged(function(value)
		state.onlyMe = value
		state.dirty = true
	end)

	Filters:AddToggle("Paused", { Title = "Pause logging", Default = false })
	Options.Paused:OnChanged(function(value)
		Logger.paused = value
	end)

	Filters:AddToggle("NotifyNew", { Title = "Notify on new animation", Default = false })
	Options.NotifyNew:OnChanged(function(value)
		state.notify = value
	end)

	------------------------------------------------------------ log
	local Log = Tab:AddSection("Animations")

	local summary =
		Log:AddParagraph({ Title = "0 logged", Content = "Animations show up here as they play." })

	local dropdown = Log:AddDropdown("AnimList", {
		Title = "Logged animations",
		Description = "Most recently played first",
		Values = {},
		Multi = false,
	})

	local details = Log:AddParagraph({ Title = "Nothing selected", Content = "Pick an animation above." })

	local function showDetails()
		local e = selected()
		if not e then
			details:SetTitle("Nothing selected")
			details:SetDesc("Pick an animation above.")
			return
		end
		details:SetTitle(e.name)
		details:SetDesc(
			string.format(
				"ID: rbxassetid://%s\nPlayed by: %s\nTimes played: %d",
				e.id,
				table.concat(e.ownerList, ", "),
				e.plays
			)
		)
	end

	Options.AnimList:OnChanged(function(value)
		local previous = state.selectedId
		state.selectedId = value and state.labelToId[value] or state.selectedId
		showDetails()
		-- keep the pop-out in sync with the selection
		local e = selected()
		if e and e.id ~= previous and PreviewWindow.isOpen() then
			PreviewWindow.show(e)
		end
	end)

	local function refresh()
		local list = currentList()
		local values, labelToId = {}, {}
		for i, e in ipairs(list) do
			if i > Config.AnimationLogger.MaxDropdownItems then
				break
			end
			local l = label(e)
			table.insert(values, l)
			labelToId[l] = e.id
		end
		state.labelToId = labelToId
		dropdown:SetValues(values)
		summary:SetTitle(string.format("%d logged  •  %d shown", Logger.count, #list))
		summary:SetDesc(Logger.paused and "Logging is paused." or "Listening for animations...")
		showDetails()
	end

	------------------------------------------------------------ actions
	local Actions = Tab:AddSection("Selected animation")

	local function withSelected(fn)
		return function()
			local e = selected()
			if not e then
				notify("No animation selected", "Pick one from the list first.")
				return
			end
			fn(e)
		end
	end

	Actions:AddButton({
		Title = "Copy ID",
		Description = "Copies rbxassetid://<id>",
		Callback = withSelected(function(e)
			local ok = Clipboard.copy("rbxassetid://" .. e.id)
			notify(ok and "Copied" or "Clipboard unavailable", e.id)
		end),
	})

	Actions:AddButton({
		Title = "Copy number only",
		Callback = withSelected(function(e)
			local ok = Clipboard.copy(e.id)
			notify(ok and "Copied" or "Clipboard unavailable", e.id)
		end),
	})

	Actions:AddButton({
		Title = "Play on me",
		Description = "Preview it on your own character",
		Callback = withSelected(function(e)
			local ok, err = Preview.play(e.id)
			if not ok then
				notify("Couldn't play", err)
			end
		end),
	})

	Actions:AddButton({ Title = "Stop preview", Callback = Preview.stop })

	Actions:AddButton({
		Title = "Open preview window",
		Description = "Pop-out 3D rig that plays the animation",
		Callback = withSelected(PreviewWindow.show),
	})

	------------------------------------------------------------ tools
	local Tools = Tab:AddSection("Tools")

	Tools:AddButton({
		Title = "Scan game",
		Description = "Find Animation objects that exist but aren't playing",
		Callback = function()
			local found = Scanner.scan()
			notify("Scan finished", string.format("%d new animation(s) found", found))
		end,
	})

	Tools:AddButton({
		Title = "Copy all shown",
		Callback = function()
			local list = currentList()
			local ok = Clipboard.copy(Exporter.toText(list))
			notify(ok and "Copied" or "Clipboard unavailable", string.format("%d animation(s)", #list))
		end,
	})

	Tools:AddButton({
		Title = "Save to file",
		Description = "Writes to workspace/" .. Config.AnimationLogger.SaveFolder,
		Callback = function()
			local ok, result = Exporter.save(currentList())
			notify(ok and "Saved" or "Save failed", result)
		end,
	})

	Tools:AddButton({
		Title = "Clear log",
		Callback = function()
			Window:Dialog({
				Title = "Clear log?",
				Content = "This removes every logged animation.",
				Buttons = {
					{ Title = "Clear", Callback = Logger.clear },
					{ Title = "Cancel", Callback = function() end },
				},
			})
		end,
	})

	------------------------------------------------------------ live updates
	maid:Give(Logger.Added:Connect(function(entry)
		state.dirty = true
		if state.notify then
			notify("New animation", label(entry))
		end
	end))
	maid:Give(Logger.Updated:Connect(function()
		state.dirty = true
	end))
	maid:Give(Logger.Cleared:Connect(function()
		state.selectedId = nil
		state.dirty = true
	end))

	-- throttle: rebuilding the dropdown on every play would lag
	task.spawn(function()
		while not Fluent.Unloaded do
			if state.dirty then
				state.dirty = false
				pcall(refresh)
			end
			task.wait(Config.AnimationLogger.RefreshInterval)
		end
	end)

	Tracker.start(maid)
	maid:Give(PreviewWindow.destroy)
end

return AnimationLogger
end

__modules["Features/List"] = function()
-- Every feature, in tab order. To add one, make a folder in Features/ with an
-- init.lua that returns { Title, Icon, build = function(Tab, ctx) end } and list it here.
return {
	require("Features/AnimationLogger"),
}
end

__modules["UI/HomeTab"] = function()
local Config = require("Config")

local HomeTab = {}

function HomeTab.build(Window, features)
	local Tab = Window:AddTab({ Title = "Home", Icon = "home" })

	local executor = "unknown"
	if identifyexecutor then
		local ok, name, version = pcall(identifyexecutor)
		if ok and name then
			executor = tostring(name) .. (version and (" " .. tostring(version)) or "")
		end
	end

	Tab:AddParagraph({
		Title = Config.Title .. "  v" .. Config.Version,
		Content = string.format(
			"Executor: %s\nPlace: %d\nToggle UI: %s",
			executor,
			game.PlaceId,
			Config.ToggleKey.Name
		),
	})

	local names = {}
	for _, feature in ipairs(features) do
		table.insert(names, "• " .. feature.Title)
	end
	Tab:AddParagraph({ Title = "Features", Content = table.concat(names, "\n") })

	return Tab
end

return HomeTab
end

__modules["UI/Library"] = function()
-- Downloads Fluent and its two addons.
local Config = require("Config")

local function load(url)
	return loadstring(game:HttpGet(url))()
end

return {
	Fluent = load(Config.Fluent.Library),
	SaveManager = load(Config.Fluent.SaveManager),
	InterfaceManager = load(Config.Fluent.InterfaceManager),
}
end

__modules["UI/SettingsTab"] = function()
-- Fluent's built-in theme + config saving sections.
local Config = require("Config")

local SettingsTab = {}

function SettingsTab.build(Window, lib, features)
	local Tab = Window:AddTab({ Title = "Settings", Icon = "settings" })

	lib.SaveManager:SetLibrary(lib.Fluent)
	lib.InterfaceManager:SetLibrary(lib.Fluent)

	lib.SaveManager:IgnoreThemeSettings()
	local ignore = {}
	for _, feature in ipairs(features) do
		for _, option in ipairs(feature.IgnoreOptions or {}) do
			table.insert(ignore, option)
		end
	end
	lib.SaveManager:SetIgnoreIndexes(ignore)

	lib.InterfaceManager:SetFolder(Config.ConfigFolder)
	lib.SaveManager:SetFolder(Config.ConfigFolder .. "/" .. tostring(game.PlaceId))

	lib.InterfaceManager:BuildInterfaceSection(Tab)
	lib.SaveManager:BuildConfigSection(Tab)

	return Tab
end

return SettingsTab
end

__modules["Util/Clipboard"] = function()
local Clipboard = {}

local setter = setclipboard or toclipboard

function Clipboard.isSupported()
	return setter ~= nil
end

function Clipboard.copy(text)
	if not setter then
		return false
	end
	return (pcall(setter, text))
end

return Clipboard
end

__modules["Util/Maid"] = function()
-- Collects connections / instances / functions and cleans them all at once.
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
end

__modules["Util/Services"] = function()
-- Cached, cloneref'd services so the rest of the code can just index this table.
local Services = {}

local cloneref = cloneref or function(x)
	return x
end

return setmetatable(Services, {
	__index = function(self, name)
		local service = cloneref(game:GetService(name))
		rawset(self, name, service)
		return service
	end,
})
end

__modules["Util/Signal"] = function()
-- Minimal pure-Lua signal (no BindableEvents, so args aren't copied).
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
		task.spawn(fn, ...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
end

-- entry: src/init.lua
do
local Config = require("Config")
local Maid = require("Util/Maid")
local Features = require("Features/List")
local HomeTab = require("UI/HomeTab")
local SettingsTab = require("UI/SettingsTab")

local env = getgenv and getgenv() or _G
if env.__w_wUnload then
	pcall(env.__w_wUnload)
end

local lib = require("UI/Library")
local Fluent = lib.Fluent
local maid = Maid.new()

local Window = Fluent:CreateWindow({
	Title = Config.Title,
	SubTitle = "v" .. Config.Version,
	TabWidth = 160,
	Size = Config.WindowSize,
	Acrylic = false,
	Theme = Config.Theme,
	MinimizeKey = Config.ToggleKey,
})

local ctx = { Window = Window, Fluent = Fluent, maid = maid }

HomeTab.build(Window, Features)
for _, feature in ipairs(Features) do
	local Tab = Window:AddTab({ Title = feature.Title, Icon = feature.Icon })
	local ok, err = pcall(feature.build, Tab, ctx)
	if not ok then
		Fluent:Notify({ Title = feature.Title .. " failed to load", Content = tostring(err), Duration = 8 })
	end
end
SettingsTab.build(Window, lib, Features)
Window:SelectTab(1)

local function unload()
	maid:Clean()
	if not Fluent.Unloaded then
		Fluent:Destroy()
	end
	env.__w_wUnload = nil
end
env.__w_wUnload = unload

task.spawn(function()
	while not Fluent.Unloaded do
		task.wait(1)
	end
	maid:Clean()
end)

Fluent:Notify({
	Title = Config.Title,
	Content = "Loaded. Press " .. Config.ToggleKey.Name .. " to hide/show.",
	Duration = 5,
})

lib.SaveManager:LoadAutoloadConfig()
end

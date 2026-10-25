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
return {
	Title = "w_w",
	Version = "0.1.0",
	ToggleKey = Enum.KeyCode.RightControl,
	WindowSize = UDim2.fromOffset(600, 480),
	Theme = "Dark",

	RootFolder = "w_w",
	ConfigFolder = "w_w/config",

	Fluent = {
		Library = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua",
		SaveManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
		InterfaceManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",
	},

	AnimationLogger = {
		SaveFolder = "w_w/animations",
		ScanFolder = "Alive",
		MaxDropdownItems = 200,
		RefreshInterval = 0.5,
	},

	AutoReact = {
		Folder = "w_w/reactions",
		Range = 18,
		Lead = 0.08,
		BlockHold = 0.45,
		LearnWindow = 1.5,
		Cooldown = 0.3,
		MaxSamples = 8,
		Keys = { Parry = "F", Block = "F", Dash = "Q" },
	},
}
end

__modules["Features/AnimationLogger/Exporter"] = function()
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
local Signal = require("Util/Signal")

local Logger = {
	paused = false,
	entries = {},
	count = 0,
	_order = 0,

	Added = Signal.new(),
	Updated = Signal.new(),
	Cleared = Signal.new(),
}

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
	local changed = false
	if isNew then
		Logger._order += 1
		entry = {
			id = id,
			name = name or "Animation",
			owners = {},
			ownerList = {},
			plays = 0,
			order = Logger._order,
		}
		Logger.entries[id] = entry
		Logger.count += 1
	elseif GENERIC_NAMES[entry.name] and name and not GENERIC_NAMES[name] then
		entry.name = name
		changed = true
	end

	if not entry.owners[owner] then
		entry.owners[owner] = true
		table.insert(entry.ownerList, owner)
		changed = true
	end

	entry.plays += 1
	entry.lastSeen = os.clock()

	if isNew then
		Logger.Added:Fire(entry)
	else
		Logger.Updated:Fire(entry, changed)
	end

	return entry, isNew
end

function Logger.get(id)
	return Logger.entries[id]
end

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
		return a.order > b.order
	end)
	return out
end

function Logger.clear()
	table.clear(Logger.entries)
	Logger.count = 0
	Logger._order = 0
	Logger.Cleared:Fire()
end

return Logger
end

__modules["Features/AnimationLogger/Preview"] = function()
local Services = require("Util/Services")

local LocalPlayer = Services.Players.LocalPlayer

local Preview = {}

local current, currentAnimation

function Preview.stop()
	if current then
		pcall(current.Stop, current)
		pcall(current.Destroy, current)
		current = nil
	end
	if currentAnimation then
		currentAnimation:Destroy()
		currentAnimation = nil
	end
end

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
		animation:Destroy()
		return false, "Could not load (it may be owned by another game/group)"
	end

	current, currentAnimation = track, animation
	track:Play()

	return true
end

return Preview
end

__modules["Features/AnimationLogger/PreviewWindow"] = function()
local Services = require("Util/Services")
local Maid = require("Util/Maid")
local Rig = require("Features/AnimationLogger/Rig")
local Logger = require("Features/AnimationLogger/Logger")
local Reactions = require("Features/AutoReact/Reactions")

local UserInputService = Services.UserInputService
local RunService = Services.RunService
local ContextActionService = Services.ContextActionService

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
local MAX_LIST_ITEMS = 200
local LIST_WIDTH = 190
local MIN_SIZE = Vector2.new(320 + LIST_WIDTH, 420)
local MAX_SIZE = Vector2.new(1400, 1000)
local BLOCK_CAMERA_ACTION = "w_wPreviewBlockCamera"

local gui
local ui = {}
local uiMaid = Maid.new()
local state = {
	finished = false,
	entry = nil,
	rigKind = "Me",
	rig = nil,
	track = nil,
	playing = true,
	looped = true,
	speedIndex = 3,
	yaw = math.pi,
	pitch = 0.15,
	zoom = 8,
	defaultZoom = 8,
	height = 0,
	search = "",
	listDirty = true,
	lastListRefresh = 0,
	scrubbing = false,
	orbiting = false,
	cameraBlocked = false,
}

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
	local track, animation = state.track, state.animation
	state.track, state.animation = nil, nil
	if track then
		pcall(track.Stop, track, 0)
		pcall(track.Destroy, track)
	end
	if animation then
		animation:Destroy()
	end
end

local function loadTrack(animator)
	stopTrack()

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. state.entry.id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok or not track then
		animation:Destroy()
		setStatus("Couldn't load this animation (it may belong to another game/group).")
		return
	end

	track.Looped = state.looped
	track.Stopped:Connect(function()
		if state.track == track and not track.Looped and not track.IsPlaying then
			state.finished = true
			state.playing = false
			applySpeed()
		end
	end)
	track:Play(0)
	state.track, state.animation = track, animation
	state.finished = false
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
		setStatus(animator)
		return
	end

	rig.Parent = ui.world
	state.rig = rig

	local size = rig:GetExtentsSize()
	state.height = 0
	state.defaultZoom = math.max(size.Y, size.X) * 1.6 + 2
	resetCamera()

	loadTrack(animator)
end

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function rowFor(i)
	local row = ui.rows[i]
	if row then
		return row
	end

	row = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.button,
		AutoButtonColor = true,
		RichText = true,
		Text = "",
		TextColor3 = THEME.text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = ui.list,
	}, { corner(5), new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
	row.MouseButton1Click:Connect(function()
		local entry = row:GetAttribute("AnimId") and Logger.get(row:GetAttribute("AnimId"))
		if entry then
			PreviewWindow.show(entry)
		end
	end)

	ui.rows[i] = row
	return row
end

local function refreshList()
	state.listDirty = false
	state.lastListRefresh = os.clock()

	local list = Logger.list({ text = state.search })
	local selectedId = state.entry and state.entry.id
	local count = math.min(#list, MAX_LIST_ITEMS)

	for i = 1, count do
		local entry = list[i]
		local row = rowFor(i)
		row.LayoutOrder = i
		row.Visible = true
		row:SetAttribute("AnimId", entry.id)
		row.Text = string.format(
			'<b>%s</b>\n<font size="10" color="#a0a0aa">%s</font>',
			escape(entry.name),
			entry.id
		)
		row.BackgroundColor3 = entry.id == selectedId and THEME.accent or THEME.button
	end
	for i = count + 1, #ui.rows do
		ui.rows[i].Visible = false
	end

	ui.empty.Visible = count == 0
	ui.empty.Text = Logger.count == 0 and "No animations logged yet." or "No matches."
end

local function updateReaction()
	if not ui.reaction then
		return
	end
	local id = state.entry and state.entry.id
	local r = id and Reactions.get(id)
	for action, b in pairs(ui.actionButtons) do
		b.BackgroundColor3 = (r and r.action == action) and THEME.accent or THEME.button
	end
	if not id then
		ui.reaction.Text = "Pick an animation to set a reaction."
	else
		ui.reaction.Text = Reactions.describe(id) .. "  •  scrub to the hit frame, then Set hit here"
	end
end

local function build()
	gui = new("ScreenGui", {
		Name = "w_wPreview",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Enabled = false,
	})

	local main = new("Frame", {
		Size = UDim2.fromOffset(320 + LIST_WIDTH, 460),
		Position = UDim2.new(1, -(340 + LIST_WIDTH), 0.5, -230),
		BackgroundColor3 = THEME.bg,
		BorderSizePixel = 0,
		Parent = gui,
	}, { corner(8), new("UIStroke", { Color = THEME.bar, Thickness = 1 }) })
	ui.main = main

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

	local side = new("Frame", {
		Size = UDim2.new(0, LIST_WIDTH - 8, 1, -48),
		Position = UDim2.fromOffset(8, 40),
		BackgroundColor3 = THEME.bar,
		BorderSizePixel = 0,
		Parent = main,
	}, { corner(6) })

	ui.search = new("TextBox", {
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = THEME.button,
		Text = "",
		PlaceholderText = "Search...",
		PlaceholderColor3 = THEME.sub,
		TextColor3 = THEME.text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = side,
	}, { corner(5), new("UIPadding", { PaddingLeft = UDim.new(0, 6) }) })
	ui.search:GetPropertyChangedSignal("Text"):Connect(function()
		state.search = ui.search.Text:lower()
		state.listDirty = true
	end)

	ui.list = new("ScrollingFrame", {
		Size = UDim2.new(1, -12, 1, -44),
		Position = UDim2.fromOffset(6, 38),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = THEME.accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = side,
	}, { new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }) })

	ui.empty = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "No animations logged yet.",
		TextColor3 = THEME.sub,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextWrapped = true,
		Parent = ui.list,
	})
	ui.rows = {}

	for _, signal in ipairs({ Logger.Added, Logger.Cleared }) do
		uiMaid:Give(signal:Connect(function()
			state.listDirty = true
		end))
	end
	uiMaid:Give(Logger.Updated:Connect(function(_, changed)
		if changed then
			state.listDirty = true
		end
	end))

	local content = new("Frame", {
		Size = UDim2.new(1, -LIST_WIDTH, 1, 0),
		Position = UDim2.fromOffset(LIST_WIDTH, 0),
		BackgroundTransparency = 1,
		Parent = main,
	})

	ui.viewport = new("ViewportFrame", {
		Size = UDim2.new(1, -16, 1, -200),
		Position = UDim2.fromOffset(8, 40),
		BackgroundColor3 = THEME.viewport,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = content,
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

	do
		local ORBIT_BUTTONS = {
			[Enum.UserInputType.MouseButton1] = true,
			[Enum.UserInputType.MouseButton2] = true,
			[Enum.UserInputType.Touch] = true,
		}
		local lastPos
		ui.viewport.InputBegan:Connect(function(input)
			if ORBIT_BUTTONS[input.UserInputType] then
				state.orbiting = true
				lastPos = input.Position
			end
		end)
		ui.viewport.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				state.zoom = math.clamp(state.zoom - input.Position.Z * 0.8, 2, 40)
			end
		end)
		uiMaid:Give(UserInputService.InputChanged:Connect(function(input)
			if
				state.orbiting
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				local delta = input.Position - lastPos
				lastPos = input.Position
				state.yaw -= delta.X * 0.01
				state.pitch = math.clamp(state.pitch + delta.Y * 0.01, -1.2, 1.2)
			end
		end))
		uiMaid:Give(UserInputService.InputEnded:Connect(function(input)
			if ORBIT_BUTTONS[input.UserInputType] then
				state.orbiting = false
			end
		end))
	end

	ui.timeline = new("TextButton", {
		Size = UDim2.new(1, -16, 0, 10),
		Position = UDim2.new(0, 8, 1, -153),
		BackgroundColor3 = THEME.button,
		Text = "",
		AutoButtonColor = false,
		Parent = content,
	}, { corner(4) })
	ui.progress = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.accent,
		BorderSizePixel = 0,
		Parent = ui.timeline,
	}, { corner(4) })
	local function seek(x)
		local track = state.track
		if not track or track.Length <= 0 then
			return
		end
		local frac = math.clamp((x - ui.timeline.AbsolutePosition.X) / ui.timeline.AbsoluteSize.X, 0, 1)
		if not track.IsPlaying then
			track:Play(0)
			state.finished = false
		end
		track.TimePosition = frac * track.Length
		track:AdjustSpeed(0)
	end

	ui.timeline.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			state.scrubbing = true
			seek(input.Position.X)
		end
	end)
	uiMaid:Give(UserInputService.InputChanged:Connect(function(input)
		if
			state.scrubbing
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			seek(input.Position.X)
		end
	end))
	uiMaid:Give(UserInputService.InputEnded:Connect(function(input)
		if
			state.scrubbing
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			state.scrubbing = false
			applySpeed()
		end
	end))

	local row1 = new("Frame", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 1, -136),
		BackgroundTransparency = 1,
		Parent = content,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	ui.play = button("Pause", 58, row1)
	ui.play.MouseButton1Click:Connect(function()
		state.playing = not state.playing
		if state.playing and state.track and not state.track.IsPlaying then
			state.finished = false
			state.track:Play(0)
			state.track.TimePosition = 0
		end
		applySpeed()
	end)

	local restart = button("Restart", 58, row1)
	restart.MouseButton1Click:Connect(function()
		if state.track then
			state.playing = true
			state.finished = false
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

	local row2 = new("Frame", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 1, -104),
		BackgroundTransparency = 1,
		Parent = content,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	local rigButton = button("Rig: my character", 150, row2)
	rigButton.MouseButton1Click:Connect(function()
		state.rigKind = state.rigKind == "Me" and "Owner" or "Me"
		rigButton.Text = state.rigKind == "Me" and "Rig: my character" or "Rig: who played it"
		rebuildRig()
	end)

	local camButton = button("Reset camera", 96, row2)
	camButton.MouseButton1Click:Connect(resetCamera)

	local row3 = new("Frame", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 1, -72),
		BackgroundTransparency = 1,
		Parent = content,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

	ui.actionButtons = {}
	for _, action in ipairs(Reactions.ACTIONS) do
		local b = button(action, 48, row3)
		ui.actionButtons[action] = b
		b.MouseButton1Click:Connect(function()
			if not state.entry then
				return
			end
			local r = Reactions.get(state.entry.id)
			if r and r.action == action and not r.learned then
				Reactions.setAction(state.entry.id, nil)
			else
				Reactions.setAction(state.entry.id, action)
			end
		end)
	end

	local hitButton = button("Set hit here", 78, row3)
	hitButton.MouseButton1Click:Connect(function()
		if state.entry and state.track then
			Reactions.setHit(state.entry.id, state.track.TimePosition)
		end
	end)

	local clearButton = button("Clear", 44, row3)
	clearButton.MouseButton1Click:Connect(function()
		if state.entry then
			Reactions.clear(state.entry.id)
		end
	end)

	ui.reaction = new("TextLabel", {
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 1, -42),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = THEME.sub,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = content,
	})

	ui.hitMarker = new("Frame", {
		Size = UDim2.new(0, 2, 1, 6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(250, 110, 110),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = ui.timeline,
	})

	uiMaid:Connect(Reactions.Changed, function(id)
		if state.entry and (id == nil or id == state.entry.id) then
			updateReaction()
		end
	end)

	ui.status = new("TextLabel", {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.new(0, 8, 1, -24),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(250, 160, 120),
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	local grip = new("TextButton", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -18, 1, -18),
		BackgroundTransparency = 1,
		Text = "◢",
		TextColor3 = THEME.sub,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		ZIndex = 10,
		Parent = main,
	})
	do
		local resizing, startMouse, startSize
		grip.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				resizing, startMouse, startSize = true, input.Position, main.AbsoluteSize
			end
		end)
		uiMaid:Give(UserInputService.InputChanged:Connect(function(input)
			if
				resizing
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				local d = input.Position - startMouse
				main.Size = UDim2.fromOffset(
					math.clamp(startSize.X + d.X, MIN_SIZE.X, MAX_SIZE.X),
					math.clamp(startSize.Y + d.Y, MIN_SIZE.Y, MAX_SIZE.Y)
				)
			end
		end))
		uiMaid:Give(UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				resizing = false
			end
		end))
	end

	gui.Parent = (gethui and gethui()) or Services.CoreGui
end

local function setCameraBlocked(blocked)
	if blocked == state.cameraBlocked then
		return
	end
	state.cameraBlocked = blocked
	if blocked then
		ContextActionService:BindActionAtPriority(
			BLOCK_CAMERA_ACTION,
			function()
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 1,
			Enum.UserInputType.MouseWheel,
			Enum.UserInputType.MouseButton2,
			Enum.UserInputType.MouseMovement
		)
	else
		ContextActionService:UnbindAction(BLOCK_CAMERA_ACTION)
	end
end

local function mouseOverWindow()
	local mouse = UserInputService:GetMouseLocation()
	local pos, size = ui.main.AbsolutePosition, ui.main.AbsoluteSize
	return mouse.X >= pos.X and mouse.X <= pos.X + size.X and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y
end

local function step()
	setCameraBlocked(gui.Enabled and (state.orbiting or state.scrubbing or mouseOverWindow()))

	if state.listDirty and os.clock() - state.lastListRefresh > 0.3 then
		refreshList()
	end

	local cam = ui.camera
	local center = Vector3.new(0, state.height, 0)
	cam.CFrame = CFrame.new(center)
		* CFrame.Angles(0, state.yaw, 0)
		* CFrame.Angles(-state.pitch, 0, 0)
		* CFrame.new(0, 0, state.zoom)

	local track = state.track
	local r = state.entry and Reactions.get(state.entry.id)
	if r and r.hit and track and track.Length > 0 then
		ui.hitMarker.Visible = true
		ui.hitMarker.Position = UDim2.fromScale(math.clamp(r.hit / track.Length, 0, 1), 0.5)
	else
		ui.hitMarker.Visible = false
	end
	if state.finished then
		ui.progress.Size = UDim2.fromScale(1, 1)
	elseif track and track.Length > 0 then
		ui.progress.Size = UDim2.fromScale(math.clamp(track.TimePosition / track.Length, 0, 1), 1)
	else
		ui.progress.Size = UDim2.fromScale(0, 1)
	end
end

function PreviewWindow.isOpen()
	return gui ~= nil and gui.Enabled
end

function PreviewWindow.open()
	if not gui then
		build()
	end
	if not state.render then
		state.render = RunService.RenderStepped:Connect(step)
	end
	gui.Enabled = true
	state.listDirty = true

	if not state.entry then
		ui.title.Text = "Preview"
		setStatus("Pick an animation from the list.")
	end
	updateReaction()
end

function PreviewWindow.show(entry)
	state.entry = entry
	PreviewWindow.open()

	ui.title.Text = string.format("%s  [%s]", entry.name, entry.id)
	gui.Enabled = true
	state.playing = true

	rebuildRig()
	updateReaction()
end

function PreviewWindow.close()
	if not gui then
		return
	end
	gui.Enabled = false
	state.entry = nil
	state.scrubbing = false
	state.orbiting = false
	setCameraBlocked(false)
	if state.render then
		state.render:Disconnect()
		state.render = nil
	end
	stopTrack()
	if state.rig then
		state.rig:Destroy()
		state.rig = nil
	end
end

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
end

__modules["Features/AnimationLogger/Scanner"] = function()
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
end

__modules["Features/AnimationLogger/Tracker"] = function()
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
end

__modules["Features/AnimationLogger"] = function()
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
	IgnoreOptions = { "Search", "AnimList" },
}

local function label(entry)
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
		detailsDirty = false,
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
		Description = "Pop-out 3D rig viewer with its own animation list",
		Callback = function()
			local e = selected()
			if e then
				PreviewWindow.show(e)
			else
				PreviewWindow.open()
			end
		end,
	})

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

	maid:Give(Logger.Added:Connect(function(entry)
		state.dirty = true
		local now = os.clock()
		if state.notify and now - (state.lastNotify or 0) > 0.5 then
			state.lastNotify = now
			notify("New animation", label(entry))
		end
	end))
	maid:Give(Logger.Updated:Connect(function(entry, changed)
		if changed then
			state.dirty = true
		elseif entry.id == state.selectedId then
			state.detailsDirty = true
		end
	end))
	maid:Give(Logger.Cleared:Connect(function()
		state.selectedId = nil
		state.dirty = true
	end))

	task.spawn(function()
		while not Fluent.Unloaded do
			if state.dirty then
				state.dirty = false
				state.detailsDirty = false
				pcall(refresh)
			elseif state.detailsDirty then
				state.detailsDirty = false
				pcall(showDetails)
			end
			task.wait(Config.AnimationLogger.RefreshInterval)
		end
	end)

	Tracker.start(maid)
	maid:Give(PreviewWindow.destroy)
end

return AnimationLogger
end

__modules["Features/AutoReact/Engine"] = function()
local Services = require("Util/Services")
local Config = require("Config")
local Maid = require("Util/Maid")
local Signal = require("Util/Signal")
local Tracker = require("Features/AnimationLogger/Tracker")
local Reactions = require("Features/AutoReact/Reactions")

local Players = Services.Players
local Stats = Services.Stats
local VirtualInputManager = Services.VirtualInputManager
local LocalPlayer = Players.LocalPlayer

local Engine = {
	settings = {
		enabled = false,
		learn = false,
		useLearned = true,
		learnAction = "Parry",
		range = Config.AutoReact.Range,
		lead = Config.AutoReact.Lead,
		blockHold = Config.AutoReact.BlockHold,
		learnWindow = Config.AutoReact.LearnWindow,
		inputMethod = "Auto",
		pingMode = "Auto",
		pingManual = 0,
		pingScale = 0.5,
		keys = table.clone(Config.AutoReact.Keys),
	},
	Fired = Signal.new(),
	Learned = Signal.new(),
}

local VK = {
	Space = 0x20,
	Tab = 0x09,
	LeftShift = 0xA0,
	RightShift = 0xA1,
	LeftControl = 0xA2,
	RightControl = 0xA3,
	LeftAlt = 0xA4,
	RightAlt = 0xA5,
	Zero = 0x30,
	One = 0x31,
	Two = 0x32,
	Three = 0x33,
	Four = 0x34,
	Five = 0x35,
	Six = 0x36,
	Seven = 0x37,
	Eight = 0x38,
	Nine = 0x39,
}

local smoothedPing = nil
local pending = {}
local lastFire = {}
local held = {}

local function keyCode(name)
	local ok, code = pcall(function()
		return Enum.KeyCode[name]
	end)
	return ok and code or nil
end

local function vkFor(code)
	if VK[code.Name] then
		return VK[code.Name]
	end
	if #code.Name == 1 and code.Name:match("%a") then
		return string.byte(code.Name:upper())
	end
end

local function useKeypress(code)
	local method = Engine.settings.inputMethod
	if method == "VirtualInputManager" then
		return false
	end
	return keypress ~= nil and keyrelease ~= nil and vkFor(code) ~= nil
end

local function press(code)
	if useKeypress(code) then
		keypress(vkFor(code))
	else
		VirtualInputManager:SendKeyEvent(true, code, false, game)
	end
end

local function release(code)
	if useKeypress(code) then
		keyrelease(vkFor(code))
	else
		VirtualInputManager:SendKeyEvent(false, code, false, game)
	end
end

function Engine.send(action)
	local code = keyCode(Engine.settings.keys[action] or "")
	if not code then
		return false
	end

	local now = os.clock()
	if now - (lastFire[action] or 0) < Config.AutoReact.Cooldown then
		return false
	end
	lastFire[action] = now

	if action == "Block" then
		held[code] = (held[code] or 0) + 1
		pcall(press, code)
		task.delay(Engine.settings.blockHold, function()
			held[code] -= 1
			if held[code] <= 0 then
				held[code] = nil
				pcall(release, code)
			end
		end)
	else
		pcall(press, code)
		task.delay(0.03, pcall, release, code)
	end

	Engine.Fired:Fire(action)
	return true
end

local function samplePing()
	local ok, ms = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(ms) == "number" and ms > 0 then
		return ms / 1000
	end
	local ok2, seconds = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
	if ok2 and type(seconds) == "number" and seconds > 0 then
		return seconds * 2
	end
end

function Engine.ping()
	return smoothedPing or samplePing() or 0
end

function Engine.pingOffset()
	local s = Engine.settings
	if s.pingMode == "Manual" then
		return s.pingManual / 1000
	elseif s.pingMode == "Auto" then
		return Engine.ping() * s.pingScale
	end
	return 0
end

local function rootOf(model)
	return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end

local function distanceTo(model)
	local mine = rootOf(LocalPlayer.Character)
	local theirs = rootOf(model)
	if not mine or not theirs then
		return math.huge
	end
	return (mine.Position - theirs.Position).Magnitude
end

local function trackSpeed(track)
	local ok, speed = pcall(function()
		return track.Speed
	end)
	return (ok and speed and speed > 0.01) and speed or 1
end

local function prune(now)
	for i = #pending, 1, -1 do
		local p = pending[i]
		if now - p.start > Engine.settings.learnWindow or not p.model.Parent then
			table.remove(pending, i)
		end
	end
end

local function onPlayed(maid, model, track, rawId)
	if model == LocalPlayer.Character then
		return
	end
	local s = Engine.settings
	if not s.enabled and not s.learn then
		return
	end
	if distanceTo(model) > s.range then
		return
	end

	local id = Reactions.cleanId(rawId)
	if not id then
		return
	end

	if s.learn and not track.Looped then
		prune(os.clock())
		table.insert(pending, { id = id, model = model, track = track, start = os.clock() })
	end

	if not s.enabled then
		return
	end
	local r = Reactions.get(id)
	if not r or not r.action or not r.hit or (r.learned and not s.useLearned) then
		return
	end

	local wait = math.max(0, r.hit / trackSpeed(track) - s.lead - Engine.pingOffset())
	local thread
	thread = task.delay(wait, function()
		maid:Remove(thread, true)
		if not Engine.settings.enabled then
			return
		end
		if not track.IsPlaying and wait > 0.05 then
			return
		end
		if distanceTo(model) > Engine.settings.range then
			return
		end
		Engine.send(r.action)
	end)
	maid:Give(thread)
end

local function onDamaged()
	local now = os.clock()
	prune(now)
	local best
	for _, p in ipairs(pending) do
		if now - p.start > 0.05 and (not best or p.start > best.start) then
			if distanceTo(p.model) <= Engine.settings.range + 6 then
				best = p
			end
		end
	end
	if not best then
		return
	end

	local hit = now - best.start
	if best.track.IsPlaying then
		local ok, position = pcall(function()
			return best.track.TimePosition
		end)
		if ok and position and position > 0 then
			hit = position
		end
	end

	table.remove(pending, table.find(pending, best))
	local r = Reactions.addSample(best.id, hit, Engine.settings.learnAction)
	Engine.Learned:Fire(best.id, r)
end

local function watchCharacter(charMaid, character)
	charMaid:Clean()
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or character ~= LocalPlayer.Character then
		return
	end

	local last = humanoid.Health
	charMaid:Connect(humanoid.HealthChanged, function(health)
		if health < last - 0.01 and Engine.settings.learn then
			onDamaged()
		end
		last = health
	end)
end

function Engine.start(maid)
	Reactions.load()

	local threads = maid:Extend()
	maid:Connect(Tracker.Played, function(model, track, rawId)
		onPlayed(threads, model, track, rawId)
	end)

	local charMaid = maid:Extend()
	maid:Connect(LocalPlayer.CharacterAdded, function(character)
		task.spawn(watchCharacter, charMaid, character)
	end)
	task.spawn(watchCharacter, charMaid, LocalPlayer.Character)

	local running = true
	maid:Spawn(function()
		while running do
			local sample = samplePing()
			if sample then
				smoothedPing = smoothedPing and (smoothedPing * 0.8 + sample * 0.2) or sample
			end
			task.wait(0.5)
		end
	end)

	maid:Give(function()
		running = false
		table.clear(pending)
		for code in pairs(held) do
			pcall(release, code)
		end
		table.clear(held)
	end)
end

return Engine
end

__modules["Features/AutoReact/Reactions"] = function()
local Services = require("Util/Services")
local Config = require("Config")
local Signal = require("Util/Signal")

local HttpService = Services.HttpService

local Reactions = {
	ACTIONS = { "Parry", "Block", "Dash" },
	data = {},
	Changed = Signal.new(),
}

local saveQueued = false

local function path()
	return string.format("%s/%d.json", Config.AutoReact.Folder, game.PlaceId)
end

local function cleanId(raw)
	return raw and tostring(raw):match("%d+")
end

Reactions.cleanId = cleanId

function Reactions.load()
	table.clear(Reactions.data)
	if not (readfile and isfile) then
		return
	end
	local ok, raw = pcall(function()
		return isfile(path()) and readfile(path())
	end)
	if not ok or not raw then
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if decoded and type(data) == "table" then
		for id, r in pairs(data) do
			if type(r) == "table" then
				r.samples = r.samples or {}
				Reactions.data[tostring(id)] = r
			end
		end
	end
	Reactions.Changed:Fire()
end

function Reactions.save()
	if saveQueued or not writefile then
		return
	end
	saveQueued = true
	task.delay(1, function()
		saveQueued = false
		local folder = Config.AutoReact.Folder
		if makefolder and not (isfolder and isfolder(folder)) then
			pcall(makefolder, Config.RootFolder)
			pcall(makefolder, folder)
		end
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, Reactions.data)
		if ok then
			pcall(writefile, path(), encoded)
		end
	end)
end

function Reactions.get(id)
	return Reactions.data[cleanId(id) or ""]
end

local function ensure(id)
	local r = Reactions.data[id]
	if not r then
		r = { samples = {} }
		Reactions.data[id] = r
	end
	return r
end

function Reactions.setAction(id, action)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	r.action = action
	r.learned = false
	Reactions.Changed:Fire(id)
	Reactions.save()
end

function Reactions.setHit(id, hit)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	r.hit = math.max(0, hit)
	r.manualHit = true
	Reactions.Changed:Fire(id)
	Reactions.save()
end

function Reactions.addSample(id, hit, defaultAction)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	local samples = r.samples
	table.insert(samples, hit)
	while #samples > Config.AutoReact.MaxSamples do
		table.remove(samples, 1)
	end

	if not r.manualHit then
		local sorted = table.clone(samples)
		table.sort(sorted)
		r.hit = sorted[math.ceil(#sorted / 2)]
	end
	if not r.action then
		r.action = defaultAction
		r.learned = true
	end
	Reactions.Changed:Fire(id)
	Reactions.save()
	return r
end

function Reactions.clear(id)
	id = cleanId(id)
	if id and Reactions.data[id] then
		Reactions.data[id] = nil
		Reactions.Changed:Fire(id)
		Reactions.save()
	end
end

function Reactions.clearAll()
	table.clear(Reactions.data)
	Reactions.Changed:Fire()
	Reactions.save()
end

function Reactions.count()
	local n = 0
	for _ in pairs(Reactions.data) do
		n += 1
	end
	return n
end

function Reactions.describe(id)
	local r = Reactions.get(id)
	if not r or not r.action then
		return "No reaction set"
	end
	local hit = r.hit and string.format("%.2fs", r.hit) or "no hit time"
	local extra = #r.samples > 0 and string.format(", %d sample(s)", #r.samples) or ""
	return string.format("%s at %s%s%s", r.action, hit, extra, r.learned and " (learned)" or "")
end

return Reactions
end

__modules["Features/AutoReact"] = function()
local Logger = require("Features/AnimationLogger/Logger")
local PreviewWindow = require("Features/AnimationLogger/PreviewWindow")
local Reactions = require("Features/AutoReact/Reactions")
local Engine = require("Features/AutoReact/Engine")

local AutoReact = {
	Title = "Auto react",
	Icon = "shield",
	IgnoreOptions = { "ReactSaved" },
}

local function labelFor(id)
	local entry = Logger.get(id)
	local name = entry and entry.name or "Unknown"
	return string.format("%s [%s] - %s", name, id, Reactions.describe(id))
end

function AutoReact.build(Tab, ctx)
	local Window, Fluent, maid = ctx.Window, ctx.Fluent, ctx.maid
	local Options = Fluent.Options
	local settings = Engine.settings
	local state = { labelToId = {}, selectedId = nil, dirty = true, notifyLearn = true }

	local function notify(title, content)
		Fluent:Notify({ Title = title, Content = content, Duration = 3 })
	end

	local Main = Tab:AddSection("Auto react")

	Main:AddParagraph({
		Title = "How it works",
		Content = "When someone near you plays an animation that has a reaction, w_w presses the key at its hit time. Set reactions in the preview window, or turn on learning below.",
	})

	Main:AddToggle("ReactEnabled", { Title = "Enabled", Default = false })
	Options.ReactEnabled:OnChanged(function(value)
		settings.enabled = value
	end)

	Main:AddToggle("ReactUseLearned", { Title = "React to learned animations", Default = true })
	Options.ReactUseLearned:OnChanged(function(value)
		settings.useLearned = value
	end)

	Main:AddSlider("ReactRange", {
		Title = "Range (studs)",
		Default = settings.range,
		Min = 4,
		Max = 80,
		Rounding = 0,
	})
	Options.ReactRange:OnChanged(function(value)
		settings.range = value
	end)

	Main:AddSlider("ReactLead", {
		Title = "Press early (ms)",
		Description = "Raise this if you're still getting hit",
		Default = math.floor(settings.lead * 1000),
		Min = 0,
		Max = 400,
		Rounding = 0,
	})
	Options.ReactLead:OnChanged(function(value)
		settings.lead = value / 1000
	end)

	Main:AddSlider("ReactBlockHold", {
		Title = "Block hold time (s)",
		Default = settings.blockHold,
		Min = 0.1,
		Max = 3,
		Rounding = 2,
	})
	Options.ReactBlockHold:OnChanged(function(value)
		settings.blockHold = value
	end)

	local Ping = Tab:AddSection("Ping")

	local pingInfo = Ping:AddParagraph({ Title = "Ping: ...", Content = "" })

	Ping:AddDropdown("ReactPingMode", {
		Title = "Ping adjustment",
		Description = "Auto reads your ping, Manual uses the value below",
		Values = { "Auto", "Manual", "Off" },
		Default = settings.pingMode,
	})
	Options.ReactPingMode:OnChanged(function(value)
		settings.pingMode = value
	end)

	Ping:AddSlider("ReactPingScale", {
		Title = "Auto amount (%)",
		Description = "How much of your ping to press early by. 50% is one-way latency",
		Default = math.floor(settings.pingScale * 100),
		Min = 0,
		Max = 150,
		Rounding = 0,
	})
	Options.ReactPingScale:OnChanged(function(value)
		settings.pingScale = value / 100
	end)

	Ping:AddSlider("ReactPingManual", {
		Title = "Manual adjustment (ms)",
		Default = settings.pingManual,
		Min = 0,
		Max = 500,
		Rounding = 0,
	})
	Options.ReactPingManual:OnChanged(function(value)
		settings.pingManual = value
	end)

	local Keys = Tab:AddSection("Keys")

	for _, action in ipairs(Reactions.ACTIONS) do
		local id = "ReactKey" .. action
		Keys:AddInput(id, {
			Title = action .. " key",
			Default = settings.keys[action],
			Placeholder = "F",
			Numeric = false,
			Finished = true,
		})
		Options[id]:OnChanged(function(value)
			local ok = pcall(function()
				return Enum.KeyCode[value]
			end)
			if ok and value ~= "" then
				settings.keys[action] = value
			end
		end)
		Keys:AddButton({
			Title = "Test " .. action,
			Description = "Sends the " .. action:lower() .. " input now",
			Callback = function()
				if not Engine.send(action) then
					notify("Couldn't send", "Check the key name (like F, Q, Space, LeftShift)")
				end
			end,
		})
	end

	Keys:AddDropdown("ReactInputMethod", {
		Title = "Input method",
		Description = "Auto uses keypress when available, otherwise VirtualInputManager",
		Values = { "Auto", "VirtualInputManager" },
		Default = "Auto",
	})
	Options.ReactInputMethod:OnChanged(function(value)
		settings.inputMethod = value
	end)

	local Learn = Tab:AddSection("Learn from damage")

	Learn:AddParagraph({
		Title = "Learning",
		Content = "When you take damage, the most recent attack animation from someone in range gets saved with that hit time. Get hit a couple of times by a move to make its timing reliable.",
	})

	Learn:AddToggle("ReactLearn", { Title = "Learn from damage", Default = false })
	Options.ReactLearn:OnChanged(function(value)
		settings.learn = value
	end)

	Learn:AddDropdown("ReactLearnAction", {
		Title = "Learned animations use",
		Values = Reactions.ACTIONS,
		Default = settings.learnAction,
	})
	Options.ReactLearnAction:OnChanged(function(value)
		settings.learnAction = value
	end)

	Learn:AddSlider("ReactLearnWindow", {
		Title = "Max time to hit (s)",
		Description = "Animations that started longer ago than this are ignored",
		Default = settings.learnWindow,
		Min = 0.3,
		Max = 4,
		Rounding = 1,
	})
	Options.ReactLearnWindow:OnChanged(function(value)
		settings.learnWindow = value
	end)

	Learn:AddToggle("ReactNotifyLearn", { Title = "Notify when something is learned", Default = true })
	Options.ReactNotifyLearn:OnChanged(function(value)
		state.notifyLearn = value
	end)

	local Saved = Tab:AddSection("Saved reactions")

	local summary = Saved:AddParagraph({ Title = "0 saved", Content = "Saved per game." })

	local dropdown = Saved:AddDropdown("ReactSaved", {
		Title = "Reactions",
		Values = {},
		Multi = false,
	})
	Options.ReactSaved:OnChanged(function(value)
		state.selectedId = value and state.labelToId[value] or nil
	end)

	local function refresh()
		local ids = {}
		for id, r in pairs(Reactions.data) do
			if r.action or r.hit then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		local values, labelToId = {}, {}
		for _, id in ipairs(ids) do
			local l = labelFor(id)
			table.insert(values, l)
			labelToId[l] = id
		end
		state.labelToId = labelToId
		dropdown:SetValues(values)
		summary:SetTitle(string.format("%d saved", #ids))
	end

	local function withSelected(fn)
		return function()
			if not state.selectedId then
				notify("Nothing selected", "Pick a reaction first.")
				return
			end
			fn(state.selectedId)
		end
	end

	Saved:AddButton({
		Title = "Open in preview",
		Callback = withSelected(function(id)
			local entry = Logger.get(id)
			if entry then
				PreviewWindow.show(entry)
			else
				notify("Not logged yet", "That animation hasn't played this session.")
			end
		end),
	})

	Saved:AddButton({
		Title = "Delete selected",
		Callback = withSelected(function(id)
			Reactions.clear(id)
			state.selectedId = nil
		end),
	})

	Saved:AddButton({
		Title = "Delete all",
		Callback = function()
			Window:Dialog({
				Title = "Delete all reactions?",
				Content = "This removes every saved reaction for this game.",
				Buttons = {
					{ Title = "Delete", Callback = Reactions.clearAll },
					{ Title = "Cancel", Callback = function() end },
				},
			})
		end,
	})

	maid:Connect(Reactions.Changed, function()
		state.dirty = true
	end)
	maid:Connect(Logger.Added, function(entry)
		if Reactions.get(entry.id) then
			state.dirty = true
		end
	end)
	maid:Connect(Engine.Learned, function(id, r)
		if state.notifyLearn and r then
			notify("Learned", labelFor(id))
		end
	end)

	task.spawn(function()
		while not Fluent.Unloaded do
			if state.dirty then
				state.dirty = false
				pcall(refresh)
			end
			pcall(function()
				pingInfo:SetTitle(string.format("Ping: %d ms", math.floor(Engine.ping() * 1000 + 0.5)))
				pingInfo:SetDesc(
					string.format(
						"Pressing %d ms early (%d ms ping + %d ms press early)",
						math.floor((Engine.pingOffset() + settings.lead) * 1000 + 0.5),
						math.floor(Engine.pingOffset() * 1000 + 0.5),
						math.floor(settings.lead * 1000 + 0.5)
					)
				)
			end)
			task.wait(0.5)
		end
	end)

	Engine.start(maid)
end

return AutoReact
end

__modules["Features/List"] = function()
return {
	require("Features/AnimationLogger"),
	require("Features/AutoReact"),
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
end

__modules["Util/Services"] = function()
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
		local ok, err = pcall(fn, ...)
		if not ok then
			warn(err)
		end
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

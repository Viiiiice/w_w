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
	WindowSize = UDim2.fromOffset(620, 580),
	Theme = "Dark",

	RootFolder = "w_w",
	ConfigFolder = "w_w/config",

	Linoria = {
		Library = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/Library.lua",
		SaveManager = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/addons/SaveManager.lua",
		ThemeManager = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/addons/ThemeManager.lua",
	},

	AnimationLogger = {
		SaveFolder = "w_w/animations",
		ScanFolder = "Auto",
		MaxDropdownItems = 60,
		RefreshInterval = 0.5,
	},

	AutoReact = {
		Folder = "w_w/reactions",
		Range = 18,
		Lead = 0.08,
		BlockHold = 0.45,
		LearnWindow = 1.5,
		Cooldown = 0.08,
		MaxSamples = 8,
		HitboxModule = "ReplicatedStorage.Shared.Utils.HitboxUtils",
		HitboxPadding = 2,
		IgnoreIds = {},
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

local DEFAULT_THEME = {
	FontColor = Color3.fromRGB(255, 255, 255),
	MainColor = Color3.fromRGB(28, 28, 28),
	BackgroundColor = Color3.fromRGB(20, 20, 20),
	AccentColor = Color3.fromRGB(0, 85, 255),
	OutlineColor = Color3.fromRGB(50, 50, 50),
	DisabledTextColor = Color3.fromRGB(142, 142, 142),
	RiskColor = Color3.fromRGB(255, 50, 50),
	Black = Color3.new(0, 0, 0),
}
local ACTION_COLORS = {
	Block = Color3.fromRGB(255, 170, 60),
	Dash = Color3.fromRGB(90, 220, 120),
}

local SPEEDS = { 0.25, 0.5, 1, 1.5, 2 }
local MAX_LIST_ITEMS = 200
local LIST_WIDTH = 180
local MARKER_WIDTH = 190
local MIN_SIZE = Vector2.new(660, 430)
local MAX_SIZE = Vector2.new(1600, 1000)
local HOLD_STEP = 0.05
local BLOCK_CAMERA_ACTION = "w_wPreviewBlockCamera"

local library
local gui
local ui = {}
local themed = {}
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
	markersDirty = true,
	lastListRefresh = 0,
	lastThemeCheck = 0,
	themeKey = "",
	scrubbing = false,
	orbiting = false,
	cameraBlocked = false,
	action = "Parry",
	hold = 0.45,
	markerIndex = nil,
	confirmClear = 0,
}

local function color(key)
	if library and typeof(library[key]) == "Color3" then
		return library[key]
	end
	return DEFAULT_THEME[key]
end

local function font()
	return library and typeof(library.Font) == "EnumItem" and library.Font or Enum.Font.Code
end

local function theme(inst, props)
	themed[inst] = props
	for prop, key in pairs(props) do
		inst[prop] = color(key)
	end
	return inst
end

local function applyTheme()
	for inst, props in pairs(themed) do
		if inst.Parent then
			for prop, key in pairs(props) do
				inst[prop] = color(key)
			end
		else
			themed[inst] = nil
		end
	end
end

local function themeKey()
	local parts = {}
	for key in pairs(DEFAULT_THEME) do
		table.insert(parts, key .. tostring(color(key)))
	end
	table.sort(parts)
	return table.concat(parts)
end

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

local function label(props)
	local colorKey = props.ColorKey or "FontColor"
	props.ColorKey = nil
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = font(),
		TextSize = 14,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for k, v in pairs(props) do
		l[k] = v
	end
	theme(l, { TextColor3 = colorKey })
	return l
end

local function highlight(outer, idleKey)
	outer.MouseEnter:Connect(function()
		outer.BorderColor3 = color("AccentColor")
	end)
	outer.MouseLeave:Connect(function()
		outer.BorderColor3 = color(idleKey or "Black")
	end)
end

local function button(parent, text, size)
	local outer = new("TextButton", {
		Size = size or UDim2.new(1, 0, 0, 20),
		BorderSizePixel = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	theme(outer, { BackgroundColor3 = "Black", BorderColor3 = "Black" })
	local inner = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderMode = Enum.BorderMode.Inset,
		BorderSizePixel = 1,
		Parent = outer,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(212, 212, 212)),
			Rotation = 90,
		}),
	})
	theme(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
	local text_ = label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = inner,
	})
	highlight(outer)
	return outer, text_
end

local function groupbox(parent, title, position, size)
	local outer = new("Frame", {
		Position = position,
		Size = size,
		BorderSizePixel = 1,
		Parent = parent,
	})
	theme(outer, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" })
	local inner = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderMode = Enum.BorderMode.Inset,
		BorderSizePixel = 1,
		Parent = outer,
	})
	theme(inner, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "Black" })
	theme(new("Frame", { Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0, Parent = inner }), {
		BackgroundColor3 = "AccentColor",
	})
	label({ Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 2), Text = title, Parent = inner })
	return new("Frame", {
		Size = UDim2.new(1, -8, 1, -26),
		Position = UDim2.fromOffset(4, 22),
		BackgroundTransparency = 1,
		Parent = inner,
	})
end

local function row(parent, position)
	return new("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = position,
		BackgroundTransparency = 1,
		Parent = parent,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }) })
end

local function setStatus(text, isError)
	local key = isError and "RiskColor" or "DisabledTextColor"
	ui.status.Text = text or ""
	themed[ui.status] = { TextColor3 = key }
	ui.status.TextColor3 = color(key)
end

local function speed()
	return SPEEDS[state.speedIndex]
end

local function applySpeed()
	if state.track then
		state.track:AdjustSpeed(state.playing and speed() or 0)
	end
	ui.speed.Text = string.format("%gx", speed())
	ui.playLabel.Text = state.playing and "Pause" or "Play"
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
		setStatus("Couldn't load this animation (it may belong to another game/group).", true)
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
	state.markersDirty = true
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
		setStatus(animator, true)
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

local function setRowSelected(r, selected)
	r.selected = selected
	local border = selected and "AccentColor" or "OutlineColor"
	local text = selected and "AccentColor" or "FontColor"
	themed[r.button] = { BackgroundColor3 = "MainColor", BorderColor3 = border }
	themed[r.text] = { TextColor3 = text }
	r.button.BorderColor3 = color(border)
	r.text.TextColor3 = color(text)
end

local function listRow(list, rows, i, height, onClick)
	local r = rows[i]
	if r then
		return r
	end

	local outer = new("TextButton", {
		Size = UDim2.new(1, -5, 0, height),
		BorderSizePixel = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = list,
	})
	theme(outer, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
	local text = label({
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(5, 0),
		RichText = true,
		Parent = outer,
	})
	r = { button = outer, text = text, selected = false }
	outer.MouseEnter:Connect(function()
		outer.BorderColor3 = color("AccentColor")
	end)
	outer.MouseLeave:Connect(function()
		outer.BorderColor3 = color(r.selected and "AccentColor" or "OutlineColor")
	end)
	outer.MouseButton1Click:Connect(function()
		onClick(r)
	end)
	rows[i] = r
	return r
end

local function scrollList(parent, position, size)
	local list = new("ScrollingFrame", {
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1) }),
	})
	theme(list, { ScrollBarImageColor3 = "AccentColor" })
	return list
end

local function refreshList()
	state.listDirty = false
	state.lastListRefresh = os.clock()

	local list = Logger.list({ text = state.search })
	local selectedId = state.entry and state.entry.id
	local count = math.min(#list, MAX_LIST_ITEMS)
	local sub = color("DisabledTextColor"):ToHex()
	local accent = color("AccentColor"):ToHex()

	for i = 1, count do
		local entry = list[i]
		local r = listRow(ui.list, ui.rows, i, 32, function(r)
			local e = r.id and Logger.get(r.id)
			if e then
				PreviewWindow.show(e)
			end
		end)
		r.id = entry.id
		r.button.LayoutOrder = i
		r.button.Visible = true
		local tag = Reactions.has(entry.id) and string.format(' <font color="#%s">●</font>', accent) or ""
		r.text.Text = string.format(
			'%s%s\n<font size="12" color="#%s">%s</font>',
			escape(entry.name),
			tag,
			sub,
			entry.id
		)
		setRowSelected(r, entry.id == selectedId)
	end
	for i = count + 1, #ui.rows do
		ui.rows[i].button.Visible = false
	end

	ui.empty.Visible = count == 0
	ui.empty.Text = Logger.count == 0 and "No animations logged yet." or "No matches."
end

local function currentMarkers()
	return state.entry and Reactions.markers(state.entry.id) or {}
end

local function markerColor(action)
	return ACTION_COLORS[action] or color("AccentColor")
end

local function updateMarkerControls()
	ui.actionLabel.Text = "Action: " .. state.action
	themed[ui.actionLabel] = nil
	ui.actionLabel.TextColor3 = markerColor(state.action)
	ui.holdLabel.Text = string.format("Hold %.2fs", state.hold)
	ui.holdRow.Visible = state.action == "Block"
end

local function refreshTicks(markers)
	local track = state.track
	local length = track and track.Length or 0
	for i, m in ipairs(markers) do
		local tick = ui.ticks[i]
		if not tick then
			tick = {
				line = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = ui.timelineInner,
				}),
				span = new("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0,
					BackgroundTransparency = 0.55,
					ZIndex = 3,
					Parent = ui.timelineInner,
				}),
			}
			ui.ticks[i] = tick
		end
		local visible = length > 0
		local x = visible and math.clamp(m.t / length, 0, 1) or 0
		local c = markerColor(m.action)
		local selected = i == state.markerIndex
		tick.line.Visible = visible
		tick.line.BackgroundColor3 = selected and color("FontColor") or c
		tick.line.Position = UDim2.fromScale(x, 0.5)
		tick.line.Size = UDim2.new(0, selected and 3 or 2, 1, selected and 8 or 4)
		local hasSpan = visible and m.action == "Block" and (m.hold or 0) > 0
		tick.span.Visible = hasSpan
		if hasSpan then
			tick.span.BackgroundColor3 = c
			tick.span.Position = UDim2.fromScale(x, 0.5)
			tick.span.Size = UDim2.fromScale(math.clamp(m.hold / length, 0, 1 - x), 1)
		end
	end
	for i = #markers + 1, #ui.ticks do
		ui.ticks[i].line.Visible = false
		ui.ticks[i].span.Visible = false
	end
end

local function refreshMarkers()
	state.markersDirty = false
	local markers = currentMarkers()
	if state.markerIndex and not markers[state.markerIndex] then
		state.markerIndex = nil
	end

	for i, m in ipairs(markers) do
		local r = listRow(ui.markerList, ui.markerRows, i, 20, function(r)
			PreviewWindow.selectMarker(r.index)
		end)
		r.index = i
		r.button.LayoutOrder = i
		r.button.Visible = true
		local hold = m.action == "Block" and m.hold and string.format(" hold %.2fs", m.hold) or ""
		r.text.Text = string.format(
			'%d. <font color="#%s">%s</font> %.2fs%s',
			i,
			markerColor(m.action):ToHex(),
			m.action,
			m.t,
			hold
		)
		setRowSelected(r, i == state.markerIndex)
	end
	for i = #markers + 1, #ui.markerRows do
		ui.markerRows[i].button.Visible = false
	end

	local r = state.entry and Reactions.get(state.entry.id)
	local ignored = r ~= nil and r.ignored == true
	ui.ignoreLabel.Text = ignored and "Ignore: on" or "Ignore: off"
	themed[ui.ignoreLabel] = { TextColor3 = ignored and "RiskColor" or "FontColor" }
	ui.ignoreLabel.TextColor3 = color(ignored and "RiskColor" or "FontColor")
	if not state.entry then
		ui.markerInfo.Text = "Pick an animation first."
	elseif ignored then
		ui.markerInfo.Text = "Ignored: never reacted to."
	elseif #markers == 0 then
		ui.markerInfo.Text = "Scrub to a hit, then add one."
	elseif r and r.learned then
		ui.markerInfo.Text = string.format("Learned from %d hit(s).", #r.samples)
	else
		ui.markerInfo.Text = string.format("%d marker(s).", #markers)
	end

	refreshTicks(markers)
end

local function pauseAt(t)
	local track = state.track
	if not track or track.Length <= 0 then
		return
	end
	if not track.IsPlaying then
		track:Play(0)
		state.finished = false
	end
	track.TimePosition = math.clamp(t, 0, track.Length)
	state.playing = false
	applySpeed()
end

function PreviewWindow.selectMarker(index)
	local m = currentMarkers()[index]
	if not m then
		return
	end
	state.markerIndex = index
	state.action = m.action
	if m.hold then
		state.hold = m.hold
	end
	updateMarkerControls()
	pauseAt(m.t)
	state.markersDirty = true
end

local function editSelected(fields)
	if state.entry and state.markerIndex then
		state.markerIndex = Reactions.updateMarker(state.entry.id, state.markerIndex, fields)
	end
end

local function sink()
	return Enum.ContextActionResult.Sink
end

local function pressed(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function moved(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function build()
	gui = new("ScreenGui", {
		Name = "w_wPreview",
		ResetOnSpawn = false,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Enabled = false,
	})

	local outer = new("Frame", {
		Size = UDim2.fromOffset(720, 470),
		Position = UDim2.new(0.5, -360, 0.5, -235),
		BorderSizePixel = 0,
		Parent = gui,
	})
	theme(outer, { BackgroundColor3 = "Black" })
	ui.main = outer

	local inner = new("Frame", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BorderMode = Enum.BorderMode.Inset,
		BorderSizePixel = 1,
		Parent = outer,
	})
	theme(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "AccentColor" })

	ui.title = label({
		Position = UDim2.fromOffset(7, 0),
		Size = UDim2.new(1, -40, 0, 25),
		Text = "Preview",
		Parent = inner,
	})

	local close = new("TextButton", {
		Size = UDim2.fromOffset(25, 25),
		Position = UDim2.new(1, -27, 0, 0),
		BackgroundTransparency = 1,
		Text = "X",
		Font = font(),
		TextSize = 14,
		TextStrokeTransparency = 0,
		Parent = inner,
	})
	theme(close, { TextColor3 = "FontColor" })
	close.MouseEnter:Connect(function()
		close.TextColor3 = color("RiskColor")
	end)
	close.MouseLeave:Connect(function()
		close.TextColor3 = color("FontColor")
	end)
	close.MouseButton1Click:Connect(PreviewWindow.close)

	do
		local dragging, start, startPos
		inner.InputBegan:Connect(function(input)
			if pressed(input) and input.Position.Y - outer.AbsolutePosition.Y <= 25 then
				dragging, start, startPos = true, input.Position, outer.Position
			end
		end)
		uiMaid:Connect(UserInputService.InputChanged, function(input)
			if dragging and moved(input) then
				local d = input.Position - start
				outer.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + d.X,
					startPos.Y.Scale,
					startPos.Y.Offset + d.Y
				)
			end
		end)
		uiMaid:Connect(UserInputService.InputEnded, function(input)
			if pressed(input) then
				dragging = false
			end
		end)
	end

	local section = new("Frame", {
		Position = UDim2.fromOffset(8, 25),
		Size = UDim2.new(1, -16, 1, -33),
		BorderSizePixel = 1,
		Parent = inner,
	})
	theme(section, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" })
	local sectionInner = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderMode = Enum.BorderMode.Inset,
		BorderSizePixel = 1,
		Parent = section,
	})
	theme(sectionInner, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "Black" })

	local side = groupbox(sectionInner, "Animations", UDim2.fromOffset(6, 6), UDim2.new(0, LIST_WIDTH - 8, 1, -12))

	local searchOuter = new("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BorderSizePixel = 1,
		Parent = side,
	})
	theme(searchOuter, { BackgroundColor3 = "Black", BorderColor3 = "Black" })
	local searchInner = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderMode = Enum.BorderMode.Inset,
		BorderSizePixel = 1,
		Parent = searchOuter,
	})
	theme(searchInner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
	ui.search = new("TextBox", {
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(5, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Search...",
		Font = font(),
		TextSize = 14,
		TextStrokeTransparency = 0,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = searchInner,
	})
	theme(ui.search, { TextColor3 = "FontColor", PlaceholderColor3 = "DisabledTextColor" })
	highlight(searchOuter)
	ui.search:GetPropertyChangedSignal("Text"):Connect(function()
		state.search = ui.search.Text:lower()
		state.listDirty = true
	end)

	ui.list = scrollList(side, UDim2.fromOffset(0, 26), UDim2.new(1, 0, 1, -26))
	ui.empty = label({
		Size = UDim2.new(1, 0, 0, 36),
		Text = "No animations logged yet.",
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		ColorKey = "DisabledTextColor",
		Parent = ui.list,
	})
	ui.rows = {}

	for _, signal in ipairs({ Logger.Added, Logger.Cleared }) do
		uiMaid:Connect(signal, function()
			state.listDirty = true
		end)
	end
	uiMaid:Connect(Logger.Updated, function(_, changed)
		if changed then
			state.listDirty = true
		end
	end)

	local content = groupbox(
		sectionInner,
		"Preview",
		UDim2.fromOffset(LIST_WIDTH + 4, 6),
		UDim2.new(1, -(LIST_WIDTH + MARKER_WIDTH + 8), 1, -12)
	)

	ui.viewport = new("ViewportFrame", {
		Size = UDim2.new(1, 0, 1, -98),
		BorderSizePixel = 1,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = content,
	})
	theme(ui.viewport, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
	ui.world = new("WorldModel", { Parent = ui.viewport })
	ui.camera = new("Camera", { FieldOfView = 40, Parent = ui.viewport })
	ui.viewport.CurrentCamera = ui.camera
	label({
		Size = UDim2.new(1, -8, 0, 14),
		Position = UDim2.new(0, 4, 1, -16),
		Text = "drag to rotate • scroll to zoom",
		TextSize = 12,
		TextTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Right,
		ColorKey = "DisabledTextColor",
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
		uiMaid:Connect(UserInputService.InputChanged, function(input)
			if state.orbiting and moved(input) then
				local delta = input.Position - lastPos
				lastPos = input.Position
				state.yaw -= delta.X * 0.01
				state.pitch = math.clamp(state.pitch + delta.Y * 0.01, -1.2, 1.2)
			end
		end)
		uiMaid:Connect(UserInputService.InputEnded, function(input)
			if ORBIT_BUTTONS[input.UserInputType] then
				state.orbiting = false
			end
		end)
	end

	ui.timeline = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 15),
		Position = UDim2.new(0, 0, 1, -90),
		BorderSizePixel = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = content,
	})
	theme(ui.timeline, { BackgroundColor3 = "Black", BorderColor3 = "Black" })
	highlight(ui.timeline)
	ui.timelineInner = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderMode = Enum.BorderMode.Inset,
		BorderSizePixel = 1,
		Parent = ui.timeline,
	})
	theme(ui.timelineInner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
	ui.progress = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = ui.timelineInner,
	})
	theme(ui.progress, { BackgroundColor3 = "AccentColor" })
	ui.time = label({
		Size = UDim2.fromScale(1, 1),
		Text = "0.00s / 0.00s",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
		Parent = ui.timelineInner,
	})
	ui.ticks = {}

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
		if pressed(input) then
			state.scrubbing = true
			seek(input.Position.X)
		end
	end)
	uiMaid:Connect(UserInputService.InputChanged, function(input)
		if state.scrubbing and moved(input) then
			seek(input.Position.X)
		end
	end)
	uiMaid:Connect(UserInputService.InputEnded, function(input)
		if state.scrubbing and pressed(input) then
			state.scrubbing = false
			applySpeed()
		end
	end)

	local row1 = row(content, UDim2.new(0, 0, 1, -68))
	local play
	play, ui.playLabel = button(row1, "Pause", UDim2.fromOffset(56, 20))
	play.MouseButton1Click:Connect(function()
		state.playing = not state.playing
		if state.playing and state.track and not state.track.IsPlaying then
			state.finished = false
			state.track:Play(0)
			state.track.TimePosition = 0
		end
		applySpeed()
	end)

	local restart = button(row1, "Restart", UDim2.fromOffset(62, 20))
	restart.MouseButton1Click:Connect(function()
		if state.track then
			state.playing = true
			state.finished = false
			state.track:Play(0)
			state.track.TimePosition = 0
			applySpeed()
		end
	end)

	local slower = button(row1, "-", UDim2.fromOffset(20, 20))
	ui.speed = label({
		Size = UDim2.fromOffset(38, 20),
		Text = "1x",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = row1,
	})
	local faster = button(row1, "+", UDim2.fromOffset(20, 20))
	slower.MouseButton1Click:Connect(function()
		state.speedIndex = math.max(1, state.speedIndex - 1)
		applySpeed()
	end)
	faster.MouseButton1Click:Connect(function()
		state.speedIndex = math.min(#SPEEDS, state.speedIndex + 1)
		applySpeed()
	end)

	local loop, loopLabel = button(row1, "Loop: on", UDim2.fromOffset(70, 20))
	loop.MouseButton1Click:Connect(function()
		state.looped = not state.looped
		loopLabel.Text = state.looped and "Loop: on" or "Loop: off"
		if state.track then
			state.track.Looped = state.looped
		end
	end)

	local row2 = row(content, UDim2.new(0, 0, 1, -44))
	local rigButton, rigLabel = button(row2, "Rig: my character", UDim2.fromOffset(150, 20))
	rigButton.MouseButton1Click:Connect(function()
		state.rigKind = state.rigKind == "Me" and "Owner" or "Me"
		rigLabel.Text = state.rigKind == "Me" and "Rig: my character" or "Rig: who played it"
		rebuildRig()
	end)
	local camButton = button(row2, "Reset camera", UDim2.fromOffset(100, 20))
	camButton.MouseButton1Click:Connect(resetCamera)

	ui.status = label({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -20),
		Text = "",
		TextSize = 13,
		ColorKey = "DisabledTextColor",
		Parent = content,
	})

	local markers = groupbox(
		sectionInner,
		"Markers",
		UDim2.new(1, -(MARKER_WIDTH + 2), 0, 6),
		UDim2.new(0, MARKER_WIDTH - 4, 1, -12)
	)

	local actionButton
	actionButton, ui.actionLabel = button(markers, "Action: Parry", UDim2.new(1, 0, 0, 20))
	actionButton.MouseButton1Click:Connect(function()
		local i = table.find(Reactions.ACTIONS, state.action) or 0
		state.action = Reactions.ACTIONS[i % #Reactions.ACTIONS + 1]
		updateMarkerControls()
		editSelected({ action = state.action, hold = state.action == "Block" and state.hold or nil })
	end)

	ui.holdRow = row(markers, UDim2.fromOffset(0, 25))
	local holdLess = button(ui.holdRow, "-", UDim2.fromOffset(22, 20))
	ui.holdLabel = label({
		Size = UDim2.new(1, -52, 0, 20),
		Text = "Hold 0.45s",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = ui.holdRow,
	})
	local holdMore = button(ui.holdRow, "+", UDim2.fromOffset(22, 20))
	local function nudgeHold(delta)
		state.hold = math.clamp(math.floor((state.hold + delta) / HOLD_STEP + 0.5) * HOLD_STEP, HOLD_STEP, 5)
		updateMarkerControls()
		local m = state.markerIndex and currentMarkers()[state.markerIndex]
		if m and m.action == "Block" then
			editSelected({ hold = state.hold })
		end
	end
	holdLess.MouseButton1Click:Connect(function()
		nudgeHold(-HOLD_STEP)
	end)
	holdMore.MouseButton1Click:Connect(function()
		nudgeHold(HOLD_STEP)
	end)

	local add = button(markers, "Add marker here", UDim2.new(1, 0, 0, 20))
	add.Position = UDim2.fromOffset(0, 50)
	add.MouseButton1Click:Connect(function()
		if not state.entry or not state.track then
			setStatus("Pick an animation first.", true)
			return
		end
		state.markerIndex = Reactions.addMarker(
			state.entry.id,
			state.track.TimePosition,
			state.action,
			state.action == "Block" and state.hold or nil
		)
	end)

	local editRow = row(markers, UDim2.fromOffset(0, 75))
	local move = button(editRow, "Move here", UDim2.new(0.5, -2, 0, 20))
	move.MouseButton1Click:Connect(function()
		if state.track then
			editSelected({ t = state.track.TimePosition })
		end
	end)
	local delete = button(editRow, "Delete", UDim2.new(0.5, -2, 0, 20))
	delete.MouseButton1Click:Connect(function()
		if state.entry and state.markerIndex then
			Reactions.removeMarker(state.entry.id, state.markerIndex)
			state.markerIndex = nil
		end
	end)

	ui.markerList = scrollList(markers, UDim2.fromOffset(0, 102), UDim2.new(1, 0, 1, -170))
	ui.markerRows = {}

	ui.markerInfo = label({
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -64),
		Text = "",
		TextSize = 12,
		ColorKey = "DisabledTextColor",
		Parent = markers,
	})

	local ignore
	ignore, ui.ignoreLabel = button(markers, "Ignore: off", UDim2.new(1, 0, 0, 20))
	ignore.Position = UDim2.new(0, 0, 1, -45)
	ignore.MouseButton1Click:Connect(function()
		if state.entry then
			Reactions.setIgnored(state.entry.id, not Reactions.isIgnored(state.entry.id))
		end
	end)

	local clear, clearLabel = button(markers, "Clear markers", UDim2.new(1, 0, 0, 20))
	clear.Position = UDim2.new(0, 0, 1, -20)
	clear.MouseButton1Click:Connect(function()
		if not state.entry then
			return
		end
		if os.clock() - state.confirmClear < 2 then
			state.confirmClear = 0
			clearLabel.Text = "Clear markers"
			Reactions.clear(state.entry.id)
			state.markerIndex = nil
		else
			state.confirmClear = os.clock()
			clearLabel.Text = "Click again to clear"
			task.delay(2, function()
				if os.clock() - state.confirmClear >= 2 then
					clearLabel.Text = "Clear markers"
				end
			end)
		end
	end)

	uiMaid:Connect(Reactions.Changed, function(id)
		if id == nil or (state.entry and id == state.entry.id) then
			state.markersDirty = true
		end
		state.listDirty = true
	end)

	local grip = new("TextButton", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(1, -16, 1, -16),
		BackgroundTransparency = 1,
		Text = "◢",
		TextSize = 14,
		Font = font(),
		ZIndex = 10,
		Parent = outer,
	})
	theme(grip, { TextColor3 = "OutlineColor" })
	do
		local resizing, startMouse, startSize
		grip.InputBegan:Connect(function(input)
			if pressed(input) then
				resizing, startMouse, startSize = true, input.Position, outer.AbsoluteSize
			end
		end)
		uiMaid:Connect(UserInputService.InputChanged, function(input)
			if resizing and moved(input) then
				local d = input.Position - startMouse
				outer.Size = UDim2.fromOffset(
					math.clamp(startSize.X + d.X, MIN_SIZE.X, MAX_SIZE.X),
					math.clamp(startSize.Y + d.Y, MIN_SIZE.Y, MAX_SIZE.Y)
				)
			end
		end)
		uiMaid:Connect(UserInputService.InputEnded, function(input)
			if pressed(input) then
				resizing = false
			end
		end)
	end

	state.themeKey = themeKey()
	updateMarkerControls()
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
			sink,
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

local function updateHitboxes(position)
	ui.boxes = ui.boxes or {}
	local r = state.entry and Reactions.get(state.entry.id)
	local root = state.rig and state.rig.PrimaryPart
	local hits = (root and r and r.hits) or {}
	for i, h in ipairs(hits) do
		local box = ui.boxes[i]
		if not box then
			box = new("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 60, 60),
				Transparency = 0.75,
				Parent = ui.world,
			})
			ui.boxes[i] = box
		end
		local active = math.abs(position - h.t) < 0.12
		box.Transparency = active and 0.6 or 1
		if active then
			box.Size = Vector3.new(h.size[1], h.size[2], h.size[3])
			box.CFrame = root.CFrame * CFrame.new(h.offset[1], h.offset[2], h.offset[3])
		end
	end
	for i = #hits + 1, #ui.boxes do
		ui.boxes[i].Transparency = 1
	end
end

local function step()
	setCameraBlocked(gui.Enabled and (state.orbiting or state.scrubbing or mouseOverWindow()))

	local now = os.clock()
	if now - state.lastThemeCheck > 0.5 then
		state.lastThemeCheck = now
		local key = themeKey()
		if key ~= state.themeKey then
			state.themeKey = key
			applyTheme()
			updateMarkerControls()
			state.listDirty = true
			state.markersDirty = true
		end
	end

	if state.listDirty and now - state.lastListRefresh > 0.3 then
		refreshList()
	end
	if state.markersDirty then
		refreshMarkers()
	end

	local cam = ui.camera
	local center = Vector3.new(0, state.height, 0)
	cam.CFrame = CFrame.new(center)
		* CFrame.Angles(0, state.yaw, 0)
		* CFrame.Angles(-state.pitch, 0, 0)
		* CFrame.new(0, 0, state.zoom)

	local track = state.track
	local length = track and track.Length or 0
	local position = 0
	if state.finished then
		position = length
	elseif track and length > 0 then
		position = math.clamp(track.TimePosition, 0, length)
	end
	ui.progress.Size = UDim2.fromScale(length > 0 and position / length or 0, 1)
	ui.time.Text = string.format("%.2fs / %.2fs", position, length)
	updateHitboxes(position)
end

function PreviewWindow.setLibrary(lib)
	library = lib
	if gui then
		applyTheme()
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
	state.markersDirty = true

	if not state.entry then
		ui.title.Text = "Preview"
		setStatus("Pick an animation from the list.")
	end
end

function PreviewWindow.show(entry)
	if not state.entry or state.entry.id ~= entry.id then
		state.markerIndex = nil
	end
	state.entry = entry
	PreviewWindow.open()

	ui.title.Text = string.format("Preview - %s [%s]", entry.name, entry.id)
	state.playing = true

	rebuildRig()
	state.markersDirty = true
end

function PreviewWindow.close()
	if not gui then
		return
	end
	gui.Enabled = false
	state.entry = nil
	state.markerIndex = nil
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

	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(themed)
	table.clear(ui)
end

return PreviewWindow
end

__modules["Features/AnimationLogger/Rig"] = function()
local Services = require("Util/Services")
local Tracker = require("Features/AnimationLogger/Tracker")

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

		local folder = Tracker.folder()
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
end

__modules["Features/AnimationLogger"] = function()
local Services = require("Util/Services")
local Clipboard = require("Util/Clipboard")
local LazyDropdown = require("Util/LazyDropdown")
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
	IgnoreOptions = { "Search", "AnimList" },
}

local function label(entry)
	return string.format("%s [%s]", entry.name, entry.id)
end

function AnimationLogger.build(Tab, ctx)
	local Library, maid, notify = ctx.Library, ctx.maid, ctx.notify
	PreviewWindow.setLibrary(Library)

	local state = {
		search = "",
		onlyMe = false,
		notify = false,
		selectedId = nil,
		labelToId = {},
		summaryDirty = true,
		detailsDirty = true,
	}

	local function currentList()
		return Logger.list({
			text = state.search,
			onlyOwner = state.onlyMe and LocalPlayer.Name or nil,
		})
	end

	local function selected()
		return state.selectedId and Logger.get(state.selectedId)
	end

	local list
	local function changed()
		state.summaryDirty = true
		if list then
			list.markDirty()
		end
	end

	local Filters = Tab:AddLeftGroupbox("Filters")

	Filters:AddInput("Search", {
		Text = "Search",
		Placeholder = "name, id or player...",
		Default = "",
		Numeric = false,
		Finished = false,
		ClearTextOnFocus = false,
		Callback = function(text)
			state.search = text:lower()
			changed()
		end,
	})

	Filters:AddToggle("OnlyMe", {
		Text = "Only my animations",
		Default = false,
		Callback = function(value)
			state.onlyMe = value
			changed()
		end,
	})

	Filters:AddToggle("Paused", {
		Text = "Pause logging",
		Default = false,
		Callback = function(value)
			Logger.paused = value
			state.summaryDirty = true
		end,
	})

	Filters:AddToggle("NotifyNew", {
		Text = "Notify on new animation",
		Default = false,
		Callback = function(value)
			state.notify = value
		end,
	})

	local Log = Tab:AddRightGroupbox("Animations")

	local summary = Log:AddLabel("0 logged")
	local status = Log:AddLabel("Listening for animations...")

	local dropdown = Log:AddDropdown("AnimList", {
		Text = "Logged animations",
		Tooltip = "Most recently played first. Updates when you open it",
		Values = {},
		Multi = false,
		Searchable = true,
		AllowNull = true,
		MaxVisibleDropdownItems = 10,
		Callback = function(value)
			local previous = state.selectedId
			state.selectedId = value and state.labelToId[value] or state.selectedId
			state.detailsDirty = true

			local e = selected()
			if e and e.id ~= previous and PreviewWindow.isOpen() then
				PreviewWindow.show(e)
			end
		end,
	})

	list = LazyDropdown.wrap(dropdown, function()
		local values, labelToId = {}, {}
		for i, e in ipairs(currentList()) do
			if i > Config.AnimationLogger.MaxDropdownItems then
				break
			end
			local l = label(e)
			table.insert(values, l)
			labelToId[l] = e.id
		end
		state.labelToId = labelToId
		return values
	end)

	local details = {
		Log:AddLabel("Nothing selected."),
		Log:AddLabel(""),
		Log:AddLabel(""),
		Log:AddLabel(""),
	}

	local lastSummary, lastDetails
	local function updateSummary()
		local counts = string.format("%d logged, %d shown", Logger.count, #currentList())
		local text = Logger.paused and "Logging is paused." or "Listening for animations..."
		if counts .. text ~= lastSummary then
			lastSummary = counts .. text
			summary:SetText(counts)
			status:SetText(text)
		end
	end

	local function short(text, max)
		if #text > max then
			return text:sub(1, max - 3) .. "..."
		end
		return text
	end

	local function updateDetails()
		local e = selected()
		local lines = e
				and {
					short(e.name, 34),
					"ID: " .. e.id,
					short("Played by: " .. table.concat(e.ownerList, ", "), 34),
					"Times played: " .. e.plays,
				}
			or { "Nothing selected.", "", "", "" }
		local text = table.concat(lines, "\n")
		if text ~= lastDetails then
			lastDetails = text
			for i, line in ipairs(lines) do
				details[i]:SetText(line)
			end
		end
	end

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

	Log:AddButton({
		Text = "Copy ID",
		Tooltip = "Copies rbxassetid://<id>",
		Func = withSelected(function(e)
			local ok = Clipboard.copy("rbxassetid://" .. e.id)
			notify(ok and "Copied" or "Clipboard unavailable", e.id)
		end),
	}):AddButton({
		Text = "Number only",
		Func = withSelected(function(e)
			local ok = Clipboard.copy(e.id)
			notify(ok and "Copied" or "Clipboard unavailable", e.id)
		end),
	})

	Log:AddButton({
		Text = "Play on me",
		Tooltip = "Preview it on your own character",
		Func = withSelected(function(e)
			local ok, err = Preview.play(e.id)
			if not ok then
				notify("Couldn't play", err)
			end
		end),
	}):AddButton({ Text = "Stop", Func = Preview.stop })

	Log:AddButton({
		Text = "Open preview window",
		Tooltip = "Pop-out 3D rig viewer with its own animation list",
		Func = function()
			local e = selected()
			if e then
				PreviewWindow.show(e)
			else
				PreviewWindow.open()
			end
		end,
	})

	local Tools = Tab:AddLeftGroupbox("Tools")

	Tools:AddButton({
		Text = "Scan game",
		Tooltip = "Find Animation objects that exist but aren't playing",
		Func = function()
			local found = Scanner.scan()
			notify("Scan finished", string.format("%d new animation(s) found", found))
		end,
	})

	Tools:AddButton({
		Text = "Copy all shown",
		Func = function()
			local shown = currentList()
			local ok = Clipboard.copy(Exporter.toText(shown))
			notify(ok and "Copied" or "Clipboard unavailable", string.format("%d animation(s)", #shown))
		end,
	})

	Tools:AddButton({
		Text = "Save to file",
		Tooltip = "Writes to workspace/" .. Config.AnimationLogger.SaveFolder,
		Func = function()
			local ok, result = Exporter.save(currentList())
			notify(ok and "Saved" or "Save failed", result)
		end,
	})

	Tools:AddButton({
		Text = "Clear log",
		Tooltip = "Double click to remove every logged animation",
		DoubleClick = true,
		Func = Logger.clear,
	})

	maid:Connect(Logger.Added, function(entry)
		changed()
		local now = os.clock()
		if state.notify and now - (state.lastNotify or 0) > 0.5 then
			state.lastNotify = now
			notify("New animation", label(entry))
		end
	end)
	maid:Connect(Logger.Updated, function(entry, didChange)
		if didChange then
			changed()
		end
		if entry.id == state.selectedId then
			state.detailsDirty = true
		end
	end)
	maid:Connect(Logger.Cleared, function()
		state.selectedId = nil
		state.detailsDirty = true
		changed()
	end)

	maid:Spawn(function()
		while not Library.Unloaded do
			if state.summaryDirty then
				state.summaryDirty = false
				pcall(updateSummary)
			end
			if state.detailsDirty then
				state.detailsDirty = false
				pcall(updateDetails)
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
local Hitboxes = require("Features/AutoReact/Hitboxes")
local HitboxView = require("Features/AutoReact/HitboxView")

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
		facingOnly = true,
		useHitboxes = true,
		hitboxPadding = Config.AutoReact.HitboxPadding,
		facingAngle = 70,
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

function Engine.send(action, hold)
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
		task.delay(hold or Engine.settings.blockHold, function()
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

local function insideHitbox(model, hit)
	local mine = rootOf(LocalPlayer.Character)
	local theirs = rootOf(model)
	if not mine or not theirs then
		return false
	end
	local o, sz = hit.offset, hit.size
	local center = theirs.CFrame * CFrame.new(o[1], o[2], o[3])
	local p = center:PointToObjectSpace(mine.Position)
	local pad = Engine.settings.hitboxPadding
	return math.abs(p.X) <= sz[1] / 2 + pad and math.abs(p.Y) <= sz[2] / 2 + pad + 2 and math.abs(p.Z) <= sz[3] / 2 + pad
end

local HIT_BEFORE = 0.35
local HIT_AFTER = 0.2

local function wasHit(model, start)
	for _, at in ipairs(Tracker.damagedAt[model] or {}) do
		if at >= start - HIT_BEFORE and at <= start + HIT_AFTER then
			return true
		end
	end
	return false
end

local function facingMe(model)
	local mine = rootOf(LocalPlayer.Character)
	local theirs = rootOf(model)
	if not mine or not theirs then
		return false
	end
	local offset = mine.Position - theirs.Position
	offset = Vector3.new(offset.X, 0, offset.Z)
	if offset.Magnitude < 0.5 then
		return true
	end
	local look = theirs.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		return true
	end
	return look.Unit:Dot(offset.Unit) >= math.cos(math.rad(Engine.settings.facingAngle))
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
	if not s.enabled and not s.learn and not HitboxView.enabled then
		return
	end
	local id = Reactions.cleanId(rawId)
	local known = id and Reactions.get(id)
	local reach = s.useHitboxes and Reactions.reach(known, s.hitboxPadding) or 0
	if distanceTo(model) > math.max(s.range, reach) then
		return
	end

	if not id or Reactions.isIgnored(id) then
		return
	end
	local now = os.clock()
	if wasHit(model, now) then
		return
	end

	if s.learn and not track.Looped then
		prune(os.clock())
		table.insert(pending, { id = id, model = model, track = track, start = os.clock() })
	end

	local r = Reactions.get(id)
	if HitboxView.enabled and r and r.hits then
		local viewSpeed = trackSpeed(track)
		for _, h in ipairs(r.hits) do
			local thread
			thread = task.delay(math.max(0, h.t / viewSpeed - 0.12), function()
				maid:Remove(thread, true)
				if track.IsPlaying then
					HitboxView.show(model, h, 0.3, s.hitboxPadding)
				end
			end)
			maid:Give(thread)
		end
	end

	if not s.enabled then
		return
	end
	if not r or #r.markers == 0 or (r.learned and not s.useLearned) then
		return
	end
	if s.facingOnly and not facingMe(model) then
		return
	end

	local speed = trackSpeed(track)
	local early = s.lead + Engine.pingOffset()
	for _, marker in ipairs(r.markers) do
		local wait = math.max(0, marker.t / speed - early)
		local action = marker.action
		local hold = marker.hold and marker.hold / speed or nil
		local thread
		thread = task.delay(wait, function()
			maid:Remove(thread, true)
			if not Engine.settings.enabled or wasHit(model, now) then
				return
			end
			if not track.IsPlaying and wait > 0.05 then
				return
			end
			local hit = Engine.settings.useHitboxes and Reactions.hitNear(r, marker.t)
			if hit then
				if not insideHitbox(model, hit) then
					return
				end
			elseif distanceTo(model) > Engine.settings.range then
				return
			end
			Engine.send(action, hold)
		end)
		maid:Give(thread)
	end
end

local function onDamaged()
	local now = os.clock()
	prune(now)
	local best, bestDistance
	for _, p in ipairs(pending) do
		if now - p.start > 0.05 and not wasHit(p.model, p.start) and not Reactions.isIgnored(p.id) then
			local distance = distanceTo(p.model)
			if
				distance <= Engine.settings.range + 6
				and (
					not best
					or distance < bestDistance - 2
					or (math.abs(distance - bestDistance) <= 2 and p.start > best.start)
				)
			then
				best, bestDistance = p, distance
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

	Hitboxes.start(maid)
	maid:Connect(Hitboxes.Recorded, function(id, t, size, offset)
		HitboxView.show(LocalPlayer.Character, {
			size = { size.X, size.Y, size.Z },
			offset = { offset.X, offset.Y, offset.Z },
		}, 0.35, 0, true)
		local r, isNew = Reactions.addHit(id, t, size, offset, Engine.settings.learnAction)
		if isNew then
			Engine.Learned:Fire(id, r, "hitbox")
		end
	end)

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
		HitboxView.clear()
		table.clear(pending)
		for code in pairs(held) do
			pcall(release, code)
		end
		table.clear(held)
	end)
end

return Engine
end

__modules["Features/AutoReact/HitboxView"] = function()
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
end

__modules["Features/AutoReact/Hitboxes"] = function()
local Services = require("Util/Services")
local Config = require("Config")
local Signal = require("Util/Signal")
local Tracker = require("Features/AnimationLogger/Tracker")

local LocalPlayer = Services.Players.LocalPlayer

local Hitboxes = {
	enabled = false,
	Recorded = Signal.new(),
}

local METHODS = { GetPartsInPart = true, GetPartBoundsInBox = true, GetPartBoundsInRadius = true }

local installed = false
local original
local patched = {}
local lastMove

local function record(method, a, b)
	local move = lastMove
	if not move or not move.track.IsPlaying then
		return
	end
	local t = move.track.TimePosition
	if move.lastT and math.abs(t - move.lastT) < 0.15 then
		return
	end
	move.lastT = t
	local character = LocalPlayer.Character
	local root = character and character.HumanoidRootPart
	if not root then
		return
	end

	local cf, size
	if method == "GetPartsInPart" then
		if typeof(a) ~= "Instance" then
			return
		end
		cf, size = a.CFrame, a.Size
	elseif method == "GetPartBoundsInBox" then
		if typeof(a) ~= "CFrame" or typeof(b) ~= "Vector3" then
			return
		end
		cf, size = a, b
	else
		if typeof(a) ~= "Vector3" or type(b) ~= "number" then
			return
		end
		cf, size = a, b
	end

	task.defer(function(rootCFrame, id, t)
		local position = typeof(cf) == "CFrame" and cf.Position or cf
		local boxSize = typeof(size) == "Vector3" and size or Vector3.one * size * 2
		Hitboxes.Recorded:Fire(id, t, boxSize, rootCFrame:PointToObjectSpace(position))
	end, root.CFrame, move.id, t)
end

local function findModule()
	local current = game
	for name in string.gmatch(Config.AutoReact.HitboxModule or "", "[^%.]+") do
		local ok, child = pcall(function()
			return current == game and game:GetService(name) or current:FindFirstChild(name)
		end)
		if not ok or not child then
			return nil
		end
		current = child
	end
	return current ~= game and current:IsA("ModuleScript") and current or nil
end

local function patchModule()
	local module = findModule()
	if not module then
		return false
	end
	local ok, lib = pcall(require, module)
	if not ok or type(lib) ~= "table" then
		return false
	end
	for name in pairs(METHODS) do
		local fn = rawget(lib, name)
		if type(fn) == "function" then
			patched[name] = { lib = lib, fn = fn }
			lib[name] = function(...)
				if Hitboxes.enabled then
					local args = table.pack(...)
					local first = typeof(args[1]) == "table" and 2 or 1
					pcall(record, name, args[first], args[first + 1])
				end
				return fn(...)
			end
		end
	end
	return next(patched) ~= nil
end

function Hitboxes.install(mode)
	if installed then
		return true
	end
	if mode ~= "Namecall" and patchModule() then
		installed = "module"
		return true
	end
	if not (hookmetamethod and getnamecallmethod and checkcaller) then
		return false
	end
	local wrap = newcclosure or function(f)
		return f
	end
	original = hookmetamethod(
		game,
		"__namecall",
		wrap(function(self, ...)
			if Hitboxes.enabled and self == workspace and not checkcaller() then
				local method = getnamecallmethod()
				if METHODS[method] then
					pcall(record, method, ...)
				end
			end
			return original(self, ...)
		end)
	)
	installed = "namecall"
	return true
end

function Hitboxes.mode()
	return installed
end

function Hitboxes.uninstall()
	if installed == "namecall" and original then
		pcall(hookmetamethod, game, "__namecall", original)
	end
	for name, p in pairs(patched) do
		p.lib[name] = p.fn
	end
	table.clear(patched)
	installed = false
end

function Hitboxes.start(maid)
	maid:Connect(Tracker.Played, function(model, track, rawId)
		if model == LocalPlayer.Character and not track.Looped then
			local id = tostring(rawId):match("%d+")
			if id then
				lastMove = { id = id, track = track }
			end
		end
	end)
	maid:Give(function()
		Hitboxes.enabled = false
		Hitboxes.uninstall()
		lastMove = nil
	end)
end

return Hitboxes
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

local function gameKey()
	return game.GameId ~= 0 and game.GameId or game.PlaceId
end

local function path(id)
	return string.format("%s/%d.json", Config.AutoReact.Folder, id or gameKey())
end

local function cleanId(raw)
	return raw and tostring(raw):match("%d+")
end

Reactions.cleanId = cleanId

local function sortMarkers(r)
	table.sort(r.markers, function(a, b)
		return a.t < b.t
	end)
end

local function migrate(r)
	r.samples = r.samples or {}
	r.markers = r.markers or {}
	if #r.markers == 0 and r.action and r.hit then
		table.insert(r.markers, { t = r.hit, action = r.action })
	end
	r.action, r.hit, r.manualHit = nil, nil, nil
	for _, m in ipairs(r.markers) do
		m.t = tonumber(m.t) or 0
		if m.action ~= "Block" then
			m.hold = nil
		end
	end
	sortMarkers(r)
	return r
end

function Reactions.load()
	table.clear(Reactions.data)
	if not (readfile and isfile) then
		return
	end
	local ok, raw = pcall(function()
		for _, file in ipairs({ path(), path(game.PlaceId) }) do
			if isfile(file) then
				return readfile(file)
			end
		end
	end)
	if not ok or not raw then
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if decoded and type(data) == "table" then
		for id, r in pairs(data) do
			if type(r) == "table" then
				Reactions.data[tostring(id)] = migrate(r)
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

local function changed(id)
	Reactions.Changed:Fire(id)
	Reactions.save()
end

function Reactions.get(id)
	return Reactions.data[cleanId(id) or ""]
end

function Reactions.markers(id)
	local r = Reactions.get(id)
	return r and r.markers or {}
end

function Reactions.has(id)
	return #Reactions.markers(id) > 0
end

local hardIgnored = {}
for _, id in ipairs(Config.AutoReact.IgnoreIds or {}) do
	local clean = cleanId(id)
	if clean then
		hardIgnored[clean] = true
	end
end

function Reactions.isIgnored(id)
	id = cleanId(id)
	if not id then
		return false
	end
	if hardIgnored[id] then
		return true
	end
	local r = Reactions.data[id]
	return r ~= nil and r.ignored == true
end

function Reactions.setIgnored(id, ignored)
	id = cleanId(id)
	if not id then
		return
	end
	local r = Reactions.data[id] or { samples = {}, markers = {} }
	Reactions.data[id] = r
	r.ignored = ignored or nil
	changed(id)
end

local function ensure(id)
	local r = Reactions.data[id]
	if not r then
		r = { samples = {}, markers = {} }
		Reactions.data[id] = r
	end
	return r
end

function Reactions.addMarker(id, t, action, hold)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	r.learned = false
	local marker = { t = math.max(0, t), action = action, hold = action == "Block" and hold or nil }
	table.insert(r.markers, marker)
	sortMarkers(r)
	changed(id)
	return table.find(r.markers, marker)
end

function Reactions.updateMarker(id, index, fields)
	id = cleanId(id)
	local r = id and Reactions.data[id]
	local marker = r and r.markers[index]
	if not marker then
		return index
	end
	for k, v in pairs(fields) do
		marker[k] = v
	end
	marker.t = math.max(0, marker.t)
	if marker.action ~= "Block" then
		marker.hold = nil
	end
	r.learned = false
	sortMarkers(r)
	changed(id)
	return table.find(r.markers, marker)
end

function Reactions.removeMarker(id, index)
	id = cleanId(id)
	local r = id and Reactions.data[id]
	if r and r.markers[index] then
		table.remove(r.markers, index)
		changed(id)
	end
end

function Reactions.addSample(id, hit, defaultAction)
	id = cleanId(id)
	if not id then
		return
	end
	if Reactions.isIgnored(id) then
		return nil
	end
	local r = ensure(id)
	local samples = r.samples
	table.insert(samples, hit)
	while #samples > Config.AutoReact.MaxSamples do
		table.remove(samples, 1)
	end

	if r.learned or #r.markers == 0 then
		local sorted = table.clone(samples)
		table.sort(sorted)
		local action = r.markers[1] and r.markers[1].action or defaultAction
		r.markers = { { t = sorted[math.ceil(#sorted / 2)], action = action } }
		r.learned = true
	end
	changed(id)
	return r
end

local function vec(v)
	return { math.floor(v.X * 100 + 0.5) / 100, math.floor(v.Y * 100 + 0.5) / 100, math.floor(v.Z * 100 + 0.5) / 100 }
end

function Reactions.addHit(id, t, size, offset, defaultAction)
	id = cleanId(id)
	if not id then
		return
	end
	if Reactions.isIgnored(id) then
		return nil, false
	end
	local r = ensure(id)
	r.hits = r.hits or {}

	local merged
	for _, h in ipairs(r.hits) do
		if math.abs(h.t - t) < 0.08 then
			h.t = (h.t * h.n + t) / (h.n + 1)
			h.n += 1
			h.size = vec(Vector3.new(
				math.max(h.size[1], size.X),
				math.max(h.size[2], size.Y),
				math.max(h.size[3], size.Z)
			))
			h.offset = vec(offset)
			merged = h
			break
		end
	end
	if not merged then
		table.insert(r.hits, { t = t, n = 1, size = vec(size), offset = vec(offset) })
		table.sort(r.hits, function(a, b)
			return a.t < b.t
		end)
		while #r.hits > 8 do
			table.remove(r.hits)
		end
	end

	if r.learned or #r.markers == 0 then
		local action = r.markers[1] and r.markers[1].action or defaultAction
		r.markers = {}
		for _, h in ipairs(r.hits) do
			table.insert(r.markers, { t = h.t, action = action })
		end
		r.learned = true
	end
	changed(id)
	return r, merged == nil
end

function Reactions.hitNear(r, t)
	local best, bestGap
	for _, h in ipairs(r and r.hits or {}) do
		local gap = math.abs(h.t - t)
		if gap < 0.25 and (not best or gap < bestGap) then
			best, bestGap = h, gap
		end
	end
	return best
end

function Reactions.reach(r, padding)
	local reach = 0
	for _, h in ipairs(r and r.hits or {}) do
		local o, sz = h.offset, h.size
		local d = math.sqrt(o[1] ^ 2 + o[2] ^ 2 + o[3] ^ 2) + math.max(sz[1], sz[2], sz[3]) / 2 + (padding or 0)
		reach = math.max(reach, d)
	end
	return reach
end

function Reactions.hitboxCount()
	local n = 0
	for _, r in pairs(Reactions.data) do
		if r.hits and #r.hits > 0 then
			n += 1
		end
	end
	return n
end

function Reactions.clear(id)
	id = cleanId(id)
	if id and Reactions.data[id] then
		Reactions.data[id] = nil
		changed(id)
	end
end

function Reactions.clearAll()
	table.clear(Reactions.data)
	changed(nil)
end

function Reactions.describeMarker(m)
	if m.action == "Block" and m.hold then
		return string.format("%s %.2fs (hold %.2fs)", m.action, m.t, m.hold)
	end
	return string.format("%s %.2fs", m.action, m.t)
end

function Reactions.describe(id)
	local r = Reactions.get(id)
	if r and r.ignored then
		return "Ignored"
	end
	if not r or #r.markers == 0 then
		return "No reaction set"
	end
	local parts = {}
	for i, m in ipairs(r.markers) do
		if i > 3 then
			table.insert(parts, string.format("+%d more", #r.markers - 3))
			break
		end
		table.insert(parts, Reactions.describeMarker(m))
	end
	local text = table.concat(parts, ", ")
	if r.hits and #r.hits > 0 then
		text ..= " [hitbox]"
	end
	if r.learned then
		text ..= " (learned)"
	end
	return text
end

return Reactions
end

__modules["Features/AutoReact"] = function()
local Logger = require("Features/AnimationLogger/Logger")
local LazyDropdown = require("Util/LazyDropdown")
local PreviewWindow = require("Features/AnimationLogger/PreviewWindow")
local Reactions = require("Features/AutoReact/Reactions")
local Engine = require("Features/AutoReact/Engine")
local Hitboxes = require("Features/AutoReact/Hitboxes")
local HitboxView = require("Features/AutoReact/HitboxView")

local AutoReact = {
	Title = "Auto react",
	IgnoreOptions = { "ReactSaved" },
}

local function labelFor(id)
	local entry = Logger.get(id)
	local name = entry and entry.name or "Unknown"
	return string.format("%s [%s] - %s", name, id, Reactions.describe(id))
end

function AutoReact.build(Tab, ctx)
	local Library, maid, notify = ctx.Library, ctx.maid, ctx.notify
	local settings = Engine.settings
	local state = { labelToId = {}, selectedId = nil, summaryDirty = true, notifyLearn = true }

	local Main = Tab:AddLeftGroupbox("Auto react")

	Main:AddToggle("ReactEnabled", {
		Text = "Enabled",
		Tooltip = "Presses the key at the hit time when someone near you plays a reaction animation. Set reactions in the preview window or turn on learning",
		Default = false,
		Risky = true,
		Callback = function(value)
			settings.enabled = value
		end,
	})

	Main:AddToggle("ReactUseLearned", {
		Text = "React to learned animations",
		Default = true,
		Callback = function(value)
			settings.useLearned = value
		end,
	})

	Main:AddToggle("ReactFacing", {
		Text = "Only when they face me",
		Tooltip = "Skip attacks from players who are turned away from you",
		Default = settings.facingOnly,
		Callback = function(value)
			settings.facingOnly = value
		end,
	})

	Main:AddSlider("ReactFacingAngle", {
		Text = "Facing angle",
		Suffix = "°",
		Default = settings.facingAngle,
		Min = 20,
		Max = 180,
		Rounding = 0,
		Callback = function(value)
			settings.facingAngle = value
		end,
	})

	Main:AddSlider("ReactRange", {
		Text = "Range",
		Suffix = " studs",
		Default = settings.range,
		Min = 4,
		Max = 80,
		Rounding = 0,
		Callback = function(value)
			settings.range = value
		end,
	})

	Main:AddSlider("ReactLead", {
		Text = "Press early",
		Suffix = " ms",
		Tooltip = "Raise this if you're still getting hit",
		Default = math.floor(settings.lead * 1000),
		Min = 0,
		Max = 400,
		Rounding = 0,
		Callback = function(value)
			settings.lead = value / 1000
		end,
	})

	Main:AddSlider("ReactBlockHold", {
		Text = "Block hold time",
		Suffix = " s",
		Default = settings.blockHold,
		Min = 0.1,
		Max = 3,
		Rounding = 2,
		Callback = function(value)
			settings.blockHold = value
		end,
	})

	local Ping = Tab:AddLeftGroupbox("Ping")

	local pingInfo = Ping:AddLabel("Ping: ...")
	local earlyInfo = Ping:AddLabel("Pressing early: ...")

	Ping:AddDropdown("ReactPingMode", {
		Text = "Ping adjustment",
		Tooltip = "Auto reads your ping, Manual uses the slider below",
		Values = { "Auto", "Manual", "Off" },
		Default = settings.pingMode,
		Callback = function(value)
			settings.pingMode = value
		end,
	})

	Ping:AddSlider("ReactPingScale", {
		Text = "Auto amount",
		Suffix = "%",
		Tooltip = "How much of your ping to press early by. 50% is one-way latency",
		Default = math.floor(settings.pingScale * 100),
		Min = 0,
		Max = 150,
		Rounding = 0,
		Callback = function(value)
			settings.pingScale = value / 100
		end,
	})

	Ping:AddSlider("ReactPingManual", {
		Text = "Manual adjustment",
		Suffix = " ms",
		Default = settings.pingManual,
		Min = 0,
		Max = 500,
		Rounding = 0,
		Callback = function(value)
			settings.pingManual = value
		end,
	})

	local Keys = Tab:AddRightGroupbox("Keys")

	for _, action in ipairs(Reactions.ACTIONS) do
		Keys:AddInput("ReactKey" .. action, {
			Text = action .. " key",
			Default = settings.keys[action],
			Placeholder = "F",
			Numeric = false,
			Finished = true,
			ClearTextOnFocus = false,
			Callback = function(value)
				local ok = pcall(function()
					return Enum.KeyCode[value]
				end)
				if ok and value ~= "" then
					settings.keys[action] = value
				end
			end,
		})
	end

	Keys:AddButton({
		Text = "Test Parry",
		Func = function()
			Engine.send("Parry")
		end,
	})
		:AddButton({
			Text = "Test Block",
			Func = function()
				Engine.send("Block")
			end,
		})
	Keys:AddButton({
		Text = "Test Dash",
		Func = function()
			Engine.send("Dash")
		end,
	})

	Keys:AddDropdown("ReactInputMethod", {
		Text = "Input method",
		Tooltip = "Auto uses keypress when available, otherwise VirtualInputManager",
		Values = { "Auto", "VirtualInputManager" },
		Default = "Auto",
		Callback = function(value)
			settings.inputMethod = value
		end,
	})

	local Learn = Tab:AddRightGroupbox("Learn from damage")

	Learn:AddToggle("ReactLearn", {
		Text = "Learn from damage",
		Tooltip = "When you take damage, the latest attack animation from someone in range is saved with that hit time. Get hit by a move a couple of times to make it reliable",
		Default = false,
		Callback = function(value)
			settings.learn = value
		end,
	})

	Learn:AddDropdown("ReactLearnAction", {
		Text = "Learned animations use",
		Values = Reactions.ACTIONS,
		Default = settings.learnAction,
		Callback = function(value)
			settings.learnAction = value
		end,
	})

	Learn:AddSlider("ReactLearnWindow", {
		Text = "Max time to hit",
		Suffix = " s",
		Tooltip = "Animations that started longer ago than this are ignored",
		Default = settings.learnWindow,
		Min = 0.3,
		Max = 4,
		Rounding = 1,
		Callback = function(value)
			settings.learnWindow = value
		end,
	})

	Learn:AddToggle("ReactNotifyLearn", {
		Text = "Notify when something is learned",
		Default = true,
		Callback = function(value)
			state.notifyLearn = value
		end,
	})

	local Boxes = Tab:AddLeftGroupbox("Hitboxes")

	local hitboxInfo = Boxes:AddLabel("0 moves recorded")
	local hookMode = "Auto"

	Boxes:AddToggle("ReactRecordHitboxes", {
		Text = "Record my hitboxes",
		Tooltip = "When you use a move, saves its hitbox size and hit time. Enemies using the same move then use that hitbox",
		Default = false,
		Callback = function(value)
			if value and not Hitboxes.install(hookMode) then
				notify("Hitboxes", "Couldn't hook the hitbox function in this game.")
			end
			Hitboxes.enabled = value
		end,
	})

	Boxes:AddDropdown("ReactHitboxHook", {
		Text = "Hook",
		Tooltip = "Auto patches the game's hitbox module (set in Config). Namecall catches every workspace hitbox query",
		Values = { "Auto", "Namecall" },
		Default = "Auto",
		Callback = function(value)
			hookMode = value
			if Hitboxes.mode() then
				Hitboxes.uninstall()
				Hitboxes.install(hookMode)
			end
		end,
	})

	Boxes:AddToggle("ReactUseHitboxes", {
		Text = "Use hitboxes for range",
		Tooltip = "Only react when you're inside the attacker's recorded hitbox. Moves without one use the studs range",
		Default = settings.useHitboxes,
		Callback = function(value)
			settings.useHitboxes = value
		end,
	})

	Boxes:AddToggle("ReactShowHitboxes", {
		Text = "Show hitboxes",
		Tooltip = "Draws recorded hitboxes in the world when someone uses a move: red if you're inside, yellow if not, green for your own while recording",
		Default = false,
		Callback = function(value)
			HitboxView.enabled = value
			if not value then
				HitboxView.clear()
			end
		end,
	})

	Boxes:AddSlider("ReactHitboxPadding", {
		Text = "Hitbox padding",
		Suffix = " studs",
		Default = settings.hitboxPadding,
		Min = 0,
		Max = 10,
		Rounding = 1,
		Callback = function(value)
			settings.hitboxPadding = value
		end,
	})

	local Saved = Tab:AddRightGroupbox("Saved reactions")

	local summary = Saved:AddLabel("0 saved for this game")

	local function savedIds()
		local ids = {}
		for id, r in pairs(Reactions.data) do
			if #r.markers > 0 or r.ignored then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		return ids
	end

	local dropdown = Saved:AddDropdown("ReactSaved", {
		Text = "Reactions",
		Values = {},
		Multi = false,
		Searchable = true,
		AllowNull = true,
		Callback = function(value)
			state.selectedId = value and state.labelToId[value] or nil
		end,
	})

	local list = LazyDropdown.wrap(dropdown, function()
		local values, labelToId = {}, {}
		for _, id in ipairs(savedIds()) do
			local l = labelFor(id)
			table.insert(values, l)
			labelToId[l] = id
		end
		state.labelToId = labelToId
		return values
	end)

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
		Text = "Open in preview",
		Func = withSelected(function(id)
			local entry = Logger.get(id)
			if entry then
				PreviewWindow.show(entry)
			else
				notify("Not logged yet", "That animation hasn't played this session.")
			end
		end),
	}):AddButton({
		Text = "Delete",
		Func = withSelected(function(id)
			Reactions.clear(id)
			state.selectedId = nil
		end),
	})

	Saved:AddButton({
		Text = "Ignore / unignore",
		Tooltip = "Ignored animations are never reacted to or learned, like hit reactions",
		Func = withSelected(function(id)
			Reactions.setIgnored(id, not Reactions.isIgnored(id))
		end),
	})

	Saved:AddButton({
		Text = "Delete all",
		Tooltip = "Double click to remove every saved reaction for this game",
		DoubleClick = true,
		Func = Reactions.clearAll,
	})

	maid:Connect(Reactions.Changed, function()
		state.summaryDirty = true
		list.markDirty()
	end)
	maid:Connect(Logger.Added, function(entry)
		if Reactions.get(entry.id) then
			list.markDirty()
		end
	end)
	maid:Connect(Engine.Learned, function(id, r, source)
		if state.notifyLearn and r then
			notify(source == "hitbox" and "Hitbox recorded" or "Learned", labelFor(id))
		end
	end)

	local lastPing
	maid:Spawn(function()
		while not Library.Unloaded do
			if state.summaryDirty then
				state.summaryDirty = false
				pcall(function()
					summary:SetText(string.format("%d saved for this game", #savedIds()))
					hitboxInfo:SetText(string.format("%d move(s) with a hitbox", Reactions.hitboxCount()))
				end)
			end
			pcall(function()
				local offset = Engine.pingOffset()
				local ping = string.format("Ping: %d ms", math.floor(Engine.ping() * 1000 + 0.5))
				local early = string.format(
					"Pressing %d ms early (%d + %d)",
					math.floor((offset + settings.lead) * 1000 + 0.5),
					math.floor(offset * 1000 + 0.5),
					math.floor(settings.lead * 1000 + 0.5)
				)
				local text = ping .. early
				if text ~= lastPing then
					lastPing = text
					pingInfo:SetText(ping)
					earlyInfo:SetText(early)
				end
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
	local Tab = Window:AddTab("Home")

	local executor = "unknown"
	if identifyexecutor then
		local ok, name, version = pcall(identifyexecutor)
		if ok and name then
			executor = tostring(name) .. (version and (" " .. tostring(version)) or "")
		end
	end

	local Info = Tab:AddLeftGroupbox(Config.Title .. " v" .. Config.Version)
	Info:AddLabel("Executor: " .. executor)
	Info:AddLabel("Game: " .. game.GameId)
	Info:AddLabel("Place: " .. game.PlaceId)
	Info:AddLabel("Toggle UI: " .. Config.ToggleKey.Name)

	local List = Tab:AddRightGroupbox("Features")
	for _, feature in ipairs(features) do
		List:AddLabel("• " .. feature.Title)
	end

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
	Library = load(Config.Linoria.Library),
	SaveManager = load(Config.Linoria.SaveManager),
	ThemeManager = load(Config.Linoria.ThemeManager),
}
end

__modules["UI/SettingsTab"] = function()
local Config = require("Config")

local SettingsTab = {}

function SettingsTab.build(Window, lib, features)
	local Library = lib.Library
	local Tab = Window:AddTab("Settings")

	local Menu = Tab:AddLeftGroupbox("Menu")
	Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
		Default = Config.ToggleKey.Name,
		NoUI = true,
		Text = "Menu keybind",
	})
	Menu:AddToggle("CustomCursor", {
		Text = "Custom cursor",
		Default = false,
		Callback = function(value)
			Library.ShowCustomCursor = value
		end,
	})
	Menu:AddButton({
		Text = "Unload",
		DoubleClick = true,
		Tooltip = "Double click to unload w_w",
		Func = function()
			Library:Unload()
		end,
	})
	Library.ToggleKeybind = Library.Options.MenuKeybind

	lib.ThemeManager:SetLibrary(Library)
	lib.SaveManager:SetLibrary(Library)

	lib.SaveManager:IgnoreThemeSettings()
	local ignore = { "MenuKeybind" }
	for _, feature in ipairs(features) do
		for _, option in ipairs(feature.IgnoreOptions or {}) do
			table.insert(ignore, option)
		end
	end
	lib.SaveManager:SetIgnoreIndexes(ignore)

	lib.ThemeManager:SetFolder(Config.ConfigFolder)
	lib.SaveManager:SetFolder(Config.ConfigFolder .. "/" .. tostring(game.GameId ~= 0 and game.GameId or game.PlaceId))

	lib.SaveManager:BuildConfigSection(Tab)
	lib.ThemeManager:ApplyToTab(Tab)

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

__modules["Util/LazyDropdown"] = function()
local LazyDropdown = {}

function LazyDropdown.wrap(dropdown, getValues)
	local self = { dirty = true, last = nil }

	local function same(a, b)
		if not a or #a ~= #b then
			return false
		end
		for i, v in ipairs(a) do
			if b[i] ~= v then
				return false
			end
		end
		return true
	end

	function self.rebuild()
		self.dirty = false
		local values = getValues()
		if not same(self.last, values) then
			self.last = values
			dropdown:SetValues(values)
		end
	end

	function self.markDirty()
		self.dirty = true
	end

	local open = dropdown.OpenDropdown
	dropdown.OpenDropdown = function(...)
		if self.dirty then
			pcall(self.rebuild)
		end
		return open(...)
	end

	return self
end

return LazyDropdown
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
local Library = lib.Library
local maid = Maid.new()

Library.ShowCustomCursor = false

local Window = Library:CreateWindow({
	Title = Config.Title .. " v" .. Config.Version,
	Center = true,
	AutoShow = true,
	Resizable = true,
	Size = Config.WindowSize,
	ShowCustomCursor = false,
	UnlockMouseWhileOpen = true,
	TabPadding = 8,
	MenuFadeTime = 0.2,
})

local function notify(title, content, duration)
	Library:Notify({ Title = title, Description = content or "", Time = duration or 3 })
end

local ctx = { Window = Window, Library = Library, maid = maid, notify = notify }

HomeTab.build(Window, Features)
for _, feature in ipairs(Features) do
	local Tab = Window:AddTab(feature.Title)
	local ok, err = pcall(feature.build, Tab, ctx)

	if not ok then
		notify(feature.Title .. " failed to load", tostring(err), 8)
	end
end

SettingsTab.build(Window, lib, Features)

Library:OnUnload(function()
	maid:Clean()
	env.__w_wUnload = nil
end)
env.__w_wUnload = function()
	if not Library.Unloaded then
		Library:Unload()
	end
end

notify(Config.Title, "Loaded. Press " .. Config.ToggleKey.Name .. " to hide/show.", 5)

lib.SaveManager:LoadAutoloadConfig()
end

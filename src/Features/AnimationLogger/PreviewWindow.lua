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
	if not state.entry then
		ui.markerInfo.Text = "Pick an animation first."
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

	ui.markerList = scrollList(markers, UDim2.fromOffset(0, 102), UDim2.new(1, 0, 1, -146))
	ui.markerRows = {}

	ui.markerInfo = label({
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -40),
		Text = "",
		TextSize = 12,
		ColorKey = "DisabledTextColor",
		Parent = markers,
	})

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

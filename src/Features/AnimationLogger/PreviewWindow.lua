local Services = require("Util/Services")
local Maid = require("Util/Maid")
local Rig = require("Features/AnimationLogger/Rig")
local Logger = require("Features/AnimationLogger/Logger")

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
local MIN_SIZE = Vector2.new(320 + LIST_WIDTH, 340)
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
		Size = UDim2.fromOffset(320 + LIST_WIDTH, 400),
		Position = UDim2.new(1, -(340 + LIST_WIDTH), 0.5, -200),
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
		Size = UDim2.new(1, -16, 1, -150),
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
		Position = UDim2.new(0, 8, 1, -103),
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
		Position = UDim2.new(0, 8, 1, -86),
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
		Position = UDim2.new(0, 8, 1, -54),
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
				main.Size = UDim2.fromOffset(math.clamp(startSize.X + d.X, MIN_SIZE.X, MAX_SIZE.X), math.clamp(startSize.Y + d.Y, MIN_SIZE.Y, MAX_SIZE.Y))
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
	cam.CFrame = CFrame.new(center) * CFrame.Angles(0, state.yaw, 0) * CFrame.Angles(-state.pitch, 0, 0) * CFrame.new(0, 0, state.zoom)

	local track = state.track
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
end

function PreviewWindow.show(entry)
	state.entry = entry
	PreviewWindow.open()

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

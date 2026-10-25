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

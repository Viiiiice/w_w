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

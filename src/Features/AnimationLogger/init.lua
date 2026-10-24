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
		Description = "Pop-out 3D rig that plays the animation",
		Callback = withSelected(PreviewWindow.show),
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

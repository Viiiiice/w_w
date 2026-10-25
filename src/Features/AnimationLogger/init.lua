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
	return string.format("%s  [%s]", entry.name, entry.id)
end

function AnimationLogger.build(Tab, ctx)
	local Library, maid, notify = ctx.Library, ctx.maid, ctx.notify

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

	local summary = Log:AddLabel("0 logged", true)

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

	local details = Log:AddLabel("Nothing selected.", true)

	local lastSummary, lastDetails
	local function updateSummary()
		local text = string.format(
			"%d logged  •  %d shown\n%s",
			Logger.count,
			#currentList(),
			Logger.paused and "Logging is paused." or "Listening for animations..."
		)
		if text ~= lastSummary then
			lastSummary = text
			summary:SetText(text)
		end
	end

	local function updateDetails()
		local e = selected()
		local text = e
				and string.format(
					"%s\nID: rbxassetid://%s\nPlayed by: %s\nTimes played: %d",
					e.name,
					e.id,
					table.concat(e.ownerList, ", "),
					e.plays
				)
			or "Nothing selected."
		if text ~= lastDetails then
			lastDetails = text
			details:SetText(text)
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

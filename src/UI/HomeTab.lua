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

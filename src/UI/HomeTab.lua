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

	local Info = Tab:AddLeftGroupbox(Config.Title .. "  v" .. Config.Version)
	Info:AddLabel(
		string.format("Executor: %s\nPlace: %d\nToggle UI: %s", executor, game.PlaceId, Config.ToggleKey.Name),
		true
	)

	local names = {}
	for _, feature in ipairs(features) do
		table.insert(names, "• " .. feature.Title)
	end
	local List = Tab:AddRightGroupbox("Features")
	List:AddLabel(table.concat(names, "\n"), true)

	return Tab
end

return HomeTab

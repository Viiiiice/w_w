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
	Info:AddLabel("Place: " .. game.PlaceId)
	Info:AddLabel("Toggle UI: " .. Config.ToggleKey.Name)

	local List = Tab:AddRightGroupbox("Features")
	for _, feature in ipairs(features) do
		List:AddLabel("• " .. feature.Title)
	end

	return Tab
end

return HomeTab

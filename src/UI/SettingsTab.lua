local Config = require("Config")

local SettingsTab = {}

function SettingsTab.build(Window, lib, features)
	local Tab = Window:AddTab({ Title = "Settings", Icon = "settings" })

	lib.SaveManager:SetLibrary(lib.Fluent)
	lib.InterfaceManager:SetLibrary(lib.Fluent)

	lib.SaveManager:IgnoreThemeSettings()
	local ignore = {}
	for _, feature in ipairs(features) do
		for _, option in ipairs(feature.IgnoreOptions or {}) do
			table.insert(ignore, option)
		end
	end
	lib.SaveManager:SetIgnoreIndexes(ignore)

	lib.InterfaceManager:SetFolder(Config.ConfigFolder)
	lib.SaveManager:SetFolder(Config.ConfigFolder .. "/" .. tostring(game.PlaceId))

	lib.InterfaceManager:BuildInterfaceSection(Tab)
	lib.SaveManager:BuildConfigSection(Tab)

	return Tab
end

return SettingsTab

local Config = require("Config")

local SettingsTab = {}

function SettingsTab.build(Window, lib, features)
	local Library = lib.Library
	local Tab = Window:AddTab("Settings")

	local Menu = Tab:AddLeftGroupbox("Menu")
	Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
		Default = Config.ToggleKey.Name,
		NoUI = true,
		Text = "Menu keybind",
	})
	Menu:AddToggle("CustomCursor", {
		Text = "Custom cursor",
		Default = false,
		Callback = function(value)
			Library.ShowCustomCursor = value
		end,
	})
	Menu:AddButton({
		Text = "Unload",
		DoubleClick = true,
		Tooltip = "Double click to unload w_w",
		Func = function()
			Library:Unload()
		end,
	})
	Library.ToggleKeybind = Library.Options.MenuKeybind

	lib.ThemeManager:SetLibrary(Library)
	lib.SaveManager:SetLibrary(Library)

	lib.SaveManager:IgnoreThemeSettings()
	local ignore = { "MenuKeybind" }
	for _, feature in ipairs(features) do
		for _, option in ipairs(feature.IgnoreOptions or {}) do
			table.insert(ignore, option)
		end
	end
	lib.SaveManager:SetIgnoreIndexes(ignore)

	lib.ThemeManager:SetFolder(Config.ConfigFolder)
	lib.SaveManager:SetFolder(Config.ConfigFolder .. "/" .. tostring(game.GameId ~= 0 and game.GameId or game.PlaceId))

	lib.SaveManager:BuildConfigSection(Tab)
	lib.ThemeManager:ApplyToTab(Tab)

	return Tab
end

return SettingsTab

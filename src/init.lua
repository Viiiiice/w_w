local Config = require("Config")
local Maid = require("Util/Maid")
local Features = require("Features/List")
local HomeTab = require("UI/HomeTab")
local SettingsTab = require("UI/SettingsTab")

local env = getgenv and getgenv() or _G
if env.__w_wUnload then
	pcall(env.__w_wUnload)
end

local lib = require("UI/Library")
local Library = lib.Library
local maid = Maid.new()

Library.ShowCustomCursor = false

local Window = Library:CreateWindow({
	Title = Config.Title .. "  v" .. Config.Version,
	Center = true,
	AutoShow = true,
	Resizable = true,
	Size = Config.WindowSize,
	ShowCustomCursor = false,
	UnlockMouseWhileOpen = true,
	TabPadding = 8,
	MenuFadeTime = 0.2,
})

local function notify(title, content, duration)
	Library:Notify({ Title = title, Description = content or "", Time = duration or 3 })
end

local ctx = { Window = Window, Library = Library, maid = maid, notify = notify }

HomeTab.build(Window, Features)
for _, feature in ipairs(Features) do
	local Tab = Window:AddTab(feature.Title)
	local ok, err = pcall(feature.build, Tab, ctx)

	if not ok then
		notify(feature.Title .. " failed to load", tostring(err), 8)
	end
end

SettingsTab.build(Window, lib, Features)

Library:OnUnload(function()
	maid:Clean()
	env.__w_wUnload = nil
end)
env.__w_wUnload = function()
	if not Library.Unloaded then
		Library:Unload()
	end
end

notify(Config.Title, "Loaded. Press " .. Config.ToggleKey.Name .. " to hide/show.", 5)

lib.SaveManager:LoadAutoloadConfig()

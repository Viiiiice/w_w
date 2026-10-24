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
local Fluent = lib.Fluent
local maid = Maid.new()

local Window = Fluent:CreateWindow({
	Title = Config.Title,
	SubTitle = "v" .. Config.Version,
	TabWidth = 160,
	Size = Config.WindowSize,
	Acrylic = false,
	Theme = Config.Theme,
	MinimizeKey = Config.ToggleKey,
})

local ctx = { Window = Window, Fluent = Fluent, maid = maid }

HomeTab.build(Window, Features)
for _, feature in ipairs(Features) do
	local Tab = Window:AddTab({ Title = feature.Title, Icon = feature.Icon })
	local ok, err = pcall(feature.build, Tab, ctx)

	if not ok then
		Fluent:Notify({ Title = feature.Title .. " failed to load", Content = tostring(err), Duration = 8 })
	end
end

SettingsTab.build(Window, lib, Features)
Window:SelectTab(1)

local function unload()
	maid:Clean()
	if not Fluent.Unloaded then
		Fluent:Destroy()
	end

	env.__w_wUnload = nil
end
env.__w_wUnload = unload

task.spawn(function()
	while not Fluent.Unloaded do
		task.wait(1)
	end
	
	maid:Clean()
end)

Fluent:Notify({
	Title = Config.Title,
	Content = "Loaded. Press " .. Config.ToggleKey.Name .. " to hide/show.",
	Duration = 5,
})

lib.SaveManager:LoadAutoloadConfig()

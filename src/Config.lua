return {
	Title = "w_w",
	Version = "0.1.0",
	ToggleKey = Enum.KeyCode.RightControl,
	WindowSize = UDim2.fromOffset(620, 580),
	Theme = "Dark",

	RootFolder = "w_w",
	ConfigFolder = "w_w/config",

	Linoria = {
		Library = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/Library.lua",
		SaveManager = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/addons/SaveManager.lua",
		ThemeManager = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/addons/ThemeManager.lua",
	},

	AnimationLogger = {
		SaveFolder = "w_w/animations",
		ScanFolder = "Auto",
		MaxDropdownItems = 60,
		RefreshInterval = 0.5,
	},

	AutoReact = {
		Folder = "w_w/reactions",
		Range = 18,
		Lead = 0.08,
		BlockHold = 0.45,
		LearnWindow = 1.5,
		Cooldown = 0.3,
		MaxSamples = 8,
		Keys = { Parry = "F", Block = "F", Dash = "Q" },
	},
}

return {
	Title = "w_w",
	Version = "0.1.0",
	ToggleKey = Enum.KeyCode.RightControl,
	WindowSize = UDim2.fromOffset(600, 480),
	Theme = "Dark",

	RootFolder = "w_w",
	ConfigFolder = "w_w/config",

	Fluent = {
		Library = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua",
		SaveManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
		InterfaceManager = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",
	},

	AnimationLogger = {
		SaveFolder = "w_w/animations",
		ScanFolder = "Alive",
		MaxDropdownItems = 200,
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

local Config = require("Config")

local function load(url)
	return loadstring(game:HttpGet(url))()
end

return {
	Fluent = load(Config.Fluent.Library),
	SaveManager = load(Config.Fluent.SaveManager),
	InterfaceManager = load(Config.Fluent.InterfaceManager),
}

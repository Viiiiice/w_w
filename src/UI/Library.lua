local Config = require("Config")

local function load(url)
	return loadstring(game:HttpGet(url))()
end

return {
	Library = load(Config.Linoria.Library),
	SaveManager = load(Config.Linoria.SaveManager),
	ThemeManager = load(Config.Linoria.ThemeManager),
}

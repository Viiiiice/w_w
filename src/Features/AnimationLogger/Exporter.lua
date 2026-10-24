local Config = require("Config")

local Exporter = {}

function Exporter.toText(entries)
	local lines = {}
	for _, e in ipairs(entries) do
		table.insert(
			lines,
			string.format("%s | rbxassetid://%s | %s", e.name, e.id, table.concat(e.ownerList, ", "))
		)
	end
	return table.concat(lines, "\n")
end

function Exporter.save(entries)
	if not writefile then
		return false, "writefile is not available"
	end

	local folder = Config.AnimationLogger.SaveFolder
	if makefolder and not (isfolder and isfolder(folder)) then
		pcall(makefolder, folder)
	end

	local path = string.format("%s/%d_%s.txt", folder, game.PlaceId, os.date("%Y%m%d_%H%M%S"))
	local ok, err = pcall(writefile, path, Exporter.toText(entries))
	if not ok then
		return false, tostring(err)
	end
	
	return true, path
end

return Exporter

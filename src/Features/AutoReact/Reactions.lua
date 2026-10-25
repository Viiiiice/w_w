local Services = require("Util/Services")
local Config = require("Config")
local Signal = require("Util/Signal")

local HttpService = Services.HttpService

local Reactions = {
	ACTIONS = { "Parry", "Block", "Dash" },
	data = {},
	Changed = Signal.new(),
}

local saveQueued = false

local function gameKey()
	return game.GameId ~= 0 and game.GameId or game.PlaceId
end

local function path(id)
	return string.format("%s/%d.json", Config.AutoReact.Folder, id or gameKey())
end

local function cleanId(raw)
	return raw and tostring(raw):match("%d+")
end

Reactions.cleanId = cleanId

local function sortMarkers(r)
	table.sort(r.markers, function(a, b)
		return a.t < b.t
	end)
end

local function migrate(r)
	r.samples = r.samples or {}
	r.markers = r.markers or {}
	if #r.markers == 0 and r.action and r.hit then
		table.insert(r.markers, { t = r.hit, action = r.action })
	end
	r.action, r.hit, r.manualHit = nil, nil, nil
	for _, m in ipairs(r.markers) do
		m.t = tonumber(m.t) or 0
		if m.action ~= "Block" then
			m.hold = nil
		end
	end
	sortMarkers(r)
	return r
end

function Reactions.load()
	table.clear(Reactions.data)
	if not (readfile and isfile) then
		return
	end
	local ok, raw = pcall(function()
		for _, file in ipairs({ path(), path(game.PlaceId) }) do
			if isfile(file) then
				return readfile(file)
			end
		end
	end)
	if not ok or not raw then
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if decoded and type(data) == "table" then
		for id, r in pairs(data) do
			if type(r) == "table" then
				Reactions.data[tostring(id)] = migrate(r)
			end
		end
	end
	Reactions.Changed:Fire()
end

function Reactions.save()
	if saveQueued or not writefile then
		return
	end
	saveQueued = true
	task.delay(1, function()
		saveQueued = false
		local folder = Config.AutoReact.Folder
		if makefolder and not (isfolder and isfolder(folder)) then
			pcall(makefolder, Config.RootFolder)
			pcall(makefolder, folder)
		end
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, Reactions.data)
		if ok then
			pcall(writefile, path(), encoded)
		end
	end)
end

local function changed(id)
	Reactions.Changed:Fire(id)
	Reactions.save()
end

function Reactions.get(id)
	return Reactions.data[cleanId(id) or ""]
end

function Reactions.markers(id)
	local r = Reactions.get(id)
	return r and r.markers or {}
end

function Reactions.has(id)
	return #Reactions.markers(id) > 0
end

local function ensure(id)
	local r = Reactions.data[id]
	if not r then
		r = { samples = {}, markers = {} }
		Reactions.data[id] = r
	end
	return r
end

function Reactions.addMarker(id, t, action, hold)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	r.learned = false
	local marker = { t = math.max(0, t), action = action, hold = action == "Block" and hold or nil }
	table.insert(r.markers, marker)
	sortMarkers(r)
	changed(id)
	return table.find(r.markers, marker)
end

function Reactions.updateMarker(id, index, fields)
	id = cleanId(id)
	local r = id and Reactions.data[id]
	local marker = r and r.markers[index]
	if not marker then
		return index
	end
	for k, v in pairs(fields) do
		marker[k] = v
	end
	marker.t = math.max(0, marker.t)
	if marker.action ~= "Block" then
		marker.hold = nil
	end
	r.learned = false
	sortMarkers(r)
	changed(id)
	return table.find(r.markers, marker)
end

function Reactions.removeMarker(id, index)
	id = cleanId(id)
	local r = id and Reactions.data[id]
	if r and r.markers[index] then
		table.remove(r.markers, index)
		changed(id)
	end
end

function Reactions.addSample(id, hit, defaultAction)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	local samples = r.samples
	table.insert(samples, hit)
	while #samples > Config.AutoReact.MaxSamples do
		table.remove(samples, 1)
	end

	if r.learned or #r.markers == 0 then
		local sorted = table.clone(samples)
		table.sort(sorted)
		local action = r.markers[1] and r.markers[1].action or defaultAction
		r.markers = { { t = sorted[math.ceil(#sorted / 2)], action = action } }
		r.learned = true
	end
	changed(id)
	return r
end

function Reactions.clear(id)
	id = cleanId(id)
	if id and Reactions.data[id] then
		Reactions.data[id] = nil
		changed(id)
	end
end

function Reactions.clearAll()
	table.clear(Reactions.data)
	changed(nil)
end

function Reactions.describeMarker(m)
	if m.action == "Block" and m.hold then
		return string.format("%s %.2fs (hold %.2fs)", m.action, m.t, m.hold)
	end
	return string.format("%s %.2fs", m.action, m.t)
end

function Reactions.describe(id)
	local r = Reactions.get(id)
	if not r or #r.markers == 0 then
		return "No reaction set"
	end
	local parts = {}
	for i, m in ipairs(r.markers) do
		if i > 3 then
			table.insert(parts, string.format("+%d more", #r.markers - 3))
			break
		end
		table.insert(parts, Reactions.describeMarker(m))
	end
	local text = table.concat(parts, ", ")
	if r.learned then
		text ..= string.format(" (learned, %d sample(s))", #r.samples)
	end
	return text
end

return Reactions

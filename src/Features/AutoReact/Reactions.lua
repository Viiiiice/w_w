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

local hardIgnored = {}
for _, id in ipairs(Config.AutoReact.IgnoreIds or {}) do
	local clean = cleanId(id)
	if clean then
		hardIgnored[clean] = true
	end
end

function Reactions.isIgnored(id)
	id = cleanId(id)
	if not id then
		return false
	end
	if hardIgnored[id] then
		return true
	end
	local r = Reactions.data[id]
	return r ~= nil and r.ignored == true
end

function Reactions.setIgnored(id, ignored)
	id = cleanId(id)
	if not id then
		return
	end
	local r = Reactions.data[id] or { samples = {}, markers = {} }
	Reactions.data[id] = r
	r.ignored = ignored or nil
	changed(id)
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
	if Reactions.isIgnored(id) then
		return nil
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

local function vec(v)
	return { math.floor(v.X * 100 + 0.5) / 100, math.floor(v.Y * 100 + 0.5) / 100, math.floor(v.Z * 100 + 0.5) / 100 }
end

function Reactions.addHit(id, t, size, offset, defaultAction)
	id = cleanId(id)
	if not id then
		return
	end
	if Reactions.isIgnored(id) then
		return nil, false
	end
	local r = ensure(id)
	r.hits = r.hits or {}

	local merged
	for _, h in ipairs(r.hits) do
		if math.abs(h.t - t) < 0.08 then
			h.t = (h.t * h.n + t) / (h.n + 1)
			h.n += 1
			h.size = vec(Vector3.new(
				math.max(h.size[1], size.X),
				math.max(h.size[2], size.Y),
				math.max(h.size[3], size.Z)
			))
			h.offset = vec(offset)
			merged = h
			break
		end
	end
	if not merged then
		table.insert(r.hits, { t = t, n = 1, size = vec(size), offset = vec(offset) })
		table.sort(r.hits, function(a, b)
			return a.t < b.t
		end)
		while #r.hits > 8 do
			table.remove(r.hits)
		end
	end

	if r.learned or #r.markers == 0 then
		local action = r.markers[1] and r.markers[1].action or defaultAction
		r.markers = {}
		for _, h in ipairs(r.hits) do
			table.insert(r.markers, { t = h.t, action = action })
		end
		r.learned = true
	end
	changed(id)
	return r, merged == nil
end

function Reactions.hitNear(r, t)
	local best, bestGap
	for _, h in ipairs(r and r.hits or {}) do
		local gap = math.abs(h.t - t)
		if gap < 0.25 and (not best or gap < bestGap) then
			best, bestGap = h, gap
		end
	end
	return best
end

function Reactions.reach(r, padding)
	local reach = 0
	for _, h in ipairs(r and r.hits or {}) do
		local o, sz = h.offset, h.size
		local d = math.sqrt(o[1] ^ 2 + o[2] ^ 2 + o[3] ^ 2) + math.max(sz[1], sz[2], sz[3]) / 2 + (padding or 0)
		reach = math.max(reach, d)
	end
	return reach
end

function Reactions.hitboxCount()
	local n = 0
	for _, r in pairs(Reactions.data) do
		if r.hits and #r.hits > 0 then
			n += 1
		end
	end
	return n
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
	if r and r.ignored then
		return "Ignored"
	end
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
	if r.hits and #r.hits > 0 then
		text ..= " [hitbox]"
	end
	if r.learned then
		text ..= " (learned)"
	end
	return text
end

return Reactions

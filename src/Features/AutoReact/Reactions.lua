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

local function path()
	return string.format("%s/%d.json", Config.AutoReact.Folder, game.PlaceId)
end

local function cleanId(raw)
	return raw and tostring(raw):match("%d+")
end

Reactions.cleanId = cleanId

function Reactions.load()
	table.clear(Reactions.data)
	if not (readfile and isfile) then
		return
	end
	local ok, raw = pcall(function()
		return isfile(path()) and readfile(path())
	end)
	if not ok or not raw then
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if decoded and type(data) == "table" then
		for id, r in pairs(data) do
			if type(r) == "table" then
				r.samples = r.samples or {}
				Reactions.data[tostring(id)] = r
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

function Reactions.get(id)
	return Reactions.data[cleanId(id) or ""]
end

local function ensure(id)
	local r = Reactions.data[id]
	if not r then
		r = { samples = {} }
		Reactions.data[id] = r
	end
	return r
end

function Reactions.setAction(id, action)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	r.action = action
	r.learned = false
	Reactions.Changed:Fire(id)
	Reactions.save()
end

function Reactions.setHit(id, hit)
	id = cleanId(id)
	if not id then
		return
	end
	local r = ensure(id)
	r.hit = math.max(0, hit)
	r.manualHit = true
	Reactions.Changed:Fire(id)
	Reactions.save()
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

	if not r.manualHit then
		local sorted = table.clone(samples)
		table.sort(sorted)
		r.hit = sorted[math.ceil(#sorted / 2)]
	end
	if not r.action then
		r.action = defaultAction
		r.learned = true
	end
	Reactions.Changed:Fire(id)
	Reactions.save()
	return r
end

function Reactions.clear(id)
	id = cleanId(id)
	if id and Reactions.data[id] then
		Reactions.data[id] = nil
		Reactions.Changed:Fire(id)
		Reactions.save()
	end
end

function Reactions.clearAll()
	table.clear(Reactions.data)
	Reactions.Changed:Fire()
	Reactions.save()
end

function Reactions.count()
	local n = 0
	for _ in pairs(Reactions.data) do
		n += 1
	end
	return n
end

function Reactions.describe(id)
	local r = Reactions.get(id)
	if not r or not r.action then
		return "No reaction set"
	end
	local hit = r.hit and string.format("%.2fs", r.hit) or "no hit time"
	local extra = #r.samples > 0 and string.format(", %d sample(s)", #r.samples) or ""
	return string.format("%s at %s%s%s", r.action, hit, extra, r.learned and " (learned)" or "")
end

return Reactions

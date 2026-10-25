local Services = require("Util/Services")
local Config = require("Config")
local Signal = require("Util/Signal")

local HttpService = Services.HttpService

local Logger = {
	paused = false,
	entries = {},
	count = 0,
	_order = 0,

	Added = Signal.new(),
	Updated = Signal.new(),
	Cleared = Signal.new(),
	Loaded = Signal.new(),
}

local saveQueued = false

local function gameKey()
	return game.GameId ~= 0 and game.GameId or game.PlaceId
end

local function path(id)
	return string.format("%s/%d.json", Config.AnimationLogger.SaveFolder, id or gameKey())
end

local GENERIC_NAMES = { [""] = true, Animation = true, AnimationTrack = true }

local function cleanId(raw)
	return tostring(raw):match("%d+")
end

function Logger.save()
	if saveQueued or not writefile then
		return
	end
	saveQueued = true
	task.delay(2, function()
		saveQueued = false
		local folder = Config.AnimationLogger.SaveFolder
		if makefolder and not (isfolder and isfolder(folder)) then
			pcall(makefolder, Config.RootFolder)
			pcall(makefolder, folder)
		end
		local out = {}
		for id, e in pairs(Logger.entries) do
			out[id] = e.name
		end
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, out)
		if ok then
			pcall(writefile, path(), encoded)
		end
	end)
end

local function add(id, name)
	Logger._order += 1
	local entry = {
		id = id,
		name = name or "Animation",
		owners = {},
		ownerList = {},
		plays = 0,
		order = Logger._order,
	}
	Logger.entries[id] = entry
	Logger.count += 1
	return entry
end

function Logger.seed(ids)
	local added = 0
	for rawId, name in pairs(ids) do
		local id = cleanId(rawId)
		if id and id ~= "0" then
			local entry = Logger.entries[id]
			if not entry then
				add(id, type(name) == "string" and name or nil)
				added += 1
			elseif type(name) == "string" and GENERIC_NAMES[entry.name] and not GENERIC_NAMES[name] then
				entry.name = name
				added += 1
			end
		end
	end
	if added > 0 then
		Logger.save()
		Logger.Loaded:Fire(added)
	end
	return added
end

function Logger.load()
	if not (readfile and isfile) then
		return 0
	end
	local ok, raw = pcall(function()
		for _, file in ipairs({ path(), path(game.PlaceId) }) do
			if isfile(file) then
				return readfile(file)
			end
		end
	end)
	if not ok or not raw then
		return 0
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decoded or type(data) ~= "table" then
		return 0
	end
	return Logger.seed(data)
end

function Logger.log(rawId, name, owner)
	if Logger.paused then
		return nil, false
	end
	
	local id = cleanId(rawId)
	if not id or id == "0" then
		return nil, false
	end
	owner = owner or "?"

	local entry = Logger.entries[id]
	local isNew = entry == nil
	local changed, renamed = false, false
	if isNew then
		entry = add(id, name)
	elseif GENERIC_NAMES[entry.name] and name and not GENERIC_NAMES[name] then
		entry.name = name
		changed = true
		renamed = true
	end

	if not entry.owners[owner] then
		entry.owners[owner] = true
		table.insert(entry.ownerList, owner)
		changed = true
	end

	entry.plays += 1
	entry.lastSeen = os.clock()

	if isNew or renamed then
		Logger.save()
	end

	if isNew then
		Logger.Added:Fire(entry)
	else
		Logger.Updated:Fire(entry, changed)
	end

	return entry, isNew
end

function Logger.get(id)
	return Logger.entries[id]
end

function Logger.list(filter)
	filter = filter or {}
	local text = filter.text or ""
	local out = {}
	for _, e in pairs(Logger.entries) do
		local ok = true
		if filter.onlyOwner and not e.owners[filter.onlyOwner] then
			ok = false
		end

		if ok and text ~= "" then
			local hay = (e.name .. " " .. e.id .. " " .. table.concat(e.ownerList, " ")):lower()
			ok = hay:find(text, 1, true) ~= nil
		end

		if ok then
			table.insert(out, e)
		end
	end
	table.sort(out, function(a, b)
		return a.order > b.order
	end)
	return out
end

function Logger.clear()
	table.clear(Logger.entries)
	Logger.count = 0
	Logger._order = 0
	Logger.save()
	Logger.Cleared:Fire()
end

return Logger

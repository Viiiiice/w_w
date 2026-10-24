-- Central store of every animation seen. Everything else reads from here.
local Signal = require("Util/Signal")

local Logger = {
	paused = false,
	entries = {}, -- [id] = Entry
	count = 0,

	Added = Signal.new(), -- (entry) first time an id is seen
	Updated = Signal.new(), -- (entry) seen again / new owner
	Cleared = Signal.new(),
}

--[[ Entry:
	id        string   numeric asset id
	name      string   best name we've found
	owners    {[name]=true}
	ownerList {string}
	plays     number
	lastSeen  number   os.clock() of last play
]]

local GENERIC_NAMES = { [""] = true, Animation = true, AnimationTrack = true }

local function cleanId(raw)
	return tostring(raw):match("%d+")
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
	if isNew then
		entry = { id = id, name = name or "Animation", owners = {}, ownerList = {}, plays = 0 }
		Logger.entries[id] = entry
		Logger.count += 1
	elseif GENERIC_NAMES[entry.name] and name and not GENERIC_NAMES[name] then
		entry.name = name
	end

	if not entry.owners[owner] then
		entry.owners[owner] = true
		table.insert(entry.ownerList, owner)
	end
	entry.plays += 1
	entry.lastSeen = os.clock()

	if isNew then
		Logger.Added:Fire(entry)
	else
		Logger.Updated:Fire(entry)
	end
	return entry, isNew
end

function Logger.get(id)
	return Logger.entries[id]
end

-- filter = { text = "lowercase search", onlyOwner = "PlayerName" | nil }
-- Returns entries sorted most-recently-played first.
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
		return a.lastSeen > b.lastSeen
	end)
	return out
end

function Logger.clear()
	table.clear(Logger.entries)
	Logger.count = 0
	Logger.Cleared:Fire()
end

return Logger

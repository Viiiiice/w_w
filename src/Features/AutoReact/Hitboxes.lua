local Services = require("Util/Services")
local Config = require("Config")
local Signal = require("Util/Signal")
local Tracker = require("Features/AnimationLogger/Tracker")

local LocalPlayer = Services.Players.LocalPlayer

local Hitboxes = {
	enabled = false,
	Recorded = Signal.new(),
}

local METHODS = { GetPartsInPart = true, GetPartBoundsInBox = true, GetPartBoundsInRadius = true }

local installed = false
local original
local patched = {}
local lastMove

local function record(method, a, b)
	local move = lastMove
	if not move or not move.track.IsPlaying then
		return
	end
	local t = move.track.TimePosition
	if move.lastT and math.abs(t - move.lastT) < 0.15 then
		return
	end
	move.lastT = t
	local character = LocalPlayer.Character
	local root = character and character.HumanoidRootPart
	if not root then
		return
	end

	local cf, size
	if method == "GetPartsInPart" then
		if typeof(a) ~= "Instance" then
			return
		end
		cf, size = a.CFrame, a.Size
	elseif method == "GetPartBoundsInBox" then
		if typeof(a) ~= "CFrame" or typeof(b) ~= "Vector3" then
			return
		end
		cf, size = a, b
	else
		if typeof(a) ~= "Vector3" or type(b) ~= "number" then
			return
		end
		cf, size = a, b
	end

	task.defer(function(rootCFrame, id, t)
		local position = typeof(cf) == "CFrame" and cf.Position or cf
		local boxSize = typeof(size) == "Vector3" and size or Vector3.one * size * 2
		Hitboxes.Recorded:Fire(id, t, boxSize, rootCFrame:PointToObjectSpace(position))
	end, root.CFrame, move.id, t)
end

local function findModule()
	local current = game
	for name in string.gmatch(Config.AutoReact.HitboxModule or "", "[^%.]+") do
		local ok, child = pcall(function()
			return current == game and game:GetService(name) or current:FindFirstChild(name)
		end)
		if not ok or not child then
			return nil
		end
		current = child
	end
	return current ~= game and current:IsA("ModuleScript") and current or nil
end

local function patchModule()
	local module = findModule()
	if not module then
		return false
	end
	local ok, lib = pcall(require, module)
	if not ok or type(lib) ~= "table" then
		return false
	end
	for name in pairs(METHODS) do
		local fn = rawget(lib, name)
		if type(fn) == "function" then
			patched[name] = { lib = lib, fn = fn }
			lib[name] = function(...)
				if Hitboxes.enabled then
					local args = table.pack(...)
					local first = typeof(args[1]) == "table" and 2 or 1
					pcall(record, name, args[first], args[first + 1])
				end
				return fn(...)
			end
		end
	end
	return next(patched) ~= nil
end

function Hitboxes.install(mode)
	if installed then
		return true
	end
	if mode ~= "Namecall" and patchModule() then
		installed = "module"
		return true
	end
	if not (hookmetamethod and getnamecallmethod and checkcaller) then
		return false
	end
	local wrap = newcclosure or function(f)
		return f
	end
	original = hookmetamethod(
		game,
		"__namecall",
		wrap(function(self, ...)
			if Hitboxes.enabled and self == workspace and not checkcaller() then
				local method = getnamecallmethod()
				if METHODS[method] then
					pcall(record, method, ...)
				end
			end
			return original(self, ...)
		end)
	)
	installed = "namecall"
	return true
end

function Hitboxes.mode()
	return installed
end

function Hitboxes.uninstall()
	if installed == "namecall" and original then
		pcall(hookmetamethod, game, "__namecall", original)
	end
	for name, p in pairs(patched) do
		p.lib[name] = p.fn
	end
	table.clear(patched)
	installed = false
end

function Hitboxes.start(maid)
	maid:Connect(Tracker.Played, function(model, track, rawId)
		if model == LocalPlayer.Character and not track.Looped then
			local id = tostring(rawId):match("%d+")
			if id then
				lastMove = { id = id, track = track }
			end
		end
	end)
	maid:Give(function()
		Hitboxes.enabled = false
		Hitboxes.uninstall()
		lastMove = nil
	end)
end

return Hitboxes

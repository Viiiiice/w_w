local Services = require("Util/Services")
local Config = require("Config")
local Maid = require("Util/Maid")
local Signal = require("Util/Signal")
local Tracker = require("Features/AnimationLogger/Tracker")
local Reactions = require("Features/AutoReact/Reactions")

local Players = Services.Players
local Stats = Services.Stats
local VirtualInputManager = Services.VirtualInputManager
local LocalPlayer = Players.LocalPlayer

local Engine = {
	settings = {
		enabled = false,
		learn = false,
		useLearned = true,
		learnAction = "Parry",
		range = Config.AutoReact.Range,
		lead = Config.AutoReact.Lead,
		blockHold = Config.AutoReact.BlockHold,
		learnWindow = Config.AutoReact.LearnWindow,
		inputMethod = "Auto",
		pingMode = "Auto",
		pingManual = 0,
		pingScale = 0.5,
		keys = table.clone(Config.AutoReact.Keys),
	},
	Fired = Signal.new(),
	Learned = Signal.new(),
}

local VK = {
	Space = 0x20,
	Tab = 0x09,
	LeftShift = 0xA0,
	RightShift = 0xA1,
	LeftControl = 0xA2,
	RightControl = 0xA3,
	LeftAlt = 0xA4,
	RightAlt = 0xA5,
	Zero = 0x30,
	One = 0x31,
	Two = 0x32,
	Three = 0x33,
	Four = 0x34,
	Five = 0x35,
	Six = 0x36,
	Seven = 0x37,
	Eight = 0x38,
	Nine = 0x39,
}

local smoothedPing = nil
local pending = {}
local lastFire = {}
local held = {}

local function keyCode(name)
	local ok, code = pcall(function()
		return Enum.KeyCode[name]
	end)
	return ok and code or nil
end

local function vkFor(code)
	if VK[code.Name] then
		return VK[code.Name]
	end
	if #code.Name == 1 and code.Name:match("%a") then
		return string.byte(code.Name:upper())
	end
end

local function useKeypress(code)
	local method = Engine.settings.inputMethod
	if method == "VirtualInputManager" then
		return false
	end
	return keypress ~= nil and keyrelease ~= nil and vkFor(code) ~= nil
end

local function press(code)
	if useKeypress(code) then
		keypress(vkFor(code))
	else
		VirtualInputManager:SendKeyEvent(true, code, false, game)
	end
end

local function release(code)
	if useKeypress(code) then
		keyrelease(vkFor(code))
	else
		VirtualInputManager:SendKeyEvent(false, code, false, game)
	end
end

function Engine.send(action, hold)
	local code = keyCode(Engine.settings.keys[action] or "")
	if not code then
		return false
	end

	local now = os.clock()
	if now - (lastFire[action] or 0) < Config.AutoReact.Cooldown then
		return false
	end
	lastFire[action] = now

	if action == "Block" then
		held[code] = (held[code] or 0) + 1
		pcall(press, code)
		task.delay(hold or Engine.settings.blockHold, function()
			held[code] -= 1
			if held[code] <= 0 then
				held[code] = nil
				pcall(release, code)
			end
		end)
	else
		pcall(press, code)
		task.delay(0.03, pcall, release, code)
	end

	Engine.Fired:Fire(action)
	return true
end

local function samplePing()
	local ok, ms = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(ms) == "number" and ms > 0 then
		return ms / 1000
	end
	local ok2, seconds = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
	if ok2 and type(seconds) == "number" and seconds > 0 then
		return seconds * 2
	end
end

function Engine.ping()
	return smoothedPing or samplePing() or 0
end

function Engine.pingOffset()
	local s = Engine.settings
	if s.pingMode == "Manual" then
		return s.pingManual / 1000
	elseif s.pingMode == "Auto" then
		return Engine.ping() * s.pingScale
	end
	return 0
end

local function rootOf(model)
	return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end

local function distanceTo(model)
	local mine = rootOf(LocalPlayer.Character)
	local theirs = rootOf(model)
	if not mine or not theirs then
		return math.huge
	end
	return (mine.Position - theirs.Position).Magnitude
end

local function trackSpeed(track)
	local ok, speed = pcall(function()
		return track.Speed
	end)
	return (ok and speed and speed > 0.01) and speed or 1
end

local function prune(now)
	for i = #pending, 1, -1 do
		local p = pending[i]
		if now - p.start > Engine.settings.learnWindow or not p.model.Parent then
			table.remove(pending, i)
		end
	end
end

local function onPlayed(maid, model, track, rawId)
	if model == LocalPlayer.Character then
		return
	end
	local s = Engine.settings
	if not s.enabled and not s.learn then
		return
	end
	if distanceTo(model) > s.range then
		return
	end

	local id = Reactions.cleanId(rawId)
	if not id then
		return
	end

	if s.learn and not track.Looped then
		prune(os.clock())
		table.insert(pending, { id = id, model = model, track = track, start = os.clock() })
	end

	if not s.enabled then
		return
	end
	local r = Reactions.get(id)
	if not r or #r.markers == 0 or (r.learned and not s.useLearned) then
		return
	end

	local speed = trackSpeed(track)
	local early = s.lead + Engine.pingOffset()
	for _, marker in ipairs(r.markers) do
		local wait = math.max(0, marker.t / speed - early)
		local action = marker.action
		local hold = marker.hold and marker.hold / speed or nil
		local thread
		thread = task.delay(wait, function()
			maid:Remove(thread, true)
			if not Engine.settings.enabled then
				return
			end
			if not track.IsPlaying and wait > 0.05 then
				return
			end
			if distanceTo(model) > Engine.settings.range then
				return
			end
			Engine.send(action, hold)
		end)
		maid:Give(thread)
	end
end

local function onDamaged()
	local now = os.clock()
	prune(now)
	local best
	for _, p in ipairs(pending) do
		if now - p.start > 0.05 and (not best or p.start > best.start) then
			if distanceTo(p.model) <= Engine.settings.range + 6 then
				best = p
			end
		end
	end
	if not best then
		return
	end

	local hit = now - best.start
	if best.track.IsPlaying then
		local ok, position = pcall(function()
			return best.track.TimePosition
		end)
		if ok and position and position > 0 then
			hit = position
		end
	end

	table.remove(pending, table.find(pending, best))
	local r = Reactions.addSample(best.id, hit, Engine.settings.learnAction)
	Engine.Learned:Fire(best.id, r)
end

local function watchCharacter(charMaid, character)
	charMaid:Clean()
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or character ~= LocalPlayer.Character then
		return
	end

	local last = humanoid.Health
	charMaid:Connect(humanoid.HealthChanged, function(health)
		if health < last - 0.01 and Engine.settings.learn then
			onDamaged()
		end
		last = health
	end)
end

function Engine.start(maid)
	Reactions.load()

	local threads = maid:Extend()
	maid:Connect(Tracker.Played, function(model, track, rawId)
		onPlayed(threads, model, track, rawId)
	end)

	local charMaid = maid:Extend()
	maid:Connect(LocalPlayer.CharacterAdded, function(character)
		task.spawn(watchCharacter, charMaid, character)
	end)
	task.spawn(watchCharacter, charMaid, LocalPlayer.Character)

	local running = true
	maid:Spawn(function()
		while running do
			local sample = samplePing()
			if sample then
				smoothedPing = smoothedPing and (smoothedPing * 0.8 + sample * 0.2) or sample
			end
			task.wait(0.5)
		end
	end)

	maid:Give(function()
		running = false
		table.clear(pending)
		for code in pairs(held) do
			pcall(release, code)
		end
		table.clear(held)
	end)
end

return Engine

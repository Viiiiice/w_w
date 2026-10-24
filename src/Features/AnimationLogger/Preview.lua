local Services = require("Util/Services")

local LocalPlayer = Services.Players.LocalPlayer

local Preview = {}

local current

function Preview.stop()
	if current then
		pcall(current.Stop, current)
		current = nil
	end
end

function Preview.play(id)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "No character"
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid

	Preview.stop()

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok or not track then
		return false, "Could not load (it may be owned by another game/group)"
	end

	current = track
	track:Play()
	
	return true
end

return Preview

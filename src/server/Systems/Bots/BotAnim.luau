--!strict
-- Minimal server-driven idle/run animation for bot rigs (server-played tracks replicate).
-- IDs are Roblox's default R15 Animate ids; every call is pcall'd so a bad id only means no anim.

local BotAnim = {}

local IDS = {
	Idle = "rbxassetid://507766666",
	Run = "rbxassetid://507767714",
}

export type Anim = { Idle: AnimationTrack?, Run: AnimationTrack?, Moving: boolean }

local function load(animator: Animator, id: string): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	return if ok then track else nil
end

function BotAnim.Setup(humanoid: Humanoid): Anim
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end
	assert(animator, "Animator missing")
	local anim: Anim = { Idle = load(animator, IDS.Idle), Run = load(animator, IDS.Run), Moving = false }
	if anim.Run then
		anim.Run.Looped = true
	end
	if anim.Idle then
		anim.Idle.Looped = true
		pcall(function()
			(anim.Idle :: AnimationTrack):Play()
		end)
	end
	return anim
end

function BotAnim.Update(anim: Anim, horizontalSpeed: number)
	local moving = horizontalSpeed > 0.8
	pcall(function()
		if moving ~= anim.Moving then
			anim.Moving = moving
			if moving then
				if anim.Run then
					anim.Run:Play(0.2)
				end
			elseif anim.Run then
				anim.Run:Stop(0.2)
			end
		end
		if moving and anim.Run then
			anim.Run:AdjustSpeed(math.clamp(horizontalSpeed / 16, 0.35, 1.2))
		end
	end)
end

return BotAnim

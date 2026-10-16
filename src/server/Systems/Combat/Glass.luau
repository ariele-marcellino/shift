--!strict
-- Breakable window glass (parts tagged "BreakableGlass", e.g. the side-lane centre-wall windows).
-- Panes take HITS_TO_BREAK bullets (the first ones pass through like a thin wall, losing damage);
-- the last one shatters it: the glass disappears with falling shards and a
-- crash, bullets then fly through the empty frame at full damage, and players can climb through it
-- (sill 3.5, a jump reaches ~4; owner 2026-10-16). After REPAIR_SECONDS the pane is back - as soon
-- as nobody is standing in the frame, so no one gets sealed inside the glass.
-- A grenade (frag or smoke) thrown at more than Tuning.Throw.GlassBreakStrength shatters a pane it
-- flies into and carries on through; a weaker throw just bounces off.
-- Server-side, so everyone sees the same windows.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Glass = {}

Glass.TAG = "BreakableGlass"
Glass.REPAIR_SECONDS = 20
Glass.HITS_TO_BREAK = 10 -- owner: AK 10 bullets; sniper hits count 5 -> 2 shots (Ballistics.GLASS_HITS)
Glass.KNIFE_HITS = 4 -- knife slashes that shatter a pane (owner, 2026-10-16); each counts 10 / 4
Glass.BARRIER_TAG = "BrokenWindowBarrier" -- (no barrier is made any more; kept for older callers)
-- One shot can trace the same ray more than once on the server (claim check + resolve); hits on a
-- pane closer together than this count once.
local SAME_SHOT = 0.04
Glass.SOUND = 128763165071133 -- yours: "glass break" (was Roblox "glassbreak.wav" 12222005)

local SHARD_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type Saved = { Transparency: number, CanCollide: boolean, CanQuery: boolean }
local broken: { [BasePart]: Saved } = {}
local hits: { [BasePart]: { Count: number, At: number } } = {}

local function shatterFx(pane: BasePart)
	local shards = Instance.new("ParticleEmitter")
	shards.Name = "Shards"
	shards.Enabled = false
	shards.Rate = 0
	shards.Shape = Enum.ParticleEmitterShape.Box
	shards.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	shards.Texture = SHARD_TEXTURE
	shards.Lifetime = NumberRange.new(0.7, 1.3)
	shards.Speed = NumberRange.new(2, 7)
	shards.SpreadAngle = Vector2.new(180, 180)
	shards.Acceleration = Vector3.new(0, -60, 0)
	shards.Size = NumberSequence.new(0.2)
	shards.Rotation = NumberRange.new(0, 360)
	shards.RotSpeed = NumberRange.new(-300, 300)
	shards.Color = ColorSequence.new(Color3.fromRGB(210, 222, 228))
	shards.LightEmission = 0.2
	shards.LightInfluence = 0.7
	shards.Parent = pane
	-- Shard count scales with the pane's area (a 21 x 6 window throws a good shower).
	local area = pane.Size.Y * math.max(pane.Size.X, pane.Size.Z)
	shards:Emit(math.clamp(math.floor(area * 0.8), 20, 120))

	local s = Instance.new("Sound")
	s.Name = "Shatter"
	s.SoundId = "rbxassetid://" .. tostring(Glass.SOUND)
	s.Volume = 0.638 -- 0.4725 +35% (owner, 2026-10-16)
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 140
	s.Parent = pane
	s:Play()
	task.delay(3, function()
		shards:Destroy()
		s:Destroy()
	end)
end

-- Is any character part inside the (empty) pane's box?
local function occupied(pane: BasePart): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { pane }
	for _, part in workspace:GetPartBoundsInBox(pane.CFrame, pane.Size + Vector3.new(0.6, 0, 0.6), params) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return true
		end
	end
	return false
end

local function repair(pane: BasePart)
	local saved = broken[pane]
	if not saved then
		return
	end
	if pane.Parent and occupied(pane) then
		task.delay(1, repair, pane) -- someone is climbing through: try again in a second
		return
	end
	broken[pane] = nil
	if pane.Parent then
		pane.Transparency = saved.Transparency
		pane.CanCollide = saved.CanCollide
		pane.CanQuery = saved.CanQuery
	end
end

function Glass.IsGlass(part: Instance): boolean
	return CollectionService:HasTag(part, Glass.TAG)
end

function Glass.IsBarrier(part: Instance): boolean
	return CollectionService:HasTag(part, Glass.BARRIER_TAG)
end

-- A bullet hit `pane`, counting as `weight` hits (default 1). Returns true if this hit shattered it
-- (the bullet then passes freely).
function Glass.Hit(pane: BasePart, weight: number?): boolean
	if broken[pane] then
		return true
	end
	local now = os.clock()
	local h = hits[pane]
	if h and now - h.At < SAME_SHOT then
		return false -- same shot traced again
	end
	if not h then
		h = { Count = 0, At = now }
		hits[pane] = h
	end
	h.Count += weight or 1
	h.At = now
	if h.Count >= Glass.HITS_TO_BREAK then
		hits[pane] = nil
		Glass.Break(pane)
		return true
	end
	return false
end

-- Shatter `pane` (no-op if it is already broken). The frame is then open: bullets, grenades and
-- players all pass through until it repairs.
function Glass.Break(pane: BasePart)
	if broken[pane] or not pane.Parent then
		return
	end
	broken[pane] = {
		Transparency = pane.Transparency,
		CanCollide = pane.CanCollide,
		CanQuery = pane.CanQuery,
	}
	pane.Transparency = 1
	pane.CanCollide = false
	pane.CanQuery = false
	shatterFx(pane)
	task.delay(Glass.REPAIR_SECONDS, repair, pane)
end

-- Watch a grenade thrown at `strength` until it is gone: just before each physics step, look ahead
-- along its velocity; if it is about to fly into a pane, shatter the pane so it carries on through.
function Glass.WatchThrown(ball: BasePart, strength: number)
	if strength <= Tuning.Throw.GlassBreakStrength then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local conn: RBXScriptConnection
	conn = RunService.PreSimulation:Connect(function(dt: number)
		if not ball.Parent then
			conn:Disconnect()
			return
		end
		local vel = ball.AssemblyLinearVelocity
		local speed = vel.Magnitude
		if speed < 1 then
			return
		end
		params.FilterDescendantsInstances = CollectionService:GetTagged(Glass.TAG)
		local reach = speed * dt * 2 + ball.Size.X / 2 + 0.2
		local r = workspace:Raycast(ball.Position, vel.Unit * reach, params)
		if not r or not r.Instance:IsA("BasePart") then
			return
		end
		local pane = r.Instance :: BasePart
		if broken[pane] or -vel:Dot(r.Normal) < 4 then
			return -- already broken, or only rolling / skimming along it
		end
		Glass.Break(pane)
	end)
	ball.Destroying:Once(function()
		conn:Disconnect()
	end)
end

return Glass

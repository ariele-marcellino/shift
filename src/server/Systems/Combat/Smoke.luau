--!strict
-- Smoke grenades: a server-simulated bouncing canister, then a dense cloud of large, fully
-- light-influenced particles. LightInfluence = 1 means the cloud is near invisible in the dark but
-- lights up where a doorway lamp, muzzle flash or flashlight hits it, so a lit doorway full of smoke
-- turns into a glowing wall instead of a silhouette frame.
-- Clouds are server parts so every client sees the same thing; IsSmoked() serves bot vision.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local Glass = require(script.Parent:WaitForChild("Glass"))
local Lob = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lob"))
local TeamCollision =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("TeamCollision"))

-- Built-in particle texture shipped with the Roblox client (used by the legacy Smoke object).
-- If it ever fails to load, replace with a Creator Store smoke texture id.
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local GROW_SECONDS = 1.6
local VISION_FACTOR = 0.8 -- the outer fringe is wispy; only the dense core blocks vision

type Cloud = { Part: BasePart, Center: Vector3, Born: number, Expires: number }

local Smoke = {}

local folder: Folder
local clouds: { Cloud } = {}
local rng = Random.new()

function Smoke.Init(): Folder
	folder = Instance.new("Folder")
	folder.Name = "CombatSmoke"
	folder.Parent = workspace
	return folder
end

local function makeEmitters(part: BasePart)
	-- puff sizes were tuned for an 11-stud cloud; scale them with the configured radius
	local k = Tuning.Smoke.Radius / 11
	local body = Instance.new("ParticleEmitter")
	body.Name = "Body"
	body.Texture = SMOKE_TEXTURE
	body.Color = ColorSequence.new(Color3.fromRGB(205, 205, 198))
	body.LightInfluence = 1
	body.LightEmission = 0
	body.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4 * k),
		NumberSequenceKeypoint.new(0.4, 8 * k),
		NumberSequenceKeypoint.new(1, 10 * k),
	})
	body.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.04),
		NumberSequenceKeypoint.new(0.75, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	body.Lifetime = NumberRange.new(3.5, 5)
	body.Rate = 40 -- denser (was 24)
	body.Speed = NumberRange.new(0.4, 1.6)
	body.SpreadAngle = Vector2.new(180, 180)
	body.Rotation = NumberRange.new(0, 360)
	body.RotSpeed = NumberRange.new(-12, 12)
	body.Drag = 1.5
	body.Acceleration = Vector3.new(0, 0.35, 0)
	body.Shape = Enum.ParticleEmitterShape.Sphere
	body.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	body.Parent = part

	-- small bright-ish motes that sparkle when a beam crosses them (still light-influenced)
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Texture = SMOKE_TEXTURE
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 255, 250))
	motes.LightInfluence = 1
	motes.Size = NumberSequence.new(1.6 * k, 2.4 * k)
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Lifetime = NumberRange.new(2, 3)
	motes.Rate = 14
	motes.Speed = NumberRange.new(0.5, 2)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Drag = 1
	motes.Shape = Enum.ParticleEmitterShape.Sphere
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Parent = part
	return body, motes
end

local function spawnCloud(position: Vector3)
	local radius = Tuning.Smoke.Radius
	local part = Instance.new("Part")
	part.Name = "SmokeCloud"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 3
	part.Position = position
	part:SetAttribute("Radius", radius)
	local body, motes = makeEmitters(part)
	part.Parent = folder
	body:Emit(50) -- instant puff so it reads as "popped" right away
	motes:Emit(10)

	local now = os.clock()
	local cloud: Cloud =
		{ Part = part, Center = position, Born = now, Expires = now + Tuning.Smoke.DurationSeconds }
	table.insert(clouds, cloud)

	TweenService:Create(
		part,
		TweenInfo.new(GROW_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * radius * 1.7 }
	):Play()

	task.delay(Tuning.Smoke.DurationSeconds, function()
		body.Enabled = false
		motes.Enabled = false
		local i = table.find(clouds, cloud)
		if i then
			table.remove(clouds, i)
		end
		task.delay(5, function()
			part:Destroy()
		end)
	end)
end

-- origin/direction already validated by CombatService. `ignore` = thrower model; `strength`
-- (Tuning.Throw.MinStrength..1) scales the launch speed; `lead` (s) starts it that far along its
-- arc, where the thrower's screen already shows it (ping).
function Smoke.Throw(origin: Vector3, direction: Vector3, ignore: Model?, strength: number?, lead: number?)
	local power = strength or 1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if ignore then { ignore, folder } else { folder }
	-- leaves the right hand, pulled back from a wall the thrower is hugging (shared Lob)
	local spawnAt = Lob.HandStart(origin, direction, params)
	local velocity = Lob.Velocity(direction, Tuning.Smoke.ThrowSpeed * power)
	spawnAt, velocity = Lob.Advance(spawnAt, velocity, lead or 0, params)

	local can = Instance.new("Part")
	can.Name = "SmokeGrenade"
	can.Shape = Enum.PartType.Cylinder
	can.Size = Vector3.new(0.6, 0.32, 0.32)
	can.Color = Color3.fromRGB(78, 86, 66)
	can.Material = Enum.Material.Metal
	can.CanQuery = false
	can.CanTouch = false
	can.CustomPhysicalProperties = Lob.Physics(2)
	can.CFrame = CFrame.lookAt(spawnAt, spawnAt + direction) * CFrame.Angles(0, math.rad(90), 0)

	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(0.08, 0.34, 0.34)
	cap.Color = Color3.fromRGB(210, 210, 200)
	cap.Material = Enum.Material.SmoothPlastic
	cap.CanCollide = false
	cap.CanQuery = false
	cap.CanTouch = false
	cap.Massless = true
	cap.CFrame = can.CFrame * CFrame.new(0.3, 0, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = can
	weld.Part1 = cap
	weld.Parent = can
	cap.Parent = can

	-- Thrower's team group: enemy spawn barriers bounce it (no smoking out a spawn from outside).
	local team = ignore and ignore:GetAttribute("Team")
	if type(team) == "string" and TeamCollision.Ensure() then
		can.CollisionGroup = "Team_" .. team
	end
	can.Parent = folder
	can:SetNetworkOwner(nil) -- server simulates; clients can't fling it
	Lob.Launch(can, velocity)
	can.AssemblyAngularVelocity =
		Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
	Glass.WatchThrown(can, power)

	task.delay(math.max(0.1, Tuning.Smoke.FuseSeconds - (lead or 0)), function()
		if not can.Parent then
			return
		end
		can.Anchored = true
		-- hiss trail from the canister itself while the cloud builds
		local hiss = Instance.new("ParticleEmitter")
		hiss.Texture = SMOKE_TEXTURE
		hiss.LightInfluence = 1
		hiss.Color = ColorSequence.new(Color3.fromRGB(220, 220, 215))
		hiss.Size = NumberSequence.new(0.8, 3)
		hiss.Transparency = NumberSequence.new(0.3, 1)
		hiss.Lifetime = NumberRange.new(0.8, 1.2)
		hiss.Rate = 30
		hiss.Speed = NumberRange.new(6, 10)
		hiss.SpreadAngle = Vector2.new(25, 25)
		hiss.EmissionDirection = Enum.NormalId.Top
		hiss.Parent = can
		spawnCloud(can.Position + Vector3.new(0, 2.5, 0))
		task.delay(Tuning.Smoke.DurationSeconds * 0.5, function()
			hiss.Enabled = false
		end)
		task.delay(Tuning.Smoke.DurationSeconds + 2, function()
			can:Destroy()
		end)
	end)
end

local function currentRadius(cloud: Cloud, now: number): number
	local grow = math.clamp((now - cloud.Born) / GROW_SECONDS, 0.25, 1)
	return Tuning.Smoke.Radius * grow * VISION_FACTOR
end

-- Does any active smoke cloud block the straight line between a and b?
function Smoke.IsSmoked(a: Vector3, b: Vector3): boolean
	local now = os.clock()
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	for _, cloud in clouds do
		if now >= cloud.Expires then
			continue
		end
		local r = currentRadius(cloud, now)
		local t = if lengthSq > 1e-6 then math.clamp((cloud.Center - a):Dot(ab) / lengthSq, 0, 1) else 0
		local closest = a + ab * t
		if (closest - cloud.Center).Magnitude < r then
			return true
		end
	end
	return false
end

function Smoke.Clear()
	table.clear(clouds)
	if folder then
		folder:ClearAllChildren()
	end
end

return Smoke

--!strict
-- Frag grenade: server-simulated bouncing canister, explodes FuseSeconds after release.
-- Radial damage with linear falloff (MaxDamage at the centre -> MinDamage at the edge), only with
-- clear line of sight from the blast (every wall blocks, penetrable or not), breaks lamps in radius.
-- Damage itself is applied through the callback CombatService passes in (team / self rules there).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local Combatants = require(script.Parent:WaitForChild("Combatants"))
local Ballistics = require(script.Parent:WaitForChild("Ballistics"))
local Glass = require(script.Parent:WaitForChild("Glass"))
local Lob = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lob"))
local SpawnBarriers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpawnBarriers"))
local TeamCollision = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeamCollision"))

local Frag = {}

export type Victim = { Model: Model, Damage: number, Distance: number }
export type OnExplode = (position: Vector3, victims: { Victim }, lamps: { string }) -> ()

local folder: Folder
local rng = Random.new()

function Frag.Init(): Folder
	folder = Instance.new("Folder")
	folder.Name = "CombatGrenades"
	folder.Parent = workspace
	return folder
end

-- Realistic blast (no Roblox Explosion fireball): a split-second white-hot flash and fireball,
-- hot sparks and dirt thrown out under gravity, a ground-hugging dust burst, a thick grey-brown
-- smoke cloud that rolls up and hangs for a few seconds, and a scorch mark on the floor.
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local FX_SECONDS = 7 -- the flash part (and its smoke) lives this long
local VFX = 1.35 -- visual size of the blast (owner 2026-10-16: +35%); damage radius is Tuning.Frag.Radius
local SCORCH_SECONDS = 25

local function emitter(parent: BasePart, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.LightInfluence = 1
	e.SpreadAngle = Vector2.new(180, 180)
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function scorch(centre: Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(centre, Vector3.new(0, -4, 0), params)
	if not hit then
		return
	end
	local mark = Instance.new("Part")
	mark.Name = "FragScorch"
	mark.Shape = Enum.PartType.Cylinder
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Material = Enum.Material.Slate
	mark.Color = Color3.fromRGB(22, 20, 18)
	mark.Transparency = 0.25
	mark.Size = Vector3.new(0.04, 4.5 * VFX, 4.5 * VFX)
	-- cylinder axis = X: point it along the surface normal so the disc lies flat on the floor
	mark.CFrame = CFrame.lookAt(hit.Position + hit.Normal * 0.03, hit.Position + hit.Normal * 2)
		* CFrame.Angles(0, math.rad(90), 0)
	mark.Parent = folder
	TweenService:Create(
		mark,
		TweenInfo.new(SCORCH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1 }
	):Play()
	Debris:AddItem(mark, SCORCH_SECONDS + 0.5)
end

local function flash(position: Vector3)
	local p = Instance.new("Part")
	p.Name = "FragFlash"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.6
	p.Position = position

	-- light: a very bright white-orange pop that dies off fast
	local light = Instance.new("PointLight")
	light.Range = Tuning.Frag.VisualRadius * 1.6 * VFX
	light.Brightness = 14
	light.Color = Color3.fromRGB(255, 196, 130)
	light.Shadows = true
	light.Parent = p

	-- fireball: short-lived, self-lit, white-hot core cooling to orange then soot
	local fire = emitter(p, {
		Name = "Fireball",
		Texture = SMOKE_TEXTURE,
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 214)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 150, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 40, 25)),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5 * VFX),
			NumberSequenceKeypoint.new(0.4, 5 * VFX),
			NumberSequenceKeypoint.new(1, 6.5 * VFX),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.12, 0.28),
		Speed = NumberRange.new(8 * VFX, 22 * VFX),
		Drag = 8,
		Rotation = NumberRange.new(0, 360),
	})

	-- hot sparks / fragments: fast, bright streaks that fall
	local sparks = emitter(p, {
		Name = "Sparks",
		Texture = SPARK_TEXTURE,
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 120, 40)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new(0, 0.3),
		Lifetime = NumberRange.new(0.35, 0.8),
		Speed = NumberRange.new(45 * VFX, 85 * VFX),
		Drag = 2,
		Acceleration = Vector3.new(0, -90, 0),
	})

	-- dirt / debris: dark specks thrown up and out that fall back down
	local debris = emitter(p, {
		Name = "Debris",
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(58, 50, 42)),
		Size = NumberSequence.new(0.3, 0.15),
		Transparency = NumberSequence.new(0.05, 0.4),
		Lifetime = NumberRange.new(0.8, 1.5),
		Speed = NumberRange.new(18 * VFX, 40 * VFX),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -110, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-400, 400),
	})

	-- ground dust: a low, fast-spreading burst that stalls (drag) and hangs
	local dust = emitter(p, {
		Name = "Dust",
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(120, 108, 92)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2 * VFX),
			NumberSequenceKeypoint.new(1, 7 * VFX),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(20 * VFX, 34 * VFX),
		SpreadAngle = Vector2.new(180, 8), -- nearly flat ring
		EmissionDirection = Enum.NormalId.Front,
		Drag = 5,
		Rotation = NumberRange.new(0, 360),
	})

	-- smoke: thick grey-brown cloud that billows up and lingers
	local smoke = emitter(p, {
		Name = "Smoke",
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(62, 58, 54), Color3.fromRGB(110, 104, 98)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 3 * VFX),
			NumberSequenceKeypoint.new(0.5, 9 * VFX),
			NumberSequenceKeypoint.new(1, 13 * VFX),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.6, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(4 * VFX, 11 * VFX),
		Drag = 2.5,
		Acceleration = Vector3.new(0, 2.5, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
	})

	p:SetAttribute("FragExplosion", true) -- clients: sound + camera shake (Effects)
	p.Parent = folder
	fire:Emit(34)
	sparks:Emit(60)
	debris:Emit(40)
	smoke:Emit(34)
	-- the ring is emitted in several yaw directions so it spreads all round
	for i = 0, 5 do
		p.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(i * 60), 0)
		dust:Emit(5)
	end
	scorch(position)

	TweenService:Create(light, TweenInfo.new(0.09), { Brightness = 5 }):Play()
	task.delay(0.09, function()
		TweenService:Create(light, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	end)
	task.delay(0.45, function()
		light.Enabled = false
	end)
	Debris:AddItem(p, FX_SECONDS)
end

local function explode(position: Vector3, onExplode: OnExplode, team: string?)
	local cfg = Tuning.Frag
	local centre = position + Vector3.new(0, 0.5, 0)
	flash(centre)

	local victims: { Victim } = {}
	for model in Combatants.All() do
		if not Combatants.IsAlive(model) then
			continue
		end
		local torso = Combatants.Torso(model)
		local head = Combatants.Head(model)
		if not torso then
			continue
		end
		local distance = (torso.Position - centre).Magnitude
		if distance > cfg.Radius then
			continue
		end
		local ignore: { Instance } = { folder }
		if SpawnBarriers.Blocked(centre, torso.Position, team) then
			continue -- an enemy spawn barrier shields everyone behind it
		end
		if
			Ballistics.Clear(centre, torso.Position, ignore)
			or (head ~= nil and Ballistics.Clear(centre, head.Position, ignore))
		then
			local t = math.clamp(distance / cfg.Radius, 0, 1)
			local damage = cfg.MaxDamage + (cfg.MinDamage - cfg.MaxDamage) * t
			table.insert(victims, { Model = model, Damage = math.floor(damage + 0.5), Distance = distance })
		end
	end

	local lamps: { string } = {}
	for _, lamp in CollectionService:GetTagged("BreakableLamp") do
		local part: BasePart? = if lamp:IsA("BasePart")
			then lamp
			elseif lamp:IsA("Model") then lamp.PrimaryPart or lamp:FindFirstChildWhichIsA(
				"BasePart",
				true
			)
			else nil
		if not part or (part.Position - centre).Magnitude > cfg.Radius then
			continue
		end
		-- line of sight to the lamp itself: the first thing hit must be the lamp
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { folder }
		local r = workspace:Raycast(centre, part.Position - centre, params)
		if not r or r.Instance == part or r.Instance:IsDescendantOf(lamp) then
			local id = lamp:GetAttribute("LampId")
			if id ~= nil then
				table.insert(lamps, tostring(id))
			end
		end
	end
	onExplode(centre, victims, lamps)
end

-- `strength` (Tuning.Throw.MinStrength..1) scales the launch speed. `lead` (s): how far along its
-- arc the grenade starts, so it appears where the thrower's own screen already shows it (ping).
function Frag.Throw(
	origin: Vector3,
	direction: Vector3,
	thrower: Model?,
	strength: number,
	onExplode: OnExplode,
	lead: number?
)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if thrower then { thrower, folder } else { folder }
	-- leaves the right hand (shared Lob, same as the thrower's local ghost grenade)
	local spawnAt = Lob.HandStart(origin, direction, params)
	local velocity = Lob.Velocity(direction, Tuning.Frag.ThrowSpeed * strength)
	spawnAt, velocity = Lob.Advance(spawnAt, velocity, lead or 0, params)

	local ball = Instance.new("Part")
	ball.Name = "FragGrenade"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 0.42
	ball.Color = Color3.fromRGB(62, 72, 48)
	ball.Material = Enum.Material.Metal
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CustomPhysicalProperties = Lob.Physics(2.5)
	ball.Position = spawnAt
	local spoon = Instance.new("Part")
	spoon.Name = "Spoon"
	spoon.Size = Vector3.new(0.08, 0.3, 0.1)
	spoon.Color = Color3.fromRGB(150, 150, 140)
	spoon.Material = Enum.Material.Metal
	spoon.CanCollide = false
	spoon.CanQuery = false
	spoon.CanTouch = false
	spoon.Massless = true
	spoon.CFrame = ball.CFrame * CFrame.new(0.2, 0.15, 0)
	local w = Instance.new("WeldConstraint")
	w.Part0 = ball
	w.Part1 = spoon
	w.Parent = ball
	spoon.Parent = ball
	-- tiny blinking light so a cooking frag reads in the dark
	local blink = Instance.new("PointLight")
	blink.Range = 5
	blink.Brightness = 1.5
	blink.Color = Color3.fromRGB(255, 80, 60)
	blink.Parent = ball

	-- In the thrower's team group: enemy spawn barriers bounce it, its own let it through.
	local team = SpawnBarriers.TeamOf(thrower)
	if team and TeamCollision.Ensure() then
		ball.CollisionGroup = "Team_" .. team
	end
	ball.Parent = folder
	ball:SetNetworkOwner(nil)
	Lob.Launch(ball, velocity)
	ball.AssemblyAngularVelocity =
		Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
	Glass.WatchThrown(ball, strength)

	task.spawn(function()
		local fuse = Tuning.Frag.FuseSeconds - (lead or 0) -- the lead already counts as flight time
		local started = os.clock()
		while os.clock() - started < fuse and ball.Parent do
			blink.Enabled = not blink.Enabled
			task.wait(math.max(0.08, 0.35 * (1 - (os.clock() - started) / fuse)))
		end
		if not ball.Parent then
			return
		end
		local position = ball.Position
		ball:Destroy()
		explode(position, onExplode, team)
	end)
end

function Frag.Clear()
	if folder then
		folder:ClearAllChildren()
	end
end

return Frag

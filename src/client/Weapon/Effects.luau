--!strict
-- Client-only visual effects (nothing here replicates):
--   muzzle light for own shots, pooled flash lights + mini flashes for other shooters,
--   tracers, impact sparks / dust, bullet holes, the local player's own flashlight.
-- Everything lives in a local Folder in workspace (lights inside the Camera are avoided on purpose).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local SpawnBarriers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpawnBarriers"))
local TweenService = game:GetService("TweenService")

local TRACER_SPEED = 900
local TRACER_LENGTH = 9
local MAX_HOLES = 60
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FAR = CFrame.new(0, -1e5, 0)
local MUZZLE_COLOR = Color3.fromRGB(255, 188, 105)

local Effects = {}
Effects.OnExplosion = nil :: ((position: Vector3) -> ())?

type Tracer = { Part: BasePart, From: Vector3, To: Vector3, Dir: Vector3, Length: number, Travel: number }
type FlashSlot = { Part: BasePart, Light: PointLight, Until: number }

local folder: Folder
local anchor: BasePart -- holds attachments for sounds / particle emission points
local muzzleLightPart: BasePart
local muzzleLight: PointLight
local muzzleUntil = 0
local tracers: { Tracer } = {}
local tracerPool: { BasePart } = {}
local holes: { BasePart } = {}
local holeIndex = 0
local flashSlots: { FlashSlot } = {}
local flashIndex = 0
local emitters: { [string]: ParticleEmitter } = {}
local emitAttachment: Attachment
local flashlightPart: BasePart
local flashlight: SpotLight
local rng = Random.new()

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = FAR
	p.Parent = folder
	return p
end

local function makeEmitter(name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = emitAttachment
	emitters[name] = e
	return e
end

function Effects.Init()
	folder = Instance.new("Folder")
	folder.Name = "LocalWeaponFx"
	folder.Parent = workspace

	anchor = newPart("FxAnchor", Vector3.one * 0.1, Color3.new(), nil)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.identity
	emitAttachment = Instance.new("Attachment")
	emitAttachment.Parent = anchor

	makeEmitter("Sparks", {
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 140, 60)),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new(0.09, 0),
		Lifetime = NumberRange.new(0.12, 0.3),
		Speed = NumberRange.new(14, 30),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -60, 0),
		Drag = 2,
	})
	makeEmitter("Dust", {
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(190, 180, 160)),
		LightInfluence = 0.8,
		Size = NumberSequence.new(0.4, 1.8),
		Transparency = NumberSequence.new(0.35, 1),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(30, 30),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
	})
	makeEmitter("Puff", { -- body hit: dark fabric puff, no blood
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(70, 70, 72)),
		LightInfluence = 0.5,
		Size = NumberSequence.new(0.5, 1.4),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(60, 60),
		Drag = 6,
	})
	makeEmitter("Glass", {
		Color = ColorSequence.new(Color3.fromRGB(230, 245, 255)),
		LightEmission = 0.6,
		Size = NumberSequence.new(0.12, 0.05),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -80, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
	})

	muzzleLightPart = newPart("MuzzleLight", Vector3.one * 0.1, Color3.new(), nil)
	muzzleLightPart.Transparency = 1
	muzzleLight = Instance.new("PointLight")
	muzzleLight.Range = Tuning.AK.MuzzleLightRange
	muzzleLight.Brightness = 6
	muzzleLight.Color = MUZZLE_COLOR
	muzzleLight.Shadows = true
	muzzleLight.Enabled = false
	muzzleLight.Parent = muzzleLightPart

	for i = 1, 6 do
		local p =
			newPart("RemoteFlash" .. i, Vector3.one * 0.35, Color3.fromRGB(255, 210, 130), Enum.Material.Neon)
		p.Shape = Enum.PartType.Ball
		p.Transparency = 1
		local l = Instance.new("PointLight")
		l.Range = Tuning.AK.MuzzleLightRange
		l.Brightness = 6
		l.Color = MUZZLE_COLOR
		l.Shadows = false
		l.Enabled = false
		l.Parent = p
		table.insert(flashSlots, { Part = p, Light = l, Until = 0 })
	end

	flashlightPart = newPart("OwnFlashlight", Vector3.one * 0.1, Color3.new(), nil)
	flashlightPart.Transparency = 1
	flashlight = Instance.new("SpotLight")
	flashlight.Face = Enum.NormalId.Front
	flashlight.Range = Tuning.Flashlight.Range
	flashlight.Angle = Tuning.Flashlight.Angle
	flashlight.Brightness = Tuning.Flashlight.Brightness
	flashlight.Color = Color3.fromRGB(255, 244, 222)
	flashlight.Shadows = true
	flashlight.Enabled = false
	flashlight.Parent = flashlightPart

	-- frag explosion sound + camera shake hook
	task.spawn(function()
		local grenades = workspace:WaitForChild("CombatGrenades", 30)
		if grenades then
			grenades.ChildAdded:Connect(function(child)
				if child:IsA("BasePart") and child:GetAttribute("FragExplosion") then
					Sounds.PlayAt("FragExplode", anchor, child.Position, 1, 600)
					if Effects.OnExplosion then
						Effects.OnExplosion(child.Position)
					end
				end
			end)
		end
	end)

	-- smoke "pop" sound when any cloud appears
	task.spawn(function()
		local smoke = workspace:WaitForChild("CombatSmoke", 30)
		if smoke then
			smoke.ChildAdded:Connect(function(child)
				if child:IsA("BasePart") and child.Name == "SmokeCloud" then
					-- Hiss for as long as the cloud lasts (grow time + duration), fading out with it.
					Sounds.LoopOn("SmokePop", child, Tuning.Smoke.DurationSeconds + 1.6, 2)
				end
			end)
		end
	end)
end

function Effects.Folder(): Folder
	return folder
end

local function emit(name: string, position: Vector3, normal: Vector3, count: number)
	local e = emitters[name]
	if not e then
		return
	end
	emitAttachment.WorldCFrame = CFrame.lookAt(position, position + normal)
		* CFrame.Angles(-math.pi / 2, 0, 0)
	e:Emit(count)
end

-- When a window pane shatters (goes fully transparent), drop the bullet holes that were on it so
-- they don't hang in the empty frame.
local function clearHolesOn(pane: BasePart)
	local half = pane.Size / 2 + Vector3.new(0.1, 0.1, 0.1)
	for _, hole in holes do
		local p = pane.CFrame:PointToObjectSpace(hole.Position)
		if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
			hole.CFrame = FAR
		end
	end
end

local function watchPane(pane: Instance)
	if pane:IsA("BasePart") then
		pane:GetPropertyChangedSignal("Transparency"):Connect(function()
			if pane.Transparency >= 0.95 then
				clearHolesOn(pane)
			end
		end)
	end
end
for _, pane in CollectionService:GetTagged("BreakableGlass") do
	watchPane(pane)
end
CollectionService:GetInstanceAddedSignal("BreakableGlass"):Connect(watchPane)

local function addHole(position: Vector3, normal: Vector3)
	holeIndex = holeIndex % MAX_HOLES + 1
	local hole = holes[holeIndex]
	if not hole then
		-- Round hole: a thin cylinder (its axis is the part's X) turned to lie flat on the wall.
		hole = newPart("BulletHole", Vector3.new(0.02, 0.14, 0.14), Color3.fromRGB(14, 12, 10), nil)
		hole.Shape = Enum.PartType.Cylinder
		holes[holeIndex] = hole
	end
	hole.CFrame = CFrame.lookAt(position + normal * 0.012, position + normal * 2)
		* CFrame.Angles(0, math.pi / 2, 0)
end

-- kind: "World" | "Player" | "Lamp" | "Smoke" | nil
function Effects.Impact(position: Vector3, normal: Vector3, kind: string?, makeHole: boolean)
	if kind == "Player" then
		emit("Puff", position, normal, 6)
		Sounds.PlayAt("ImpactPlayer", anchor, position, rng:NextNumber(0.95, 1.05), 80)
	elseif kind == "Lamp" then
		emit("Glass", position, normal, 14)
		emit("Sparks", position, normal, 10)
	elseif kind == "World" then
		emit("Sparks", position, normal, rng:NextInteger(3, 6))
		emit("Dust", position, normal, 3)
		if makeHole then
			addHole(position, normal)
		end
		Sounds.PlayAt("ImpactWorld", anchor, position, rng:NextNumber(0.9, 1.1), 80)
	end
end

-- A bullet stopped by an enemy spawn barrier: a team-coloured ripple on the barrier, sparks, a
-- deflected tracer and a ricochet whine - so it's obvious the barrier can't be shot through.
function Effects.BarrierHit(position: Vector3, from: Vector3)
	local _, part = SpawnBarriers.Hit(from, position + (position - from).Unit * 0.5, nil)
	local color = Color3.fromRGB(150, 200, 255)
	local normal = -(position - from).Unit
	if part then
		normal = SpawnBarriers.Normal(part, from)
		color = part.Color
	end
	local ring = newPart("BarrierRipple", Vector3.new(0.05, 0.6, 0.6), color, Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.1
	-- Cylinders run along X: point X along the barrier normal so the disc lies on its face.
	ring.CFrame = CFrame.lookAt(position + normal * 0.05, position + normal * 2)
		* CFrame.Angles(0, math.rad(90), 0)
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 3.2, 3.2),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		ring:Destroy()
	end)
	emit("Sparks", position, normal, rng:NextInteger(8, 12))
	local dir = (position - from).Unit
	local reflected = dir - 2 * dir:Dot(normal) * normal
	local spread =
		Vector3.new(rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.1, 0.25), rng:NextNumber(-0.2, 0.2))
	Effects.Tracer(position, position + (reflected + spread).Unit * rng:NextNumber(14, 24))
	Sounds.PlayAt("Ricochet", anchor, position, rng:NextNumber(0.9, 1.15), 120)
end

function Effects.Tracer(from: Vector3, to: Vector3)
	local delta = to - from
	local dist = delta.Magnitude
	if dist < 3 then
		return
	end
	local part = table.remove(tracerPool)
	if not part then
		part = newPart(
			"Tracer",
			Vector3.new(0.05, 0.05, TRACER_LENGTH),
			Color3.fromRGB(255, 222, 150),
			Enum.Material.Neon
		)
		part.Transparency = 0.15
	end
	local length = math.min(TRACER_LENGTH, dist * 0.5)
	part.Size = Vector3.new(0.05, 0.05, length)
	table.insert(
		tracers,
		{ Part = part, From = from, To = to, Dir = delta / dist, Length = dist, Travel = 0 }
	)
end

local function statsFor(weapon: string?): any
	return if weapon == "Sniper" then Tuning.Sniper else Tuning.AK
end

-- Own shot: flash light at the viewmodel muzzle.
function Effects.OwnShot(muzzle: Vector3, weapon: string?, brightness: number?)
	local stats = statsFor(weapon)
	muzzleUntil = os.clock() + stats.MuzzleLightSeconds
	muzzleLightPart.CFrame = CFrame.new(muzzle)
	muzzleLight.Range = stats.MuzzleLightRange
	muzzleLight.Brightness = rng:NextNumber(5, 8)
		* (if weapon == "Sniper" then 1.5 else 1)
		* (brightness or 1)
	muzzleLight.Enabled = true
end

-- Wallbang: holes + dust on both faces of every penetrated wall (points = entry, exit, ...).
function Effects.Walls(points: { Vector3 }, direction: Vector3)
	for i = 1, #points - 1, 2 do
		local entry, exit = points[i], points[i + 1]
		if typeof(entry) == "Vector3" and typeof(exit) == "Vector3" then
			Effects.Impact(entry, -direction, "World", true)
			Effects.Impact(exit, direction, "World", true)
		end
	end
end

local function findShooter(name: string): Model?
	local player = Players:FindFirstChild(name)
	if player and player:IsA("Player") and player.Character then
		return player.Character
	end
	for _, m in CollectionService:GetTagged("Combatant") do
		if m.Name == name and m:IsA("Model") then
			return m
		end
	end
	return nil
end

-- Another combatant's shot (ShotFx remote).
function Effects.RemoteShot(
	shooterName: string,
	origin: Vector3,
	hitPos: Vector3,
	kind: string?,
	weapon: string?,
	walls: { Vector3 }?
)
	local stats = statsFor(weapon)
	local muzzle = origin
	local shooter = findShooter(shooterName)
	local gun = shooter and shooter:FindFirstChild("WorldPrimary")
	local receiver = gun and gun:FindFirstChild("Receiver")
	local att = receiver and receiver:FindFirstChild("Muzzle")
	if att and att:IsA("Attachment") and (att.WorldPosition - origin).Magnitude < 9 then
		muzzle = att.WorldPosition
	end

	flashIndex = flashIndex % #flashSlots + 1
	local slot = flashSlots[flashIndex]
	slot.Part.CFrame = CFrame.new(muzzle)
	slot.Part.Size = Vector3.one * rng:NextNumber(0.3, 0.5)
	slot.Part.Transparency = 0.1
	slot.Light.Range = stats.MuzzleLightRange
	slot.Light.Enabled = true
	slot.Until = os.clock() + stats.MuzzleLightSeconds

	Effects.Tracer(muzzle, hitPos)

	local camera = workspace.CurrentCamera
	local far = camera and (camera.CFrame.Position - muzzle).Magnitude > 60
	local fire = if weapon == "Sniper" then "SniperFire" else "Fire"
	Sounds.PlayAt(fire, anchor, muzzle, rng:NextNumber(0.96, 1.04), 500)
	if far then
		Sounds.PlayAt("FireDistant", anchor, muzzle, rng:NextNumber(0.95, 1.05), 900)
	end
	if walls and #walls >= 2 and (hitPos - origin).Magnitude > 0.1 then
		Effects.Walls(walls, (hitPos - origin).Unit)
	end

	if kind == "Barrier" then
		Effects.BarrierHit(hitPos, muzzle)
	elseif kind == "World" or kind == "Lamp" or kind == "Player" then
		-- recover a surface normal with one short ray near the hit
		local dir = (hitPos - origin)
		if dir.Magnitude > 0.1 then
			dir = dir.Unit
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { folder, camera :: Instance }
			local r = workspace:Raycast(hitPos - dir * 0.5, dir, params)
			local normal = if r then r.Normal else -dir
			Effects.Impact(hitPos, normal, kind, kind == "World")
		end
	end
end

function Effects.SetFlashlight(on: boolean)
	flashlight.Enabled = on
end

-- per-frame: move tracers, expire lights, place own flashlight
function Effects.Update(dt: number, camera: CFrame)
	local now = os.clock()
	if muzzleLight.Enabled and now >= muzzleUntil then
		muzzleLight.Enabled = false
	end
	for _, slot in flashSlots do
		if slot.Light.Enabled and now >= slot.Until then
			slot.Light.Enabled = false
			slot.Part.Transparency = 1
		end
	end
	for i = #tracers, 1, -1 do
		local t = tracers[i]
		t.Travel += TRACER_SPEED * dt
		local len = t.Part.Size.Z
		if t.Travel - len >= t.Length then
			t.Part.CFrame = FAR
			table.insert(tracerPool, t.Part)
			table.remove(tracers, i)
		else
			local head = math.min(t.Travel, t.Length)
			local tail = math.max(0, t.Travel - len)
			local mid = t.From + t.Dir * ((head + tail) / 2)
			t.Part.Size = Vector3.new(0.05, 0.05, math.max(0.1, head - tail))
			t.Part.CFrame = CFrame.lookAt(mid, mid + t.Dir)
		end
	end
	if flashlight.Enabled then
		-- slightly right/below the eye so its shadows read
		flashlightPart.CFrame = camera * CFrame.new(0.35, -0.25, -0.3)
	end
end

return Effects

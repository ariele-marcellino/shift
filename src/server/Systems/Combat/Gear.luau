--!strict
-- What other players see on a combatant: a simple third-person AK (slung on the back when
-- holstered), a head-mounted flashlight (SpotLight + glowing lens), head/torso pitch so the beam and
-- gun follow where the player looks, and a crouch pose. All server-side so it replicates.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local StoreKnife = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoreKnife"))
local StoreAssets = require(script.Parent.Parent:WaitForChild("StoreAssets"))

local Gear = {}

-- The owner's store karambit ("Karambit", inventory 2026-10-16). Loaded once (scripts stripped by
-- StoreAssets), published to ReplicatedStorage.StoreModels.Karambit for the first-person viewmodel
-- and used for the third-person knife. Until it has loaded (or if it can't) the handmade one stays.
Gear.KNIFE_ASSET = 10363483880
local WORLD_KNIFE_LENGTH = 1.5 -- longest side of the third-person store knife (studs)
local knifeTemplate: Model? = nil

local METAL = Color3.fromRGB(38, 38, 40)
local WOOD = Color3.fromRGB(118, 66, 34)
local MAG = Color3.fromRGB(130, 62, 32)

-- Weld C0 (relative to the upper torso) for each carry pose. Gun forward is -Z.
local DRAWN_C0 = CFrame.new(0.45, 0.05, -0.95) * CFrame.Angles(0, math.rad(4), 0)
local HOLSTERED_C0 = CFrame.new(0, 0.1, 0.62)
	* CFrame.Angles(0, 0, math.rad(-45))
	* CFrame.Angles(0, math.rad(90), 0)
local KNIFE_C0 = CFrame.new(0.75, -0.2, -0.85) * CFrame.Angles(math.rad(10), 0, 0)

local CROUCH_HIP_DROP = 0.9
local CROUCH_HIP_ANGLE = math.rad(55)
local CROUCH_KNEE_ANGLE = math.rad(-95)

type Pose = {
	Neck: Motor6D?,
	NeckC0: CFrame?,
	Waist: Motor6D?,
	WaistC0: CFrame?,
	Hips: { { Motor: Motor6D, C0: CFrame } },
	Knees: { { Motor: Motor6D, C0: CFrame } },
	HipHeight: number,
	Crouching: boolean,
}

local poses: { [Model]: Pose } = {}

local function part(
	parent: Instance,
	root: BasePart?,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	if root then
		p.CFrame = root.CFrame * cf
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
	end
	p.Parent = parent
	return p
end

local function torsoOf(model: Model): BasePart?
	local t = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if t and t:IsA("BasePart") then
		return t
	end
	return nil
end

-- Low-detail primaries for third person (~10 parts). Root = receiver centre, forward = -Z.
local function buildWorldPrimary(model: Model, torso: BasePart, primary: string): Model
	local gun = Instance.new("Model")
	gun.Name = "WorldPrimary"
	gun:SetAttribute("Weapon", primary)
	local root =
		part(gun, nil, "Receiver", Vector3.new(0.22, 0.3, 1.1), CFrame.identity, METAL, Enum.Material.Metal)
	root.CFrame = torso.CFrame * HOLSTERED_C0
	gun.PrimaryPart = root
	local cyl = Enum.PartType.Cylinder
	local muzzleZ: number
	if primary == "Sniper" then
		local olive = Color3.fromRGB(78, 88, 62)
		part(
			gun,
			root,
			"ForeEnd",
			Vector3.new(0.24, 0.24, 1.1),
			CFrame.new(0, -0.05, -0.95),
			olive,
			Enum.Material.Plastic
		)
		local barrelCF = CFrame.new(0, 0.02, -2.0) * CFrame.Angles(0, math.rad(90), 0)
		part(gun, root, "Barrel", Vector3.new(1.9, 0.09, 0.09), barrelCF, METAL, Enum.Material.Metal, cyl)
		local scopeCF = CFrame.new(0, 0.32, -0.25) * CFrame.Angles(0, math.rad(90), 0)
		part(gun, root, "Scope", Vector3.new(1.2, 0.17, 0.17), scopeCF, METAL, Enum.Material.Metal, cyl)
		local lensCF = CFrame.new(0, 0.32, -0.9) * CFrame.Angles(0, math.rad(90), 0)
		part(gun, root, "Objective", Vector3.new(0.3, 0.24, 0.24), lensCF, METAL, Enum.Material.Metal, cyl)
		local gripCF = CFrame.new(0, -0.3, 0.3) * CFrame.Angles(math.rad(-15), 0, 0)
		part(gun, root, "Grip", Vector3.new(0.15, 0.36, 0.18), gripCF, olive, Enum.Material.Plastic)
		part(
			gun,
			root,
			"Stock",
			Vector3.new(0.22, 0.38, 1.0),
			CFrame.new(0, -0.12, 1.0),
			olive,
			Enum.Material.Plastic
		)
		muzzleZ = -3.05
	else
		part(
			gun,
			root,
			"Handguard",
			Vector3.new(0.24, 0.26, 0.62),
			CFrame.new(0, 0.02, -0.88),
			WOOD,
			Enum.Material.Wood
		)
		local barrelCF = CFrame.new(0, 0.04, -1.45) * CFrame.Angles(0, math.rad(90), 0)
		part(gun, root, "Barrel", Vector3.new(0.9, 0.08, 0.08), barrelCF, METAL, Enum.Material.Metal, cyl)
		part(
			gun,
			root,
			"FrontSight",
			Vector3.new(0.08, 0.2, 0.1),
			CFrame.new(0, 0.12, -1.72),
			METAL,
			Enum.Material.Metal
		)
		local gripCF = CFrame.new(0, -0.3, 0.22) * CFrame.Angles(math.rad(-20), 0, 0)
		part(
			gun,
			root,
			"Grip",
			Vector3.new(0.14, 0.36, 0.16),
			gripCF,
			Color3.fromRGB(60, 34, 24),
			Enum.Material.Plastic
		)
		local magCF = CFrame.new(0, -0.28, -0.24) * CFrame.Angles(math.rad(10), 0, 0)
		part(gun, root, "Mag1", Vector3.new(0.13, 0.3, 0.24), magCF, MAG, Enum.Material.Plastic)
		local mag2CF = magCF
			* CFrame.new(0, -0.2, 0)
			* CFrame.Angles(math.rad(18), 0, 0)
			* CFrame.new(0, -0.12, 0)
		part(gun, root, "Mag2", Vector3.new(0.13, 0.26, 0.22), mag2CF, MAG, Enum.Material.Plastic)
		part(
			gun,
			root,
			"StockNeck",
			Vector3.new(0.16, 0.2, 0.36),
			CFrame.new(0, -0.03, 0.72),
			WOOD,
			Enum.Material.Wood
		)
		local stockCF = CFrame.new(0, -0.12, 1.2) * CFrame.Angles(math.rad(7), 0, 0)
		part(gun, root, "Stock", Vector3.new(0.18, 0.34, 0.7), stockCF, WOOD, Enum.Material.Wood)
		muzzleZ = -1.95
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.04, muzzleZ)
	muzzle.Parent = root

	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = torso
	weld.Part1 = root
	weld.C0 = HOLSTERED_C0
	weld.Parent = root
	gun.Parent = model
	return gun
end

-- The store karambit, posed in the right-hand area like the handmade one (StoreKnife grip space
-- placed at KNIFE_C0 on the torso), each part welded to the torso; hidden until held. Parts keep
-- their own transparency in the "BaseTransparency" attribute (SetHeld restores it).
local function buildStoreWorldKnife(model: Model, torso: BasePart, template: Model): Model
	local knife = StoreKnife.Posed(template, WORLD_KNIFE_LENGTH)
	knife.Name = "WorldKnife"
	knife:SetAttribute("Store", true)
	local base = torso.CFrame * KNIFE_C0
	for _, d in knife:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
			d.CFrame = base * d.CFrame
			d.Anchored = false
			d.Massless = true
			d.Transparency = 1
			local w = Instance.new("WeldConstraint")
			w.Part0 = torso
			w.Part1 = d
			w.Parent = d
		end
	end
	knife.Parent = model
	return knife
end

-- Karambit held forward in the right hand area (ring behind the fist, claw blade hooking forward);
-- hidden (transparent) when not held. The store model once it has loaded, else the handmade one.
local function buildWorldKnife(model: Model, torso: BasePart): Model
	if knifeTemplate then
		local ok, knife = pcall(buildStoreWorldKnife, model, torso, knifeTemplate)
		if ok then
			return knife
		end
		warn("[Gear] store karambit failed, using the handmade one:", knife)
	end
	local knife = Instance.new("Model")
	knife.Name = "WorldKnife"
	local handle = part(
		knife,
		nil,
		"Handle",
		Vector3.new(0.1, 0.12, 0.4),
		CFrame.identity,
		Color3.fromRGB(25, 25, 25),
		Enum.Material.Plastic
	)
	handle.CFrame = torso.CFrame * KNIFE_C0
	knife.PrimaryPart = handle
	-- claw blade: 4 segments bending up from down-forward
	local cur = CFrame.new(0, -0.02, -0.2) * CFrame.Angles(math.rad(-32), 0, 0)
	for i = 1, 4 do
		local len = 0.15
		part(
			knife,
			handle,
			"Blade" .. i,
			Vector3.new(0.03, 0.14 - i * 0.02, len + 0.02),
			cur * CFrame.new(0, 0, -len / 2),
			Color3.fromRGB(160, 163, 168),
			Enum.Material.Metal
		)
		cur = cur * CFrame.new(0, 0, -len) * CFrame.Angles(math.rad(24), 0, 0)
	end
	-- finger ring behind the fist
	for i = 0, 5 do
		part(
			knife,
			handle,
			"Ring" .. i,
			Vector3.new(0.04, 0.04, 0.1),
			CFrame.new(0, 0.04, 0.3) * CFrame.Angles(i * math.pi / 3, 0, 0) * CFrame.new(0, 0.09, 0),
			Color3.fromRGB(40, 40, 42),
			Enum.Material.Metal
		)
	end
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = torso
	weld.Part1 = handle
	weld.C0 = KNIFE_C0
	weld.Parent = handle
	for _, d in knife:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	knife.Parent = model
	return knife
end

local function buildFlashlight(head: BasePart)
	if head:FindFirstChild("FlashlightAttachment") then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "FlashlightAttachment"
	att.Position = Vector3.new(0.32, 0.15, -0.55)
	att.Parent = head
	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Face = Enum.NormalId.Front
	light.Range = Tuning.Flashlight.Range
	light.Angle = Tuning.Flashlight.Angle
	light.Brightness = Tuning.Flashlight.Brightness
	light.Color = Color3.fromRGB(255, 244, 222)
	light.Shadows = true
	light.Enabled = false
	light.Parent = att

	-- a small lens that glows when on: readable "someone has a light" dot even from behind walls' edges
	local lens = Instance.new("Part")
	lens.Name = "FlashlightLens"
	lens.Shape = Enum.PartType.Ball
	lens.Size = Vector3.one * 0.22
	lens.Material = Enum.Material.Neon
	lens.Color = Color3.fromRGB(255, 246, 225)
	lens.Transparency = 1
	lens.CanCollide = false
	lens.CanQuery = false
	lens.CanTouch = false
	lens.Massless = true
	lens.CastShadow = false
	lens.CFrame = head.CFrame * CFrame.new(0.32, 0.15, -0.5)
	local w = Instance.new("WeldConstraint")
	w.Part0 = head
	w.Part1 = lens
	w.Parent = lens
	lens.Parent = head
end

local function findMotor(model: Model, name: string): Motor6D?
	local m = model:FindFirstChild(name, true)
	if m and m:IsA("Motor6D") then
		return m
	end
	return nil
end

local function makePose(model: Model, humanoid: Humanoid): Pose
	local pose: Pose = {
		Hips = {},
		Knees = {},
		HipHeight = humanoid.HipHeight,
		Crouching = false,
	}
	local neck = findMotor(model, "Neck")
	if neck then
		pose.Neck = neck
		pose.NeckC0 = neck.C0
	end
	local waist = findMotor(model, "Waist")
	if waist then
		pose.Waist = waist
		pose.WaistC0 = waist.C0
	end
	for _, side in { "Right", "Left" } do
		local hip = findMotor(model, side .. "Hip")
		if hip then
			table.insert(pose.Hips, { Motor = hip, C0 = hip.C0 })
		end
		local knee = findMotor(model, side .. "Knee")
		if knee then
			table.insert(pose.Knees, { Motor = knee, C0 = knee.C0 })
		end
	end
	return pose
end

-- Called on every (re)spawn and on primary change. Idempotent.
function Gear.Equip(model: Model, humanoid: Humanoid, primary: string)
	-- accessories (hats/hair) shouldn't eat bullets meant for the head
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Parent and d.Parent:IsA("Accessory") then
			d.CanQuery = false
		end
	end
	local torso = torsoOf(model)
	if torso then
		local existing = model:FindFirstChild("WorldPrimary")
		if existing and existing:GetAttribute("Weapon") ~= primary then
			existing:Destroy()
			existing = nil
		end
		if not existing then
			buildWorldPrimary(model, torso, primary)
		end
		local knife = model:FindFirstChild("WorldKnife")
		if knife and knifeTemplate and knife:GetAttribute("Store") ~= true then
			knife:Destroy() -- the store karambit has loaded since: swap the handmade one out
			knife = nil
		end
		if not knife then
			buildWorldKnife(model, torso)
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		buildFlashlight(head)
	end
	if not poses[model] then
		poses[model] = makePose(model, humanoid)
		model.Destroying:Connect(function()
			poses[model] = nil
		end)
	end
end

-- weapon = "AK" | "Sniper" | "Knife" | "Frag" | "Smoke". Primary goes to the hands when held,
-- otherwise on the back; the knife is only visible in hand.
function Gear.SetHeld(model: Model, weapon: string)
	local gun = model:FindFirstChild("WorldPrimary")
	local root = gun and (gun :: Model).PrimaryPart
	local weld = root and root:FindFirstChild("CarryWeld")
	local primaryHeld = weapon == "AK" or weapon == "Sniper"
	if weld and weld:IsA("Weld") then
		weld.C0 = if primaryHeld then DRAWN_C0 else HOLSTERED_C0
	end
	local knife = model:FindFirstChild("WorldKnife")
	if knife then
		for _, d in knife:GetDescendants() do
			if d:IsA("BasePart") then
				local base = d:GetAttribute("BaseTransparency")
				d.Transparency = if weapon ~= "Knife" then 1 elseif type(base) == "number" then base else 0
			end
		end
	end
end

function Gear.SetFlashlight(model: Model, on: boolean)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local att = head:FindFirstChild("FlashlightAttachment")
	local light = att and att:FindFirstChild("Flashlight")
	if light and light:IsA("SpotLight") then
		light.Enabled = on
	end
	local lens = head:FindFirstChild("FlashlightLens")
	if lens and lens:IsA("BasePart") then
		lens.Transparency = if on then 0 else 1
	end
end

-- pitch in radians, + = looking up
function Gear.SetPitch(model: Model, pitch: number)
	local pose = poses[model]
	if not pose then
		return
	end
	pitch = math.clamp(pitch, -1.2, 1.2)
	if pose.Neck and pose.NeckC0 then
		pose.Neck.C0 = pose.NeckC0 * CFrame.Angles(pitch * 0.6, 0, 0)
	end
	if pose.Waist and pose.WaistC0 then
		pose.Waist.C0 = pose.WaistC0 * CFrame.Angles(pitch * 0.4, 0, 0)
	end
end

function Gear.SetCrouch(model: Model, humanoid: Humanoid, crouching: boolean)
	local pose = poses[model]
	if not pose or pose.Crouching == crouching then
		return
	end
	pose.Crouching = crouching
	model:SetAttribute("Crouching", crouching)
	humanoid.HipHeight = if crouching then pose.HipHeight - CROUCH_HIP_DROP else pose.HipHeight
	for _, h in pose.Hips do
		h.Motor.C0 = if crouching then h.C0 * CFrame.Angles(CROUCH_HIP_ANGLE, 0, 0) else h.C0
	end
	for _, k in pose.Knees do
		k.Motor.C0 = if crouching then k.C0 * CFrame.Angles(CROUCH_KNEE_ANGLE, 0, 0) else k.C0
	end
end

-- Load the store karambit (yields; call from a task at startup): publish it for the clients'
-- viewmodel and give every combatant already spawned the store knife.
function Gear.PreloadKnife()
	local template = StoreAssets.Load(Gear.KNIFE_ASSET)
	if not template then
		return -- not in the owner's inventory / failed: the handmade karambit stays
	end
	local copy = template:Clone()
	copy.Name = "Karambit"
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local folder = ReplicatedStorage:FindFirstChild("StoreModels")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "StoreModels"
		folder.Parent = ReplicatedStorage
	end
	copy.Parent = folder
	knifeTemplate = copy
	print("[Gear] store karambit loaded")
	for _, model in CollectionService:GetTagged("Combatant") do
		local torso = if model:IsA("Model") then torsoOf(model) else nil
		local old = model:FindFirstChild("WorldKnife")
		if torso and old and old:GetAttribute("Store") ~= true then
			old:Destroy()
			buildWorldKnife(model :: Model, torso)
			local held = model:GetAttribute("HeldWeapon")
			Gear.SetHeld(model :: Model, if type(held) == "string" then held else "AK")
		end
	end
end

return Gear

--!strict
-- Shared builder for first-person viewmodels made of anchored parts. Every part is registered
-- under an animation group; Viewmodel moves all of them with one BulkMoveTo per frame.
-- Groups: Gun, Mag, Bolt, LeftArm, RightArm, Flash (flash locals are relative to the muzzle).

local ModelKit = {}

export type Entry = { Part: BasePart, Group: string, Local: CFrame }

-- How a weapon sits and animates. All CFrames are camera space except Muzzle/MagPivot (gun space).
export type Profile = {
	Kind: "Rifle" | "Sniper" | "Knife" | "Grenade",
	Hip: CFrame,
	Aim: CFrame?,
	AimHide: { string }?, -- part names hidden while aimed in (they'd sit under the camera)
	Lowered: CFrame, -- pose relative to Hip while drawing (equip starts here)
	Muzzle: CFrame?,
	MagPivot: CFrame?,
	EquipSeconds: number,
	ReloadSeconds: number?,
	AimInSeconds: number?, -- default 0.18
	AimOutSeconds: number?, -- default 0.14
}

export type Built = {
	Model: Model,
	Entries: { Entry },
	FlashParts: { BasePart },
	Petals: { BasePart },
	Profile: Profile,
}

export type Kit = {
	Add: (
		group: string,
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?,
		shape: Enum.PartType?
	) -> BasePart,
	Adopt: (group: string, part: BasePart, cf: CFrame) -> (),
	Forearm: (group: string, wrist: Vector3, elbow: Vector3) -> (),
	Flash: (scale: number) -> (),
	Finish: (profile: Profile) -> Built,
}

ModelKit.CYL_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinders run along X; this turns them along Z
ModelKit.METAL = Color3.fromRGB(36, 36, 38)
ModelKit.METAL_LIGHT = Color3.fromRGB(56, 56, 60)
ModelKit.SLEEVE = Color3.fromRGB(46, 50, 56)
ModelKit.GLOVE = Color3.fromRGB(26, 26, 28)
local FLASH = Color3.fromRGB(255, 206, 120)

function ModelKit.new(name: string): Kit
	local model = Instance.new("Model")
	model.Name = name
	local entries: { Entry } = {}
	local flashParts: { BasePart } = {}
	local petals: { BasePart } = {}

	local function add(
		group: string,
		partName: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?,
		shape: Enum.PartType?
	): BasePart
		local p = Instance.new("Part")
		p.Name = partName
		-- Grow each part by a tiny amount that differs per part, so no two faces are ever exactly
		-- coplanar. Coplanar faces z-fight, which shows as shimmering ("wiggly") on the gun parts
		-- right in front of the camera, especially while aiming. Tiny details (dots, posts) keep
		-- their exact size so the sight picture stays precise.
		if math.min(size.X, size.Y, size.Z) >= 0.04 then
			size += Vector3.one * (0.0015 * ((#entries % 7) + 1))
		end
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		table.insert(entries, { Part = p, Group = group, Local = cf })
		return p
	end

	-- an existing part (e.g. a store mesh) moved by the viewmodel at `cf` in gun space
	local function adopt(group: string, part: BasePart, cf: CFrame)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		table.insert(entries, { Part = part, Group = group, Local = cf })
	end

	local function forearm(group: string, wrist: Vector3, elbow: Vector3)
		local len = (elbow - wrist).Magnitude
		local cf = CFrame.lookAt((wrist + elbow) / 2, elbow) * ModelKit.CYL_Z
		add(
			group,
			"Forearm",
			Vector3.new(len, 0.32, 0.32),
			cf,
			ModelKit.SLEEVE,
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
		add(
			group,
			"Cuff",
			Vector3.new(0.08, 0.34, 0.34),
			CFrame.lookAt(wrist, elbow) * CFrame.new(0, 0, -0.12) * ModelKit.CYL_Z,
			ModelKit.GLOVE,
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
	end

	-- muzzle flash: hot core, forward plume, 4 star petals (randomly rolled per shot)
	local function flash(scale: number)
		local core = add(
			"Flash",
			"FlashCore",
			Vector3.one * 0.24 * scale,
			CFrame.identity,
			FLASH,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		local plume = add(
			"Flash",
			"FlashPlume",
			Vector3.new(0.13, 0.13, 0.6) * scale,
			CFrame.new(0, 0, -0.3 * scale),
			FLASH,
			Enum.Material.Neon
		)
		table.insert(flashParts, core)
		table.insert(flashParts, plume)
		for i = 0, 3 do
			local petal = add(
				"Flash",
				"Petal" .. i,
				Vector3.new(0.05, 0.42, 0.05) * scale,
				CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, 0.24 * scale, -0.05),
				FLASH,
				Enum.Material.Neon
			)
			table.insert(flashParts, petal)
			table.insert(petals, petal)
		end
		for _, p in flashParts do
			p.Transparency = 1
		end
	end

	return {
		Add = add,
		Adopt = adopt,
		Forearm = forearm,
		Flash = flash,
		Finish = function(profile: Profile): Built
			return {
				Model = model,
				Entries = entries,
				FlashParts = flashParts,
				Petals = petals,
				Profile = profile,
			}
		end,
	}
end

return ModelKit

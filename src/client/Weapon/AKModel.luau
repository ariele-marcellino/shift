--!strict
-- First-person AK-47 + arms. Gun space: origin = receiver centre, -Z = muzzle, +Y = up.
-- Iron-sight line (rear notch -> front post) is at Y = SIGHT_Y.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local ModelKit = require(script.Parent:WaitForChild("ModelKit"))

local AKModel = {}

local SIGHT_Y = 0.265
local MAG_PIVOT = CFrame.new(0, -0.15, -0.2)

local WOOD = Color3.fromRGB(122, 68, 34)
local WOOD_DARK = Color3.fromRGB(92, 50, 26)
local BAKELITE = Color3.fromRGB(140, 60, 30)
local GRIP = Color3.fromRGB(64, 36, 24)
local TRITIUM = Color3.fromRGB(110, 255, 150) -- subtle green, Neon so it reads in dark rooms

function AKModel.Build(): ModelKit.Built
	local kit = ModelKit.new("AKViewmodel")
	local add = kit.Add
	local cyl = Enum.PartType.Cylinder
	local metal, wood = Enum.Material.Metal, Enum.Material.Wood
	local neon, ball = Enum.Material.Neon, Enum.PartType.Ball
	local METAL, METAL_LIGHT, CYL_Z = ModelKit.METAL, ModelKit.METAL_LIGHT, ModelKit.CYL_Z
	local GLOVE = ModelKit.GLOVE

	-- receiver + dust cover
	add("Gun", "Receiver", Vector3.new(0.2, 0.3, 1.0), CFrame.new(0, 0, 0.05), METAL, metal)
	add("Gun", "DustCover", Vector3.new(0.17, 0.08, 0.95), CFrame.new(0, 0.19, 0.08), METAL_LIGHT, metal)
	add("Gun", "CoverRib", Vector3.new(0.1, 0.03, 0.9), CFrame.new(0, 0.235, 0.1), METAL_LIGHT, metal)
	add("Gun", "Trunnion", Vector3.new(0.21, 0.26, 0.14), CFrame.new(0, 0.01, -0.5), METAL, metal)
	add("Gun", "Selector", Vector3.new(0.02, 0.06, 0.42), CFrame.new(0.11, 0.02, 0.22), METAL_LIGHT, metal)
	add("Gun", "TriggerGuard", Vector3.new(0.03, 0.03, 0.3), CFrame.new(0, -0.24, 0.03), METAL, metal)
	add("Gun", "Trigger", Vector3.new(0.03, 0.08, 0.03), CFrame.new(0, -0.19, 0.07), METAL, metal)

	-- rear sight: base + tangent leaf with a U notch. The notch floor sits just under SIGHT_Y so the
	-- front post tip fills it; two tritium dots flank the notch.
	add("Gun", "RearSightBase", Vector3.new(0.14, 0.07, 0.22), CFrame.new(0, 0.185, -0.48), METAL, metal)
	add("Gun", "RearLeaf", Vector3.new(0.13, 0.012, 0.16), CFrame.new(0, 0.224, -0.46), METAL_LIGHT, metal)
	local leafZ = -0.53
	add("Gun", "LeafL", Vector3.new(0.05, 0.05, 0.025), CFrame.new(-0.04, 0.25, leafZ), METAL, metal)
	add("Gun", "LeafR", Vector3.new(0.05, 0.05, 0.025), CFrame.new(0.04, 0.25, leafZ), METAL, metal)
	add("Gun", "NotchFloor", Vector3.new(0.032, 0.033, 0.025), CFrame.new(0, 0.2415, leafZ), METAL, metal)
	add("Gun", "TritiumL", Vector3.one * 0.011, CFrame.new(-0.033, 0.258, leafZ + 0.014), TRITIUM, neon, ball)
	add("Gun", "TritiumR", Vector3.one * 0.011, CFrame.new(0.033, 0.258, leafZ + 0.014), TRITIUM, neon, ball)

	-- wooden handguards + gas tube
	add("Gun", "LowerHandguard", Vector3.new(0.22, 0.2, 0.6), CFrame.new(0, -0.02, -0.84), WOOD, wood)
	add("Gun", "UpperHandguard", Vector3.new(0.15, 0.1, 0.5), CFrame.new(0, 0.14, -0.86), WOOD_DARK, wood)
	add(
		"Gun",
		"GasTube",
		Vector3.new(0.32, 0.09, 0.09),
		CFrame.new(0, 0.15, -1.27) * CYL_Z,
		METAL,
		metal,
		cyl
	)
	add("Gun", "GasBlock", Vector3.new(0.1, 0.19, 0.11), CFrame.new(0, 0.1, -1.44), METAL, metal)

	-- barrel, front sight (post at SIGHT_Y with protective ears), slant muzzle brake
	add(
		"Gun",
		"Barrel",
		Vector3.new(0.92, 0.075, 0.075),
		CFrame.new(0, 0.03, -1.46) * CYL_Z,
		METAL,
		metal,
		cyl
	)
	-- front sight: thin post centred between two hood ears, tip exactly on SIGHT_Y, tritium dot
	add("Gun", "FrontSightBase", Vector3.new(0.09, 0.13, 0.12), CFrame.new(0, 0.11, -1.78), METAL, metal)
	add(
		"Gun",
		"FrontPost",
		Vector3.new(0.014, 0.09, 0.014),
		CFrame.new(0, SIGHT_Y - 0.045, -1.8),
		METAL,
		metal
	)
	add("Gun", "FrontEarL", Vector3.new(0.014, 0.13, 0.08), CFrame.new(-0.05, 0.225, -1.8), METAL, metal)
	add("Gun", "FrontEarR", Vector3.new(0.014, 0.13, 0.08), CFrame.new(0.05, 0.225, -1.8), METAL, metal)
	add(
		"Gun",
		"TritiumFront",
		Vector3.one * 0.012,
		CFrame.new(0, SIGHT_Y - 0.008, -1.79),
		TRITIUM,
		neon,
		ball
	)
	add(
		"Gun",
		"MuzzleBrake",
		Vector3.new(0.16, 0.1, 0.1),
		CFrame.new(0, 0.03, -1.99) * CYL_Z,
		METAL,
		metal,
		cyl
	)

	-- pistol grip
	local gripCF = CFrame.new(0, -0.3, 0.25) * CFrame.Angles(math.rad(-18), 0, 0)
	add("Gun", "PistolGrip", Vector3.new(0.13, 0.36, 0.17), gripCF, GRIP, Enum.Material.Plastic)

	-- stock: thin wrist into a deeper, slightly dropped butt
	add("Gun", "StockWrist", Vector3.new(0.15, 0.19, 0.34), CFrame.new(0, -0.03, 0.72), WOOD, wood)
	local stockCF = CFrame.new(0, -0.13, 1.22) * CFrame.Angles(math.rad(7), 0, 0)
	add("Gun", "Stock", Vector3.new(0.17, 0.33, 0.75), stockCF, WOOD, wood)
	add("Gun", "ButtPlate", Vector3.new(0.18, 0.36, 0.04), stockCF * CFrame.new(0, 0, 0.39), METAL, metal)

	-- charging handle (racked during reload)
	add(
		"Bolt",
		"ChargingHandle",
		Vector3.new(0.16, 0.05, 0.05),
		CFrame.new(0.15, 0.06, 0.18),
		METAL_LIGHT,
		metal,
		cyl
	)

	-- curved magazine: segments chained, each tilted further forward
	do
		local cur = MAG_PIVOT * CFrame.Angles(math.rad(4), 0, 0)
		local depth = 0.25
		for i = 1, 4 do
			cur = cur * CFrame.Angles(math.rad(9), 0, 0)
			local len = 0.14
			add(
				"Mag",
				"Mag" .. i,
				Vector3.new(0.12, len + 0.01, depth),
				cur * CFrame.new(0, -len / 2, 0),
				BAKELITE
			)
			add(
				"Mag",
				"MagRib" .. i,
				Vector3.new(0.13, 0.03, 0.03),
				cur * CFrame.new(0, -len / 2, -depth / 2),
				Color3.fromRGB(110, 46, 22)
			)
			cur = cur * CFrame.new(0, -len, 0)
			depth -= 0.008
		end
		add("Mag", "MagFloor", Vector3.new(0.14, 0.03, depth + 0.02), cur, METAL, metal)
	end

	-- arms
	local fabric = Enum.Material.Fabric
	add(
		"RightArm",
		"RightHand",
		Vector3.new(0.2, 0.24, 0.28),
		gripCF * CFrame.new(0.03, -0.02, 0.02),
		GLOVE,
		fabric
	)
	add("RightArm", "RightThumb", Vector3.new(0.07, 0.07, 0.2), CFrame.new(-0.09, -0.12, 0.12), GLOVE, fabric)
	kit.Forearm("RightArm", Vector3.new(0.05, -0.4, 0.42), Vector3.new(0.5, -0.95, 1.7))
	add("LeftArm", "LeftHand", Vector3.new(0.24, 0.18, 0.32), CFrame.new(-0.04, -0.15, -0.86), GLOVE, fabric)
	add("LeftArm", "LeftFingers", Vector3.new(0.06, 0.12, 0.28), CFrame.new(0.1, -0.06, -0.86), GLOVE, fabric)
	kit.Forearm("LeftArm", Vector3.new(-0.1, -0.28, -0.74), Vector3.new(-0.8, -0.9, 0.35))

	kit.Flash(1)

	return kit.Finish({
		Kind = "Rifle",
		Hip = CFrame.new(0.6, -0.62, -1.45),
		-- Eye on the sight line ~1.6 studs behind the rear leaf: far enough back that the dust cover
		-- (just under the sight line) never passes the camera (it rendered as a giant stretched wedge).
		Aim = CFrame.new(0, -SIGHT_Y, -1.05),
		-- Parts that would sit under/behind the camera when fully aimed; hidden while aimed in.
		AimHide = { "StockWrist", "Stock", "ButtPlate" },
		Lowered = CFrame.new(0.2, -0.85, 0.25) * CFrame.Angles(math.rad(-55), math.rad(35), math.rad(25)),
		Muzzle = CFrame.new(0, 0.03, -2.08),
		MagPivot = MAG_PIVOT,
		EquipSeconds = Tuning.AK.EquipSeconds,
		ReloadSeconds = Tuning.AK.ReloadSeconds,
	})
end

return AKModel

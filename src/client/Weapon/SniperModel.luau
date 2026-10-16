--!strict
-- First-person BOLT-7 sniper (AWP-style silhouette, generic): olive thumbhole stock, long fluted
-- barrel with a big brake, large scope with bell + turrets, bolt handle on the right, short box mag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local ModelKit = require(script.Parent:WaitForChild("ModelKit"))

local SniperModel = {}

local OLIVE = Color3.fromRGB(78, 88, 62)
local OLIVE_DARK = Color3.fromRGB(58, 66, 46)
local RUBBER = Color3.fromRGB(22, 22, 22)
local LENS = Color3.fromRGB(40, 70, 90)
local SCOPE_Y = 0.32
local MAG_PIVOT = CFrame.new(0, -0.12, -0.15)

function SniperModel.Build(): ModelKit.Built
	local kit = ModelKit.new("SniperViewmodel")
	local add = kit.Add
	local cyl = Enum.PartType.Cylinder
	local metal, plastic, fabric = Enum.Material.Metal, Enum.Material.Plastic, Enum.Material.Fabric
	local METAL, METAL_LIGHT, CYL_Z, GLOVE =
		ModelKit.METAL, ModelKit.METAL_LIGHT, ModelKit.CYL_Z, ModelKit.GLOVE

	-- action + chassis
	add("Gun", "Receiver", Vector3.new(0.19, 0.22, 1.1), CFrame.new(0, 0.02, 0), METAL, metal)
	add("Gun", "ForeEnd", Vector3.new(0.25, 0.24, 1.15), CFrame.new(0, -0.06, -0.98), OLIVE, plastic)
	add("Gun", "ForeEndTop", Vector3.new(0.2, 0.06, 1.1), CFrame.new(0, 0.07, -0.98), OLIVE_DARK, plastic)
	add("Gun", "TriggerGuard", Vector3.new(0.04, 0.04, 0.34), CFrame.new(0, -0.24, 0.12), OLIVE_DARK, plastic)

	-- barrel (fluted look: thin dark rings) + brake
	add(
		"Gun",
		"Barrel",
		Vector3.new(1.95, 0.095, 0.095),
		CFrame.new(0, 0.02, -2.0) * CYL_Z,
		METAL,
		metal,
		cyl
	)
	for i = 0, 3 do
		local z = -1.75 - i * 0.22
		add(
			"Gun",
			"Flute" .. i,
			Vector3.new(0.04, 0.105, 0.105),
			CFrame.new(0, 0.02, z) * CYL_Z,
			METAL_LIGHT,
			metal,
			cyl
		)
	end
	add("Gun", "Brake", Vector3.new(0.28, 0.14, 0.14), CFrame.new(0, 0.02, -3.06) * CYL_Z, METAL, metal, cyl)
	add(
		"Gun",
		"BrakePortL",
		Vector3.new(0.02, 0.06, 0.16),
		CFrame.new(-0.075, 0.02, -3.06),
		Color3.new(0, 0, 0)
	)
	add(
		"Gun",
		"BrakePortR",
		Vector3.new(0.02, 0.06, 0.16),
		CFrame.new(0.075, 0.02, -3.06),
		Color3.new(0, 0, 0)
	)

	-- thumbhole stock
	local gripCF = CFrame.new(0, -0.3, 0.32) * CFrame.Angles(math.rad(-14), 0, 0)
	add("Gun", "Grip", Vector3.new(0.15, 0.38, 0.19), gripCF, OLIVE, plastic)
	add("Gun", "StockComb", Vector3.new(0.2, 0.11, 0.85), CFrame.new(0, 0.05, 1.0), OLIVE, plastic)
	add("Gun", "StockLower", Vector3.new(0.22, 0.2, 0.75), CFrame.new(0, -0.26, 1.12), OLIVE, plastic)
	add("Gun", "StockRear", Vector3.new(0.22, 0.46, 0.22), CFrame.new(0, -0.1, 1.42), OLIVE, plastic)
	add(
		"Gun",
		"ButtPad",
		Vector3.new(0.23, 0.48, 0.07),
		CFrame.new(0, -0.1, 1.56),
		RUBBER,
		Enum.Material.Rubber
	)

	-- scope: rings, tube, objective bell, eyepiece, turrets, lens caps
	add("Gun", "RingFront", Vector3.new(0.06, 0.16, 0.08), CFrame.new(0, 0.2, -0.55), METAL, metal)
	add("Gun", "RingRear", Vector3.new(0.06, 0.16, 0.08), CFrame.new(0, 0.2, 0.05), METAL, metal)
	add(
		"Gun",
		"ScopeTube",
		Vector3.new(1.25, 0.17, 0.17),
		CFrame.new(0, SCOPE_Y, -0.25) * CYL_Z,
		METAL,
		metal,
		cyl
	)
	add(
		"Gun",
		"ScopeBell",
		Vector3.new(0.34, 0.25, 0.25),
		CFrame.new(0, SCOPE_Y, -0.98) * CYL_Z,
		METAL,
		metal,
		cyl
	)
	add(
		"Gun",
		"ScopeLens",
		Vector3.new(0.02, 0.22, 0.22),
		CFrame.new(0, SCOPE_Y, -1.16) * CYL_Z,
		LENS,
		Enum.Material.Glass,
		cyl
	)
	add(
		"Gun",
		"Eyepiece",
		Vector3.new(0.24, 0.22, 0.22),
		CFrame.new(0, SCOPE_Y, 0.44) * CYL_Z,
		METAL,
		metal,
		cyl
	)
	add(
		"Gun",
		"EyeRubber",
		Vector3.new(0.06, 0.23, 0.23),
		CFrame.new(0, SCOPE_Y, 0.58) * CYL_Z,
		RUBBER,
		Enum.Material.Rubber,
		cyl
	)
	add(
		"Gun",
		"TurretTop",
		Vector3.new(0.12, 0.1, 0.1),
		CFrame.new(0, SCOPE_Y + 0.12, -0.25) * CFrame.Angles(0, 0, math.rad(90)),
		METAL_LIGHT,
		metal,
		cyl
	)
	add(
		"Gun",
		"TurretSide",
		Vector3.new(0.12, 0.1, 0.1),
		CFrame.new(0.12, SCOPE_Y, -0.25),
		METAL_LIGHT,
		metal,
		cyl
	)

	-- bolt handle (animated)
	add("Bolt", "BoltBody", Vector3.new(0.09, 0.09, 0.5), CFrame.new(0.08, 0.06, 0.25), METAL_LIGHT, metal)
	add(
		"Bolt",
		"BoltArm",
		Vector3.new(0.24, 0.04, 0.04),
		CFrame.new(0.2, 0.04, 0.38),
		METAL_LIGHT,
		metal,
		cyl
	)
	add(
		"Bolt",
		"BoltKnob",
		Vector3.one * 0.1,
		CFrame.new(0.33, 0.04, 0.38),
		RUBBER,
		Enum.Material.Plastic,
		Enum.PartType.Ball
	)

	-- box magazine
	add("Mag", "Mag", Vector3.new(0.14, 0.2, 0.32), MAG_PIVOT * CFrame.new(0, -0.1, 0), METAL, metal)

	-- arms
	add(
		"RightArm",
		"RightHand",
		Vector3.new(0.2, 0.24, 0.28),
		gripCF * CFrame.new(0.03, -0.02, 0.02),
		GLOVE,
		fabric
	)
	kit.Forearm("RightArm", Vector3.new(0.05, -0.42, 0.5), Vector3.new(0.5, -0.95, 1.8))
	add("LeftArm", "LeftHand", Vector3.new(0.26, 0.18, 0.32), CFrame.new(-0.04, -0.2, -1.0), GLOVE, fabric)
	kit.Forearm("LeftArm", Vector3.new(-0.1, -0.3, -0.9), Vector3.new(-0.8, -0.95, 0.25))

	kit.Flash(1.6)

	local s = Tuning.Sniper
	return kit.Finish({
		Kind = "Sniper",
		Hip = CFrame.new(0.62, -0.6, -1.6),
		Aim = CFrame.new(0, -SCOPE_Y, -0.3), -- eye at the eyepiece; the overlay takes over when scoped
		Lowered = CFrame.new(0.2, -0.9, 0.3) * CFrame.Angles(math.rad(-50), math.rad(35), math.rad(25)),
		Muzzle = CFrame.new(0, 0.02, -3.22),
		MagPivot = MAG_PIVOT,
		EquipSeconds = s.EquipSeconds,
		ReloadSeconds = s.ReloadSeconds,
		AimInSeconds = s.ScopeInSeconds,
		AimOutSeconds = 0.12,
	})
end

return SniperModel

--!strict
-- First-person grenade in the right hand. kind = "Frag" (olive ball, spoon + pin ring) or
-- "Smoke" (grey-green canister with a white band).

local ModelKit = require(script.Parent:WaitForChild("ModelKit"))

local GrenadeModel = {}

function GrenadeModel.Build(kind: "Frag" | "Smoke"): ModelKit.Built
	local kit = ModelKit.new(kind .. "Viewmodel")
	local add = kit.Add
	local metal = Enum.Material.Metal
	local GLOVE = ModelKit.GLOVE

	if kind == "Frag" then
		add(
			"Gun",
			"Body",
			Vector3.one * 0.36,
			CFrame.identity,
			Color3.fromRGB(62, 72, 48),
			metal,
			Enum.PartType.Ball
		)
		add("Gun", "Fuse", Vector3.new(0.12, 0.1, 0.12), CFrame.new(0, 0.2, 0), ModelKit.METAL_LIGHT, metal)
		add(
			"Gun",
			"Spoon",
			Vector3.new(0.05, 0.3, 0.08),
			CFrame.new(0.13, 0.08, 0) * CFrame.Angles(0, 0, math.rad(-10)),
			ModelKit.METAL_LIGHT,
			metal
		)
		add(
			"Gun",
			"PinRing",
			Vector3.new(0.02, 0.12, 0.12),
			CFrame.new(-0.1, 0.24, 0) * ModelKit.CYL_Z,
			Color3.fromRGB(190, 190, 180),
			metal,
			Enum.PartType.Cylinder
		)
	else
		local can = CFrame.Angles(0, 0, math.rad(90))
		add(
			"Gun",
			"Body",
			Vector3.new(0.5, 0.3, 0.3),
			can,
			Color3.fromRGB(78, 86, 66),
			metal,
			Enum.PartType.Cylinder
		)
		add(
			"Gun",
			"Band",
			Vector3.new(0.08, 0.31, 0.31),
			CFrame.new(0, 0.1, 0) * can,
			Color3.fromRGB(220, 220, 210),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		add(
			"Gun",
			"Top",
			Vector3.new(0.08, 0.2, 0.2),
			CFrame.new(0, 0.28, 0) * can,
			ModelKit.METAL_LIGHT,
			metal,
			Enum.PartType.Cylinder
		)
		add(
			"Gun",
			"Spoon",
			Vector3.new(0.05, 0.36, 0.08),
			CFrame.new(0.15, 0.06, 0),
			ModelKit.METAL_LIGHT,
			metal
		)
	end
	add(
		"RightArm",
		"RightHand",
		Vector3.new(0.26, 0.26, 0.3),
		CFrame.new(0.06, -0.12, 0.08),
		GLOVE,
		Enum.Material.Fabric
	)
	kit.Forearm("RightArm", Vector3.new(0.08, -0.22, 0.28), Vector3.new(0.4, -0.75, 1.4))

	return kit.Finish({
		Kind = "Grenade",
		Hip = CFrame.new(0.5, -0.5, -1.15),
		Lowered = CFrame.new(0, -0.8, 0.2) * CFrame.Angles(math.rad(-40), 0, 0),
		EquipSeconds = 0.3,
	})
end

return GrenadeModel

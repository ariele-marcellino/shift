--!strict
-- First-person karambit in the right hand, left arm out of view. FromStore builds it from the
-- owner's store karambit (StoreKnife, published by the server); Build is the handmade one used
-- until that has loaded (or if it can't): a short curved handle in the fist, the finger ring behind
-- it (towards the camera) and the claw blade hooking forward and up out of the front of the fist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local ModelKit = require(script.Parent:WaitForChild("ModelKit"))
local StoreKnife = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoreKnife"))

local KnifeModel = {}

local STEEL = Color3.fromRGB(150, 154, 160)
local EDGE = Color3.fromRGB(205, 208, 214) -- ground edge: brighter than the blade flat
local G10 = Color3.fromRGB(30, 32, 30)
local VIEW_LENGTH = 1.15 -- longest side of the store knife in first person (studs)
local HIP = CFrame.new(0.55, -0.55, -1.1) * CFrame.Angles(math.rad(8), math.rad(12), math.rad(-15))
local LOWERED = CFrame.new(0.1, -0.7, 0.3) * CFrame.Angles(math.rad(-50), 0, 0)

local function hand(kit: ModelKit.Kit)
	kit.Add(
		"RightArm",
		"RightHand",
		Vector3.new(0.22, 0.24, 0.3),
		CFrame.new(0.02, -0.02, 0.06),
		ModelKit.GLOVE,
		Enum.Material.Fabric
	)
	kit.Forearm("RightArm", Vector3.new(0.05, -0.08, 0.24), Vector3.new(0.45, -0.6, 1.4))
end

-- The owner's store karambit (template = ReplicatedStorage.StoreModels.Karambit), in the fist.
function KnifeModel.FromStore(template: Model): ModelKit.Built
	local kit = ModelKit.new("KnifeViewmodel")
	local posed = StoreKnife.Posed(template, VIEW_LENGTH)
	for _, d in posed:GetDescendants() do
		if d:IsA("BasePart") then
			kit.Adopt("Gun", d, d.CFrame)
		end
	end
	posed:Destroy()
	hand(kit)
	return kit.Finish({
		Kind = "Knife",
		Hip = HIP,
		Lowered = LOWERED,
		EquipSeconds = Tuning.Knife.EquipSeconds,
	})
end

function KnifeModel.Build(): ModelKit.Built
	local kit = ModelKit.new("KnifeViewmodel")
	local add = kit.Add
	local metal = Enum.Material.Metal

	-- gun space origin = grip centre, the blade leaves the fist along -Z
	-- handle: two slightly bent slabs with grip texture strips and two pivot bolts
	add("Gun", "Handle", Vector3.new(0.09, 0.13, 0.26), CFrame.new(0, 0, -0.02), G10, Enum.Material.Plastic)
	add(
		"Gun",
		"HandleBack",
		Vector3.new(0.09, 0.12, 0.16),
		CFrame.new(0, 0.025, 0.17) * CFrame.Angles(math.rad(-14), 0, 0),
		G10,
		Enum.Material.Plastic
	)
	for i = 0, 2 do
		add(
			"Gun",
			"GripStrip" .. i,
			Vector3.new(0.095, 0.02, 0.05),
			CFrame.new(0, -0.065, 0.06 - i * 0.07),
			Color3.fromRGB(48, 50, 46),
			Enum.Material.Plastic
		)
	end
	for _, z in { -0.1, 0.08 } do
		add(
			"Gun",
			"Bolt",
			Vector3.new(0.1, 0.03, 0.03),
			CFrame.new(0, 0.01, z) * CFrame.Angles(0, 0, math.rad(90)),
			ModelKit.METAL_LIGHT,
			metal,
			Enum.PartType.Cylinder
		)
	end

	-- finger ring behind the fist: 10 short segments round a circle in the Y-Z plane
	local ringCentre = CFrame.new(0, 0.05, 0.36)
	local r, n = 0.095, 10
	for i = 0, n - 1 do
		add(
			"Gun",
			"Ring" .. i,
			Vector3.new(0.035, 0.03, 2 * math.pi * r / n + 0.012),
			ringCentre * CFrame.Angles(i * 2 * math.pi / n, 0, 0) * CFrame.new(0, r, 0),
			ModelKit.METAL,
			metal
		)
	end

	-- claw blade: chained segments, starting down-forward and bending up a little more each step,
	-- tapering to the point; a bright edge strip on the inner (upper, concave) side
	do
		local cur = CFrame.new(0, -0.01, -0.15) * CFrame.Angles(math.rad(-32), 0, 0)
		local segments = 7
		for i = 1, segments do
			local len = 0.085
			local t = (i - 1) / (segments - 1)
			local h = 0.12 - 0.085 * t
			local mid = cur * CFrame.new(0, 0, -len / 2)
			add("Gun", "Blade" .. i, Vector3.new(0.022, h, len + 0.012), mid, STEEL, metal)
			add(
				"Gun",
				"Edge" .. i,
				Vector3.new(0.012, 0.025, len + 0.012),
				mid * CFrame.new(0, h / 2 - 0.006, 0),
				EDGE,
				metal
			)
			cur = cur * CFrame.new(0, 0, -len) * CFrame.Angles(math.rad(14), 0, 0)
		end
		add("Gun", "Point", Vector3.new(0.018, 0.03, 0.06), cur * CFrame.new(0, 0.005, -0.02), EDGE, metal)
	end

	hand(kit)

	return kit.Finish({
		Kind = "Knife",
		Hip = HIP,
		Lowered = LOWERED,
		EquipSeconds = Tuning.Knife.EquipSeconds,
	})
end

return KnifeModel

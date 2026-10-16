--!strict
-- Dedicated, invisible hitboxes on every combatant (players + bots). One box per body part, welded,
-- non-colliding, in collision group "CombatHitbox" which does NOT collide with Default, so ordinary
-- raycasts (bots' vision, world queries) never see them; combat raycasts include them explicitly.
-- Damage zones come from the box's "Zone" attribute, never from meshes or accessories.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Hitboxes = {}

Hitboxes.GROUP = "CombatHitbox"
Hitboxes.FOLDER = "Hitboxes"

local ZONES: { [string]: "Head" | "Body" | "Limb" } = {
	Head = "Head",
	UpperTorso = "Body",
	LowerTorso = "Body",
	Torso = "Body", -- R6
	LeftUpperArm = "Limb",
	LeftLowerArm = "Limb",
	LeftHand = "Limb",
	RightUpperArm = "Limb",
	RightLowerArm = "Limb",
	RightHand = "Limb",
	LeftUpperLeg = "Limb",
	LeftLowerLeg = "Limb",
	LeftFoot = "Limb",
	RightUpperLeg = "Limb",
	RightLowerLeg = "Limb",
	RightFoot = "Limb",
	["Left Arm"] = "Limb", -- R6
	["Right Arm"] = "Limb",
	["Left Leg"] = "Limb",
	["Right Leg"] = "Limb",
}

local groupReady = false

function Hitboxes.Init()
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(Hitboxes.GROUP) then
			PhysicsService:RegisterCollisionGroup(Hitboxes.GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(Hitboxes.GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(Hitboxes.GROUP, Hitboxes.GROUP, true)
	end)
	groupReady = ok
	if not ok then
		warn("[Combat] hitbox collision group unavailable:", err)
	end
end

local function scaleFor(zone: string): number
	local h = Tuning.Hitbox
	return if zone == "Head" then h.HeadScale elseif zone == "Body" then h.BodyScale else h.LimbScale
end

-- Builds (or completes) the hitbox set for a model. Idempotent.
function Hitboxes.Build(model: Model)
	local folder = model:FindFirstChild(Hitboxes.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Hitboxes.FOLDER
		folder.Parent = model
	end
	for _, child in model:GetChildren() do
		local zone = ZONES[child.Name]
		if not zone or not child:IsA("BasePart") then
			continue
		end
		local name = "HB_" .. child.Name
		if (folder :: Instance):FindFirstChild(name) then
			continue
		end
		local box = Instance.new("Part")
		box.Name = name
		box.Size = child.Size * scaleFor(zone)
		box.CFrame = child.CFrame
		box.Transparency = 1
		box.CanCollide = false
		box.CanTouch = false
		box.CanQuery = true
		box.Massless = true
		box.CastShadow = false
		box.Anchored = false
		if groupReady then
			box.CollisionGroup = Hitboxes.GROUP
		end
		box:SetAttribute("Zone", zone)
		box:SetAttribute("Bone", child.Name)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = child
		weld.Part1 = box
		weld.Parent = box
		box.Parent = folder
	end
end

function Hitboxes.Folder(model: Model): Instance?
	return model:FindFirstChild(Hitboxes.FOLDER)
end

function Hitboxes.Zone(part: BasePart): ("Head" | "Body" | "Limb")?
	local z = part:GetAttribute("Zone")
	if z == "Head" or z == "Body" or z == "Limb" then
		return z
	end
	return nil
end

function Hitboxes.GroupReady(): boolean
	return groupReady
end

return Hitboxes

--!strict
-- Bot bodies: an R15 rig from Players:CreateHumanoidModelFromDescription with a plain description
-- (built once, cloned per spawn), or a simple welded fallback rig if that call fails.

local Players = game:GetService("Players")

local BotBody = {}

local template: Model? = nil
local triedTemplate = false

local function plainDescription(): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(204, 170, 140)
	desc.HeadColor = skin
	desc.TorsoColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.LeftLegColor = skin
	desc.RightLegColor = skin
	return desc
end

local function fallbackRig(): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	local function limb(name: string, size: Vector3, offset: Vector3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = root.CFrame * CFrame.new(offset)
		p.CanCollide = name == "UpperTorso" or name == "LowerTorso"
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	limb("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 0.6, 0))
	limb("LowerTorso", Vector3.new(2, 0.6, 1), Vector3.new(0, -0.4, 0))
	limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 2.05, 0))
	limb("LeftUpperArm", Vector3.new(1, 1.6, 1), Vector3.new(-1.5, 0.6, 0))
	limb("RightUpperArm", Vector3.new(1, 1.6, 1), Vector3.new(1.5, 0.6, 0))
	limb("LeftUpperLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -1.7, 0))
	limb("RightUpperLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, -1.7, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2.7
	humanoid.Parent = model
	return model
end

local function buildTemplate(): Model?
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(plainDescription(), Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn("[Bots] CreateHumanoidModelFromDescription failed, using fallback rig: " .. tostring(result))
		return nil
	end
	local model = result :: Model
	-- Client-side scripts that came with the rig don't run on NPCs; we animate from the server.
	for _, name in { "Animate", "Health" } do
		local child = model:FindFirstChild(name)
		if child and child:IsA("LuaSourceContainer") then
			child:Destroy()
		end
	end
	return model
end

function BotBody.Create(name: string): Model
	if not triedTemplate then
		triedTemplate = true
		template = buildTemplate()
	end
	local model = if template then template:Clone() else fallbackRig()
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = true
	end
	return model
end

return BotBody

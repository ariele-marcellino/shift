--!strict
-- Team uniforms readable in the dark: team-colored torso and sleeves, dark trousers and gloves,
-- avatar clothing removed, and a small team-colored shoulder light (non-shadow PointLight).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Uniform = {}

local TROUSERS = Color3.fromRGB(38, 40, 44)
local GLOVES = Color3.fromRGB(28, 28, 30)
local LIGHT_NAME = "TeamShoulderLight"

local function partRole(name: string): string?
	if name == "UpperTorso" or name == "LowerTorso" or name == "Torso" then
		return "Torso"
	elseif name:find("Hand") then
		return "Hand"
	elseif name:find("Arm") then
		return "Arm"
	elseif name:find("Leg") or name:find("Foot") then
		return "Leg"
	end
	return nil
end

local function addShoulderLight(model: Model, color: Color3)
	local old = model:FindFirstChild(LIGHT_NAME)
	if old then
		old:Destroy()
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local lamp = Instance.new("Part")
	lamp.Name = LIGHT_NAME
	lamp.Shape = Enum.PartType.Ball
	lamp.Size = Vector3.new(0.3, 0.3, 0.3)
	lamp.Material = Enum.Material.Neon
	lamp.Color = color
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CanTouch = false
	lamp.Massless = true
	lamp.CastShadow = false
	lamp.Anchored = false
	-- Left shoulder, slightly forward so the owner's first-person camera doesn't sit inside it.
	lamp.CFrame = torso.CFrame * CFrame.new(-torso.Size.X * 0.42, torso.Size.Y * 0.5, -torso.Size.Z * 0.2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = lamp
	weld.Parent = lamp
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 5
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = lamp
	lamp.Parent = model
end

function Uniform.Apply(model: Model, team: string)
	local info = (Tuning.Teams :: any)[team]
	if not info then
		return
	end
	local teamColor: Color3 = info.Color
	local shirt = teamColor:Lerp(Color3.new(0, 0, 0), 0.2)

	for _, child in model:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end

	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if not bodyColors then
		bodyColors = Instance.new("BodyColors")
		bodyColors.Parent = model
	end
	assert(bodyColors, "BodyColors missing")
	bodyColors.TorsoColor3 = shirt
	bodyColors.LeftArmColor3 = shirt
	bodyColors.RightArmColor3 = shirt
	bodyColors.LeftLegColor3 = TROUSERS
	bodyColors.RightLegColor3 = TROUSERS

	-- BodyColors colors hands with the arms; paint parts directly too (also covers fallback rigs).
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local role = partRole(part.Name)
			if role == "Torso" or role == "Arm" then
				part.Color = shirt
			elseif role == "Hand" then
				part.Color = GLOVES
			elseif role == "Leg" then
				part.Color = TROUSERS
			end
		end
	end

	addShoulderLight(model, teamColor)
end

return Uniform

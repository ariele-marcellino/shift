--!strict
-- Server-side movement speeds from replicated character attributes (v2).
-- Base speed by HeldWeapon (Knife 20, AK 16, Sniper 14, grenades 16); then the slowest applicable
-- modifier wins: Scoped (sniper) 7, Aiming (AK) 10, Crouching 8, Wading 10, CarryingCore -> Carrier 18.
-- Mode sets `Wading` itself from WorldService:IsInWater (see Movement.UpdateWading).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Deps = require(script.Parent.Deps)

local Movement = {}

local WATCHED =
	{ "HeldWeapon", "Scoped", "Aiming", "Crouching", "Wading", "CarryingCore", "Sprinting", "Sliding" }

local function weaponSpeed(held: any): number
	local m = Tuning.Movement
	if held == "Knife" then
		return m.Knife
	elseif held == "Sniper" then
		return m.Sniper
	elseif held == "Frag" or held == "Smoke" then
		return m.Grenade
	end
	return m.AK
end

function Movement.SpeedFor(model: Model): number
	local m = Tuning.Movement
	local held = model:GetAttribute("HeldWeapon")
	if model:GetAttribute("Sliding") == true then
		-- Slide overrides weapon/crouch speed; eases out to EndSpeed. Wading still caps it.
		local s = Tuning.Slide
		local started = model:GetAttribute("SlideStart")
		local t = if type(started) == "number"
			then math.clamp((workspace:GetServerTimeNow() - started) / s.Seconds, 0, 1)
			else 1
		local eased = 1 - (1 - t) * (1 - t)
		local slide = s.Speed + (s.EndSpeed - s.Speed) * eased
		if model:GetAttribute("Wading") == true then
			slide = math.min(slide, m.Wading)
		end
		return slide
	end
	local speed = weaponSpeed(held)
	local carrying = model:GetAttribute("CarryingCore") ~= nil
	-- Sprint: flat bonus on the weapon speed; aiming/scoping/crouching/wading cancel it below.
	if model:GetAttribute("Sprinting") == true and (not carrying or m.SprintCarrier) then
		speed += m.SprintBonus
	end
	if carrying then
		speed = if model:GetAttribute("Sprinting") == true and m.SprintCarrier
			then m.Carrier + m.SprintBonus
			else m.Carrier -- knife-locked carrier: fixed carrier speed instead of the knife's
	elseif model:GetAttribute("Scoped") == true then
		speed = math.min(speed, m.SniperScoped)
	elseif model:GetAttribute("Aiming") == true then
		speed = math.min(speed, if held == "Sniper" then m.SniperScoped else m.Aiming)
	end
	if model:GetAttribute("Crouching") == true then
		speed = math.min(speed, m.Crouch)
	end
	if model:GetAttribute("Wading") == true then
		speed = math.min(speed, m.Wading)
	end
	return speed
end

function Movement.Apply(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local speed = Movement.SpeedFor(model)
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

-- Sets the Wading attribute from World's water volumes (the attribute change re-applies speed).
function Movement.UpdateWading(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local wading = Deps.IsInWater(root.Position)
	if (model:GetAttribute("Wading") == true) ~= wading then
		model:SetAttribute("Wading", wading)
	end
end

-- React immediately to attribute changes; MatchService also re-asserts periodically.
function Movement.Track(model: Model)
	for _, attribute in WATCHED do
		model:GetAttributeChangedSignal(attribute):Connect(function()
			Movement.Apply(model)
		end)
	end
	Movement.Apply(model)
end

return Movement

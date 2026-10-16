--!strict
-- Honest bot perception: field of view, line of sight, smoke, and darkness.
-- Lit targets are seen up to ViewDistanceLit. A target standing in the dark is only seen within
-- ViewDistanceDark, unless it gives itself away: flashlight on, recent muzzle flash, carrying a
-- glowing Core, or caught in the bot's own flashlight beam.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Deps = require(script.Parent.Parent.Mode.Deps)
local WorldRay = require(script.Parent.WorldRay)

local Perception = {}

local MUZZLE_REVEAL_SECONDS = 0.7
local DARK_CACHE_SECONDS = 0.5
local CLOSE_RANGE = 10 -- "heard / felt": no FOV check this close
local FOV_COS = math.cos(math.rad(75)) -- 150 degree view cone

local lastShot: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local darkCache: { [Model]: { At: number, Dark: boolean } } = setmetatable({}, { __mode = "k" }) :: any

function Perception.NoteShot(model: Model?)
	if model then
		lastShot[model] = os.clock()
	end
end

function Perception.RecentlyFired(model: Model, now: number): boolean
	local t = lastShot[model]
	return t ~= nil and now - t < MUZZLE_REVEAL_SECONDS
end

-- WorldService:IsDark is cached per model to keep calls cheap.
function Perception.IsModelInDark(model: Model, position: Vector3, now: number): boolean
	local entry = darkCache[model]
	if entry and now - entry.At < DARK_CACHE_SECONDS then
		return entry.Dark
	end
	local dark = Deps.IsDark(position)
	darkCache[model] = { At = now, Dark = dark }
	return dark
end

function Perception.GivesLight(model: Model, now: number): boolean
	return model:GetAttribute("Flashlight") == true
		or model:GetAttribute("CarryingCore") ~= nil
		or Perception.RecentlyFired(model, now)
end

local function part(model: Model, name: string): BasePart?
	local p = model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

export type Observer = {
	Model: Model,
	FlashlightOn: boolean,
	WideAwareUntil: number, -- 360 degree awareness (just took damage / tracking a target)
}

-- Returns the visible aim point on the target, or nil.
function Perception.CanSee(observer: Observer, target: Model, now: number): Vector3?
	local eyePart = part(observer.Model, "Head")
	local obsRoot = part(observer.Model, "HumanoidRootPart")
	local targetRoot = part(target, "HumanoidRootPart")
	if not eyePart or not obsRoot or not targetRoot then
		return nil
	end
	local eye = eyePart.Position
	local toTarget = targetRoot.Position - eye
	local dist = toTarget.Magnitude
	if dist > Tuning.Bots.ViewDistanceLit then
		return nil
	end

	-- Field of view (flat), skipped up close or while alert.
	if dist > CLOSE_RANGE and now > observer.WideAwareUntil then
		local look = obsRoot.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flatLook.Magnitude > 0 and flatDir.Magnitude > 0 then
			if flatLook.Unit:Dot(flatDir.Unit) < FOV_COS then
				return nil
			end
		end
	end

	-- Darkness limits range unless the target is lit or caught in our beam.
	if dist > Tuning.Bots.ViewDistanceDark then
		local dark = Perception.IsModelInDark(target, targetRoot.Position, now)
		if dark and not Perception.GivesLight(target, now) then
			local inBeam = false
			if observer.FlashlightOn and dist <= Tuning.Flashlight.Range then
				local look = eyePart.CFrame.LookVector
				local cosHalf = math.cos(math.rad(Tuning.Flashlight.Angle * 0.5 + 5))
				inBeam = look:Dot(toTarget.Unit) >= cosHalf
			end
			if not inBeam then
				return nil
			end
		end
	end

	-- Line of sight to head, else torso.
	local aimPoints = {}
	local torso = part(target, "UpperTorso") or part(target, "Torso")
	if torso then
		table.insert(aimPoints, torso.Position)
	end
	local head = part(target, "Head")
	if head then
		table.insert(aimPoints, head.Position)
	end
	for _, point in aimPoints do
		if WorldRay.Clear(eye, point) then
			if Deps.IsSmoked(eye, point) then
				return nil
			end
			-- Always aim center mass when it is visible; head only when that's all we can see.
			return point
		end
	end
	return nil
end

return Perception

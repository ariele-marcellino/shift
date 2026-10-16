--!strict
-- Client mirror of the server's hit resolution, used at fire time to build the hit claim and to
-- place impacts: a world ray that ignores every combatant model (bodies/accessories never block),
-- passes through invisible volumes and wallbangs through "Penetrable" parts, plus an Include-only
-- ray against live enemy hitboxes (server-built "Hitboxes" folders) up to where the world ray stops.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local HitScan = {}

local GROUP = "CombatHitbox"
local MAX_PASSES = 10

export type Wall = { Entry: Vector3, Exit: Vector3, Distance: number }
export type Result = {
	Position: Vector3,
	Normal: Vector3,
	Distance: number,
	Victim: Model?,
	Hitbox: BasePart?,
	WorldPart: BasePart?,
	Walls: { Wall },
}

local function taggedUp(part: Instance, tag: string, levels: number): boolean
	local node: Instance? = part
	for _ = 1, levels do
		if not node or node == workspace then
			return false
		end
		if CollectionService:HasTag(node, tag) then
			return true
		end
		node = node.Parent
	end
	return false
end

local groupKnown: boolean? = nil
local function hitboxGroup(): string?
	if groupKnown == nil or groupKnown == false then
		local ok, registered = pcall(function()
			return PhysicsService:IsCollisionGroupRegistered(GROUP)
		end)
		groupKnown = ok and registered == true
	end
	return if groupKnown then GROUP else nil
end

local function combatants(): { Model }
	local list: { Model } = {}
	for _, inst in CollectionService:GetTagged("Combatant") do
		if inst:IsA("Model") then
			table.insert(list, inst)
		end
	end
	local me = Players.LocalPlayer.Character
	if me and not table.find(list, me) then
		table.insert(list, me)
	end
	return list
end

local function alive(model: Model): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- Hitbox folders of live enemies of the local player.
function HitScan.EnemyHitboxes(): { Instance }
	local me = Players.LocalPlayer.Character
	local team = me and me:GetAttribute("Team")
	local list: { Instance } = {}
	for _, model in combatants() do
		if model == me or not alive(model) then
			continue
		end
		if team ~= nil and model:GetAttribute("Team") == team then
			continue
		end
		local folder = model:FindFirstChild("Hitboxes")
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

-- ignore: extra local-only instances (camera, fx folders, own character).
function HitScan.Cast(origin: Vector3, direction: Vector3, weapon: string, ignore: { Instance }): Result?
	local stats = if weapon == "Sniper" then Tuning.Sniper else Tuning.AK
	local pen = (Tuning.Penetration :: any)[weapon] or { MaxWalls = 0, MaxThickness = 0 }
	local range = stats.Range

	-- world
	local filter: { Instance } = table.clone(ignore)
	for _, m in combatants() do
		table.insert(filter, m)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local walls: { Wall } = {}
	local start, travelled = origin, 0
	local stop: RaycastResult? = nil
	local stopDistance = range
	for _ = 1, MAX_PASSES do
		if travelled >= range then
			break
		end
		params.FilterDescendantsInstances = filter
		local r = workspace:Raycast(start, direction * (range - travelled), params)
		if not r then
			break
		end
		local part = r.Instance :: BasePart
		local distance = travelled + (r.Position - start).Magnitude
		if
			(not part.CanCollide and part.Transparency >= 0.95)
			or part:HasTag("BrokenWindowBarrier") -- broken window: blocks players only
			or (weapon == "Sniper" and part:HasTag("BreakableGlass")) -- sniper: glass costs no damage
		then
			table.insert(filter, part)
			travelled, start = distance, r.Position
			continue
		end
		if #walls < pen.MaxWalls and taggedUp(part, "Penetrable", 3) then
			local probe = pen.MaxThickness + 0.05
			local inc = RaycastParams.new()
			inc.FilterType = Enum.RaycastFilterType.Include
			inc.FilterDescendantsInstances = { part }
			local back = workspace:Raycast(r.Position + direction * probe, -direction * probe, inc)
			if back then
				table.insert(walls, { Entry = r.Position, Exit = back.Position, Distance = distance })
				table.insert(filter, part)
				travelled = distance + (back.Position - r.Position).Magnitude
				start = back.Position
				continue
			end
		end
		stop, stopDistance = r, distance
		break
	end

	-- enemy hitboxes up to where the bullet stopped
	local folders = HitScan.EnemyHitboxes()
	if #folders > 0 then
		local hp = RaycastParams.new()
		hp.FilterType = Enum.RaycastFilterType.Include
		hp.FilterDescendantsInstances = folders
		local group = hitboxGroup()
		if group then
			hp.CollisionGroup = group
		end
		local hb = workspace:Raycast(origin, direction * stopDistance, hp)
		if hb then
			local part = hb.Instance :: BasePart
			local victim = part.Parent and part.Parent.Parent
			return {
				Position = hb.Position,
				Normal = hb.Normal,
				Distance = (hb.Position - origin).Magnitude,
				Victim = if victim and victim:IsA("Model") then victim else nil,
				Hitbox = part,
				WorldPart = nil,
				Walls = walls,
			}
		end
	end
	if stop then
		return {
			Position = stop.Position,
			Normal = stop.Normal,
			Distance = stopDistance,
			Victim = nil,
			Hitbox = nil,
			WorldPart = stop.Instance :: BasePart,
			Walls = walls,
		}
	end
	return nil
end

return HitScan

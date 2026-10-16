--!strict
-- Team-only spawn barriers via collision groups. Each character's parts go in "Team_<team>"; a
-- barrier part in "Barrier_<team>" blocks only the OTHER team's characters. Barriers ignore the
-- world, hitboxes and projectiles; they are CanQuery false, so bullets pass through them.
-- A flag carrier's parts go in "Carrier" instead, which EVERY barrier blocks: you can't take the
-- enemy flag into your own spawn (owner, 2026-10-16). Back to "Team_<team>" once it's dropped.
-- Server-side (collision groups replicate). Groups are registered lazily on first use.

local PhysicsService = game:GetService("PhysicsService")

local TeamCollision = {}

local TEAMS = { "Blue", "Red" }
local HITBOX_GROUP = "CombatHitbox"
local CARRIER_GROUP = "Carrier"

local ready = false

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

function TeamCollision.Ensure(): boolean
	if ready then
		return true
	end
	local ok, err = pcall(function()
		register(HITBOX_GROUP)
		register(CARRIER_GROUP)
		for _, team in TEAMS do
			register("Team_" .. team)
			register("Barrier_" .. team)
		end
		for _, team in TEAMS do
			local barrier = "Barrier_" .. team
			PhysicsService:CollisionGroupSetCollidable(barrier, "Default", false)
			PhysicsService:CollisionGroupSetCollidable(barrier, HITBOX_GROUP, false)
			PhysicsService:CollisionGroupSetCollidable(barrier, CARRIER_GROUP, true) -- blocks every carrier
			for _, other in TEAMS do
				PhysicsService:CollisionGroupSetCollidable(barrier, "Barrier_" .. other, false)
				-- Own team passes, the other team is blocked.
				PhysicsService:CollisionGroupSetCollidable(barrier, "Team_" .. other, other ~= team)
			end
		end
	end)
	if not ok then
		warn("[TeamCollision] collision groups unavailable:", err)
	end
	ready = ok
	return ok
end

local function setPart(part: Instance, group: string)
	if part:IsA("BasePart") and part.CollisionGroup ~= HITBOX_GROUP then
		part.CollisionGroup = group
	end
end

local watched: { [Model]: { RBXScriptConnection } } = {}

local function carrying(model: Model): boolean
	local c = model:GetAttribute("CarryingCore")
	return c ~= nil and c ~= false and c ~= ""
end

-- Put every part of a character (now and later) in its team's group, or in "Carrier" while it
-- carries a flag (CarryingCore attribute).
function TeamCollision.ApplyCharacter(model: Model, team: string?)
	if not TeamCollision.Ensure() then
		return
	end
	local function groupNow(): string
		if carrying(model) then
			return CARRIER_GROUP
		end
		return if team then "Team_" .. team else "Default"
	end
	local function applyAll()
		local group = groupNow()
		for _, d in model:GetDescendants() do
			setPart(d, group)
		end
	end
	applyAll()
	local old = watched[model]
	if old then
		for _, conn in old do
			conn:Disconnect()
		end
	end
	watched[model] = {
		model.DescendantAdded:Connect(function(d)
			setPart(d, groupNow())
		end),
		model:GetAttributeChangedSignal("CarryingCore"):Connect(applyAll),
	}
	model.Destroying:Once(function()
		local conns = watched[model]
		if conns then
			for _, conn in conns do
				conn:Disconnect()
			end
			watched[model] = nil
		end
	end)
end

function TeamCollision.ApplyBarrier(part: BasePart, team: string)
	if TeamCollision.Ensure() then
		part.CollisionGroup = "Barrier_" .. team
	end
end

return TeamCollision

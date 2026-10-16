--!strict
-- One-way spawn barriers for combat (shared: the server decides, the client mirrors it so your own
-- shot visibly ricochets off an enemy barrier). A barrier (tag "SpawnBarrier", attribute Team) lets its own
-- team shoot out but stops everything the other team fires in: bullets end at the barrier, enemy
-- grenades bounce off it (TeamCollision groups) and blasts don't reach through it.
-- Barriers are axis-aligned boxes, so this is a plain segment-vs-AABB test.

local CollectionService = game:GetService("CollectionService")

local SpawnBarriers = {}

local TAG = "SpawnBarrier"

-- Slab test: entry distance along [from, to] (0..1), or nil if the segment misses the box.
local function segmentEntry(from: Vector3, to: Vector3, part: BasePart): number?
	local half = part.Size / 2
	local lo, hi = part.Position - half, part.Position + half
	local d = to - from
	local tmin, tmax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local o = (from :: any)[axis] :: number
		local dir = (d :: any)[axis] :: number
		local a, b = (lo :: any)[axis] :: number, (hi :: any)[axis] :: number
		if math.abs(dir) < 1e-9 then
			if o < a or o > b then
				return nil
			end
		else
			local t1, t2 = (a - o) / dir, (b - o) / dir
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end

-- First point where the segment from -> to enters a barrier that blocks `team` (any barrier of
-- another team), and that barrier. nil when nothing blocks. A shooter standing inside a barrier is
-- not blocked by it.
function SpawnBarriers.Hit(from: Vector3, to: Vector3, team: string?): (Vector3?, BasePart?)
	local best: number? = nil
	local bestPart: BasePart? = nil
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("BasePart") and inst:GetAttribute("Team") ~= team then
			local t = segmentEntry(from, to, inst)
			if t and t > 0 and (best == nil or t < best) then
				best, bestPart = t, inst
			end
		end
	end
	if best then
		return from:Lerp(to, best), bestPart
	end
	return nil, nil
end

function SpawnBarriers.Blocked(from: Vector3, to: Vector3, team: string?): Vector3?
	local point = SpawnBarriers.Hit(from, to, team)
	return point
end

-- Face normal of a barrier on the side `from` is on (barriers are thin along one world axis).
function SpawnBarriers.Normal(part: BasePart, from: Vector3): Vector3
	local s = part.Size
	local d = from - part.Position
	if s.X <= s.Y and s.X <= s.Z then
		return Vector3.new(if d.X >= 0 then 1 else -1, 0, 0)
	elseif s.Z <= s.Y then
		return Vector3.new(0, 0, if d.Z >= 0 then 1 else -1)
	end
	return Vector3.new(0, if d.Y >= 0 then 1 else -1, 0)
end

function SpawnBarriers.TeamOf(model: Instance?): string?
	local team = model and model:GetAttribute("Team")
	return if type(team) == "string" then team else nil
end

return SpawnBarriers

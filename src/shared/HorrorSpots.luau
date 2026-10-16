--!strict
-- Where a creepy figure can stand, seen from an eye position (camera on the client, head on the
-- server). Used by HorrorController (one-player scares) and HorrorService (shared apparitions that
-- everyone nearby sees). All queries take the caller's RaycastParams (what to ignore).
--
-- Placement uses the model's VISIBLE parts only: store models often carry big invisible root /
-- hitbox parts, which made figures float or sink when placed by their full bounding box.

local HorrorSpots = {}

function HorrorSpots.FlatLook(cf: CFrame): Vector3
	local l = cf.LookVector
	local f = Vector3.new(l.X, 0, l.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

local function direction(look: Vector3, rng: Random, minAng: number, maxAng: number): Vector3
	local ang = math.rad(rng:NextNumber(minAng, maxAng) * (if rng:NextNumber() < 0.5 then -1 else 1))
	return (CFrame.Angles(0, ang, 0) * CFrame.new(Vector3.zero, look)).LookVector
end

function HorrorSpots.FloorAt(pos: Vector3, params: RaycastParams): Vector3?
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position else nil
end

function HorrorSpots.Clear(from: Vector3, to: Vector3, params: RaycastParams): boolean
	local d = to - from
	if d.Magnitude < 0.6 then
		return true
	end
	return workspace:Raycast(from, d - d.Unit * 0.5, params) == nil
end

-- A wall in a horizontal direction `minAng..maxAng` degrees off the view (either side).
function HorrorSpots.FindWall(
	eye: CFrame,
	params: RaycastParams,
	rng: Random,
	minAng: number,
	maxAng: number,
	minD: number,
	maxD: number
): RaycastResult?
	local look = HorrorSpots.FlatLook(eye)
	for _ = 1, 12 do
		local hit = workspace:Raycast(eye.Position, direction(look, rng, minAng, maxAng) * maxD, params)
		if hit and hit.Distance >= minD and math.abs(hit.Normal.Y) < 0.3 then
			return hit
		end
	end
	return nil
end

-- A room corner `minAng..maxAng` degrees off the view: hit a wall, then slide along it until a
-- second, roughly perpendicular wall. Returns a floor point ~1.3 studs out of both walls that the
-- eye can see.
function HorrorSpots.FindCorner(
	eye: CFrame,
	params: RaycastParams,
	rng: Random,
	minAng: number,
	maxAng: number,
	minD: number,
	maxD: number
): Vector3?
	local look = HorrorSpots.FlatLook(eye)
	for _ = 1, 10 do
		local first = workspace:Raycast(eye.Position, direction(look, rng, minAng, maxAng) * maxD, params)
		if first and math.abs(first.Normal.Y) < 0.3 then
			local n1 = Vector3.new(first.Normal.X, 0, first.Normal.Z).Unit
			local along = n1:Cross(Vector3.yAxis)
			local from = first.Position + n1 * 1.3
			for _, side in { 1, -1 } do
				local second = workspace:Raycast(from, along * side * 18, params)
				if second and math.abs(second.Normal.Y) < 0.3 and math.abs(second.Normal:Dot(n1)) < 0.35 then
					local n2 = Vector3.new(second.Normal.X, 0, second.Normal.Z).Unit
					local spot = second.Position + n2 * 1.3
					local d = (spot - eye.Position).Magnitude
					local floor = HorrorSpots.FloorAt(spot, params)
					if
						floor
						and d >= minD
						and d <= maxD + 18
						and HorrorSpots.Clear(eye.Position, floor + Vector3.new(0, 4, 0), params)
					then
						return floor
					end
				end
			end
		end
	end
	return nil
end

-- A corner if there is one, else a spot in front of a wall, in the given view cone.
function HorrorSpots.FindSpot(
	eye: CFrame,
	params: RaycastParams,
	rng: Random,
	minAng: number,
	maxAng: number,
	minD: number,
	maxD: number
): Vector3?
	local corner = HorrorSpots.FindCorner(eye, params, rng, minAng, maxAng, minD, maxD)
	if corner then
		return corner
	end
	local hit = HorrorSpots.FindWall(eye, params, rng, minAng, maxAng, minD, maxD)
	local floor = hit and HorrorSpots.FloorAt(hit.Position + hit.Normal * 2, params)
	if floor and HorrorSpots.Clear(eye.Position, floor + Vector3.new(0, 4, 0), params) then
		return floor
	end
	return nil
end

-- World-space box around the visible parts (Transparency < 0.9). Falls back to the full box.
local SIGNS = { -1, 1 } -- box corner signs (constant: no per-part allocation)

function HorrorSpots.VisibleBounds(model: Model): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local any = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			any = true
			local cf, half = d.CFrame, d.Size / 2
			for _, sx in SIGNS do
				for _, sy in SIGNS do
					for _, sz in SIGNS do
						local p = cf:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
						lo = lo:Min(p)
						hi = hi:Max(p)
					end
				end
			end
		end
	end
	if not any then
		local cf, size = model:GetBoundingBox()
		return cf.Position - size / 2, cf.Position + size / 2
	end
	return lo, hi
end

-- Stand a model on `floor` (visible bottom on the floor, centred on it), turned to face `face`
-- (a world point) or a random way.
function HorrorSpots.StandOn(model: Model, floor: Vector3, face: Vector3?, rng: Random)
	local pivot = model:GetPivot()
	local yaw = if face
		then math.atan2(-(face.X - floor.X), -(face.Z - floor.Z))
		else rng:NextNumber(0, math.pi * 2)
	-- Keep the model's own tilt; replace only its heading.
	local _, curYaw = pivot:ToEulerAnglesYXZ()
	model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, yaw - curYaw, 0) * pivot.Rotation)
	local lo, hi = HorrorSpots.VisibleBounds(model)
	local bottom = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	model:PivotTo(model:GetPivot() + (floor + Vector3.new(0, 0.02, 0) - bottom))
end

return HorrorSpots

--!strict
-- Server hit resolution (v3, hitbox-based):
--   * World ray: excludes every combatant model (bodies + accessories never block), passes through
--     invisible non-colliding volumes, wallbangs through "Penetrable" parts per
--     Tuning.Penetration[weapon] (max walls / thickness / damage kept per wall).
--   * Hitbox ray: Include-only ray against the enemy hitboxes (Hitboxes.luau) up to where the world
--     ray stopped. Nearest wins; walls in front of the victim cost damage.
--   * ValidateClaim: favor-the-shooter. The client's claimed hitbox + point are accepted if the point
--     lies within tolerance of that hitbox rewound by the shooter's latency (<= MaxRewindSeconds),
--     sits on the shot ray, the shot faces where the body faces, and the world doesn't block the path.
--   * Resolve: server re-cast, then a rewound hitbox test per enemy, used when there is no valid claim.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local Combatants = require(script.Parent:WaitForChild("Combatants"))
local Hitboxes = require(script.Parent:WaitForChild("Hitboxes"))

local Glass = require(script.Parent:WaitForChild("Glass"))

local Ballistics = {}

Ballistics.MAX_REWIND_SECONDS = Tuning.Hitbox.MaxRewindSeconds
local MAX_REWIND_STUDS = 8
local MAX_PASSES = 10

export type Wall = { Entry: Vector3, Exit: Vector3, Distance: number }

export type Hit = {
	Part: BasePart,
	Position: Vector3,
	Normal: Vector3,
	Distance: number,
	Victim: Model?, -- live enemy combatant
	Zone: ("Head" | "Body" | "Limb")?,
	Lamp: string?, -- LampId if a BreakableLamp was hit
	Multiplier: number, -- damage kept after walls
	Walls: { Wall }, -- penetrated walls before this hit
}

export type Claim = { Target: Model, Part: string, Position: Vector3 }

type Pen = { MaxWalls: number, MaxThickness: number, DamageMultiplier: number }

local NO_PEN: Pen = { MaxWalls = 0, MaxThickness = 0, DamageMultiplier = 1 }

local extraIgnore: { Instance } = {}

-- Folders whose contents never stop bullets (smoke clouds, grenades). Registered by other modules.
function Ballistics.Ignore(instance: Instance)
	table.insert(extraIgnore, instance)
end

local function taggedUp(part: Instance, tag: string, levels: number): Instance?
	local node: Instance? = part
	for _ = 1, levels do
		if not node or node == workspace then
			return nil
		end
		if CollectionService:HasTag(node, tag) then
			return node
		end
		node = node.Parent
	end
	return nil
end

function Ballistics.LampIdOf(part: BasePart): string?
	local tagged = taggedUp(part, "BreakableLamp", 4)
	if tagged then
		local id = tagged:GetAttribute("LampId")
		if id ~= nil then
			return tostring(id)
		end
	end
	return nil
end

function Ballistics.IsPenetrable(part: BasePart): boolean
	return taggedUp(part, "Penetrable", 3) ~= nil
end

local function penFor(weapon: string): Pen
	return ((Tuning.Penetration :: any)[weapon] :: Pen?) or NO_PEN
end

-- Where does the ray leave `part`? nil if it is thicker than maxThickness.
local function exitPoint(part: BasePart, entry: Vector3, direction: Vector3, maxThickness: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }
	local probe = maxThickness + 0.05
	local back = workspace:Raycast(entry + direction * probe, -direction * probe, params)
	return if back then back.Position else nil
end

local function combatantModels(): { Instance }
	local list: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for model in Combatants.All() do
		table.insert(list, model)
		seen[model] = true
	end
	for _, inst in CollectionService:GetTagged("Combatant") do
		if not seen[inst] then
			seen[inst] = true
			table.insert(list, inst)
		end
	end
	return list
end

type WorldStop = { Part: BasePart, Position: Vector3, Normal: Vector3, Distance: number }

-- World-only ray (no combatants). Returns where the bullet stops (nil = flew out of range) and the
-- walls it went through on the way.
-- How many window-glass "hits" one bullet counts as (Glass.HITS_TO_BREAK = 10): the sniper's heavy
-- round breaks a pane in 2 shots, the AK in 10 bullets.
local GLASS_HITS: { [string]: number } = { Sniper = 5 }

local function worldCast(
	origin: Vector3,
	direction: Vector3,
	range: number,
	pen: Pen,
	weapon: string?
): (WorldStop?, { Wall })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local filter = combatantModels()
	for _, inst in extraIgnore do
		table.insert(filter, inst)
	end
	local walls: { Wall } = {}
	local start = origin
	local travelled = 0
	for _ = 1, MAX_PASSES do
		if travelled >= range then
			return nil, walls
		end
		params.FilterDescendantsInstances = filter
		local result = workspace:Raycast(start, direction * (range - travelled), params)
		if not result then
			return nil, walls
		end
		local part = result.Instance :: BasePart
		local distance = travelled + (result.Position - start).Magnitude
		if not part.CanCollide and part.Transparency >= 0.95 then
			table.insert(filter, part)
			travelled, start = distance, result.Position
			continue
		end
		-- Broken window: its invisible barrier only blocks players, never bullets. (A part that
		-- collides can't be made unqueryable, so it has to be skipped here.)
		if Glass.IsBarrier(part) then
			table.insert(filter, part)
			travelled, start = distance, result.Position
			continue
		end
		if Glass.IsGlass(part) and Glass.Hit(part, GLASS_HITS[weapon or ""] or 1) then
			-- This hit shattered the pane: the bullet flies on through the empty frame.
			table.insert(filter, part)
			travelled, start = distance, result.Position
			continue
		end
		if Glass.IsGlass(part) and weapon == "Sniper" then
			-- The sniper round goes through intact window glass without losing damage (it still
			-- cracks the pane above): a body shot through the tinted window kills (owner 2026-10-16).
			table.insert(filter, part)
			travelled, start = distance, result.Position
			continue
		end
		if #walls < pen.MaxWalls and Ballistics.IsPenetrable(part) then
			local exit = exitPoint(part, result.Position, direction, pen.MaxThickness)
			if exit then
				table.insert(walls, { Entry = result.Position, Exit = exit, Distance = distance })
				table.insert(filter, part)
				travelled = distance + (exit - result.Position).Magnitude
				start = exit
				continue
			end
		end
		return { Part = part, Position = result.Position, Normal = result.Normal, Distance = distance }, walls
	end
	return nil, walls
end

-- Hitbox folders of live enemies of `shooter` (or just `only`).
local function enemyHitboxes(shooter: Model?, only: Model?): { Instance }
	local list: { Instance } = {}
	local team = Combatants.Team(shooter)
	for model in Combatants.All() do
		if only and model ~= only then
			continue
		end
		if model == shooter or not Combatants.IsAlive(model) then
			continue
		end
		if team ~= nil and Combatants.Team(model) == team then
			continue
		end
		local folder = Hitboxes.Folder(model)
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

local function hitboxCast(
	origin: Vector3,
	direction: Vector3,
	maxDistance: number,
	folders: { Instance }
): RaycastResult?
	if #folders == 0 or maxDistance <= 0 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = folders
	if Hitboxes.GroupReady() then
		params.CollisionGroup = Hitboxes.GROUP
	end
	return workspace:Raycast(origin, direction * maxDistance, params)
end

local function wallsBefore(walls: { Wall }, distance: number, pen: Pen): ({ Wall }, number)
	local before = {}
	local m = 1
	for _, w in walls do
		if w.Distance < distance then
			table.insert(before, w)
			m *= pen.DamageMultiplier
		end
	end
	return before, m
end

-- One bullet, current positions. Returns the hit (or nil) and all walls the bullet went through.
function Ballistics.Cast(
	shooter: Model?,
	origin: Vector3,
	direction: Vector3,
	weapon: string
): (Hit?, { Wall })
	local stats = Combatants.Stats(weapon)
	local pen = penFor(weapon)
	local stop, walls = worldCast(origin, direction, stats.Range, pen, weapon)
	local maxD = if stop then stop.Distance else stats.Range
	local hb = hitboxCast(origin, direction, maxD, enemyHitboxes(shooter, nil))
	if hb then
		local part = hb.Instance :: BasePart
		local distance = (hb.Position - origin).Magnitude
		local before, m = wallsBefore(walls, distance, pen)
		return {
			Part = part,
			Position = hb.Position,
			Normal = hb.Normal,
			Distance = distance,
			Victim = Combatants.FromPart(part),
			Zone = Hitboxes.Zone(part) or "Body",
			Lamp = nil,
			Multiplier = m,
			Walls = before,
		},
			walls
	end
	if stop then
		local before, m = wallsBefore(walls, stop.Distance, pen)
		return {
			Part = stop.Part,
			Position = stop.Position,
			Normal = stop.Normal,
			Distance = stop.Distance,
			Victim = nil,
			Zone = nil,
			Lamp = Ballistics.LampIdOf(stop.Part),
			Multiplier = m,
			Walls = before,
		},
			walls
	end
	return nil, walls
end

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else nil
end

-- Rewound offset for a combatant: where it was `rewind` seconds ago minus where it is now.
local function rewindOffset(model: Model, rewind: number): Vector3
	local state = Combatants.Get(model)
	local root = Combatants.Root(model)
	if not state or not root or rewind <= 0 then
		return Vector3.zero
	end
	local past = Combatants.PositionAt(state, os.clock() - rewind)
	if not past then
		return Vector3.zero
	end
	local offset = past - root.Position
	if offset.Magnitude > MAX_REWIND_STUDS then
		offset = offset.Unit * MAX_REWIND_STUDS
	end
	return offset
end

local function insideBox(cf: CFrame, size: Vector3, point: Vector3, tolerance: number): boolean
	local p = cf:PointToObjectSpace(point)
	local h = size / 2
	return math.abs(p.X) <= h.X + tolerance
		and math.abs(p.Y) <= h.Y + tolerance
		and math.abs(p.Z) <= h.Z + tolerance
end

-- Favor-the-shooter check of a client claim. Returns the accepted hit, or nil + reason.
function Ballistics.ValidateClaim(
	shooter: Model,
	origin: Vector3,
	direction: Vector3,
	weapon: string,
	claim: any,
	rewind: number
): (Hit?, string?, { Wall }?)
	if type(claim) ~= "table" then
		return nil, "no claim"
	end
	local target, partName, point = claim.Target, claim.Part, claim.Position
	if typeof(target) ~= "Instance" or not target:IsA("Model") or type(partName) ~= "string" then
		return nil, "bad claim"
	end
	if typeof(point) ~= "Vector3" or point.X ~= point.X or point.Y ~= point.Y or point.Z ~= point.Z then
		return nil, "bad point"
	end
	local victim = target :: Model
	if victim == shooter or not Combatants.Get(victim) or not Combatants.IsAlive(victim) then
		return nil, "not a live combatant"
	end
	local team = Combatants.Team(shooter)
	if team ~= nil and Combatants.Team(victim) == team then
		return nil, "teammate"
	end
	local folder = Hitboxes.Folder(victim)
	local box = folder and folder:FindFirstChild(partName)
	if not box or not box:IsA("BasePart") then
		return nil, "no such hitbox"
	end
	local stats = Combatants.Stats(weapon)
	local h = Tuning.Hitbox

	-- on the ray?
	local toPoint = point - origin
	local along = toPoint:Dot(direction)
	if along <= 0 or along > stats.Range then
		return nil, "out of range"
	end
	if (toPoint - direction * along).Magnitude > h.RayTolerance then
		return nil, "off ray"
	end
	-- facing: the shot must leave roughly where the body faces
	local root = Combatants.Root(shooter)
	local fd, fl = flat(direction), if root then flat(root.CFrame.LookVector) else nil
	if fd and fl and math.deg(math.acos(math.clamp(fd:Dot(fl), -1, 1))) > h.FacingToleranceDegrees then
		return nil, "facing"
	end
	-- inside the rewound (or current) hitbox?
	rewind = math.clamp(rewind, 0, Ballistics.MAX_REWIND_SECONDS)
	local offset = rewindOffset(victim, rewind)
	local inside = insideBox(box.CFrame + offset, box.Size, point, h.ClaimTolerance)
		or insideBox(box.CFrame, box.Size, point, h.ClaimTolerance)
	if not inside then
		return nil, "outside hitbox"
	end
	-- line of sight (wallbangs allowed through Penetrable parts)
	local pen = penFor(weapon)
	local dir = toPoint.Unit
	local stop, walls = worldCast(origin, dir, math.max(0, toPoint.Magnitude - 0.05), pen, weapon)
	if stop then
		return nil, "blocked"
	end
	local before, m = wallsBefore(walls, toPoint.Magnitude, pen)
	return {
		Part = box,
		Position = point,
		Normal = -dir,
		Distance = toPoint.Magnitude,
		Victim = victim,
		Zone = Hitboxes.Zone(box) or "Body",
		Lamp = nil,
		Multiplier = m,
		Walls = before,
	},
		nil,
		walls
end

-- Server re-cast with lag compensation (no / invalid claim).
function Ballistics.Resolve(
	shooter: Model,
	origin: Vector3,
	direction: Vector3,
	rewind: number,
	weapon: string
): (Hit?, { Wall })
	local direct, walls = Ballistics.Cast(shooter, origin, direction, weapon)
	if (direct and direct.Victim) or rewind <= 0 then
		return direct, walls
	end
	rewind = math.min(rewind, Ballistics.MAX_REWIND_SECONDS)
	local pen = penFor(weapon)
	local blockDistance = if direct then direct.Distance else Combatants.Stats(weapon).Range
	local best: Hit? = nil
	for _, folder in enemyHitboxes(shooter, nil) do
		local model = folder.Parent :: Model
		local offset = rewindOffset(model, rewind)
		if offset.Magnitude < 0.25 then
			continue -- didn't move: the direct ray already covered it
		end
		-- moving the ray by -offset == moving the target back to where the client saw it
		local r = hitboxCast(origin - offset, direction, blockDistance + 0.5, { folder })
		if r then
			local distance = (r.Position - (origin - offset)).Magnitude
			if distance <= blockDistance + 0.5 and (not best or distance < best.Distance) then
				local before, m = wallsBefore(walls, distance, pen)
				local part = r.Instance :: BasePart
				best = {
					Part = part,
					Position = r.Position + offset,
					Normal = r.Normal,
					Distance = distance,
					Victim = model,
					Zone = Hitboxes.Zone(part) or "Body",
					Lamp = nil,
					Multiplier = m,
					Walls = before,
				}
			end
		end
	end
	return best or direct, walls
end

-- Random direction inside a cone of `degrees` (half-angle), centre-weighted.
function Ballistics.Cone(direction: Vector3, degrees: number, rng: Random): Vector3
	if degrees <= 0 then
		return direction
	end
	local r = math.rad(degrees) * rng:NextNumber()
	local theta = rng:NextNumber() * math.pi * 2
	local cf = CFrame.lookAt(Vector3.zero, direction)
	return (cf * CFrame.Angles(math.sin(theta) * r, math.cos(theta) * r, 0)).LookVector
end

function Ballistics.Falloff(weapon: string, distance: number): number
	local stats = Combatants.Stats(weapon)
	if distance <= stats.FalloffStart then
		return 1
	end
	local t =
		math.clamp((distance - stats.FalloffStart) / math.max(stats.Range - stats.FalloffStart, 1), 0, 1)
	return 1 - 0.3 * t
end

-- Line of sight for explosions: true if nothing solid (penetrable walls included) is between.
function Ballistics.Clear(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = table.clone(ignore)
	for _, inst in extraIgnore do
		table.insert(filter, inst)
	end
	for _, m in combatantModels() do
		table.insert(filter, m)
	end
	params.IgnoreWater = true
	local start = from
	for _ = 1, 6 do
		params.FilterDescendantsInstances = filter
		local delta = to - start
		if delta.Magnitude < 0.05 then
			return true
		end
		local r = workspace:Raycast(start, delta, params)
		if not r then
			return true
		end
		local part = r.Instance :: BasePart
		if not part.CanCollide and part.Transparency >= 0.95 then
			table.insert(filter, part)
			start = r.Position
		else
			return false
		end
	end
	return false
end

return Ballistics

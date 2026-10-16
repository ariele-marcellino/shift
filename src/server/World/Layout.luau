--!strict
-- "Level 0 - Office Annex" v4 (sniper sides), half-map mirrored across x = 0 (Blue x < 0).
--
-- Top-down, Blue half (+X towards the centre / enemy, +Z = "north"). Map size unchanged (x +-177, z +-81).
--
--  z 81                      .cage.
--  z 76                  +--+---[ ]-----------------------------+###|  NORTH  Maintenance Gallery: one long
--                        |D |PERCH   I1      ~~water~~   I4    #B#|         open industrial hall, ~110-stud
--  z 46 +----------------+i |  >     pump  panel  gen          #k#|         sniper line per half, cover
--       | SECURITY (flank)|s+---------------------+-T---+-B-----+-J-+         islands, perch at the base end
--  z 20 +--win--door------+t|                     |T|   | Break  |J|
--       |                 v r ===== Long Hall ===[D]=== ATRIUM [E]  MID   close-quarters tactical lane
--       |  CORE ROOM   (P)  i                  |Rec|  mezzanine  |
--       |  booth          = b                  |ords|           |
--  z-20 +-----------------+ u +----------------+-+-+------------+J+
--   z-26   +-----------+  t |  >      I1   drywall  I3     I4  #S#|  SOUTH  Open Office: long open floor,
--          | LOCKERS   =    |PERCH  panel     I2               #r#|         ~110-stud sniper line per half
--  z-50 +--  -------+--+    +-------[d]-[ nook ]----------------+###|
--       |  SPAWN    =ps|         |                                    d = service door (x -86)
--  z-76 +-----------+  +=========+  service corridor (z -81..-76)     ps = spawn passage
--     -176  -156  -144 -126 -114          -58 -40 -36             0
--
-- Each side lane ends at a centre block (#) with a zig-zag 10-stud band beside the junction mouth:
-- one smoke crosses it, and no ray runs perch-to-perch. Lanes end in the distribution corridor (a
-- bend), so they never see into a spawn or Core room.
-- Core room: exactly 3 entrances - MAIN door (east, z = -12), FLANK door (north, via Security),
-- VENT (east, z = +12, jump in).
-- Spawn area: 3 exits on different routes, each behind a bend (no ray leaves the spawn room):
--   A: NORTH door -> lockers -> distribution corridor door (x -126, z -40) -> centre / office west;
--   B: EAST door (z -71) -> spawn passage -> service corridor (z -81..-76) -> Open Office SOUTH door
--      (x -86, beside the perch stairs);
--   C: NORTH-WEST door (x -166) -> armory (x -176..-156, z -50..-20) -> spawn elevator car at its
--      north end -> ride -> arrive in the atrium elevator (your half of the shaft) and walk out of the
--      shaft door on your side (ElevatorService). Each team's shaft door has a barrier.
-- The spawn area (spawn room, lockers, armory, passage, service corridor) is team-only: the
-- outer doors and your atrium elevator door has a barrier that blocks the enemy team (TeamCollision; bullets pass).
-- Approx. walk Blue spawn -> Red Core at 16 studs/s: South ~26 s (either spawn exit), Mid ~25 s
-- (+ blast door when sealed), North ~33 s (incl. wading, ends at the enemy flank). Spawn -> own
-- Core ~7 s (north exit only; the service corridor never passes the Core).
-- Floor top is y = 0, office ceiling underside y = 12, maintenance ceiling underside y = 11.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local Style = require(script.Parent.Style)
local Pieces = require(script.Parent.Pieces)
local Lamps = require(script.Parent.Lamps)
local Hinges = require(script.Parent.Hinges)
local NavGraph = require(script.Parent.NavGraph)
local Regions = require(script.Parent.Regions)
local Detail = require(script.Parent.Detail)
local Decor = require(script.Parent.Decor)
local TeamCollision = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeamCollision"))

type Ctx = Pieces.Ctx
type Surface = Style.Surface
type LightPreset = Style.LightPreset

export type Room = { Name: string, Center: Vector3, Size: Vector3, Dark: boolean }
export type TeamRooms = { Spawn: Room, Core: Room }

export type Result = {
	Root: Folder,
	Spawns: { [string]: { CFrame } },
	Pedestals: { [string]: CFrame },
	SpawnNode: { [string]: string },
	CoreNode: { [string]: string },
	TeamRooms: { [string]: TeamRooms },
	HallEnds: { [string]: Vector3 },
	SniperSpots: { [string]: { CFrame } },
	-- Spawn elevator (exit C) per team: Pad/PadSize (spawn car zone), Arrivals (CFrames in your half
	-- of the atrium shaft), Leaves ({Part, Closed, Open}), Shaft/ShaftSize (your half's interior).
	Elevators: { [string]: any },
	Bounds: { Min: Vector3, Max: Vector3 },
	Rooms: { Room },
}

local Layout = {}

-- Wing partitions (x -144, north + south wing) that hide the flag room's flank doors from the
-- corridor. Off for now (owner, 2026-10-16); true brings them back.
Layout.WING_PARTITIONS = false

-- TEST decor (plants, posters, sprinklers, drums, ...; see World/Decor.luau). Set false to remove.
Layout.DECOR_TEST = true

local S = Style.Surf
local L = Style.Light
local H = Style.Dims.CeilingHeight
local MH = Style.Dims.MaintCeilingHeight
local SPAWN_DOOR_H = 10 -- spawn exits: 9 wide x 10 tall (other doors are 6 x 8)
local LAMP_Y = 9.3 -- doorway lamps sit just above the 8-stud door lintel
local DRY = { Thickness = 0.6, Penetrable = true } -- penetrable drywall
local WINDOW_SILL, WINDOW_TOP = 3.6, 7.6 -- chest-high sill: shoot over it, crouch behind it
-- Tinted windows in the side-lane centre walls (x = 0), office side (z < 0); the gallery mirrors.
-- One wide window, centred on each wall (z -61 / 61), about 35% of the wall's area:
-- office wall 30 x 12 -> 21 x 6 window; gallery wall 30 x 11 -> 21 x 5.5 window.
local CENTRE_WINDOW_Z, CENTRE_WINDOW_W, CENTRE_WINDOW_SILL = -61, 21, 3.5
local CENTRE_WINDOW_TOP = { Office = 9.5, Gallery = 9 }

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function withColor(preset: LightPreset, color: Color3): LightPreset
	local copy = table.clone(preset)
	copy.Color = color
	return copy
end

-- Shared helpers -------------------------------------------------------------------------------

type LampOpts = {
	Breakable: boolean,
	Power: string?,
	Emitters: { ParticleEmitter }?,
	Radius: number?, -- light coverage for IsDark (lit / dim areas)
	Zone: string?, -- LightDirector zone (suffix; prefixed with the half's id)
}

local function registerLamp(ctx: Ctx, name: string, part: BasePart, light: Light?, opts: LampOpts): string
	local id = Pieces.Id(ctx, name)
	Lamps.Register({
		Id = id,
		Part = part,
		Lights = if light then { light } else {},
		Emitters = opts.Emitters,
		Breakable = opts.Breakable,
		PowerGroup = opts.Power,
		Zone = if opts.Zone then Pieces.Id(ctx, opts.Zone) else nil,
	})
	if opts.Radius then
		Regions.AddZoneLight(part.Position, opts.Radius, id)
	end
	return id
end

-- Doorway lamp + dust cone. `door` is the door centre on the wall line (half coords, y ignored);
-- `into` points from the wall into the dark room the lamp hangs in.
local function doorLamp(
	ctx: Ctx,
	name: string,
	door: Vector3,
	into: Vector3,
	kind: "Exit" | "Cage",
	zone: string
)
	local offset = if kind == "Exit" then 0.75 else 1.25
	local pos = v(door.X, LAMP_Y, door.Z) + into * offset
	local part, light = Pieces.DoorLamp(ctx, name, pos, into, kind)
	Pieces.RegisterDoorLamp(Pieces.Id(ctx, name), Pieces.P(ctx, v(door.X, 4, door.Z)))
	local dust = Pieces.Dust(ctx, name .. "Dust", v(door.X, 4.5, door.Z) + into * 3.5, v(7, 9, 7))
	registerLamp(ctx, name, part, light, { Breakable = true, Emitters = dust, Zone = zone })
end

local function fill(ctx: Ctx, name: string, pos: Vector3, range: number?, base: LightPreset?)
	local preset = base or L.Fill
	if range then
		preset = table.clone(preset)
		preset.Range = range
	end
	Pieces.AttachLight(ctx, name, "PointLight", pos, preset)
end

local function nid(ctx: Ctx, name: string): string
	if string.sub(name, 1, 2) == "C." then
		return name
	end
	return Pieces.Id(ctx, name)
end

local function dark(ctx: Ctx, x1: number, z1: number, x2: number, z2: number)
	Regions.AddDark(Pieces.P(ctx, v(x1, 0, z1)), Pieces.P(ctx, v(x2, H, z2)))
end

local function prop(ctx: Ctx, name: string, center: Vector3, size: Vector3, surf: Surface): Part
	return Pieces.BoxAt(ctx, name, center, size, surf, ctx.Folders.Props)
end

-- Chest-high cover (3.5 tall): crouch behind it, or stand and only your head shows (head glitch).
local function cover(ctx: Ctx, x: number, z: number, sx: number, sz: number, surf: Surface?)
	prop(ctx, "Cover", v(x, 1.75, z), v(sx, 3.5, sz), surf or S.Crate)
end

-- Boost spot: a 3-stud crate you can jump onto, next to a 6-stud stack you can climb from it.
local function boost(ctx: Ctx, x: number, z: number, alongX: boolean)
	local step = if alongX then v(3, 0, 0) else v(0, 0, 3)
	prop(ctx, "BoostLow", v(x, 1.5, z), v(3, 3, 3), S.Crate)
	prop(ctx, "BoostHigh", v(x, 3, z) - step, v(3, 6, 3), S.Crate)
end

local function pillar(ctx: Ctx, x: number, z: number)
	prop(ctx, "Pillar", v(x, H / 2, z), v(2, H, 2), S.Pillar)
end

-- Structure -----------------------------------------------------------------------------------

local function buildStructure(ctx: Ctx, result: Result)
	local team = ctx.Team :: string
	local function room(
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		surf: Surface,
		isDark: boolean
	): Room
		Pieces.Floor(ctx, x1, z1, x2, z2, surf)
		local a, b = Pieces.P(ctx, v(x1, 0, z1)), Pieces.P(ctx, v(x2, 0, z2))
		local r: Room = {
			Name = name,
			Center = (a + b) / 2 + v(0, H / 2, 0),
			Size = Vector3.new(math.abs(b.X - a.X), H, math.abs(b.Z - a.Z)),
			Dark = isDark,
		}
		table.insert(result.Rooms, r)
		return r
	end
	-- Spawn directly behind (west of) the flag room; wings north and south of the flag room.
	local spawnRoom = room("Spawn", -186, -32, -162, 32, S.BaseFloor, false)
	room("South Wing", -162, -46, -126, -20, S.OfficeCarpet, false)
	local coreRoom = room("Core Room", -162, -20, -126, 20, S.BaseFloor, false)
	room("North Wing", -162, 20, -126, 46, S.OfficeCarpet, false)
	room("Distribution", -126, -66, -114, 62, S.OfficeCarpet, false)
	room("Open Office", -114, -76, 0, -36, S.CubicleCarpet, false)
	room("Office Nook", -66, -81, -56, -76, S.CubicleCarpet, false)
	room("Long Hall", -114, -6, -36, 6, S.OfficeCarpet, false)
	room("Atrium", -36, -14, 0, 14, S.OfficeCarpet, false)
	room("Records", -58, -36, -40, -6, S.OfficeCarpet, true)
	room("Junction", -6, -36, 0, -14, S.OfficeCarpet, false)
	room("Junction", -6, 14, 0, 36, S.OfficeCarpet, false)
	room("Tunnel", -46, 6, -40, 36, S.MaintFloor, true)
	room("Break Room", -30, 14, -6, 36, S.CubicleCarpet, false)
	room("Gallery", -114, 36, -80, 76, S.MaintFloor, false)
	Pieces.Floor(ctx, -80, 36, -60, 76, S.WetFloor) -- flooded crossing (part of the gallery)
	Pieces.Floor(ctx, -60, 36, 0, 76, S.MaintFloor)
	room("Tool Cage", -40, 76, -30, 81, S.MaintFloor, false)
	result.TeamRooms[team] = { Spawn = spawnRoom, Core = coreRoom }

	-- Ceilings
	Pieces.Ceiling(ctx, -187, -81, -126, 81, H, S.BaseCeiling)
	Pieces.Ceiling(ctx, -126, -81, 0, 36, H, S.OfficeCeiling)
	Pieces.Ceiling(ctx, -126, 36, -114, 81, H, S.OfficeCeiling)
	Pieces.Ceiling(ctx, -114, 36, 0, 81, MH, S.MaintCeiling)

	local OW, MW, DW = S.OfficeWall, S.MaintWall, S.Drywall

	-- Spawn room (behind the flag room, x -186..-162) with three exits:
	--   NORTH door (x -162, z 26.5) -> north wing -> distribution corridor door (z 38) / flag-room flank
	--   SOUTH door (x -162, z -26.5) -> south wing -> distribution corridor door (z -38) / flag-room flank
	--   ELEVATOR car (west alcove) -> atrium elevator at mid-map (ElevatorService)
	-- Each wing has a partition (x -144) so nothing in the corridor sees the spawn door, and the spawn
	-- doors can't see the pedestal. Both spawn doors carry the team barrier.
	Pieces.WallX(ctx, -186, -32, 32, nil, OW)
	Pieces.WallZ(ctx, 32, -186, -162, nil, OW)
	Pieces.WallZ(ctx, -32, -186, -162, nil, OW)
	Pieces.WallX(
		ctx,
		-162,
		-46,
		46,
		{ { c = -26.5, w = 9, h = SPAWN_DOOR_H }, { c = 26.5, w = 9, h = SPAWN_DOOR_H } },
		OW
	)
	-- Elevator car: alcove in the west wall (x -186..-180, z -4..4), open front under a lintel.
	Pieces.WallZ(ctx, -4, -186, -180, nil, S.Elevator)
	Pieces.WallZ(ctx, 4, -186, -180, nil, S.Elevator)
	Pieces.WallX(ctx, -180, -4, 4, { { c = 0, w = 7 } }, S.Elevator)

	-- Flag room: 3 entrances - MAIN door (east, z -12) and a FLANK door from each wing (x -140).
	-- The wing walls are plain drywall now (no window onto the pedestal).
	Pieces.WallZ(ctx, -20, -162, -126, { { c = -140, w = 6 } }, DW, DRY)
	Pieces.WallZ(ctx, 20, -162, -126, { { c = -140, w = 6 } }, DW, DRY)
	-- Wings: outer walls + partitions (gap at the outer end).
	Pieces.WallZ(ctx, 46, -162, -126, nil, OW)
	Pieces.WallZ(ctx, -46, -162, -126, nil, OW)
	if Layout.WING_PARTITIONS then
		Pieces.WallX(ctx, -144, 20, 38, nil, OW)
		Pieces.WallX(ctx, -144, -38, -20, nil, OW)
	end

	-- Distribution corridor (spawn corridor / defender rotation), trimmed to the doors it serves.
	Pieces.WallX(ctx, -126, -66, 62, {
		{ c = -38, w = 6 }, -- south wing
		{ c = -12, w = 6 }, -- flag room MAIN door
		{ c = 38, w = 6 }, -- north wing
	}, OW)
	Pieces.WallZ(ctx, 62, -126, -114, nil, OW)
	Pieces.WallZ(ctx, -66, -126, -114, nil, OW)
	Pieces.WallX(
		ctx,
		-114,
		-76,
		76,
		{ { c = -56, w = 16, h = H }, { c = 0, w = 12, h = H }, { c = 56, w = 6 } },
		OW
	)

	-- Open Office (south sniper lane): a nook in the south wall, drywall onto Records (wallbang)
	Pieces.WallZ(ctx, -76, -114, 0, { { c = -61, w = 10 } }, OW)
	Pieces.WallZ(ctx, -81, -66, -56, nil, OW)
	Pieces.WallX(ctx, -66, -81, -76, nil, OW)
	Pieces.WallX(ctx, -56, -81, -76, nil, OW)
	Pieces.WallZ(ctx, -36, -114, -58, nil, OW)
	Pieces.WallZ(ctx, -36, -58, -40, { { c = -49, w = 6 } }, DW, DRY)
	Pieces.WallZ(ctx, -36, -40, 0, { { c = -3, w = 6, h = H } }, OW)

	-- Long Hall (ends at the atrium), Records (drywall towards the hall; its locked wooden door at
	-- x -43 was walled up, owner 2026-10-16)
	Pieces.WallZ(ctx, -6, -114, -58, nil, OW)
	Pieces.WallZ(ctx, -6, -58, -40, { { c = -49, w = 6 } }, DW, DRY)
	Pieces.WallZ(ctx, -6, -40, -36, nil, OW)
	Pieces.WallZ(ctx, 6, -114, -36, { { c = -43, w = 6 } }, OW)
	Pieces.WallX(ctx, -58, -36, -6, nil, OW)
	Pieces.WallX(ctx, -40, -36, -6, nil, OW)

	-- Atrium: window into the break room, open to both junction corridors
	Pieces.WallX(ctx, -36, -14, -6, nil, OW)
	Pieces.WallX(ctx, -36, 6, 14, nil, OW)
	Pieces.WallZ(ctx, -14, -36, 0, { { c = -3, w = 6, h = H } }, OW)
	Pieces.WallZ(ctx, 14, -36, 0, {
		{ c = -21, w = 6 },
		{ c = -27, w = 5, s = WINDOW_SILL, h = WINDOW_TOP },
		{ c = -3, w = 6, h = H },
	}, OW)

	-- Junctions, tunnel, break room (drywall + wooden door towards the north junction)
	Pieces.WallX(ctx, -6, -36, -14, nil, OW)
	Pieces.WallX(ctx, -6, 14, 36, { { c = 25, w = 3.6, h = 7 } }, DW, DRY)
	Pieces.WoodDoor(ctx, v(-6, 3.5, 25), v(0.8, 7, 3.6))
	Pieces.WallX(ctx, -46, 6, 36, nil, MW)
	Pieces.WallX(ctx, -40, 6, 36, nil, MW)
	Pieces.WallX(ctx, -30, 14, 36, nil, OW)

	-- Maintenance Gallery (north sniper lane): one long hall, a tool cage alcove in the north wall
	Pieces.WallZ(ctx, 36, -114, 0, { { c = -43, w = 6 }, { c = -21, w = 6 }, { c = -3, w = 6 } }, MW)
	Pieces.WallZ(ctx, 76, -114, 0, { { c = -35, w = 10 } }, MW)
	Pieces.WallZ(ctx, 81, -40, -30, nil, MW)
	Pieces.WallX(ctx, -40, 76, 81, nil, MW)
	Pieces.WallX(ctx, -30, 76, 81, nil, MW)
end

-- Bases ------------------------------------------------------------------------------------------

local function buildBase(ctx: Ctx, result: Result)
	local team = ctx.Team :: string
	local teamColor = (Tuning.Teams :: any)[team].Color :: Color3
	local soft = teamColor:Lerp(Color3.new(1, 1, 1), 0.55)

	-- Core pedestal under a shadow-casting team-tinted spot
	result.Pedestals[team] = Pieces.Pedestal(ctx, v(-148, 0, 0), teamColor)
	Pieces.BoxAt(ctx, "PedestalFixture", v(-148, 11.85, 0), v(2.4, 0.3, 2.4), S.Housing, ctx.Folders.Lights)
	local spotPart = Pieces.BoxAt(ctx, "PedestalLamp", v(-148, 11.65, 0), v(1.8, 0.1, 1.8), {
		Color = soft,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	}, ctx.Folders.Lights)
	Pieces.NewLight("SpotLight", spotPart, withColor(L.PedestalSpot, soft))

	-- Team floods (unbreakable, never touched by the LightDirector) + neon strips
	for _, p in { v(-155, 11.5, 14), v(-133, 11.5, -14), v(-133, 11.5, 14) } do
		Pieces.Emergency(ctx, "TeamFlood", p, teamColor, withColor(L.TeamFlood, teamColor))
	end
	local strip: Surface =
		{ Color = teamColor, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }
	Pieces.Block(ctx, "TeamStrip", v(-161, 10.3, -19.5), v(-127, 10.6, -19.3), strip, ctx.Folders.Props)
	Pieces.Block(ctx, "TeamStrip", v(-161.5, 10.3, -19), v(-161.3, 10.6, 19), strip, ctx.Folders.Props)
	Pieces.Block(ctx, "TeamStrip", v(-125.5, 8.2, -15), v(-125.3, 8.5, -9), strip, ctx.Folders.Props)
	Regions.AddZoneLight(Pieces.P(ctx, v(-144, 0, 0)), 30, nil)

	-- Defender booth: raised platform in the south-west corner (stairs + railing), overlooking the
	-- main door and the pedestal. Its lamp is the one breakable base light: attackers shoot it out
	-- to darken the booth (the other floods + pedestal spot keep the room readable).
	prop(ctx, "Booth", v(-156, 2, -15), v(10, 4, 8), S.Mezzanine)
	for i, h in { 3, 2, 1 } do
		prop(ctx, "BoothStair", v(-150 + (i - 1) * 2, h / 2, -17), v(2, h, 4), S.Mezzanine)
	end
	prop(ctx, "BoothRail", v(-156, 5.25, -10.8), v(10, 2.5, 0.4), S.Railing)
	prop(ctx, "BoothRail", v(-150.8, 5.25, -13), v(0.4, 2.5, 4), S.Railing)
	local boothLamp, boothLight =
		Pieces.Emergency(ctx, "BoothLamp", v(-156, 11.5, -15), teamColor, withColor(L.TeamFlood, teamColor))
	registerLamp(ctx, "Core.Booth", boothLamp, boothLight, { Breakable = true })

	-- Core room cover: crates flanking the pedestal, half wall facing the main door, pillars beside
	-- the main door and the vent (jiggle-peek corners for both sides).
	cover(ctx, -140, -7, 3, 3)
	cover(ctx, -140, 7, 3, 3)
	cover(ctx, -132, 0, 1, 8, S.BaseWall)
	pillar(ctx, -130, -16)
	pillar(ctx, -130, 16)

	-- Security office (the flank, dim): window over the Core room, desks to hold it
	for i, z in { 27, 39 } do
		local lit = i == 1
		local tube, light =
			Pieces.Tube(ctx, `SecT{i}`, v(if i == 1 then -152 else -135, H, z), "X", lit, L.DimTube)
		if lit then
			registerLamp(ctx, "Security.T", tube, light, { Breakable = true, Radius = 18, Zone = "Security" })
		end
	end
	cover(ctx, -153, 23, 7, 2, S.Desk)
	cover(ctx, -134, 26, 4, 4, S.Desk)
	prop(ctx, "Filing", v(-159.5, 3, 40), v(3, 6, 6), S.Cabinet)
	boost(ctx, -150, 42, true)
	Regions.AddZoneLight(Pieces.P(ctx, v(-144, 0, 33)), 10, nil) -- desk lamp glow keeps it dim, not dark
	fill(ctx, "SecurityFill", v(-150, 9, 33), 20)

	-- South wing (mirror of the north wing): bench, locker row, crate; plain tubes.
	cover(ctx, -153, -23, 7, 2, S.Desk)
	cover(ctx, -134, -26, 4, 4, S.Crate)
	prop(ctx, "Lockers", v(-153, 3.5, -45.25), v(14, 7, 1.5), S.Locker)
	boost(ctx, -150, -42, true) -- mirror of the north wing's boost: jump spot over the partition
	for i, x in { -152, -135 } do
		Pieces.Tube(ctx, `SouthWingT{i}`, v(x, H, -33), "X", true, L.DimTube)
	end
	Regions.AddZoneLight(Pieces.P(ctx, v(-144, 0, -33)), 18, nil)

	-- Spawn room: lit by plain ceiling tubes (never in a LightDirector zone, never break) plus two
	-- team-coloured emergency lights.
	for i, z in { -24, -12, 0, 12, 24 } do
		Pieces.Tube(ctx, `SpawnTube{i}`, v(-171, H, z), "X", true, L.HallTube)
	end
	Pieces.Emergency(ctx, "SpawnLight", v(-164, 11.5, -6), teamColor, withColor(L.Emergency, soft))
	Pieces.Emergency(ctx, "SpawnLight", v(-164, 11.5, 6), teamColor, withColor(L.Emergency, soft))
	Regions.AddZoneLight(Pieces.P(ctx, v(-174, 0, 0)), 34, nil)
	local spawns = {}
	for _, z in { -8, 0, 8 } do
		Pieces.BoxAt(ctx, "SpawnPad", v(-172, 0.05, z), v(4, 0.1, 4), {
			Color = teamColor,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.5,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}, ctx.Folders.Markers)
		table.insert(spawns, CFrame.lookAt(Pieces.P(ctx, v(-172, 0, z)), Pieces.P(ctx, v(-162, 0, z))))
	end
	result.Spawns[team] = spawns

	-- Global "most time played" board on the spawn's north wall (drawn by LeaderboardController).
	local board =
		Pieces.BoxAt(ctx, "TimeLeaderboard", v(-174, 7, 31.4), v(12, 6, 0.15), S.Elevator, ctx.Folders.Props)
	board.CanQuery = false
	board:AddTag("TimeLeaderboard")

	-- Magazine bags (owner, 2026-10-16): an equipment crate against the south wall with a duffel of
	-- AK magazines and one of sniper magazines on it. Hold E (tap on mobile) at a bag to refill the
	-- spare magazines of that weapon (CombatService:Resupply).
	prop(ctx, "AmmoCrate", v(-176, 1.1, -30.3), v(7, 2.2, 2.4), S.Crate)
	local canvas: Surface = { Color = Color3.fromRGB(70, 74, 52), Material = Enum.Material.Fabric }
	local strap: Surface = { Color = Color3.fromRGB(32, 32, 30), Material = Enum.Material.Fabric }
	for _, bag in
		{
			{ X = -178, Weapon = "AK", Label = "AK MAGAZINES" },
			{ X = -174, Weapon = "Sniper", Label = "SNIPER MAGAZINES" },
		}
	do
		local x = bag.X
		local body = prop(ctx, "AmmoBag", v(x, 2.75, -30.3), v(2.6, 1.1, 1.3), canvas)
		body.CanQuery = false
		prop(ctx, "AmmoBagStrap", v(x - 0.7, 2.76, -30.3), v(0.18, 1.14, 1.34), strap).CanQuery = false
		prop(ctx, "AmmoBagStrap", v(x + 0.7, 2.76, -30.3), v(0.18, 1.14, 1.34), strap).CanQuery = false
		prop(ctx, "AmmoBagZip", v(x, 3.31, -30.3), v(2.2, 0.04, 0.12), strap).CanQuery = false
		-- magazines sticking out of the open end
		if bag.Weapon == "AK" then
			local mag: Surface =
				{ Color = Color3.fromRGB(140, 60, 30), Material = Enum.Material.SmoothPlastic }
			for i, dx in { -0.45, 0, 0.45 } do
				local m = prop(ctx, "AmmoBagMag", v(x + dx, 3.55, -30.15), v(0.22, 0.7, 0.45), mag)
				m.CFrame = m.CFrame * CFrame.Angles(math.rad(12 + i * 4), 0, math.rad(dx * 14))
				m.CanQuery = false
			end
		else
			local mag: Surface = { Color = Color3.fromRGB(30, 30, 32), Material = Enum.Material.Metal }
			for _, dx in { -0.35, 0.05, 0.45 } do
				prop(ctx, "AmmoBagMag", v(x + dx, 3.45, -30.2), v(0.24, 0.45, 0.6), mag).CanQuery = false
			end
		end
		body:SetAttribute("Weapon", bag.Weapon)
		body:AddTag("AmmoBag")
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take magazines"
		prompt.ObjectText = bag.Label
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = body
	end

	-- Spawn elevator car (west alcove): floor plate + cab light; the pad is the car interior.
	Pieces.BoxAt(ctx, "ElevatorCarFloor", v(-183, 0.04, 0), v(5.6, 0.08, 7.6), S.Mezzanine, ctx.Folders.Props)
	Pieces.Tube(ctx, "ElevatorCarLight", v(-183, H, 0), "Z", true, L.HallTube)
	result.Elevators[team] = {
		Pad = CFrame.new(Pieces.P(ctx, v(-183, 4, 0))),
		PadSize = Vector3.new(5.4, 8, 7.4),
	} :: any

	-- Team-only barriers on the spawn area's three outer doors (enemies can't get in; bullets pass).
	local barrierSurf: Surface = {
		Color = teamColor,
		Material = Enum.Material.ForceField,
		Transparency = 0.15,
		CanCollide = true,
		CanQuery = false,
		CastShadow = false,
	}
	local frameSurf: Surface = {
		Color = teamColor,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}
	-- Glowing team-coloured frame on both wall faces around the doorway: marks a restricted exit.
	local function barrierFrame(a: Vector3, b: Vector3)
		local alongZ = (b.X - a.X) < (b.Z - a.Z) -- wall runs along Z (door in an x = const wall)
		local line = if alongZ then (a.X + b.X) / 2 else (a.Z + b.Z) / 2
		local lo = if alongZ then a.Z else a.X
		local hi = if alongZ then b.Z else b.X
		local top = b.Y
		local W, D = 0.28, 0.05
		for _, side in { -1, 1 } do
			local off = line + side * (0.5 + 0.03 + D / 2)
			local function frameStrip(u0: number, u1: number, y0: number, y1: number)
				if alongZ then
					Pieces.Block(
						ctx,
						"BarrierFrame",
						v(off - D / 2, y0, u0),
						v(off + D / 2, y1, u1),
						frameSurf,
						ctx.Folders.Markers
					)
				else
					Pieces.Block(
						ctx,
						"BarrierFrame",
						v(u0, y0, off - D / 2),
						v(u1, y1, off + D / 2),
						frameSurf,
						ctx.Folders.Markers
					)
				end
			end
			frameStrip(lo - W - 0.05, lo - 0.05, 0.02, top + 0.05) -- left jamb
			frameStrip(hi + 0.05, hi + W + 0.05, 0.02, top + 0.05) -- right jamb
			frameStrip(lo - W - 0.05, hi + W + 0.05, top + 0.05, top + 0.05 + W) -- header
		end
	end
	local function barrier(a: Vector3, b: Vector3)
		local part = Pieces.Block(ctx, "SpawnBarrier", a, b, barrierSurf, ctx.Folders.Markers)
		part.CanTouch = false
		part:SetAttribute("Team", team)
		part:AddTag("SpawnBarrier")
		TeamCollision.ApplyBarrier(part, team)
		barrierFrame(a, b)
	end
	local DH = Style.Dims.DoorHeight
	barrier(v(-162.2, 0, 22.01), v(-161.8, SPAWN_DOOR_H, 30.99)) -- spawn -> north wing
	barrier(v(-162.2, 0, -30.99), v(-161.8, SPAWN_DOOR_H, -22.01)) -- spawn -> south wing
	-- C: your side of the atrium elevator shaft (inside, just behind the sliding doors; no frame).
	local elevBarrier = Pieces.Block(
		ctx,
		"SpawnBarrier",
		v(-3.98, 0, -1.99),
		v(-3.78, DH, 1.99),
		barrierSurf,
		ctx.Folders.Markers
	)
	elevBarrier.CanTouch = false
	elevBarrier:SetAttribute("Team", team)
	elevBarrier:AddTag("SpawnBarrier")
	TeamCollision.ApplyBarrier(elevBarrier, team)

	-- Spawn-corridor emergency lights outside each base door (unbreakable)
	-- (Part of the corridor's light zone, so they dim / go dark / flicker with it.)
	for _, z in { -38, -12, 38 } do
		local part, light =
			Pieces.Emergency(ctx, `DoorEmergency{z}`, v(-124.8, 9.6, z), teamColor, L.Emergency)
		registerLamp(ctx, `Dist.E{z}`, part, light, { Breakable = false, Zone = "Dist" })
		Regions.AddZoneLight(Pieces.P(ctx, v(-120, 0, z)), 12, nil)
	end
end

-- Long Hall + atrium ---------------------------------------------------------------------------

local function buildHall(ctx: Ctx, result: Result)
	local team = ctx.Team :: string
	result.HallEnds[team] = Pieces.P(ctx, v(-112, 0, 0))

	-- Weak tubes every 16 studs (was 12: fewer lights for performance, and a darker hall); the inner
	-- ones share the "HallCenter" power group (shift).
	local breakable = { [-92] = true, [-60] = true, [-44] = true }
	local flicker = { [-108] = true, [-76] = true, [-44] = true }
	for k = 0, 4 do
		local x = -108 + 16 * k
		local shadow = x == -60
		local tube, light = Pieces.Tube(
			ctx,
			`HallT{k}`,
			v(x, H, 0),
			"Z",
			true,
			if shadow then L.HallTubeShadow else L.HallTube
		)
		if light and flicker[x] then
			Pieces.MarkFlicker(light)
		end
		local emitters = if shadow then Pieces.Dust(ctx, `HallT{k}Dust`, v(x, 5.5, 0), v(8, 10, 10)) else nil
		registerLamp(ctx, `Hall.T{k}`, tube, light, {
			Breakable = breakable[x] == true,
			Power = if x >= -48 then "HallCenter" else nil,
			Emitters = emitters,
			Radius = 12,
			Zone = "Hall",
		})
	end

	-- Hall cover: pillars to peek from, head-glitch crates around the blast door, a boost spot
	pillar(ctx, -104, -4)
	pillar(ctx, -58, 4)
	boost(ctx, -97, 3.5, true)
	cover(ctx, -86, 3.5, 3, 3)
	cover(ctx, -74, -3.5, 4, 3)
	cover(ctx, -52, -3.5, 3, 3)

	-- Hall security door hinge (x = -80): blast door that drops from the ceiling.
	local model = Instance.new("Model")
	model.Name = Pieces.Id(ctx, "HallDoor")
	model.Parent = ctx.Folders.Hinges
	Pieces.Block(ctx, "Frame", v(-81, 0, -5.5), v(-79, H, -4.5), S.BlastDoor, model)
	Pieces.Block(ctx, "Frame", v(-81, 0, 4.5), v(-79, H, 5.5), S.BlastDoor, model)
	Pieces.Block(ctx, "Header", v(-81, 11, -4.5), v(-79, H, 4.5), S.Hazard, model)
	local panel = Pieces.Block(ctx, "Panel", v(-80.4, 0, -4.5), v(-79.6, H, 4.5), S.BlastDoor, model)
	Pieces.RegisterDoor(Pieces.Id(ctx, "HallDoor"), Pieces.P(ctx, v(-80, 4, 0)), v(0, 0, 1), 9, 8)
	local status = {}
	for _, x in { -81.2, -78.8 } do
		local sp = Pieces.BoxAt(ctx, "Status", v(x, 10.4, 0), v(0.4, 0.4, 0.4), {
			Color = L.StatusOpen.Color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}, model)
		table.insert(status, { Part = sp, Light = Pieces.NewLight("PointLight", sp, L.StatusOpen) })
	end
	Hinges.Register({
		Id = Pieces.Id(ctx, "HallDoor"),
		Kind = "HallDoor",
		InitialOpen = true,
		Panels = {
			{
				Part = panel,
				ClosedCFrame = panel.CFrame,
				OpenCFrame = panel.CFrame + Vector3.new(0, 11.6, 0),
			},
		},
		Volumes = {
			{
				CFrame = CFrame.new(Pieces.P(ctx, v(-80, 6, 0))),
				Size = v(5, 12, 11),
				Exits = { Pieces.P(ctx, v(-85, 0, 0)), Pieces.P(ctx, v(-75, 0, 0)) },
			},
		},
		Status = status,
		Position = Pieces.P(ctx, v(-80, 6, 0)),
		Size = v(2, H, 10),
	})

	-- Atrium: elevator core at x = 0 (built from both halves) blocks every hall-to-hall ray.
	-- A closed elevator shaft (walls on every side, each half builds its side) with the doors set
	-- into its wall. Blocks every hall-to-hall ray; the door leaves are solid, non-penetrable metal.
	Pieces.WallX(ctx, -4.5, -7.2, 7.2, { { c = 0, w = 4, h = 8 } }, S.Elevator)
	Pieces.WallZ(ctx, 7.2, -5, 0, nil, S.Elevator)
	Pieces.WallZ(ctx, -7.2, -5, 0, nil, S.Elevator)
	-- Sliding door leaves (ElevatorService opens them when this team's riders arrive). Closed they
	-- meet at z = 0; open they slide 2 studs into the wall on each side.
	local leaves = {}
	for _, sz in { -1, 1 } do
		local leaf = Pieces.BoxAt(
			ctx,
			"ElevatorLeaf",
			v(-4.5, 4, sz),
			v(0.5, 8, 1.98),
			S.ElevatorDoor,
			ctx.Folders.Hinges
		)
		table.insert(
			leaves,
			{ Part = leaf, Closed = leaf.CFrame, Open = leaf.CFrame + Vector3.new(0, 0, sz * 2) }
		)
	end
	-- Cab floor: the same diamond-plate as the spawn car, flush on the atrium floor.
	Pieces.BoxAt(
		ctx,
		"ElevatorCabFloor",
		v(-2.25, 0.04, 0),
		v(3.4, 0.08, 13.3),
		S.Mezzanine,
		ctx.Folders.Props
	)
	-- Cab light inside your half of the shaft.
	local cab = Pieces.BoxAt(
		ctx,
		"ElevatorCabLight",
		v(-2.2, H - 0.1, 0),
		v(1.6, 0.1, 1.6),
		S.TubeOn,
		ctx.Folders.Lights
	)
	Pieces.NewLight("PointLight", cab, L.Emergency)
	local arrivals = {}
	for _, z in { -3.5, 0, 3.5 } do
		local p = v(-1.8, 3, z)
		table.insert(arrivals, CFrame.lookAt(Pieces.P(ctx, p), Pieces.P(ctx, p + v(-1, 0, 0))))
	end
	result.Elevators[team] = result.Elevators[team] or {} :: any
	local e = result.Elevators[team] :: any
	e.Leaves = leaves
	e.Arrivals = arrivals
	e.Shaft = CFrame.new(Pieces.P(ctx, v(-2.25, 4, 0)))
	e.ShaftSize = Vector3.new(3.5, 8, 13.4)
	local indicator = prop(ctx, "ElevatorIndicator", v(-5.06, 9.2, 0), v(0.1, 0.5, 1.6), {
		Color = Color3.fromRGB(255, 140, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	indicator.CanQuery = false

	-- Raised mezzanine along the south wall with stairs and a railing (drop-down gap in the middle).
	prop(ctx, "Mezzanine", v(-24, 2, -11.5), v(16, 4, 5), S.Mezzanine)
	for i, h in { 3, 2, 1 } do
		local x = -15 + (i - 1) * 2
		prop(ctx, "Stair", v(x, h / 2, -11.5), v(2, h, 5), S.Mezzanine)
	end
	prop(ctx, "Railing", v(-29, 5.5, -8.8), v(6, 3, 0.4), S.Railing)
	prop(ctx, "Railing", v(-19, 5.5, -8.8), v(6, 3, 0.4), S.Railing)

	-- Atrium cover: half wall, crate, a planter
	prop(ctx, "HalfWall", v(-27, 1.75, 4), v(6, 3.5, 1), S.OfficeWall)
	prop(ctx, "MezzBoost", v(-24, 1.5, -7.3), v(3, 3, 3), S.Crate) -- jump crate -> mezzanine (railing gap)
	cover(ctx, -14, 11, 3, 3, S.Cabinet)

	-- Atrium lights (HallCenter power group; LightDirector zone "Atrium")
	local atrium = {
		{ name = "A1", pos = v(-30, H, 0), preset = L.HallTube, breakable = true },
		{ name = "A2", pos = v(-18, H, 8), preset = L.DimTube, breakable = false },
		{ name = "A3", pos = v(-14, H, -6), preset = L.HallTubeShadow, breakable = true },
	}
	for _, a in atrium do
		local tube, light = Pieces.Tube(ctx, `Atrium{a.name}`, a.pos, "X", true, a.preset)
		if light and a.name == "A2" then
			Pieces.MarkFlicker(light)
		end
		local emitters = if a.preset == L.HallTubeShadow
			then Pieces.Dust(ctx, "AtriumDust", v(a.pos.X, 5.5, a.pos.Z), v(9, 10, 9))
			else nil
		registerLamp(ctx, `Atrium.{a.name}`, tube, light, {
			Breakable = a.breakable,
			Power = "HallCenter",
			Emitters = emitters,
			Radius = 15,
			Zone = "Atrium",
		})
	end

	-- Distribution corridor tubes (unbreakable; LightDirector zone "Dist") + staggered cover so a
	-- Core carrier running the corridor breaks line of sight every ~24 studs.
	for i, z in { -56, -20, 16, 50 } do
		local tube, light = Pieces.Tube(ctx, `DistT{i}`, v(-120, H, z), "X", true, L.CorridorTube)
		if light and (z == -56 or z == 50) then
			Pieces.MarkFlicker(light)
		end
		registerLamp(ctx, `Dist.T{i}`, tube, light, { Breakable = false, Radius = 16, Zone = "Dist" })
	end
	cover(ctx, -124, -52, 3, 3)
	cover(ctx, -116, -28, 3, 3)
	cover(ctx, -124, 24, 3, 3)
	cover(ctx, -116, 46, 3, 3)
end

-- Cubicles -------------------------------------------------------------------------------------

-- Sniper perch: a raised platform in a lane's base-end corner with stairs and a rail to rest on
-- (head-glitch spot). Built in the lane's own materials so it reads as part of the room:
-- plaster + wood in the office, concrete + diamond plate with hazard edges in the maintenance hall.
-- `sz` = +1 for the north lane (maintenance), -1 for the south lane (office).
local function perch(ctx: Ctx, result: Result, sz: number)
	local z = 70 * sz
	local office = sz < 0
	local body = if office then S.Pillar else S.MaintWall
	local step = if office then S.Desk else S.Mezzanine
	prop(ctx, "Perch", v(-109, 1.95, z), v(9, 3.9, 11), body)
	prop(ctx, "PerchTop", v(-109, 3.95, z), v(9.1, 0.1, 11.1), step)
	for i, h in { 3, 2, 1 } do
		prop(ctx, "PerchStair", v(-103.5 + (i - 1) * 2, h / 2, 73.5 * sz), v(2, h, 4), step)
	end
	if not office then
		for i, h in { 3, 2, 1 } do
			prop(
				ctx,
				"StairEdge",
				v(-102.55 + (i - 1) * 2, h + 0.01, 73.5 * sz),
				v(0.12, 0.1, 4.02),
				S.Hazard
			)
		end
	end
	prop(ctx, "PerchRail", v(-104.5, 5.25, 68 * sz), v(0.4, 2.5, 7), S.Railing) -- rest your rifle here
	prop(ctx, "PerchRail", v(-109, 5.25, 64.7 * sz), v(9, 2.5, 0.4), S.Railing)
	local team = ctx.Team :: string
	result.SniperSpots[team] = result.SniperSpots[team] or {}
	table.insert(
		result.SniperSpots[team],
		CFrame.lookAt(Pieces.P(ctx, v(-108, 4, z)), Pieces.P(ctx, v(0, 4, 56 * sz)))
	)
end

-- Hard cover island: full-height pillar + a chest-high wall beside it (carrier hops between these).
local function island(ctx: Ctx, x: number, z: number, surf: Surface)
	pillar(ctx, x, z)
	prop(ctx, "IslandWall", v(x + 3.5, 1.75, z), v(5, 3.5, 1.5), surf)
end

-- Zig-zag band beside the junction mouth: two staggered pillars whose z-ranges overlap by 3 studs,
-- so no near-straight ray passes along the lane through the centre. `sz` = lane side (+1 / -1).
local function band(ctx: Ctx, sz: number)
	local function block(x: number, za: number, zb: number)
		local lo, hi = math.min(za, zb) * 1, math.max(za, zb)
		prop(ctx, "BandPillar", v(x, H / 2, (lo + hi) / 2), v(2, H, hi - lo), S.Pillar)
	end
	block(-30, 36 * sz, 42.5 * sz)
	block(-14, 39.5 * sz, 46 * sz)
end

-- Side-lane ceiling tubes: the same long fluorescent tubes (HallTube) as the Long Hall, in three
-- staggered rows across the 40-deep lane so it is lit like the hall. Used by both side lanes (Open
-- Office south, Maintenance Gallery north). `sz` = lane side (-1 south / +1 north). All breakable
-- (shoot them out to darken the sniper line). The middle-row x's dodge the ceiling decor on z = -56.
local LANE_ROWS = {
	-- (x = -6: a column beside the x = 0 centre wall that ends the lane, so that wall gets lit.)
	{ z = 44, xs = { -104, -88, -72, -56, -40, -24, -6 } },
	{ z = 56, xs = { -102, -87, -76, -61, -46, -30, -14, -4 } },
	{ z = 68, xs = { -104, -88, -72, -56, -40, -24, -6 } },
}
local function laneTubes(ctx: Ctx, prefix: string, sz: number, ceiling: number, zoneW: string, zoneE: string)
	for r, row in LANE_ROWS do
		for k, x in row.xs do
			local z = row.z * sz
			local shadow = r == 2 and x == -61
			local name = `{prefix}T{r}_{k}`
			local tube, light = Pieces.Tube(
				ctx,
				name,
				v(x, ceiling, z),
				"Z",
				true,
				if shadow then L.HallTubeShadow else L.HallTube
			)
			if light and r ~= 2 and k == 3 then
				Pieces.MarkFlicker(light)
			end
			local emitters = if shadow
				then Pieces.Dust(ctx, name .. "Dust", v(x, 5.5, z), v(8, 10, 10))
				else nil
			registerLamp(ctx, `{prefix}.T{r}_{k}`, tube, light, {
				Breakable = true,
				Emitters = emitters,
				Radius = 12,
				Zone = if x <= -60 then zoneW else zoneE,
			})
		end
	end
end

local function buildSouthLane(ctx: Ctx, result: Result)
	-- Open Office: lit by the Long Hall's ceiling tubes (laneTubes), same as the Maintenance Gallery.
	laneTubes(ctx, "Office", -1, H, "OfficeW", "OfficeE")
	fill(ctx, "OfficeFillW", v(-100, 9, -56), 30)
	fill(ctx, "OfficeFillM", v(-60, 9, -56), 30)
	fill(ctx, "OfficeFillE", v(-20, 9, -56), 30)
	perch(ctx, result, -1)
	-- Cover islands every ~22 studs, alternating north / south edges
	island(ctx, -94, -44, S.Desk)
	island(ctx, -72, -68, S.Desk)
	island(ctx, -58, -46, S.Desk)
	island(ctx, -36, -68, S.Desk)
	band(ctx, -1)
	-- Wallbang panel: freestanding drywall partition, turned 90 deg to run across the lane (owner,
	-- 2026-10-16) and set off-centre towards the south wall: z -70..-62 (lane centre is z -56, the
	-- bots' S2 -> S3 line), clear of the south-wall desk and the island at (-72, -68).
	local panel = prop(ctx, "DrywallPanel", v(-80, 3.5, -66), v(0.6, 7, 8), S.Drywall)
	panel:AddTag("Penetrable")
	-- Close-fight nook: copier + boxes in the south-wall alcove
	cover(ctx, -63, -79, 3, 3, S.Cabinet)
	cover(ctx, -58.5, -78.5, 2.5, 3, S.Box)
end

-- Side rooms -----------------------------------------------------------------------------------

local function buildSideRooms(ctx: Ctx)
	-- Records: dark room between hall and cubicles, lit only at its two doorways.
	doorLamp(ctx, "Records.HallDoor", v(-49, 0, -6), v(0, 0, -1), "Exit", "Records")
	doorLamp(ctx, "Records.CubDoor", v(-49, 0, -36), v(0, 0, 1), "Cage", "Records")
	fill(ctx, "RecordsFill", v(-49, 9, -21))
	dark(ctx, -58, -36, -40, -6)
	prop(ctx, "Shelf", v(-53.5, 4, -21), v(1.5, 8, 16), S.Shelf)
	prop(ctx, "Shelf", v(-44.5, 4, -21), v(1.5, 8, 16), S.Shelf)
	cover(ctx, -56, -10, 2.5, 3, S.Box)
	cover(ctx, -42, -32, 2.5, 3, S.Box)

	-- Break room (dim): one working tube of three, a humming vending machine, window to the atrium.
	for i, z in { 18, 25, 32 } do
		local lit = z == 25
		local tube, light = Pieces.Tube(ctx, `BreakT{i}`, v(-18, H, z), "X", lit, L.DimTube)
		if lit and light then
			Pieces.MarkFlicker(light)
			registerLamp(ctx, "Break.T", tube, light, { Breakable = true, Radius = 14, Zone = "Break" })
		end
	end
	-- Vending machine: the handmade one is a Decor slot that DecorService swaps for the owner's store
	-- model (Blue: snack machine, Red: Pepsi machine; same 7-stud height, back to the west wall). The
	-- blue glow light stays on its own invisible part so the room's lighting is unchanged.
	local body = prop(ctx, "Vending", v(-28.6, 3.5, 30), v(2.2, 7, 3), S.Cabinet)
	local front = prop(ctx, "VendingFront", v(-27.45, 4, 30), v(0.1, 4, 2.4), {
		Color = Color3.fromRGB(150, 190, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	local vending = Instance.new("Model")
	vending.Name = "Vending"
	body.Parent = vending
	front.Parent = vending
	vending:SetAttribute("Kind", "Prop")
	vending:SetAttribute("Prop", if ctx.Team == "Red" then "VendingPepsi" else "VendingSnack")
	vending:SetAttribute("Facing", if ctx.Mirror then v(-1, 0, 0) else v(1, 0, 0))
	vending:SetAttribute("AgainstWall", true)
	vending:SetAttribute("Spot", Pieces.P(ctx, v(-29.5, 0, 30))) -- west wall face, floor level
	vending:AddTag("DecorSlot")
	vending.Parent = ctx.Folders.Props
	local glow = prop(ctx, "VendingGlow", front.Position, v(0.1, 0.1, 0.1), {
		Color = Color3.new(0, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	glow.CanQuery = false
	Pieces.NewLight("PointLight", glow, L.Vending)
	Regions.AddZoneLight(front.Position, 6, nil)
	cover(ctx, -13, 22, 4, 6, S.Desk)
	cover(ctx, -26, 17, 3, 3, S.Box)

	-- Maintenance tunnel hinge: closed by a shutter at each mouth.
	dark(ctx, -46, 6, -40, 36)
	Pieces.Cylinder(ctx, "Pipe", v(-44.8, 10.6, 21), 31, 0.9, "Z", S.Pipe)
	Pieces.Cylinder(ctx, "Pipe", v(-41.3, 11.1, 21), 31, 0.5, "Z", S.Pipe)
	Pieces.BoxAt(ctx, "BulbCage", v(-43, 10.4, 21), v(1, 1, 1), S.Cage, ctx.Folders.Lights)
	local bulb =
		Pieces.BoxAt(ctx, "TunnelBulb", v(-43, 10.4, 21), v(0.7, 0.7, 0.7), S.Bulb, ctx.Folders.Lights)
	bulb.Shape = Enum.PartType.Ball
	bulb:SetAttribute("OnColor", S.Bulb.Color)
	local bulbLight = Pieces.NewLight("PointLight", bulb, L.TunnelBulb)
	Pieces.MarkFlicker(bulbLight)
	registerLamp(ctx, "Tunnel.Bulb", bulb, bulbLight, { Breakable = true, Zone = "MaintE" })
	fill(ctx, "TunnelFill", v(-43, 7, 21), 14)

	local model = Instance.new("Model")
	model.Name = Pieces.Id(ctx, "Tunnel")
	model.Parent = ctx.Folders.Hinges
	local panels = {}
	local status = {}
	for _, z in { 6, 36 } do
		local panel =
			Pieces.Block(ctx, "Shutter", v(-45.5, 0, z - 0.4), v(-40.5, 8, z + 0.4), S.BlastDoor, model)
		table.insert(
			panels,
			{ Part = panel, ClosedCFrame = panel.CFrame, OpenCFrame = panel.CFrame + Vector3.new(0, 7.85, 0) }
		)
		local outside = if z == 6 then -1 else 1
		local sp = Pieces.BoxAt(ctx, "Status", v(-43, 8.7, z + outside * 0.75), v(0.4, 0.4, 0.4), {
			Color = L.StatusSealed.Color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}, model)
		table.insert(status, { Part = sp, Light = Pieces.NewLight("PointLight", sp, L.StatusSealed) })
	end
	Hinges.Register({
		Id = Pieces.Id(ctx, "Tunnel"),
		Kind = "Tunnel",
		InitialOpen = false,
		Panels = panels,
		Volumes = {
			{
				CFrame = CFrame.new(Pieces.P(ctx, v(-43, 4, 21))),
				Size = v(6, 8, 31.5),
				Exits = { Pieces.P(ctx, v(-43, 0, 1.5)), Pieces.P(ctx, v(-43, 0, 40.5)) },
			},
		},
		Status = status,
		Position = Pieces.P(ctx, v(-43, 6, 21)),
		Size = v(6, H, 30),
	})
end

-- Maintenance ----------------------------------------------------------------------------------

local function buildNorthLane(ctx: Ctx, result: Result)
	-- Doorway lamps for the doors into the gallery (distribution corridor, break room, tunnel)
	local X, Z = v(1, 0, 0), v(0, 0, 1)
	doorLamp(ctx, "Maint.D1", v(-114, 0, 56), X, "Exit", "MaintW")
	doorLamp(ctx, "Maint.Break", v(-21, 0, 36), Z, "Exit", "MaintE")
	doorLamp(ctx, "Maint.Tunnel", v(-43, 0, 36), Z, "Cage", "MaintE")
	fill(ctx, "GalleryFillW", v(-100, 9, 56), 30)
	fill(ctx, "GalleryFillM", v(-60, 9, 56), 30)
	fill(ctx, "GalleryFillE", v(-20, 9, 56), 30)

	-- Ceiling tubes down the gallery: the Long Hall's tubes, same layout as the Open Office.
	laneTubes(ctx, "Gallery", 1, MH, "MaintW", "MaintE")

	perch(ctx, result, 1)

	-- Flooded crossing (non-colliding water sheet) under a cold light shaft
	-- (The raised water sheet was removed; the crossing keeps its wet, reflective floor.)
	Pieces.BoxAt(ctx, "Grate", v(-70, 10.9, 58), v(4, 0.2, 4), S.Vent, ctx.Folders.Props)
	local shaft = Pieces.BoxAt(ctx, "ShaftLamp", v(-70, 10.75, 58), v(3, 0.1, 3), {
		Color = L.Shaft.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	}, ctx.Folders.Lights)
	shaft:SetAttribute("OnColor", L.Shaft.Color)
	local shaftLight = Pieces.NewLight("SpotLight", shaft, L.Shaft)
	local shaftDust = Pieces.Dust(ctx, "ShaftDust", v(-70, 5.5, 58), v(5, 10, 5), true)
	registerLamp(
		ctx,
		"Maint.Shaft",
		shaft,
		shaftLight,
		{ Breakable = true, Emitters = shaftDust, Zone = "MaintW" }
	)

	-- Cover islands every ~22 studs, alternating south / north edges (hard, industrial)
	-- (Pump moved from x -94 and generator from (-48, 46), owner 2026-10-16: the lab's south-wall
	-- specimen tubes stand there now, x -93..-82 Blue / -60..-48 Red, and need a clear front.)
	prop(ctx, "Pump", v(-100, 2.5, 44), v(5, 5, 4), S.Machine)
	prop(ctx, "PumpPipe", v(-104, 1.75, 44), v(3, 3.5, 1.5), S.Pipe)
	-- (The two concrete columns by the lab benches, (-70, 68) and (-66, 42), were removed: owner.)
	-- Generator: slim (5 x 4) and away from the lab benches (owner, 2026-10-16): towards the tinted
	-- window, in line with the tool-cage picture (x -35), north of the bots' N4 -> N5 path and clear
	-- of the island at (-28, 68) and the cage crates.
	prop(ctx, "Generator", v(-36, 2.5, 63), v(5, 5, 4), S.Machine)
	Pieces.Cylinder(ctx, "Pipe", v(-37.2, 7.75, 63), 5.5, 0.6, "Y", S.Pipe)
	island(ctx, -28, 68, S.Machine)
	band(ctx, 1)
	-- Wallbang panel: thin sheet-metal partition (penetrable), standing free on the south side of
	-- the gallery at x -36, in line with the generator (owner, 2026-10-16; was in front of the lab
	-- benches). Clear of the tunnel-door path and the N4 -> N5 bot line.
	local sheet = prop(ctx, "SheetPanel", v(-36, 3.5, 46), v(0.5, 7, 8), S.Vent)
	sheet.CanCollide = true
	sheet:AddTag("Penetrable")
	-- Close-fight alcove: tool cage with crates
	cover(ctx, -37.5, 78.5, 3, 3, S.Box)
	cover(ctx, -32, 79, 2.5, 2.5, S.Box)

	-- Long pipes along the ceiling
	Pieces.Cylinder(ctx, "Pipe", v(-57, 9.9, 74), 114, 1.4, "X", S.Pipe)
	Pieces.Cylinder(ctx, "Pipe", v(-57, 10.4, 38.5), 114, 0.8, "X", S.Pipe)
	Pieces.BoxAt(ctx, "Vent", v(-100, 10.85, 50), v(3, 0.2, 3), S.Vent, ctx.Folders.Props)
end

-- Navigation -----------------------------------------------------------------------------------

local function buildNav(ctx: Ctx, result: Result)
	local team = ctx.Team :: string
	local function N(name: string, x: number, z: number, owned: boolean?)
		NavGraph.AddNode(nid(ctx, name), Pieces.P(ctx, v(x, 0, z)), if owned then team else nil)
	end
	local function Lk(a: string, b: string, hinge: string?)
		NavGraph.Link(nid(ctx, a), nid(ctx, b), if hinge then Pieces.Id(ctx, hinge) else nil)
	end

	-- Spawn (behind the flag room) -> north / south wing -> distribution corridor or flag-room flank.
	-- (The third exit is the spawn elevator; bots use the wings.)
	N("SP", -172, 0, true)
	N("SPN", -168, 27, true)
	N("WNs", -162, 26.5, true)
	N("SPS", -168, -27, true)
	N("WSs", -162, -26.5, true)
	N("WN1", -154, 30)
	N("WNg", -144, 42)
	N("WN3", -135, 32)
	N("WS1", -154, -30)
	N("WSg", -144, -42)
	N("WS3", -135, -32)
	-- Flag room (main door east, a flank door from each wing)
	N("Core", -143.5, 0)
	N("B", -136, -4)
	N("BN", -134, 10)
	N("BS", -134, -11)
	N("BDs", -126, -12)
	N("CN", -140, 20)
	N("CS", -140, -20)
	N("SD", -126, 38)
	N("SDs", -126, -38)
	-- Distribution corridor
	N("DCs2", -120, -56)
	N("DCs", -120, -38)
	N("DCs1", -120, -12)
	N("DC0", -120, 0)
	N("DCn1", -120, 12)
	N("DCn", -120, 38)
	N("DCn2", -120, 56)
	-- Long hall + atrium
	N("H1", -108, 0)
	N("H2", -92, 0)
	N("H4", -66, 0)
	N("HR", -49, 0)
	N("H5", -43, 0)
	N("AW", -30, 0)
	N("AC", -12, -1)
	N("AS", -6, -11)
	N("AN", -6, 11)
	-- Records
	N("R1", -49, -9)
	N("R2", -49, -21)
	N("R3", -49, -33)
	N("CD", -49, -40)
	-- South lane (Open Office)
	N("S1", -104, -56)
	N("S2", -82, -56)
	N("S3", -62, -56)
	N("S4", -40, -56)
	N("S5", -26, -44.5)
	N("S6", -21, -37.5)
	N("SPa", -97, -73.5) -- foot of the perch stairs
	NavGraph.AddNode(nid(ctx, "SPerch"), Pieces.P(ctx, v(-108, 4, -73)))
	-- North lane (Gallery)
	N("N1", -100, 56)
	N("N2", -80, 56)
	N("N3", -62, 56)
	N("N4", -40, 58)
	N("N5", -26, 44.5)
	N("N6", -21, 37.5)
	N("NPa", -97, 73.5)
	NavGraph.AddNode(nid(ctx, "NPerch"), Pieces.P(ctx, v(-108, 4, 73)))
	-- Tunnel, break room
	N("T0", -43, 9)
	N("T1", -43, 21)
	N("T2", -43, 33)
	N("BR1", -21, 18)
	N("BR2", -21, 30)
	N("D1", -114, 56)
	N("M3t", -43, 40)

	Lk("SP", "SPN")
	Lk("SPN", "WNs")
	Lk("WNs", "WN1")
	Lk("WN1", "WNg")
	Lk("WNg", "WN3")
	Lk("WN3", "SD")
	Lk("WN3", "CN")
	Lk("SD", "DCn")
	Lk("SP", "SPS")
	Lk("SPS", "WSs")
	Lk("WSs", "WS1")
	Lk("WS1", "WSg")
	Lk("WSg", "WS3")
	Lk("WS3", "SDs")
	Lk("WS3", "CS")
	Lk("SDs", "DCs")
	Lk("Core", "B")
	Lk("B", "BN")
	Lk("B", "BS")
	Lk("BS", "BDs")
	Lk("BDs", "DCs1")
	Lk("BN", "CN")
	Lk("BS", "CS")
	Lk("DCs2", "DCs")
	Lk("DCs", "DCs1")
	Lk("DCs1", "DC0")
	Lk("DC0", "DCn1")
	Lk("DCn1", "DCn")
	Lk("DCn", "DCn2")
	Lk("DC0", "H1")
	Lk("DCn2", "D1")
	Lk("DCs2", "S1")
	-- Hall + atrium
	Lk("H1", "H2")
	Lk("H2", "H4", "HallDoor")
	Lk("H4", "HR")
	Lk("HR", "H5")
	Lk("H5", "AW")
	Lk("AW", "AC")
	Lk("AC", "AS")
	Lk("AC", "AN")
	Lk("AS", "C.JS")
	Lk("AN", "C.JN")
	Lk("AS", "C.AtS")
	Lk("AN", "C.AtN")
	Lk("AC", "BR1")
	Lk("HR", "R1")
	Lk("R1", "R2")
	Lk("R2", "R3")
	Lk("R3", "CD")
	Lk("CD", "S4")
	Lk("H5", "T0", "Tunnel")
	Lk("T0", "T1")
	Lk("T1", "T2")
	Lk("T2", "M3t", "Tunnel")
	Lk("BR1", "BR2")
	Lk("BR2", "N6")
	-- South lane
	Lk("S1", "S2")
	Lk("S2", "S3")
	Lk("S3", "S4")
	Lk("S4", "S5")
	Lk("S5", "S6")
	Lk("S6", "C.SB")
	Lk("S2", "SPa")
	Lk("SPa", "SPerch")
	-- North lane
	Lk("D1", "N1")
	Lk("N1", "N2")
	Lk("N2", "N3")
	Lk("N3", "N4")
	Lk("N4", "N5")
	Lk("N5", "N6")
	Lk("N6", "C.MJ")
	Lk("M3t", "N4")
	Lk("N2", "NPa")
	Lk("NPa", "NPerch")

	result.SpawnNode[team] = Pieces.Id(ctx, "SP")
	result.CoreNode[team] = Pieces.Id(ctx, "Core")
end

-- Centre (x = 0), built once ------------------------------------------------------------------

local function buildCenter(ctx: Ctx)
	-- Junction (dim): north/south corridors linking all three lanes either side of the elevator
	for _, z in { -25, 25 } do
		local t, l = Pieces.Tube(ctx, "JunctionTube", v(0, H, z), "X", true, L.DimTube)
		if l and z > 0 then
			Pieces.MarkFlicker(l)
		end
		registerLamp(
			ctx,
			if z < 0 then "Junction.S" else "Junction.N",
			t,
			l,
			{ Breakable = true, Radius = 14, Zone = "Junction" }
		)
	end
	doorLamp(ctx, "Maint.Junction", v(0, 0, 36), v(0, 0, 1), "Exit", "Junction")

	-- Side-lane centre walls: a normal (1-stud, office-coloured) wall at x = 0 splits each side lane
	-- and ends both sniper lines at mid-map; the zig-zag bands beside the junction mouths are the
	-- lanes' key chokes. (Were 12-stud server-room / boiler blocks.)
	-- Each has one wide tinted window centred in it (CENTRE_WINDOW_*): chest-high sill (stand to
	-- see / shoot, crouch to hide), lightly tinted glass that bullets pass through like a thin wall
	-- (Penetrable) and bots see through (Transparency >= 0.5).
	for _, wall in
		{
			{ Z = CENTRE_WINDOW_Z, Top = CENTRE_WINDOW_TOP.Office },
			{ Z = -CENTRE_WINDOW_Z, Top = CENTRE_WINDOW_TOP.Gallery },
		}
	do
		local opening = { { c = wall.Z, w = CENTRE_WINDOW_W, s = CENTRE_WINDOW_SILL, h = wall.Top } }
		if wall.Z < 0 then
			Pieces.WallX(ctx, 0, -76, -46, opening, S.OfficeWall)
		else
			Pieces.WallX(ctx, 0, 46, 76, opening, S.OfficeWall, { Height = MH })
		end
		local glass = prop(
			ctx,
			"TintedGlass",
			v(0, (CENTRE_WINDOW_SILL + wall.Top) / 2, wall.Z),
			v(0.2, wall.Top - CENTRE_WINDOW_SILL, CENTRE_WINDOW_W),
			S.TintedGlass
		)
		glass:AddTag("Penetrable")
		glass:AddTag("BreakableGlass") -- shatters when shot, repairs after 20 s (Combat/Glass)
	end
	for _, z in { -41, 41 } do
		local y = if z < 0 then H else MH
		local t, l = Pieces.Tube(ctx, "BandTube", v(0, y, z), "X", true, L.DimTube)
		registerLamp(
			ctx,
			if z < 0 then "Band.S" else "Band.N",
			t,
			l,
			{ Breakable = true, Radius = 14, Zone = "Junction" }
		)
	end

	-- Divider inside the elevator shaft: each team's half is its own car (no meeting inside).
	Pieces.WallX(ctx, 0, -7.2, 7.2, nil, S.Elevator)

	-- Nav (both halves link into these)
	NavGraph.AddNode("C.JS", v(0, 0, -24))
	NavGraph.AddNode("C.JN", v(0, 0, 24))
	NavGraph.AddNode("C.SB", v(0, 0, -38))
	NavGraph.AddNode("C.MJ", v(0, 0, 38))
	NavGraph.AddNode("C.AtS", v(0, 0, -11)) -- atrium, south of the elevator shaft
	NavGraph.AddNode("C.AtN", v(0, 0, 11)) -- atrium, north of the elevator shaft
	NavGraph.Link("C.SB", "C.JS")
	NavGraph.Link("C.AtS", "C.JS")
	NavGraph.Link("C.AtN", "C.JN")
	NavGraph.Link("C.JN", "C.MJ")
end

-- Minimap data: one Vector3Value per labelled area (Value = centre, attribute Size = footprint),
-- in Facility.MapRooms. Players' minimap draws the walls itself; this only adds names.
-- Display names differ from the internal room names where the internal ones are terse.
local MAP_NAMES: { [string]: string } = {
	["Core Room"] = "Flag Room",
	["Spawn Passage"] = "Passage",
	Gallery = "Maint. Gallery",
	Distribution = "Corridor",
}

local function exportMap(root: Folder, result: Result)
	local folder = Instance.new("Folder")
	folder.Name = "MapRooms"
	local function add(name: string, center: Vector3, size: Vector3)
		local value = Instance.new("Vector3Value")
		value.Name = name
		value.Value = center
		value:SetAttribute("Size", size)
		value.Parent = folder
	end
	local junctions: { [number]: boolean } = {}
	for _, room in result.Rooms do
		if room.Name == "Junction" then
			-- Each half has its own 6-wide junction strip either side of x = 0: label the pair once,
			-- centred on the seam (two labels there overlapped each other and the break rooms).
			local key = math.sign(room.Center.Z)
			if not junctions[key] then
				junctions[key] = true
				add(
					"Junction",
					Vector3.new(0, room.Center.Y, room.Center.Z),
					Vector3.new(room.Size.X * 2, room.Size.Y, room.Size.Z)
				)
			end
		else
			add(MAP_NAMES[room.Name] or room.Name, room.Center, room.Size)
		end
	end
	-- The gallery floor is split (dry / flooded / dry); label the flooded crossing and the east end too.
	for _, x in { 70, -70 } do
		add("Flooded", Vector3.new(x, 6, 56), Vector3.new(20, 12, 40))
	end
	folder.Parent = root
end

-- Entry -----------------------------------------------------------------------------------------

function Layout.Build(parent: Instance): Result
	Pieces.ResetWallRegistry()
	local root = Instance.new("Folder")
	root.Name = "Facility"

	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end
	local folders: Pieces.Folders = {
		Structure = sub("Structure"),
		Lights = sub("Lights"),
		Props = sub("Props"),
		Hinges = sub("Hinges"),
		Markers = sub("Markers"),
		Fx = sub("Fx"),
		Detail = sub("Detail"),
		Decor = sub("Decor"),
	}

	local anchor =
		Pieces.RawPart("LightAnchor", CFrame.new(0, -0.5, 0), Vector3.new(1, 1, 1), S.Invisible, root)

	local result: Result = {
		Root = root,
		Spawns = {},
		Pedestals = {},
		SpawnNode = {},
		CoreNode = {},
		TeamRooms = {},
		HallEnds = {},
		SniperSpots = {},
		Elevators = {},
		Bounds = { Min = Vector3.new(-187, 0, -81), Max = Vector3.new(187, H + 1, 81) },
		Rooms = {},
	}

	-- Centre first so half-map nav links to "C." nodes resolve.
	local center = Pieces.NewCtx("C", nil, false, folders, anchor)
	buildCenter(center)

	for _, spec in { { "B", "Blue", false }, { "R", "Red", true } } do
		local ctx = Pieces.NewCtx(spec[1] :: string, spec[2] :: string, spec[3] :: boolean, folders, anchor)
		buildStructure(ctx, result)
		buildBase(ctx, result)
		buildHall(ctx, result)
		buildSouthLane(ctx, result)
		buildSideRooms(ctx)
		buildNorthLane(ctx, result)
		buildNav(ctx, result)
		Detail.Build(ctx)
		if Layout.DECOR_TEST then
			Decor.Build(ctx)
		end
	end

	exportMap(root, result)
	root.Parent = parent
	return result
end

return Layout

--!strict
-- Modular greybox pieces for "Level 0 - Office Annex".
--
-- Every function takes coordinates for the BLUE half of the map (x <= 0). A ctx with Mirror = true
-- maps x -> -x, so the Red half is an exact mirror image built from the same calls. Parts are only
-- axis-aligned boxes (or cylinders about X/Y/Z), which mirror cleanly without rotation math.

local CollectionService = game:GetService("CollectionService")

local Style = require(script.Parent.Style)

type Surface = Style.Surface
type LightPreset = Style.LightPreset

export type Folders = {
	Structure: Instance,
	Lights: Instance,
	Props: Instance,
	Hinges: Instance,
	Markers: Instance,
	Fx: Instance,
	Detail: Instance, -- environmental wall / ceiling dressing (World/Detail.luau)
	Decor: Instance, -- TEST set dressing (World/Decor.luau), removable
}

export type Ctx = {
	Prefix: string, -- "B" (Blue half), "R" (Red half), "C" (centre, built once)
	Team: string?, -- "Blue" / "Red" for halves, nil for centre
	Mirror: boolean,
	Folders: Folders,
	Anchor: BasePart, -- invisible part at the origin that holds attachment lights
}

export type Opening = { c: number, w: number, h: number?, s: number? }

local Pieces = {}

Pieces.Stats = { Parts = 0, Lights = 0, ShadowLights = 0 }

-- Every door / window / vent opening (and door lamp) is recorded so WorldService can verify at
-- startup that each one sits in a real wall (jambs on both sides) and is open through the middle.
export type DoorRecord = { Name: string, Center: Vector3, Along: Vector3, Width: number, Height: number }
export type DoorLampRecord = { Name: string, Door: Vector3 }
Pieces.Doors = {} :: { DoorRecord }
Pieces.DoorLamps = {} :: { DoorLampRecord }

function Pieces.RegisterDoor(name: string, center: Vector3, along: Vector3, width: number, height: number)
	table.insert(
		Pieces.Doors,
		{ Name = name, Center = center, Along = along, Width = width, Height = height }
	)
end

function Pieces.RegisterDoorLamp(name: string, door: Vector3)
	table.insert(Pieces.DoorLamps, { Name = name, Door = door })
end

-- Records the openings of one wall. Openings that end on the x = 0 seam continue in the mirrored
-- half, so they are merged into one record (registered once, by the Blue half).
local function registerOpenings(
	ctx: Ctx,
	axis: "X" | "Z",
	line: number,
	openings: { Opening }?,
	height: number
)
	for _, op in openings or {} do
		local top = op.h or Style.Dims.DoorHeight
		if top < height then
			local sill = op.s or 0
			local a, b = op.c - op.w / 2, op.c + op.w / 2
			local c, w = op.c, op.w
			local onSeam = axis == "Z" and (a == 0 or b == 0)
			if onSeam then
				c, w = 0, 2 * math.max(math.abs(a), math.abs(b))
			end
			if not onSeam or ctx.Prefix == "B" then
				local half = if axis == "X"
					then Vector3.new(line, (sill + top) / 2, c)
					else Vector3.new(c, (sill + top) / 2, line)
				local center = if onSeam then half else Pieces.P(ctx, half)
				local along = if axis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
				local kind = if sill > 0 then "Window" else "Door"
				local prefix = if onSeam then "C" else ctx.Prefix
				Pieces.RegisterDoor(
					`{prefix}.{kind}@{math.floor(center.X + 0.5)},{math.floor(center.Z + 0.5)}`,
					center,
					along,
					w,
					top - sill
				)
			end
		end
	end
end

local H = Style.Dims.CeilingHeight
local T = Style.Dims.WallThickness

function Pieces.NewCtx(
	prefix: string,
	team: string?,
	mirror: boolean,
	folders: Folders,
	anchor: BasePart
): Ctx
	return { Prefix = prefix, Team = team, Mirror = mirror, Folders = folders, Anchor = anchor }
end

function Pieces.P(ctx: Ctx, v: Vector3): Vector3
	if ctx.Mirror then
		return Vector3.new(-v.X, v.Y, v.Z)
	end
	return v
end

function Pieces.Id(ctx: Ctx, name: string): string
	return ctx.Prefix .. "." .. name
end

-- Mirror a direction/normal (used for SurfaceGui faces).
function Pieces.FaceFromVector(v: Vector3): Enum.NormalId
	if v.X > 0.5 then
		return Enum.NormalId.Right
	elseif v.X < -0.5 then
		return Enum.NormalId.Left
	elseif v.Z > 0.5 then
		return Enum.NormalId.Back
	elseif v.Z < -0.5 then
		return Enum.NormalId.Front
	elseif v.Y > 0.5 then
		return Enum.NormalId.Top
	end
	return Enum.NormalId.Bottom
end

function Pieces.ApplySurface(part: BasePart, surf: Surface)
	part.Color = surf.Color
	part.Material = surf.Material
	part.Transparency = surf.Transparency or 0
	part.Reflectance = surf.Reflectance or 0
	part.CanCollide = if surf.CanCollide == nil then true else surf.CanCollide
	part.CanQuery = if surf.CanQuery == nil then true else surf.CanQuery
	part.CastShadow = if surf.CastShadow == nil then true else surf.CastShadow
end

-- Raw part in world space (no mirroring). Everything else goes through this so we can count parts.
function Pieces.RawPart(name: string, cframe: CFrame, size: Vector3, surf: Surface, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	Pieces.ApplySurface(part, surf)
	part.Parent = parent
	Pieces.Stats.Parts += 1
	return part
end

-- Axis-aligned box from two corners (half coordinates; mirrored by ctx).
-- Every wall box built so far (world space). Used to stop two collinear walls overlapping, which
-- happens where two rooms share an edge or both mirrored halves build the same wall: coplanar
-- faces z-fight. Cleared by Pieces.ResetWallRegistry() before a full rebuild.
type WallBox = { Lo: Vector3, Hi: Vector3, Part: Part }
local wallBoxes: { WallBox } = {}
local MIN_PIECE = 0.05

function Pieces.ResetWallRegistry()
	table.clear(wallBoxes)
end

local function axisOf(lo: Vector3, hi: Vector3): "X" | "Z"
	return if (hi.X - lo.X) >= (hi.Z - lo.Z) then "X" else "Z"
end

-- Remove from [lo, hi] (along its length axis) every interval already covered by a collinear wall
-- that fully contains it across the other two axes. Returns the remaining boxes and, if nothing is
-- left, the existing part that covers it.
local function clipWall(lo: Vector3, hi: Vector3): ({ { Vector3 } }, Part?)
	local axis = axisOf(lo, hi)
	local function len(v: Vector3): number
		return if axis == "X" then v.X else v.Z
	end
	local function cross(v: Vector3): number
		return if axis == "X" then v.Z else v.X
	end
	local pieces: { { number } } = { { len(lo), len(hi) } }
	local cover: Part? = nil
	for _, e in wallBoxes do
		if
			axisOf(e.Lo, e.Hi) == axis
			and cross(e.Lo) <= cross(lo) + 1e-3
			and cross(e.Hi) >= cross(hi) - 1e-3
			and e.Lo.Y <= lo.Y + 1e-3
			and e.Hi.Y >= hi.Y - 1e-3
		then
			local ea, eb = len(e.Lo), len(e.Hi)
			local nextPieces: { { number } } = {}
			for _, p in pieces do
				local a, b = p[1], p[2]
				if eb <= a or ea >= b then
					table.insert(nextPieces, p)
				else
					cover = e.Part
					if ea > a then
						table.insert(nextPieces, { a, ea })
					end
					if eb < b then
						table.insert(nextPieces, { eb, b })
					end
				end
			end
			pieces = nextPieces
		end
	end
	local out: { { Vector3 } } = {}
	for _, p in pieces do
		if p[2] - p[1] >= MIN_PIECE then
			if axis == "X" then
				table.insert(out, { Vector3.new(p[1], lo.Y, lo.Z), Vector3.new(p[2], hi.Y, hi.Z) })
			else
				table.insert(out, { Vector3.new(lo.X, lo.Y, p[1]), Vector3.new(hi.X, hi.Y, p[2]) })
			end
		end
	end
	return out, cover
end

function Pieces.Block(ctx: Ctx, name: string, a: Vector3, b: Vector3, surf: Surface, parent: Instance?): Part
	local pa, pb = Pieces.P(ctx, a), Pieces.P(ctx, b)
	local lo = Vector3.new(math.min(pa.X, pb.X), math.min(pa.Y, pb.Y), math.min(pa.Z, pb.Z))
	local hi = Vector3.new(math.max(pa.X, pb.X), math.max(pa.Y, pb.Y), math.max(pa.Z, pb.Z))
	local folder = parent or ctx.Folders.Structure
	if name ~= "Wall" then
		return Pieces.RawPart(name, CFrame.new((lo + hi) / 2), hi - lo, surf, folder)
	end
	local boxes, cover = clipWall(lo, hi)
	if #boxes == 0 and cover then
		return cover -- exact duplicate of an existing wall: reuse it
	end
	local largest: Part? = nil
	for _, box in boxes do
		local blo, bhi = box[1], box[2]
		local part = Pieces.RawPart(name, CFrame.new((blo + bhi) / 2), bhi - blo, surf, folder)
		table.insert(wallBoxes, { Lo = blo, Hi = bhi, Part = part })
		if not largest or part.Size.Magnitude > largest.Size.Magnitude then
			largest = part
		end
	end
	return largest or Pieces.RawPart(name, CFrame.new((lo + hi) / 2), hi - lo, surf, folder)
end

-- Box from centre + size.
function Pieces.BoxAt(
	ctx: Ctx,
	name: string,
	center: Vector3,
	size: Vector3,
	surf: Surface,
	parent: Instance?
): Part
	return Pieces.Block(ctx, name, center - size / 2, center + size / 2, surf, parent)
end

-- Cylinder along a world axis. Roblox cylinders run along their local X axis.
function Pieces.Cylinder(
	ctx: Ctx,
	name: string,
	center: Vector3,
	length: number,
	diameter: number,
	axis: "X" | "Y" | "Z",
	surf: Surface,
	parent: Instance?
): Part
	local rot = CFrame.identity
	if axis == "Y" then
		rot = CFrame.Angles(0, 0, math.pi / 2)
	elseif axis == "Z" then
		rot = CFrame.Angles(0, math.pi / 2, 0)
	end
	local part = Pieces.RawPart(
		name,
		CFrame.new(Pieces.P(ctx, center)) * rot,
		Vector3.new(length, diameter, diameter),
		surf,
		parent or ctx.Folders.Props
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Walls are built along a line with door/window openings:
--   { c = centre, w = width, h = top of the opening (default door height), s = sill height (window /
--   vent shortcut; default 0 = door) }. A lintel fills above, a sill wall fills below.
export type WallOpts = { Thickness: number?, Penetrable: boolean?, Height: number? }

local function wallSegments(
	from: number,
	to: number,
	openings: { Opening }?,
	height: number,
	emit: (a: number, b: number, y0: number, y1: number) -> ()
)
	local ops = table.clone(openings or {})
	table.sort(ops, function(p, q)
		return p.c < q.c
	end)
	local cur = from
	for _, op in ops do
		local a, b = op.c - op.w / 2, op.c + op.w / 2
		if a > cur then
			emit(cur, a, 0, height)
		end
		local lo, hi = math.max(a, from), math.min(b, to)
		local top = op.h or Style.Dims.DoorHeight
		if top < height then
			emit(lo, hi, top, height)
		end
		local sill = op.s or 0
		if sill > 0 then
			emit(lo, hi, 0, sill)
		end
		cur = math.max(cur, b)
	end
	if cur < to then
		emit(cur, to, 0, height)
	end
end

-- Wall ends reach into the crossing wall to close the corner, but stop JOIN_EPS short of its far
-- face: an end face exactly on that face z-fights (visible flicker where two rooms meet).
local JOIN_EPS = 0.02

local function pad(v: number, dir: number, t: number): number
	if v == 0 then
		return v
	end
	return v + dir * (t / 2 - JOIN_EPS)
end

local SEAM_SPACING = 4

-- Penetrable drywall: tag every piece and add taped seams on both faces so players learn the look.
local function markPenetrable(
	ctx: Ctx,
	part: BasePart,
	along: "X" | "Z",
	a: number,
	b: number,
	y0: number,
	y1: number,
	line: number,
	t: number
)
	part:AddTag("Penetrable")
	if y1 - y0 < 2 then
		return
	end
	local n = math.floor((b - a) / SEAM_SPACING)
	for i = 1, n do
		local pos = a + i * SEAM_SPACING
		if b - pos > 0.6 then
			for _, side in { -1, 1 } do
				local off = line + side * (t / 2 + 0.03)
				local size = if along == "Z"
					then Vector3.new(0.06, y1 - y0, 0.2)
					else Vector3.new(0.2, y1 - y0, 0.06)
				local center = if along == "Z"
					then Vector3.new(off, (y0 + y1) / 2, pos)
					else Vector3.new(pos, (y0 + y1) / 2, off)
				Pieces.BoxAt(ctx, "Seam", center, size, Style.Surf.Seam, ctx.Folders.Structure)
			end
		end
	end
end

-- Wall along Z at a fixed x, from z1 to z2.
function Pieces.WallX(
	ctx: Ctx,
	x: number,
	z1: number,
	z2: number,
	openings: { Opening }?,
	surf: Surface,
	opts: WallOpts?
)
	local o = opts or {}
	local t = o.Thickness or T
	local hgt = o.Height or H
	local lo, hi = math.min(z1, z2), math.max(z1, z2)
	registerOpenings(ctx, "X", x, openings, hgt)
	wallSegments(pad(lo, -1, t), pad(hi, 1, t), openings, hgt, function(a, b, y0, y1)
		local part =
			Pieces.Block(ctx, "Wall", Vector3.new(x - t / 2, y0, a), Vector3.new(x + t / 2, y1, b), surf)
		if o.Penetrable then
			markPenetrable(ctx, part, "Z", a, b, y0, y1, x, t)
		end
	end)
end

-- Wall along X at a fixed z, from x1 to x2.
function Pieces.WallZ(
	ctx: Ctx,
	z: number,
	x1: number,
	x2: number,
	openings: { Opening }?,
	surf: Surface,
	opts: WallOpts?
)
	local o = opts or {}
	local t = o.Thickness or T
	local hgt = o.Height or H
	local lo, hi = math.min(x1, x2), math.max(x1, x2)
	registerOpenings(ctx, "Z", z, openings, hgt)
	wallSegments(pad(lo, -1, t), pad(hi, 1, t), openings, hgt, function(a, b, y0, y1)
		local part =
			Pieces.Block(ctx, "Wall", Vector3.new(a, y0, z - t / 2), Vector3.new(b, y1, z + t / 2), surf)
		if o.Penetrable then
			markPenetrable(ctx, part, "X", a, b, y0, y1, z, t)
		end
	end)
end

-- Boarded-up look for a locked door: three slightly crooked planks nailed across each face and a
-- "NO ACCESS" plate, so it reads as locked. Pure decoration: no collision, no queries (bullets still
-- hit the penetrable door behind them).
local PLANK: Surface = {
	Color = Color3.fromRGB(128, 100, 66),
	Material = Enum.Material.WoodPlanks,
	CanCollide = false,
	CanQuery = false,
}
local SIGN_PLATE: Surface = {
	Color = Color3.fromRGB(196, 170, 60),
	Material = Enum.Material.SmoothPlastic,
	CanCollide = false,
	CanQuery = false,
	CastShadow = false,
}
local PLANKS = { { Y = -2.1, Tilt = 7 }, { Y = 0.9, Tilt = -5 }, { Y = 2.5, Tilt = 4 } }

local function boardUp(ctx: Ctx, center: Vector3, size: Vector3, alongX: boolean)
	local width = if alongX then size.X else size.Z
	local depth = if alongX then size.Z else size.X
	local normalBlue = if alongX then Vector3.zAxis else Vector3.xAxis
	for _, side in { 1, -1 } do
		local out = normalBlue * side * (depth / 2 + 0.07)
		for i, plank in PLANKS do
			local pos = Pieces.P(ctx, center + out + Vector3.new(0, plank.Y, 0))
			local tilt = math.rad(plank.Tilt * (if ctx.Mirror then -side else side))
			local cf = if alongX
				then CFrame.new(pos) * CFrame.Angles(0, 0, tilt)
				else CFrame.new(pos) * CFrame.Angles(tilt, 0, 0)
			local plankSize = if alongX
				then Vector3.new(width + 0.8, 0.45, 0.12)
				else Vector3.new(0.12, 0.45, width + 0.8)
			Pieces.RawPart(`DoorPlank{i}`, cf, plankSize, PLANK, ctx.Folders.Props)
		end
		-- Sign plate between the lower planks, text facing out of the door.
		local signPos =
			Pieces.P(ctx, center + normalBlue * side * (depth / 2 + 0.16) + Vector3.new(0, -0.6, 0))
		local signSize = if alongX then Vector3.new(1.6, 0.6, 0.04) else Vector3.new(0.04, 0.6, 1.6)
		local sign = Pieces.RawPart("DoorSign", CFrame.new(signPos), signSize, SIGN_PLATE, ctx.Folders.Props)
		local outWorld = Pieces.P(ctx, normalBlue * side) - Pieces.P(ctx, Vector3.zero)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Pieces.FaceFromVector(outWorld)
		gui.CanvasSize = Vector2.new(160, 60)
		gui.LightInfluence = 1
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "NO ACCESS"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(30, 28, 24)
		label.Parent = gui
		gui.Parent = sign
	end
end

-- Locked wooden door filling a wall opening (penetrable, collidable).
function Pieces.WoodDoor(ctx: Ctx, center: Vector3, size: Vector3)
	local door = Pieces.BoxAt(ctx, "WoodDoor", center, size, Style.Surf.WoodDoor, ctx.Folders.Props)
	door:AddTag("Penetrable")
	local alongX = size.X > size.Z
	local knob = if alongX then Vector3.new(size.X / 2 - 0.5, 0, 0) else Vector3.new(0, 0, size.Z / 2 - 0.5)
	Pieces.BoxAt(
		ctx,
		"Knob",
		center - Vector3.new(0, 0.2, 0) + knob,
		Vector3.new(0.3, 0.3, 0.3) + (if alongX then Vector3.new(0, 0, size.Z) else Vector3.new(size.X, 0, 0)),
		Style.Surf.Knob,
		ctx.Folders.Props
	)
	boardUp(ctx, center, size, alongX)
	return door
end

function Pieces.Floor(ctx: Ctx, x1: number, z1: number, x2: number, z2: number, surf: Surface)
	Pieces.Block(ctx, "Floor", Vector3.new(x1, -1, z1), Vector3.new(x2, 0, z2), surf)
end

function Pieces.Ceiling(ctx: Ctx, x1: number, z1: number, x2: number, z2: number, y: number, surf: Surface)
	Pieces.Block(ctx, "Ceiling", Vector3.new(x1, y, z1), Vector3.new(x2, y + 1, z2), surf)
end

-- Lights ---------------------------------------------------------------------------------------

function Pieces.NewLight(
	className: string,
	parent: Instance,
	preset: LightPreset,
	overrides: { [string]: any }?
): Light
	local light = Instance.new(className) :: Light
	light.Color = preset.Color
	light.Brightness = preset.Brightness * (if preset.NoScale then 1 else Style.LightScale)
	light.Shadows = preset.Shadows == true
	local l = light :: any
	l.Range = preset.Range
	if preset.Angle and (className == "SpotLight" or className == "SurfaceLight") then
		l.Angle = preset.Angle
	end
	if className == "SpotLight" or className == "SurfaceLight" then
		l.Face = Enum.NormalId.Bottom
	end
	if overrides then
		for key, value in overrides do
			l[key] = value
		end
	end
	light:SetAttribute("BaseBrightness", light.Brightness)
	light.Parent = parent
	Pieces.Stats.Lights += 1
	if light.Shadows then
		Pieces.Stats.ShadowLights += 1
	end
	return light
end

-- Client AmbienceController flickers every light with attribute Flicker = true (also tagged for a
-- cheap lookup). The fixture part keeps its "on" colour in OnColor so the tube dims with the light.
function Pieces.MarkFlicker(light: Light)
	light:SetAttribute("Flicker", true)
	CollectionService:AddTag(light, "FlickerLight")
end

-- Light on an attachment (no extra part): fills and other "invisible" sources.
function Pieces.AttachLight(
	ctx: Ctx,
	name: string,
	className: string,
	pos: Vector3,
	preset: LightPreset
): Light
	local att = Instance.new("Attachment")
	att.Name = name
	att.Parent = ctx.Anchor
	att.Position = Pieces.P(ctx, pos) - ctx.Anchor.Position
	return Pieces.NewLight(className, att, preset)
end

-- Ceiling fluorescent tube. `lit = false` builds a dead fixture (dim rooms: only some tubes work).
function Pieces.Tube(
	ctx: Ctx,
	name: string,
	pos: Vector3,
	axis: "X" | "Z",
	lit: boolean,
	preset: LightPreset?
): (Part, Light?)
	local y = pos.Y
	local len = 4.5
	local size = if axis == "X" then Vector3.new(len, 0.3, 0.8) else Vector3.new(0.8, 0.3, len)
	local hsize = if axis == "X" then Vector3.new(len + 0.6, 0.15, 1.4) else Vector3.new(1.4, 0.15, len + 0.6)
	-- Housing sits flush against the ceiling; the tube hangs just below it.
	local center = Vector3.new(pos.X, y - 0.2, pos.Z)
	Pieces.BoxAt(
		ctx,
		name .. "Housing",
		Vector3.new(pos.X, y - 0.075, pos.Z),
		hsize,
		Style.Surf.Housing,
		ctx.Folders.Lights
	)
	local tube = Pieces.BoxAt(
		ctx,
		name,
		center,
		size,
		if lit then Style.Surf.TubeOn else Style.Surf.TubeOff,
		ctx.Folders.Lights
	)
	tube:SetAttribute("OnColor", Style.Surf.TubeOn.Color)
	local light: Light? = nil
	if lit and preset then
		light = Pieces.NewLight("SurfaceLight", tube, preset)
	end
	return tube, light
end

-- Lamp mounted above a doorway on the dark-room side. `into` is the unit direction from the wall into
-- the room (half coordinates). kind "Exit" = green exit sign, "Cage" = caged bulb. Both shine down so
-- anyone standing in the doorway is lit and backlit against the corridor beyond.
function Pieces.DoorLamp(
	ctx: Ctx,
	name: string,
	pos: Vector3,
	into: Vector3,
	kind: "Exit" | "Cage"
): (BasePart, Light)
	local folder = ctx.Folders.Lights
	local intoWorld = Pieces.P(ctx, into)
	local alongX = math.abs(into.X) > 0.5 -- wall normal is along X (door in a WallX)
	if kind == "Exit" then
		local size = if alongX then Vector3.new(0.35, 0.9, 2.4) else Vector3.new(2.4, 0.9, 0.35)
		local sign = Pieces.BoxAt(ctx, name, pos, size, Style.Surf.ExitSign, folder)
		sign:SetAttribute("OnColor", Style.Surf.ExitSign.Color)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "ExitText"
		gui.Face = Pieces.FaceFromVector(intoWorld)
		gui.LightInfluence = 0
		gui.CanvasSize = Vector2.new(240, 90)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "EXIT"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(235, 255, 240)
		label.Parent = gui
		gui.Parent = sign
		local light = Pieces.NewLight("SpotLight", sign, Style.Light.ExitLamp)
		return sign, light
	end
	-- Caged bulb on a small bracket.
	local bracketSize = if alongX then Vector3.new(0.9, 0.25, 0.4) else Vector3.new(0.4, 0.25, 0.9)
	Pieces.BoxAt(
		ctx,
		name .. "Bracket",
		pos + Vector3.new(0, 0.55, 0) - into * 0.25,
		bracketSize,
		Style.Surf.Housing,
		folder
	)
	Pieces.BoxAt(ctx, name .. "Cage", pos, Vector3.new(1.15, 1.15, 1.15), Style.Surf.Cage, folder)
	local bulb = Pieces.BoxAt(ctx, name, pos, Vector3.new(0.85, 0.85, 0.85), Style.Surf.Bulb, folder)
	bulb.Shape = Enum.PartType.Ball
	bulb:SetAttribute("OnColor", Style.Surf.Bulb.Color)
	local light = Pieces.NewLight("SpotLight", bulb, Style.Light.CageLamp)
	return bulb, light
end

-- Unbreakable emergency light: small neon box + non-shadow point light.
function Pieces.Emergency(
	ctx: Ctx,
	name: string,
	pos: Vector3,
	color: Color3,
	preset: LightPreset?
): (Part, Light)
	local box = Pieces.BoxAt(ctx, name, pos, Vector3.new(1.2, 0.5, 1.2), {
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	}, ctx.Folders.Lights)
	box:SetAttribute("Emergency", true)
	local light = Pieces.NewLight("PointLight", box, preset or Style.Light.Emergency)
	return box, light
end

-- Dust motes + faint haze that only show where light hits them (LightInfluence = 1), which makes
-- doorway cones and light shafts read as volumetric beams.
function Pieces.Dust(
	ctx: Ctx,
	name: string,
	center: Vector3,
	size: Vector3,
	heavy: boolean?
): { ParticleEmitter }
	local vol = Pieces.BoxAt(ctx, name, center, size, Style.Surf.Invisible, ctx.Folders.Fx)
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Texture = Style.Textures.Sparkle
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Rate = if heavy then 6 else 3
	motes.Lifetime = NumberRange.new(6, 10)
	motes.Speed = NumberRange.new(0.05, 0.25)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0, -0.02, 0)
	motes.Drag = 0.5
	motes.Size = NumberSequence.new(0.07)
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 245, 220))
	motes.LightEmission = 0
	motes.LightInfluence = 1
	motes.Parent = vol

	local haze = Instance.new("ParticleEmitter")
	haze.Name = "Haze"
	haze.Texture = Style.Textures.Smoke
	haze.Shape = Enum.ParticleEmitterShape.Box
	haze.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	haze.Rate = if heavy then 0.9 else 0.5
	haze.Lifetime = NumberRange.new(8, 12)
	haze.Speed = NumberRange.new(0, 0.15)
	haze.SpreadAngle = Vector2.new(180, 180)
	haze.Size = NumberSequence.new(7, 9)
	haze.Rotation = NumberRange.new(0, 360)
	haze.RotSpeed = NumberRange.new(-4, 4)
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, if heavy then 0.88 else 0.92),
		NumberSequenceKeypoint.new(1, 1),
	})
	haze.Color = ColorSequence.new(Color3.fromRGB(220, 215, 200))
	haze.LightEmission = 0
	haze.LightInfluence = 1
	haze.Parent = vol
	return { motes, haze }
end

-- Core pedestal. Returns the CFrame of the top surface centre (where the Core rests).
function Pieces.Pedestal(ctx: Ctx, pos: Vector3, teamColor: Color3): CFrame
	local folder = ctx.Folders.Props
	Pieces.BoxAt(
		ctx,
		"PedestalBase",
		pos + Vector3.new(0, 0.5, 0),
		Vector3.new(6, 1, 6),
		Style.Surf.Pedestal,
		folder
	)
	Pieces.BoxAt(
		ctx,
		"PedestalColumn",
		pos + Vector3.new(0, 2, 0),
		Vector3.new(3, 2, 3),
		Style.Surf.Pedestal,
		folder
	)
	Pieces.BoxAt(ctx, "PedestalRing", pos + Vector3.new(0, 2.6, 0), Vector3.new(3.5, 0.25, 3.5), {
		Color = teamColor,
		Material = Enum.Material.Neon,
		CastShadow = false,
	}, folder)
	Pieces.BoxAt(ctx, "PedestalFloorRing", pos + Vector3.new(0, 0.05, 0), Vector3.new(9, 0.06, 9), {
		Color = teamColor,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, folder)
	return CFrame.new(Pieces.P(ctx, pos + Vector3.new(0, 3, 0)))
end

-- Office cubicle cluster: a "+" of partitions with four desks in the quadrants.
function Pieces.Cubicle(ctx: Ctx, cx: number, cz: number, height: number)
	local folder = ctx.Folders.Props
	local c = Vector3.new(cx, height / 2, cz)
	Pieces.BoxAt(ctx, "Partition", c, Vector3.new(10, height, 0.5), Style.Surf.Partition, folder)
		:AddTag("Penetrable")
	Pieces.BoxAt(ctx, "Partition", c, Vector3.new(0.5, height, 10), Style.Surf.Partition, folder)
		:AddTag("Penetrable")
	Pieces.BoxAt(
		ctx,
		"PartitionTrim",
		Vector3.new(cx, height + 0.05, cz),
		Vector3.new(10.1, 0.1, 0.6),
		Style.Surf.PartitionTrim,
		folder
	)
	for _, q in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, 1) } do
		local dc = Vector3.new(cx + q.X * 2.6, 1.5, cz + q.Z * 2.6)
		Pieces.BoxAt(ctx, "Desk", dc, Vector3.new(4.2, 3, 4.2), Style.Surf.Desk, folder)
	end
end

return Pieces

--!strict
-- Environmental detail: trim, services and signage on the long walls so each stretch reads as a
-- place (office, maintenance, base) instead of one repeated texture.
--
-- Rules (gameplay must not change):
--   * Everything is decoration from Style.Detail: CanCollide false, CanQuery false (bullets and
--     hitscan pass through), no new cover. The only solid pieces are a few filing cabinets and a
--     water cooler pressed against walls (tall / small, not cover, not jump spots).
--   * Nothing protrudes more than ~0.6 studs from a wall (except the cabinets), nothing sits in a
--     doorway, on a perch, or across a sniper line.
--   * No coplanar faces: every piece starts GAP off the wall face, layered pieces step further out,
--     and runs stop short of corners and door jambs. (ZFightFix still runs afterwards.)
--
-- Coordinates are Blue-half (x <= 0); Pieces mirrors them for Red.

local Style = require(script.Parent.Style)
local Pieces = require(script.Parent.Pieces)

type Ctx = Pieces.Ctx
type Surface = Style.Surface

local Detail = {}

local D = Style.Detail
local H = Style.Dims.CeilingHeight
local MH = Style.Dims.MaintCeilingHeight
local HALF_T = Style.Dims.WallThickness / 2

local GAP = 0.03 -- distance between a wall face and the back of anything mounted on it
local END_INSET = 0.06 -- runs stop this far from corners
local JAMB = 0.3 -- and this far from door / window openings

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- A wall face. Axis "Z": the wall runs along X at a fixed z (u = x). Axis "X": runs along Z at a
-- fixed x (u = z). Plane = the face's coordinate, Dir = +1 / -1 pointing into the room.
type Face = { Axis: "X" | "Z", Plane: number, Dir: number }

-- Face of the wall on `line` that looks towards `dir`.
local function face(axis: "X" | "Z", line: number, dir: number): Face
	return { Axis = axis, Plane = line + dir * HALF_T, Dir = dir }
end

local function at(f: Face, u: number, y: number, d: number): Vector3
	if f.Axis == "Z" then
		return v(u, y, f.Plane + f.Dir * d)
	end
	return v(f.Plane + f.Dir * d, y, u)
end

local function dims(f: Face, len: number, h: number, depth: number): Vector3
	if f.Axis == "Z" then
		return v(len, h, depth)
	end
	return v(depth, h, len)
end

local function box(ctx: Ctx, name: string, center: Vector3, size: Vector3, surf: Surface): Part
	return Pieces.BoxAt(ctx, name, center, size, surf, ctx.Folders.Detail)
end

-- Mount a box on a face: centred at u (along) and y, `depth` deep, `off` studs further out than GAP.
local function mount(
	ctx: Ctx,
	f: Face,
	name: string,
	u: number,
	y: number,
	len: number,
	h: number,
	depth: number,
	surf: Surface,
	off: number?
): Part
	local d = GAP + (off or 0) + depth / 2
	return box(ctx, name, at(f, u, y, d), dims(f, len, h, depth), surf)
end

-- Continuous segments of [a, b] that avoid each opening { c, w } (with jamb clearance).
type Gap = { c: number, w: number }
local function runs(a: number, b: number, gaps: { Gap }?): { { number } }
	local out: { { number } } = {}
	local cur = a + END_INSET
	local stop = b - END_INSET
	local sorted = table.clone(gaps or {})
	table.sort(sorted, function(p, q)
		return p.c < q.c
	end)
	for _, g in sorted do
		local lo, hi = g.c - g.w / 2 - JAMB, g.c + g.w / 2 + JAMB
		if lo > cur then
			table.insert(out, { cur, math.min(lo, stop) })
		end
		cur = math.max(cur, hi)
	end
	if stop > cur then
		table.insert(out, { cur, stop })
	end
	return out
end

local function strip(
	ctx: Ctx,
	f: Face,
	name: string,
	segs: { { number } },
	y0: number,
	y1: number,
	depth: number,
	surf: Surface,
	off: number?
)
	for _, s in segs do
		if s[2] - s[1] > 0.2 then
			mount(ctx, f, name, (s[1] + s[2]) / 2, (y0 + y1) / 2, s[2] - s[1], y1 - y0, depth, surf, off)
		end
	end
end

-- Plate with text (SurfaceGui on the face that looks into the room).
local function sign(
	ctx: Ctx,
	f: Face,
	u: number,
	y: number,
	w: number,
	h: number,
	text: string,
	plate: Surface,
	textColor: Color3
)
	local part = mount(ctx, f, "Sign", u, y, w, h, 0.08, plate, 0.02)
	local normal = if f.Axis == "Z" then v(0, 0, f.Dir) else v(f.Dir, 0, 0)
	if ctx.Mirror then
		normal = v(-normal.X, 0, normal.Z)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = Pieces.FaceFromVector(normal)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Arial
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.Parent = label
	label.Parent = gui
end

-- Pieces -----------------------------------------------------------------------------------------

-- Office trim: baseboard, lower wainscot panel, chair rail.
local function officeTrim(ctx: Ctx, f: Face, segs: { { number } })
	strip(ctx, f, "Wainscot", segs, 0.6, 3.2, 0.04, D.Wainscot)
	strip(ctx, f, "Baseboard", segs, 0.02, 0.6, 0.14, D.Baseboard)
	strip(ctx, f, "ChairRail", segs, 3.2, 3.45, 0.12, D.ChairRail)
end

local function pilaster(ctx: Ctx, f: Face, u: number, height: number)
	mount(ctx, f, "Pilaster", u, height / 2, 1.6, height - 0.08, 0.32, D.Pilaster)
	mount(ctx, f, "PilasterBase", u, 0.35, 1.9, 0.66, 0.1, D.Baseboard, 0.32)
end

-- Irregular water stain: a few overlapping translucent patches, each a step further out.
local function stain(ctx: Ctx, f: Face, u: number, y: number, scale: number, off: number)
	mount(ctx, f, "Stain", u, y, 2.2 * scale, 3.4 * scale, 0.01, D.StainLight, off)
	mount(
		ctx,
		f,
		"Stain",
		u + 0.4 * scale,
		y - 0.6 * scale,
		1.2 * scale,
		2.6 * scale,
		0.01,
		D.StainDark,
		off + 0.012
	)
	mount(
		ctx,
		f,
		"Stain",
		u - 0.5 * scale,
		y + 0.9 * scale,
		0.9 * scale,
		1.1 * scale,
		0.01,
		D.StainLight,
		off + 0.024
	)
end

local function noticeBoard(ctx: Ctx, f: Face, u: number, y: number)
	mount(ctx, f, "BoardFrame", u, y, 3, 2, 0.08, D.BoardFrame)
	mount(ctx, f, "Cork", u, y, 2.7, 1.7, 0.04, D.Cork, 0.08)
	local papers = {
		{ -0.8, 0.25, 0.6, 0.8, D.Paper },
		{ 0.05, 0.35, 0.55, 0.7, D.PaperYellow },
		{ 0.8, 0.15, 0.6, 0.85, D.Paper },
		{ -0.3, -0.45, 0.7, 0.5, D.Paper },
		{ 0.6, -0.5, 0.45, 0.45, D.PaperYellow },
	}
	for i, p in papers do
		mount(ctx, f, "Paper", u + p[1], y + p[2], p[3], p[4], 0.01, p[5], 0.12 + i * 0.004)
	end
end

local function fireCabinet(ctx: Ctx, f: Face, u: number)
	-- hung clear above the chair rail (top 3.45): cabinet y 3.6..6.2
	mount(ctx, f, "FireCabinet", u, 4.9, 1.5, 2.6, 0.42, D.FireCabinet)
	mount(ctx, f, "Extinguisher", u, 4.6, 0.55, 1.6, 0.3, D.Extinguisher, 0.05)
	-- (the glass front was removed, owner 2026-10-16)
end

local function radiator(ctx: Ctx, f: Face, u: number, len: number)
	mount(ctx, f, "Radiator", u, 1.45, len, 1.9, 0.32, D.Radiator, 0.2)
	local fins = math.floor(len / 0.5)
	for i = 1, fins - 1 do
		mount(ctx, f, "RadiatorFin", u - len / 2 + i * 0.5, 1.45, 0.08, 1.7, 0.04, D.RadiatorCap, 0.52)
	end
	mount(ctx, f, "RadiatorPipe", u - len / 2 - 0.3, 0.6, 0.2, 1.1, 0.2, D.RadiatorCap, 0.26)
end

local function clock(ctx: Ctx, f: Face, u: number, y: number)
	mount(ctx, f, "ClockRim", u, y, 1.3, 1.3, 0.1, D.ClockRim)
	mount(ctx, f, "ClockFace", u, y, 1.1, 1.1, 0.02, D.ClockFace, 0.1)
	mount(ctx, f, "ClockHand", u, y + 0.22, 0.06, 0.44, 0.02, D.ClockHand, 0.12)
	mount(ctx, f, "ClockHand", u + 0.15, y, 0.3, 0.06, 0.02, D.ClockHand, 0.14)
end

-- Tall, shallow, solid filing cabinet against a wall (not cover, not a jump spot).
-- 2.85 wide x 6.6 tall x 2.25 deep (50% bigger, owner 2026-10-16); the top is at y 6.6.
-- Stands 0.13 off the wall, in front of the wainscot / chair rail (no intersecting trim).
local function filingCabinet(ctx: Ctx, f: Face, u: number)
	mount(ctx, f, "FilingCabinet", u, 3.3, 2.85, 6.6, 2.25, D.FilingCabinet, 0.13)
	for i = 1, 4 do
		mount(ctx, f, "DrawerLine", u, 1.425 + (i - 1) * 1.575, 2.4, 0.06, 0.02, D.DrawerLine, 2.38)
	end
end

local function wallGrille(ctx: Ctx, f: Face, u: number, y: number, w: number, h: number)
	mount(ctx, f, "GrilleFrame", u, y, w, h, 0.08, D.GrilleFrame)
	local slats = math.max(2, math.floor(h / 0.25))
	for i = 1, slats - 1 do
		mount(ctx, f, "GrilleSlat", u, y - h / 2 + i * (h / slats), w - 0.2, 0.06, 0.03, D.GrilleSlat, 0.08)
	end
end

-- Electrical panel with a conduit up to the ceiling and small indicator lamps (no light source).
local function panel(ctx: Ctx, f: Face, u: number, y: number, ceiling: number, surf: Surface)
	mount(ctx, f, "Panel", u, y, 1.8, 2.6, 0.38, surf)
	mount(ctx, f, "PanelDoorLine", u, y, 0.05, 2.3, 0.02, D.PanelDark, 0.38)
	for i, ind in { D.IndicatorGreen, D.IndicatorAmber, D.IndicatorGreen } do
		mount(ctx, f, "Indicator", u - 0.5 + (i - 1) * 0.5, y + 0.95, 0.14, 0.14, 0.03, ind, 0.38)
	end
	local top = y + 1.3
	mount(ctx, f, "Conduit", u + 0.5, (top + ceiling) / 2, 0.22, ceiling - top - 0.06, 0.22, D.Conduit, 0.04)
end

-- Horizontal conduit with brackets every `spacing` studs.
local function conduitRun(ctx: Ctx, f: Face, segs: { { number } }, y: number, off: number, spacing: number)
	strip(ctx, f, "Conduit", segs, y - 0.11, y + 0.11, 0.22, D.Conduit, off)
	for _, s in segs do
		local u = s[1] + 1
		while u < s[2] - 0.5 do
			mount(ctx, f, "Bracket", u, y, 0.14, 0.42, off + 0.26, D.Bracket)
			u += spacing
		end
	end
end

-- Cable tray: a shallow open tray with a cable bundle in it.
local function cableTray(ctx: Ctx, f: Face, segs: { { number } }, y: number)
	strip(ctx, f, "TrayBase", segs, y - 0.04, y + 0.04, 0.9, D.Bracket, 0.05)
	strip(ctx, f, "TrayLip", segs, y + 0.04, y + 0.3, 0.05, D.Bracket, 0.9)
	strip(ctx, f, "Cables", segs, y + 0.05, y + 0.27, 0.5, D.Cable, 0.25)
end

-- Yellow / black kick plate beside a maintenance door (horizontal bands, no rotation).
local function hazardPlate(ctx: Ctx, f: Face, u: number)
	for i = 0, 5 do
		local surf = if i % 2 == 0 then D.HazardYellow else D.HazardBlack
		mount(ctx, f, "Hazard", u, 0.25 + i * 0.4, 1, 0.4, 0.05, surf, 0.06)
	end
end

local function streak(ctx: Ctx, f: Face, u: number, y0: number, y1: number, w: number)
	mount(ctx, f, "Streak", u, (y0 + y1) / 2, w, y1 - y0, 0.01, D.Streak, 0.005)
end

local function rust(ctx: Ctx, f: Face, u: number, y: number)
	mount(ctx, f, "Rust", u, y, 1.6, 0.9, 0.01, D.Rust, 0.02)
	mount(ctx, f, "Streak", u + 0.2, y - 1.2, 0.35, 1.6, 0.01, D.Rust, 0.032)
end

-- Missing / stained ceiling tiles (office). Thin plates just below the ceiling underside.
local function ceilingHole(ctx: Ctx, x: number, z: number, sx: number, sz: number)
	box(ctx, "CeilingHole", v(x, H - 0.05, z), v(sx, 0.04, sz), D.CeilingHole)
end

local function ceilingStain(ctx: Ctx, x: number, z: number, sx: number, sz: number)
	box(ctx, "CeilingStain", v(x, H - 0.04, z), v(sx, 0.02, sz), D.CeilingStain)
end

-- Areas -------------------------------------------------------------------------------------------

local function openOffice(ctx: Ctx, side: string)
	local text = Color3.fromRGB(46, 44, 40)
	-- South wall (z = -76, faces north): service door x -86, nook x -66..-56; perch at the west end.
	local south = face("Z", -76, 1)
	local sSegs = runs(-114 + HALF_T, -HALF_T, { { c = -61, w = 10 } })
	officeTrim(ctx, south, sSegs)
	-- (the x -14 pilaster was removed: room for the framed map beside the wardrobe, 2026-10-16)
	for _, u in { -92, -74, -50, -32 } do
		pilaster(ctx, south, u, H)
	end
	noticeBoard(ctx, south, -80, 5.6)
	-- (handmade water cooler at x -53.6 replaced by the owner's store dispenser: Decor, 2026-10-16)
	radiator(ctx, south, -41, 4)
	radiator(ctx, south, -23, 4)
	filingCabinet(ctx, south, -28)
	wallGrille(ctx, south, -20, 10.2, 1.8, 1)
	wallGrille(ctx, south, -68, 10.2, 1.8, 1)
	stain(ctx, south, -44, 7.4, 1, 0)
	stain(ctx, south, -96, 8.2, 0.8, 0)

	-- North wall (z = -36, faces south): solid west of x -58, drywall (wallbang) -58..-40 left bare
	-- so it stays readable, solid -40..-6 (junction door at x -3).
	local north = face("Z", -36, -1)
	local nSegs = { { -114 + HALF_T + END_INSET, -58 - HALF_T - END_INSET } }
	for _, s in runs(-40 + HALF_T, -6, { { c = -3, w = 6 } }) do
		table.insert(nSegs, s)
	end
	officeTrim(ctx, north, nSegs)
	for _, u in { -104, -88, -72, -20 } do
		pilaster(ctx, north, u, H)
	end
	filingCabinet(ctx, north, -109)
	fireCabinet(ctx, north, -68) -- (was -96: squeezed between the lockers and a picture)
	clock(ctx, north, -80, 9)
	panel(ctx, north, -61.5, 4.8, H, D.PanelGrey)
	radiator(ctx, north, -64, 3)
	noticeBoard(ctx, north, -34, 5.6)
	-- filing cabinets along the bare east end of the north wall, opposite the printer (owner,
	-- 2026-10-16): 2 between the band pillar at x -30 and the x -20 pilaster, 1 just east of that
	-- pilaster, 2 between the band pillar at x -14 and the junction door (opening at x -6).
	-- (the zig-zag band pillar at x -31..-29 touches this wall: 2 fit between it and the pilaster)
	-- (and the band pillar at x -15..-13 stands just out from the wall: nothing behind it)
	for _, u in { -27.4, -24.5, -17, -11.2, -8.3 } do
		filingCabinet(ctx, north, u)
	end
	stain(ctx, north, -84, 7, 1.1, 0)
	stain(ctx, north, -12, 8.4, 0.7, 0)
	sign(ctx, north, -98, 9.2, 3.4, 0.7, `OPEN OFFICE  {side}-2`, D.SignOffice, text)

	-- Centre wall (x = 0) that ends the lane: same office trim (each half dresses its own face).
	officeTrim(ctx, face("X", 0, -1), runs(-76 + HALF_T, -45.6))

	-- Ceiling: a few missing and water-stained tiles between the tube rows.
	ceilingHole(ctx, -70, -56, 4, 2)
	ceilingHole(ctx, -34, -57, 2, 2)
	ceilingHole(ctx, -98, -55, 2, 4)
	ceilingStain(ctx, -50, -55, 3.2, 2.6)
	ceilingStain(ctx, -84, -57, 2.4, 3)
	ceilingStain(ctx, -22, -54, 2.6, 2)
end

local function longHall(ctx: Ctx, side: string)
	local text = Color3.fromRGB(46, 44, 40)
	-- Gaps around the blast door frame (x -81..-79) and the Records doors.
	local south = face("Z", -6, 1)
	local sSegs = runs(-114 + HALF_T, -58 - HALF_T, { { c = -80, w = 3.6 } })
	officeTrim(ctx, south, sSegs)
	pilaster(ctx, south, -100, H)
	pilaster(ctx, south, -64, H)
	noticeBoard(ctx, south, -70, 5.6)
	stain(ctx, south, -90, 8, 0.9, 0)

	local north = face("Z", 6, -1)
	local nSegs = runs(-114 + HALF_T, -36.6, { { c = -80, w = 3.6 }, { c = -43, w = 6 } })
	officeTrim(ctx, north, nSegs)
	pilaster(ctx, north, -100, H)
	pilaster(ctx, north, -52, H)
	fireCabinet(ctx, north, -92)
	clock(ctx, north, -66, 9)
	wallGrille(ctx, north, -74, 10.2, 1.8, 1)
	sign(ctx, north, -109, 9.2, 3, 0.7, `LONG HALL  {side}`, D.SignOffice, text)

	ceilingHole(ctx, -66, 3, 2, 2)
	ceilingStain(ctx, -90, -2.5, 2.4, 2)
end

local function distribution(ctx: Ctx, side: string)
	local text = Color3.fromRGB(46, 44, 40)
	-- West wall (x = -126, faces east): lockers, Core main door, Core vent, Security.
	local west = face("X", -126, 1)
	local wSegs = runs(-66 + HALF_T, 62 - HALF_T, {
		{ c = -38, w = 6 },
		{ c = -12, w = 6 },
		{ c = 38, w = 6 },
	})
	officeTrim(ctx, west, wSegs)
	sign(ctx, west, -32.4, 6.4, 2.6, 0.6, "SOUTH WING", D.SignOffice, text)
	sign(ctx, west, -7.4, 6.4, 2.4, 0.6, `FLAG  {side}`, D.SignOffice, text)
	sign(ctx, west, 42.8, 6.4, 2.4, 0.6, "NORTH WING", D.SignOffice, text)
	fireCabinet(ctx, west, -60)
	panel(ctx, west, 52, 4.8, H, D.PanelGrey)

	-- East wall (x = -114, faces west): office mouth, hall, gallery door.
	local east = face("X", -114, -1)
	local eSegs =
		runs(-66 + HALF_T, 62 - HALF_T, { { c = -56, w = 16 }, { c = 0, w = 12 }, { c = 56, w = 6 } })
	officeTrim(ctx, east, eSegs)
	sign(ctx, east, -45.4, 9.2, 2.8, 0.6, "OFFICE  >", D.SignOffice, text)
	sign(ctx, east, 9.4, 9.2, 2.8, 0.6, "LONG HALL  >", D.SignOffice, text)
	sign(ctx, east, 51.2, 6.4, 2.8, 0.6, "MAINT.  >", D.SignOffice, text)
	clock(ctx, east, 30, 9)
	stain(ctx, east, -20, 7.6, 0.8, 0)
end

local function gallery(ctx: Ctx, side: string)
	local text = Color3.fromRGB(196, 190, 170)
	-- North wall (z = 76, faces south): tool cage x -40..-30; perch at the west end.
	local north = face("Z", 76, -1)
	local nSegs = runs(-114 + HALF_T, -HALF_T, { { c = -35, w = 10 } })
	strip(ctx, north, "MaintPaint", nSegs, 0.02, 3.6, 0.04, D.MaintPaint)
	strip(ctx, north, "PaintLine", nSegs, 3.6, 3.8, 0.05, D.PaintLine)
	strip(ctx, north, "KickRail", nSegs, 0.02, 0.5, 0.12, D.KickRail, 0.05)
	-- Upper services: a conduit and a cable tray (the 1.4 pipe runs below the ceiling at z 74).
	local upper = runs(-98.2, -HALF_T, { { c = -35, w = 10 } })
	conduitRun(ctx, north, upper, 8.4, 0, 6)
	cableTray(ctx, north, upper, 7.6)
	panel(ctx, north, -88, 4.8, 7.5, D.PanelGrey)
	panel(ctx, north, -54, 4.8, 7.5, D.PanelDark)
	panel(ctx, north, -16, 4.8, 7.5, D.PanelGrey)
	hazardPlate(ctx, north, -41.4)
	hazardPlate(ctx, north, -28.6)
	for _, u in { -92, -77, -63, -47, -22, -10 } do
		streak(ctx, north, u, 7.2, 10.6, 0.35)
	end
	rust(ctx, north, -70, 9.4)
	rust(ctx, north, -31, 9.6)
	sign(ctx, north, -45, 9.4, 3, 0.7, `MAINT-N{if side == "B" then 1 else 2}`, D.SignMaint, text)

	-- Centre wall (x = 0, office-coloured) that ends the lane: office trim to match it.
	officeTrim(ctx, face("X", 0, -1), runs(45.6, 76 - HALF_T))

	-- South wall (z = 36, faces north): tunnel door x -43, break room x -21, junction x -3.
	local south = face("Z", 36, 1)
	local sSegs = runs(-114 + HALF_T, -6, { { c = -43, w = 6 }, { c = -21, w = 6 }, { c = -3, w = 6 } })
	strip(ctx, south, "MaintPaint", sSegs, 0.02, 3.6, 0.04, D.MaintPaint)
	strip(ctx, south, "PaintLine", sSegs, 3.6, 3.8, 0.05, D.PaintLine)
	strip(ctx, south, "KickRail", sSegs, 0.02, 0.5, 0.12, D.KickRail, 0.05)
	conduitRun(ctx, south, sSegs, 8.2, 0, 6)
	panel(ctx, south, -100, 4.8, 8.0, D.PanelDark)
	panel(ctx, south, -60, 4.8, 8.0, D.PanelGrey)
	wallGrille(ctx, south, -78, 6.6, 2.4, 1.4)
	wallGrille(ctx, south, -30, 6.6, 2.4, 1.4)
	for _, u in { -46.6, -39.4, -24.6, -17.4 } do
		hazardPlate(ctx, south, u)
	end
	for _, u in { -106, -86, -70, -52, -12 } do
		streak(ctx, south, u, 4, 7.8, 0.4)
	end
	rust(ctx, south, -66, 6.8)
	sign(ctx, south, -36.2, 6.4, 2.2, 0.6, "TUNNEL", D.SignMaint, text)
	sign(ctx, south, -14.2, 6.4, 2.2, 0.6, "BREAK", D.SignMaint, text)
	sign(ctx, south, -94, 9, 4, 0.8, `MAINTENANCE GALLERY  {side}`, D.SignMaint, text)
	-- Ceiling line under the concrete slab: a duct along the centre (above lamp height).
	box(ctx, "Duct", v(-62, MH - 0.55, 64), v(70, 1, 2.2), D.Duct)
	for _, x in { -96, -84, -72, -60, -48, -36 } do
		box(ctx, "DuctFlange", v(x, MH - 0.55, 64), v(0.2, 1.12, 2.32), D.DuctFlange)
	end
end

local function base(ctx: Ctx)
	local text = Color3.fromRGB(46, 44, 40)
	-- Spawn room (behind the flag room): same office walls + trim as the rest of the facility, and
	-- signs over the three exits.
	local walls: { { f: Face, segs: { { number } } } } = {
		{ f = face("X", -186, 1), segs = runs(-32 + HALF_T, 32 - HALF_T, { { c = 0, w = 8.6 } }) },
		{ f = face("Z", 32, -1), segs = runs(-186 + HALF_T, -162 - HALF_T) },
		{ f = face("Z", -32, 1), segs = runs(-186 + HALF_T, -162 - HALF_T) },
		{
			f = face("X", -162, -1),
			segs = runs(-32 + HALF_T, 32 - HALF_T, { { c = -26.5, w = 9 }, { c = 26.5, w = 9 } }), -- spawn exits
		},
	}
	for _, w in walls do
		officeTrim(ctx, w.f, w.segs)
	end
	local east = face("X", -162, -1)
	sign(ctx, east, 26.5, 10.9, 3.6, 0.7, "NORTH WING", D.SignOffice, text) -- over the 10-stud spawn exit
	sign(ctx, east, -26.5, 10.9, 3.6, 0.7, "SOUTH WING", D.SignOffice, text)
	sign(ctx, face("X", -180, 1), 0, 9.6, 4, 0.7, "ELEVATOR  ·  ATRIUM", D.SignOffice, text)
end

-- Centre: atrium, south junction, break room, Records - same office dressing as the side lanes.
local function centre(ctx: Ctx, side: string)
	local text = Color3.fromRGB(46, 44, 40)
	-- Atrium (x -36..0, z -14..14). The mezzanine hides the trim along the south wall's west part.
	local aWest = face("X", -36, 1)
	officeTrim(ctx, aWest, runs(-14 + HALF_T, 14 - HALF_T, { { c = 0, w = 12 } }))
	local aNorth = face("Z", 14, -1)
	officeTrim(
		ctx,
		aNorth,
		runs(-36 + HALF_T, -HALF_T, { { c = -21, w = 6 }, { c = -27, w = 5 }, { c = -3, w = 6 } })
	)
	local aSouth = face("Z", -14, 1)
	officeTrim(ctx, aSouth, runs(-36 + HALF_T, -HALF_T, { { c = -3, w = 6 } }))
	pilaster(ctx, aNorth, -12, H)
	pilaster(ctx, aNorth, -33, H)
	pilaster(ctx, aSouth, -10, H)
	clock(ctx, aNorth, -15.5, 9.5)
	stain(ctx, aSouth, -12.5, 8, 0.8, 0)
	sign(ctx, aNorth, -21, 9.2, 3, 0.6, `BREAK ROOM  {side}`, D.SignOffice, text)
	ceilingHole(ctx, -26, 4, 2, 2)
	ceilingStain(ctx, -10, 4, 2.6, 2.2)
	ceilingStain(ctx, -27, -5, 2, 2.4)

	-- South junction corridor (x -6..0, z -36..-14): its west wall.
	local jWest = face("X", -6, 1)
	officeTrim(ctx, jWest, runs(-36 + HALF_T, -14 - HALF_T))
	stain(ctx, jWest, -29, 7.8, 0.7, 0)
	wallGrille(ctx, jWest, -20, 10.2, 1.8, 1)

	-- Break room (x -30..-6, z 14..36): west wall (shelf / vending side), north + south walls.
	local bWest = face("X", -30, 1)
	officeTrim(ctx, bWest, runs(14 + HALF_T, 36 - HALF_T))
	local bNorth = face("Z", 36, -1)
	officeTrim(ctx, bNorth, runs(-30 + HALF_T, -6 - HALF_T, { { c = -21, w = 6 } }))
	local bSouth = face("Z", 14, 1)
	officeTrim(ctx, bSouth, runs(-30 + HALF_T, -6 - HALF_T, { { c = -21, w = 6 }, { c = -27, w = 5 } }))
	noticeBoard(ctx, bNorth, -12, 5.6)
	stain(ctx, bNorth, -27, 7.4, 0.9, 0)
	ceilingHole(ctx, -10, 21.5, 2, 2)
	ceilingStain(ctx, -25, 28.5, 2.4, 2.2)

	-- Records (dark archive, x -58..-40, z -36..-6): its two solid side walls.
	local rWest = face("X", -58, 1)
	local rEast = face("X", -40, -1)
	officeTrim(ctx, rWest, runs(-36 + HALF_T, -6 - HALF_T))
	officeTrim(ctx, rEast, runs(-36 + HALF_T, -6 - HALF_T))
	stain(ctx, rWest, -27, 7.6, 1.1, 0)
	stain(ctx, rEast, -14, 8.2, 0.9, 0)
	sign(ctx, rEast, -30, 9.2, 2.6, 0.6, `RECORDS  {side}`, D.SignOffice, text)
end

function Detail.Build(ctx: Ctx)
	local side = ctx.Prefix
	openOffice(ctx, side)
	longHall(ctx, side)
	distribution(ctx, side)
	gallery(ctx, side)
	centre(ctx, side)
	base(ctx)
end

return Detail

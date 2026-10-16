--!strict
-- TEST DECOR (trial - easy to remove). Extra set dressing to make the facility more appealing.
-- Everything here lives in its own folder (Facility.Decor) and is built by one call in
-- Layout.Build guarded by Layout.DECOR_TEST. To undo: set DECOR_TEST = false (or delete this file
-- and that call). Nothing else in the map depends on it.
--
-- What it adds (per half, mirrored):
--   Open Office   2 potted plants (corners), ceiling sprinklers along the centre line, one sagging
--                 ceiling tile (hangs at an angle under a hole), a whiteboard on the south wall
--   Long Hall     4 framed facility posters (text) and 2 framed prints
--   Atrium        2 potted plants, 2 framed prints, an elevator call panel with lit buttons
--   (Owner's pictures, 2026-10-16 - DecorService.Paintings / .Images, the same in both halves unless
--   noted: Office = Keep Calm poster, SpongeBob, framed map, Nicki Minaj; Lab = an alien portrait
--   (a different one per half), old soldier, dark eyes; Atrium = old picture; Long Hall = Scream in
--   the Blue half.)
--   Break Room    a potted plant, a wall shelf with a coffee machine and mugs
--   Gallery       a wet-floor A-frame sign at the flooded crossing, 2 puddles, 2 vertical pipe
--                 drops with red valve wheels, hanging cables, 2 oil drums in the dead corner by
--                 the centre wall (the only solid pieces)
--   Owner's store props (DecorService.Props): Open Office 2 wall desks + 3 back-to-back desk
--                 pairs in the middle, trash bin, lockers, copier, laptop / phone / papers on
--                 existing counters; Gallery 2 lab benches, lab-safety poster, specimen tubes to
--                 each bench (6 + 4; red in the Red half, blue in the Blue half).
-- Rules: decoration is CanCollide false + CanQuery false (bullets pass) except the two drums; it
-- sits in corners / on walls / on the ceiling, off every sniper line, door and nav path.

local Style = require(script.Parent.Style)
local Pieces = require(script.Parent.Pieces)

type Ctx = Pieces.Ctx
type Surface = Style.Surface

local Decor = {}

-- Potted plants are switched off (user, 2026-10-13). True brings back the 5 per half.
Decor.PLANTS = false

local H = Style.Dims.CeilingHeight
local MH = Style.Dims.MaintCeilingHeight
local HALF_T = Style.Dims.WallThickness / 2
local GAP = 0.05 -- off the wall face (Detail uses 0.03; this keeps the two layers apart)

local rgb = Color3.fromRGB

local function deco(color: Color3, material: Enum.Material, extra: { [string]: any }?): Surface
	local s: Surface =
		{ Color = color, Material = material, CanCollide = false, CanQuery = false, CastShadow = false }
	if extra then
		for k, val in extra do
			(s :: any)[k] = val
		end
	end
	return s
end

local M = {
	Pot = deco(rgb(70, 64, 58), Enum.Material.Concrete, { CastShadow = true }),
	Soil = deco(rgb(40, 32, 26), Enum.Material.Ground),
	Leaf = deco(rgb(58, 82, 48), Enum.Material.Grass, { CastShadow = true }),
	LeafDark = deco(rgb(44, 64, 38), Enum.Material.Grass, { CastShadow = true }),
	Frame = deco(rgb(34, 34, 34), Enum.Material.SmoothPlastic),
	Paper = deco(rgb(214, 210, 196), Enum.Material.SmoothPlastic),
	PrintA = deco(rgb(96, 110, 120), Enum.Material.SmoothPlastic),
	PrintB = deco(rgb(150, 128, 92), Enum.Material.SmoothPlastic),
	Whiteboard = deco(rgb(226, 228, 226), Enum.Material.SmoothPlastic),
	Tray = deco(rgb(150, 152, 156), Enum.Material.Metal),
	Marker = deco(rgb(40, 60, 120), Enum.Material.SmoothPlastic),
	Sprinkler = deco(rgb(190, 186, 170), Enum.Material.Metal),
	Hole = deco(rgb(14, 13, 12), Enum.Material.SmoothPlastic),
	Tile = deco(rgb(196, 190, 166), Enum.Material.Slate, { CastShadow = true }),
	Panel = deco(rgb(150, 152, 154), Enum.Material.Metal),
	ButtonLit = deco(rgb(255, 196, 120), Enum.Material.Neon),
	Shelf = deco(rgb(110, 92, 70), Enum.Material.Wood),
	Coffee = deco(rgb(30, 30, 32), Enum.Material.SmoothPlastic),
	CoffeeLit = deco(rgb(220, 70, 50), Enum.Material.Neon),
	Mug = deco(rgb(200, 196, 186), Enum.Material.SmoothPlastic),
	MugBlue = deco(rgb(70, 90, 120), Enum.Material.SmoothPlastic),
	Yellow = deco(rgb(214, 176, 40), Enum.Material.SmoothPlastic, { CastShadow = true }),
	Puddle = deco(rgb(22, 26, 28), Enum.Material.Glass, { Transparency = 0.25, Reflectance = 0.25 }),
	Pipe = deco(rgb(96, 88, 76), Enum.Material.CorrodedMetal, { CastShadow = true }),
	Valve = deco(rgb(150, 36, 30), Enum.Material.Metal),
	Cable = deco(rgb(22, 22, 22), Enum.Material.SmoothPlastic),
	Drum = { Color = rgb(52, 70, 92), Material = Enum.Material.Metal } :: Surface,
	DrumRust = { Color = rgb(110, 62, 36), Material = Enum.Material.CorrodedMetal } :: Surface,
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function box(ctx: Ctx, name: string, center: Vector3, size: Vector3, surf: Surface): Part
	return Pieces.BoxAt(ctx, name, center, size, surf, ctx.Folders.Decor)
end

-- Rotated part (not axis aligned; mirrored by hand). `angles` in degrees, applied X then Y then Z.
local function tilted(
	ctx: Ctx,
	name: string,
	center: Vector3,
	size: Vector3,
	angles: Vector3,
	surf: Surface
): Part
	local p = Pieces.P(ctx, center)
	local ax, ay, az = angles.X, angles.Y, angles.Z
	if ctx.Mirror then
		ay, az = -ay, -az
	end
	return Pieces.RawPart(
		name,
		CFrame.new(p) * CFrame.Angles(math.rad(ax), math.rad(ay), math.rad(az)),
		size,
		surf,
		ctx.Folders.Decor
	)
end

local function cylinder(
	ctx: Ctx,
	name: string,
	center: Vector3,
	length: number,
	diameter: number,
	axis: "X" | "Y" | "Z",
	surf: Surface
): Part
	return Pieces.Cylinder(ctx, name, center, length, diameter, axis, surf, ctx.Folders.Decor)
end

-- Wall face helpers (same convention as Detail.luau): axis "Z" = wall along X at fixed z.
type Face = { Axis: "X" | "Z", Plane: number, Dir: number }
local function face(axis: "X" | "Z", line: number, dir: number): Face
	return { Axis = axis, Plane = line + dir * HALF_T, Dir = dir }
end
local function mount(
	ctx: Ctx,
	f: Face,
	name: string,
	u: number,
	y: number,
	w: number,
	h: number,
	depth: number,
	surf: Surface,
	off: number?
): Part
	local d = GAP + (off or 0) + depth / 2
	local center = if f.Axis == "Z" then v(u, y, f.Plane + f.Dir * d) else v(f.Plane + f.Dir * d, y, u)
	local size = if f.Axis == "Z" then v(w, h, depth) else v(depth, h, w)
	return box(ctx, name, center, size, surf)
end

local function text(ctx: Ctx, f: Face, part: BasePart, lines: string, color: Color3)
	local normal = if f.Axis == "Z" then v(0, 0, f.Dir) else v(f.Dir, 0, 0)
	if ctx.Mirror then
		normal = v(-normal.X, 0, normal.Z)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Pieces.FaceFromVector(normal)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Arial
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = color
	label.Text = lines
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.1, 0)
	pad.PaddingRight = UDim.new(0.1, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = label
	label.Parent = gui
end

-- Store slots: a handmade piece is grouped into a Model tagged "DecorSlot" (attribute Kind). If a
-- Creator Store model is configured for that kind (Server/Services/DecorService), it replaces the
-- handmade one at runtime; otherwise the handmade piece stays.
local handmadePlant: (ctx: Ctx, x: number, z: number) -> ()

local function slot(ctx: Ctx, kind: string, build: () -> ()): Model
	local folder = ctx.Folders.Decor
	local before: { [Instance]: boolean } = {}
	for _, child in folder:GetChildren() do
		before[child] = true
	end
	build()
	local model = Instance.new("Model")
	model.Name = kind
	for _, child in folder:GetChildren() do
		if not before[child] then
			child.Parent = model
		end
	end
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Mirror", ctx.Mirror)
	model:AddTag("DecorSlot")
	model.Parent = folder
	return model
end

-- Pieces -----------------------------------------------------------------------------------------

local function plant(ctx: Ctx, x: number, z: number)
	slot(ctx, "Plant", function()
		handmadePlant(ctx, x, z)
	end)
end

handmadePlant = function(ctx: Ctx, x: number, z: number)
	cylinder(ctx, "PlantPot", v(x, 0.9, z), 1.8, 1.6, "Y", M.Pot)
	cylinder(ctx, "PlantSoil", v(x, 1.82, z), 0.06, 1.4, "Y", M.Soil)
	cylinder(ctx, "PlantStem", v(x, 3, z), 2.4, 0.18, "Y", M.LeafDark)
	-- Leaves: long thin blades fanning out at different angles and heights.
	local leaves = {
		{ 0, 3.3, 0.5, 35, 0 },
		{ 0, 3.6, -0.4, -40, 0 },
		{ 0.5, 3.9, 0, 0, -38 },
		{ -0.5, 4.1, 0, 0, 42 },
		{ 0.3, 4.4, 0.3, 28, -25 },
		{ -0.3, 4.6, -0.3, -30, 25 },
		{ 0, 4.9, 0, 10, 10 },
	}
	for i, l in leaves do
		tilted(
			ctx,
			"PlantLeaf",
			v(x + l[1], l[2], z + l[3]),
			v(0.5, 1.9, 0.06),
			v(l[4], i * 47, l[5]),
			if i % 2 == 0 then M.Leaf else M.LeafDark
		)
	end
end

-- `painting` (optional): one of the owner's store paintings (DecorService.Paintings) replaces this
-- print at runtime; the handmade print stays if it can't load. Each painting is used once.
local function framedPrint(
	ctx: Ctx,
	f: Face,
	u: number,
	y: number,
	w: number,
	h: number,
	art: Surface,
	painting: string?
)
	local function build()
		mount(ctx, f, "PrintFrame", u, y, w, h, 0.06, M.Frame)
		mount(ctx, f, "PrintMat", u, y, w - 0.2, h - 0.2, 0.02, M.Paper, 0.06)
		mount(ctx, f, "PrintArt", u, y + 0.05, w - 0.6, h - 0.7, 0.02, art, 0.08)
	end
	if not painting then
		build()
		return
	end
	local normal = if f.Axis == "Z" then v(0, 0, f.Dir) else v(f.Dir, 0, 0)
	if ctx.Mirror then
		normal = v(-normal.X, 0, normal.Z)
	end
	local model = slot(ctx, "Painting", build)
	model:SetAttribute("Art", painting)
	model:SetAttribute("WallNormal", normal)
end

-- A framed print showing one of the owner's uploaded images (DecorService.Images[key], applied as a
-- Decal by DecorService). The art fills the frame minus a thin border; it stays a plain print until
-- that image id is filled in.
local function imagePrint(ctx: Ctx, f: Face, u: number, y: number, w: number, h: number, key: string)
	local normal = if f.Axis == "Z" then v(0, 0, f.Dir) else v(f.Dir, 0, 0)
	if ctx.Mirror then
		normal = v(-normal.X, 0, normal.Z)
	end
	mount(ctx, f, "PrintFrame", u, y, w, h, 0.06, M.Frame)
	local art = mount(ctx, f, "PrintImage", u, y, w - 0.3, h - 0.3, 0.02, M.Paper, 0.06)
	art:SetAttribute("Image", key)
	art:SetAttribute("ImageFace", normal)
	art:AddTag("DecorImage")
end

local function poster(ctx: Ctx, f: Face, u: number, y: number, words: string)
	mount(ctx, f, "PosterFrame", u, y, 1.9, 2.5, 0.06, M.Frame)
	local p = mount(ctx, f, "Poster", u, y, 1.7, 2.3, 0.02, M.Paper, 0.06)
	text(ctx, f, p, words, rgb(40, 38, 34))
end

local function sprinkler(ctx: Ctx, x: number, z: number, ceiling: number)
	cylinder(ctx, "Sprinkler", v(x, ceiling - 0.12, z), 0.24, 0.12, "Y", M.Sprinkler)
	cylinder(ctx, "SprinklerHead", v(x, ceiling - 0.27, z), 0.06, 0.32, "Y", M.Sprinkler)
end

-- Spot for one of the owner's Creator Store props (DecorService.Props[key]): an invisible marker
-- on the floor (or on a surface: `pos.Y` = its top). The model stands there facing `facing`; with
-- `wall` its back sits against the wall plane through `pos`. No handmade fallback.
local INVISIBLE = deco(rgb(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1 })
local function storeProp(ctx: Ctx, key: string, pos: Vector3, facing: Vector3, wall: boolean)
	local model = slot(ctx, "Prop", function()
		box(ctx, "PropSpot", pos + v(0, 0.05, 0), v(0.1, 0.1, 0.1), INVISIBLE)
	end)
	model:SetAttribute("Prop", key)
	model:SetAttribute("Facing", if ctx.Mirror then v(-facing.X, 0, facing.Z) else facing)
	model:SetAttribute("AgainstWall", wall)
end

-- Areas -------------------------------------------------------------------------------------------

local function office(ctx: Ctx)
	if Decor.PLANTS then
		plant(ctx, -112.4, -40.4)
	end
	if Decor.PLANTS then
		plant(ctx, -8.6, -73.6)
	end
	for _, x in { -106, -90, -74, -58, -42, -26 } do
		sprinkler(ctx, x, -56, H)
	end
	-- Sagging ceiling tile: dark hole above, the tile hanging from one edge.
	box(ctx, "TileHole", v(-63, H - 0.04, -57), v(2, 0.03, 2), M.Hole)
	tilted(ctx, "SaggingTile", v(-63, H - 0.55, -57.35), v(2, 0.08, 1.95), v(-28, 0, 0), M.Tile)
	-- Whiteboard (south wall) with a marker tray.
	local south = face("Z", -76, 1)
	-- (x -37: clear of the x -32 pilaster it used to overlap)
	mount(ctx, south, "WhiteboardFrame", -37, 6.2, 4.2, 2.6, 0.06, M.Tray)
	local wb = mount(ctx, south, "Whiteboard", -37, 6.2, 4, 2.4, 0.02, M.Whiteboard, 0.06)
	text(ctx, south, wb, "Q3 TARGETS\nreview pending", rgb(50, 70, 130))
	mount(ctx, south, "MarkerTray", -37, 4.8, 3, 0.1, 0.25, M.Tray, 0.06)
	mount(ctx, south, "Marker", -36.2, 4.9, 0.5, 0.08, 0.08, M.Marker, 0.12)

	-- Owner's pictures (both halves), on free wall between the pilasters, radiators and cabinets:
	-- the Keep Calm poster (uploaded image) above the west radiator, SpongeBob over the perch end,
	-- the framed map above the east radiator, Nicki Minaj by the junction door.
	-- (80% bigger than the first version, owner 2026-10-16; heights in DecorService.Paintings.)
	-- South wall: Keep Calm above the west radiator, Nicki Minaj centred between the pilasters at
	-- x -32 / -14 (9 studs clear either side), SpongeBob over the perch end.
	-- North wall: a second SpongeBob, shifted east of the first one (between the fire cabinet and
	-- the x -88 pilaster).
	imagePrint(ctx, south, -43.6, 6.7, 3.42, 4.59, "KeepCalm") -- between the whiteboard and x -50
	if not ctx.Mirror then -- Blue office only (the one with the framed map), owner 2026-10-16
		framedPrint(ctx, south, -23, 7, 4, 2.9, M.PrintA, "NickiMinaj")
	end
	framedPrint(ctx, south, -98, 7.2, 4, 2.9, M.PrintA, "SpongeBob")
	framedPrint(ctx, face("Z", -36, -1), -92.5, 7.2, 4, 2.9, M.PrintA, "SpongeBob")

	-- Owner's office props (Creator Store, DecorService.Props). Furniture stands against the walls
	-- between the pilasters / cabinets, clear of the cover islands, perch and doors.
	local N, S = v(0, 0, -1), v(0, 0, 1) -- facing into the room from the north / south wall
	storeProp(ctx, "Desk", v(-80, 0, -36.5), N, true) -- north wall, under the clock
	storeProp(ctx, "Trash", v(-74.5, 0, -37.4), N, false) -- beside that desk
	storeProp(ctx, "Desk", v(-85, 0, -75.5), S, true) -- south wall, between the pilasters
	storeProp(ctx, "Lockers", v(-100, 0, -36.5), N, true) -- north wall, west end
	storeProp(ctx, "Printer", v(-17.9, 0, -75.5), S, true) -- south wall, east end
	-- water dispenser (replaces the handmade cooler): south wall between the nook and the x -50 pilaster
	storeProp(ctx, "OfficeWaterDispenser", v(-53.4, 0, -75.5), S, true)
	storeProp(ctx, "Laptop", v(-54.5, 3.5, -46), N, false) -- on the counter of the island (-58, -46)
	storeProp(ctx, "Phone", v(-109, 6.6, -37.8), N, false) -- on the north filing cabinet
	-- The corner by the tinted centre-wall window (south wall), different per half (owner,
	-- 2026-10-16): the Blue office has the wardrobe there with the big framed map beside it on the
	-- same wall; the Red office has two bookshelves side by side in its place.
	if ctx.Mirror then
		storeProp(ctx, "Bookshelf", v(-3.9, 0, -75.5), S, true)
		storeProp(ctx, "Bookshelf", v(-10.2, 0, -75.5), S, true)
	else
		storeProp(ctx, "Wardrobe", v(-3.5, 0, -75.5), S, true)
		framedPrint(ctx, south, -10.4, 7.4, 7.6, 5, M.PrintB, "FramedMap")
	end
	storeProp(ctx, "Papers", v(-28, 6.6, -74.2), S, false) -- on the south filing cabinet
	-- Desk pairs down the middle of the room, back to back (an imaginary wall at z = -56), between
	-- the cover islands and clear of the drywall panel. The row runs on towards the tinted centre-wall
	-- window with one more pair at x -22 (owner, 2026-10-16; a pair at x -10 was taken out again),
	-- clear of the bots' path to the junction and of the zig-zag band.
	for _, x in { -92, -64, -42, -22 } do
		storeProp(ctx, "Desk", v(x, 0, -56), S, true) -- faces the north wall
		storeProp(ctx, "Desk", v(x, 0, -56), N, true) -- faces the south wall
	end
end

local function hall(ctx: Ctx)
	local south = face("Z", -6, 1)
	local north = face("Z", 6, -1)
	poster(ctx, south, -84, 5.6, "KEEP\nDOORS\nCLOSED")
	poster(ctx, south, -110, 5.6, "LEVEL 0\nOFFICE\nANNEX")
	poster(ctx, north, -84, 5.6, "REPORT\nALL\nANOMALIES")
	poster(ctx, north, -60, 5.6, "NO\nUNESCORTED\nACCESS")
	-- Store paintings (owner's inventory), each once: Blue half = not mirrored, Red = mirrored.
	local red = ctx.Mirror == true
	-- (SpongeBob moved to the office and the dark-eyes painting to the lab: owner, 2026-10-16.)
	framedPrint(ctx, south, -94, 5.8, 2.2, 1.6, M.PrintA, if red then nil else "Scream")
	framedPrint(ctx, north, -106, 5.8, 2.2, 1.6, M.PrintB)
end

local function atrium(ctx: Ctx)
	if Decor.PLANTS then
		plant(ctx, -34, 12)
	end
	if Decor.PLANTS then
		plant(ctx, -34.2, -12.3)
	end
	local west = face("X", -36, 1)
	framedPrint(ctx, west, 10, 6.2, 3, 2, M.PrintB, "OldPicture") -- middle of the map
	framedPrint(ctx, west, -10, 6.4, 2.4, 1.8, M.PrintA)
	-- Elevator call panel beside the doors (west face of the shaft).
	local shaft = face("X", -4.5, -1)
	mount(ctx, shaft, "CallPanel", 2.9, 4.2, 0.45, 0.9, 0.05, M.Panel)
	mount(ctx, shaft, "CallUp", 2.9, 4.45, 0.14, 0.14, 0.03, M.ButtonLit, 0.05)
	mount(ctx, shaft, "CallDown", 2.9, 3.95, 0.14, 0.14, 0.03, M.Panel, 0.05)
end

local function breakRoom(ctx: Ctx)
	if Decor.PLANTS then
		plant(ctx, -8.4, 34.2)
	end
	-- Wall shelf on the break room's west wall (x = -30, faces east) with a coffee machine.
	local west = face("X", -30, 1)
	mount(ctx, west, "Shelf", 21, 3.6, 3.2, 0.12, 0.9, M.Shelf)
	mount(ctx, west, "CoffeeMachine", 20.3, 4.35, 0.9, 1.3, 0.75, M.Coffee)
	mount(ctx, west, "CoffeeLight", 20.0, 4.75, 0.1, 0.1, 0.02, M.CoffeeLit, 0.75)
	cylinder(ctx, "Mug", v(-29.1, 3.86, 21.6), 0.38, 0.32, "Y", M.Mug)
	cylinder(ctx, "Mug", v(-29.0, 3.86, 22.2), 0.38, 0.32, "Y", M.MugBlue)

	-- Owner's kitchen props (Creator Store, DecorService.Props): microwave + blender on the
	-- counter-height table in the middle (cover block x -15..-11, z 19..25, top 3.5), facing the
	-- room; a water dispenser in the north-west corner, back to the north wall.
	local W = v(-1, 0, 0)
	storeProp(ctx, "Microwave", v(-13, 3.5, 20.6), W, false)
	storeProp(ctx, "Blender", v(-13, 3.5, 23.6), W, false)
	storeProp(ctx, "WaterDispenser", v(-27, 0, 35.5), v(0, 0, -1), true)
end

local function gallery(ctx: Ctx)
	-- Wet floor sign at the flooded crossing (two leaning panels).
	slot(ctx, "WetSign", function()
		-- Centre of the gallery (x -57 of -114..0, z 56 of 36..76), beside the puddle at (-58, 52).
		tilted(ctx, "WetSign", v(-57, 1.1, 55.65), v(1.1, 2.2, 0.06), v(14, 0, 0), M.Yellow)
		tilted(ctx, "WetSign", v(-57, 1.1, 56.35), v(1.1, 2.2, 0.06), v(-14, 0, 0), M.Yellow)
	end)
	box(ctx, "Puddle", v(-58, 0.03, 52), v(3.2, 0.02, 2.2), M.Puddle)
	box(ctx, "Puddle", v(-84.5, 0.03, 61), v(2.4, 0.02, 3), M.Puddle)
	-- Vertical pipe drops with valve wheels (south wall), clear of the south bench's specimen tubes
	-- on either side of it: x -105 (was -94) and x -33 (TUNNEL sign / grille gap; was -56).
	for _, x in { -105, -33 } do
		cylinder(ctx, "PipeDrop", v(x, (MH + 1) / 2, 37.0), MH - 1, 0.5, "Y", M.Pipe)
		cylinder(ctx, "Valve", v(x, 4.6, 37.45), 0.1, 1.1, "Z", M.Valve)
		cylinder(ctx, "ValveHub", v(x, 4.6, 37.35), 0.25, 0.22, "Z", M.Valve)
	end
	-- Hanging cables from the ceiling.
	for _, c in { { -52, 50, 2.6 }, { -51.4, 50.4, 1.8 }, { -86, 66, 2.2 } } do
		cylinder(ctx, "HangingCable", v(c[1], MH - c[3] / 2, c[2]), c[3], 0.07, "Y", M.Cable)
	end
	-- Owner's lab props (Creator Store, DecorService.Props): a lab bench against the north wall
	-- with the lab-safety poster above it, a second bench on the south wall, and specimen tubes
	-- standing against the wall to the RIGHT of each bench as seen from the room (owner,
	-- 2026-10-16): 6 by the north bench, 3 by the south one (all that fits between the pipe drops,
	-- the pump / generator and the tunnel door). The Red half is the mirror image, which swaps left
	-- and right, so the unmirrored Blue half puts each row on the other side of its bench (and swaps
	-- the north bench and its row). DecorService tints the Red half's tubes red.
	local red = ctx.Mirror == true
	local north = face("Z", 76, -1)
	local northBench = if red then -78.2 else -55
	storeProp(ctx, "LabBench", v(northBench, 0, 75.5), v(0, 0, -1), true)
	framedPrint(ctx, north, northBench - 1.3, 6.2, 2, 2.6, M.PrintA, "LabRules") -- top 7.5, under the tray
	for _, x in if red then { -66, -62, -58, -54, -50, -46 } else { -88, -84, -80, -76, -72, -68 } do
		storeProp(ctx, "LabTube", v(x, 0, 73), v(0, 0, -1), false)
	end
	-- Owner's pictures, 80% bigger (owner 2026-10-16): too tall for the wall above the benches (cable
	-- tray at y 7.6), so they hang on the lab's west wall (x -114, door at z 53..59), which is clear
	-- up to the ceiling: the dark-eyes painting and this half's alien portrait (uploaded image, a
	-- different one per half) south of the door, the old soldier north of it (beside the perch).
	local west = face("X", -114, 1)
	framedPrint(ctx, west, 41.5, 6.2, 3.6, 2.9, M.PrintA, "SeekEyes")
	if red then
		imagePrint(ctx, west, 48.5, 6.2, 3.71, 4.5, "AlienSuit")
	else
		imagePrint(ctx, west, 48.5, 6.2, 3.51, 4.5, "AlienTuxedo")
	end
	framedPrint(ctx, west, 62, 7, 3, 3.6, M.PrintB, "OldSoldier")
	-- More of the dark-eyes painting (owner: "several times"): above the perch on the west wall, and
	-- on the back wall of the tool cage, above its crates.
	framedPrint(ctx, west, 70.5, 7.6, 3.6, 2.9, M.PrintA, "SeekEyes")
	framedPrint(ctx, face("Z", 81, -1), -35, 7, 3.6, 2.9, M.PrintA, "SeekEyes")
	-- South bench and its 4 specimen tubes, on the other side of the bench from the first layout
	-- (owner 2026-10-16): west of it in the Blue half, east of it in the Red half. Layout moved the
	-- pump, generator and sheet panel (and the pipe drops above) so nothing stands in front of them.
	storeProp(ctx, "LabBench", v(-70, 0, 36.5), v(0, 0, 1), true)
	for _, x in if red then { -59, -55.7, -52.4, -49.1 } else { -82.5, -85.8, -89.1, -92.4 } do
		storeProp(ctx, "LabTube", v(x, 0, 39), v(0, 0, 1), false)
	end
	-- Oil drums (solid), packed tight (centres 2.1 apart: rims almost touching) into the north-east
	-- corner where the tool-cage (north) wall meets the tinted centre-wall window (owner,
	-- 2026-10-16). A different count and layout per half so the two sides of the window don't mirror
	-- each other: a 3 x 3 block (9) in the Blue half; a 4 x 3 block plus 3 more down the window wall
	-- (15) in the Red half. (Drums are 3.2 tall, the window sill 3.5, so they don't block the view.)
	local drums = if red
		then {
			{ -1.55, 74.45 },
			{ -3.65, 74.45 },
			{ -5.75, 74.45 },
			{ -7.85, 74.45 },
			{ -1.55, 72.35 },
			{ -3.65, 72.35 },
			{ -5.75, 72.35 },
			{ -7.85, 72.35 },
			{ -1.55, 70.25 },
			{ -3.65, 70.25 },
			{ -5.75, 70.25 },
			{ -7.85, 70.25 },
			{ -1.55, 68.15 },
			{ -1.55, 66.05 },
			{ -1.55, 63.95 },
		}
		else {
			{ -1.55, 74.45 },
			{ -3.65, 74.45 },
			{ -5.75, 74.45 },
			{ -1.55, 72.35 },
			{ -3.65, 72.35 },
			{ -5.75, 72.35 },
			{ -1.55, 70.25 },
			{ -3.65, 70.25 },
			{ -5.75, 70.25 },
		}
	for _, d in drums do
		slot(ctx, "Drum", function()
			cylinder(ctx, "Drum", v(d[1], 1.6, d[2]), 3.2, 2, "Y", M.Drum)
			cylinder(ctx, "DrumRing", v(d[1], 2.2, d[2]), 0.12, 2.06, "Y", M.DrumRust)
		end)
	end
end

function Decor.Build(ctx: Ctx)
	office(ctx)
	hall(ctx)
	atrium(ctx)
	breakRoom(ctx)
	gallery(ctx)
end

return Decor

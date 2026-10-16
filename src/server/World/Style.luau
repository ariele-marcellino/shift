--!strict
-- Look-and-feel constants for the Office Annex: surfaces, light presets, atmosphere. Every mood
-- number lives here so lighting can be tuned in one file after a Studio pass.

local Style = {}

export type Surface = {
	Color: Color3,
	Material: Enum.Material,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CastShadow: boolean?,
}

export type LightPreset = {
	Color: Color3,
	Brightness: number,
	Range: number,
	Angle: number?,
	Shadows: boolean?,
	NoScale: boolean?, -- ignore Style.LightScale (fills keep close-range enemies visible)
}

-- Newer materials (Carpet, Plaster, CeramicTiles) are looked up safely so an older client/engine
-- can never break the map build; we fall back to a classic material instead.
local function material(name: string, fallback: Enum.Material): Enum.Material
	local ok, result = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(result) == "EnumItem" then
		return result :: any
	end
	return fallback
end

local CARPET = material("Carpet", Enum.Material.Fabric)
local PLASTER = material("Plaster", Enum.Material.SmoothPlastic)
local TILES = material("CeramicTiles", Enum.Material.Slate)

Style.Dims = {
	CeilingHeight = 12,
	MaintCeilingHeight = 11, -- maintenance has a lower, heavier concrete ceiling
	WallThickness = 1,
	DoorHeight = 8,
}

local rgb = Color3.fromRGB

Style.Surf = {
	-- Office: sickly yellow walls, damp beige carpet, off-white tiles
	OfficeWall = { Color = rgb(186, 170, 112), Material = PLASTER } :: Surface,
	OfficeCarpet = { Color = rgb(112, 101, 68), Material = CARPET } :: Surface,
	OfficeCeiling = { Color = rgb(200, 194, 170), Material = TILES } :: Surface,
	CubicleCarpet = { Color = rgb(110, 108, 100), Material = CARPET } :: Surface,
	Partition = { Color = rgb(102, 106, 114), Material = Enum.Material.Fabric } :: Surface,
	PartitionTrim = { Color = rgb(150, 148, 140), Material = Enum.Material.SmoothPlastic } :: Surface,
	Desk = { Color = rgb(150, 132, 100), Material = Enum.Material.Wood } :: Surface,
	Cabinet = { Color = rgb(120, 122, 118), Material = Enum.Material.Metal } :: Surface,
	Shelf = { Color = rgb(88, 84, 74), Material = Enum.Material.Metal } :: Surface,
	Box = { Color = rgb(150, 124, 86), Material = material("Cardboard", Enum.Material.SmoothPlastic) } :: Surface,
	Pillar = { Color = rgb(172, 160, 110), Material = PLASTER } :: Surface,
	-- Penetrable drywall: lighter, flatter, with darker taped seams (Pieces adds the seam strips)
	Drywall = { Color = rgb(214, 204, 168), Material = Enum.Material.SmoothPlastic } :: Surface,
	Seam = {
		Color = rgb(160, 150, 116),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	} :: Surface,
	WoodDoor = { Color = rgb(118, 82, 50), Material = Enum.Material.Wood } :: Surface,
	Knob = {
		Color = rgb(170, 160, 120),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
	} :: Surface,
	Crate = { Color = rgb(120, 96, 62), Material = Enum.Material.WoodPlanks } :: Surface,
	Railing = { Color = rgb(70, 72, 74), Material = Enum.Material.Metal } :: Surface,
	Mezzanine = { Color = rgb(96, 92, 80), Material = Enum.Material.DiamondPlate } :: Surface,
	Elevator = { Color = rgb(88, 90, 92), Material = Enum.Material.Metal } :: Surface,
	ElevatorDoor = { Color = rgb(140, 142, 140), Material = Enum.Material.Metal } :: Surface,
	Locker = { Color = rgb(70, 82, 92), Material = Enum.Material.Metal } :: Surface,
	-- Maintenance: wet concrete, rusted metal. Light-grey concrete (was ~60-75 grey: under the same
	-- tubes it reflected under half the light of the office plaster, so the gallery read dark).
	MaintWall = { Color = rgb(150, 150, 142), Material = Enum.Material.Concrete } :: Surface,
	MaintFloor = { Color = rgb(112, 112, 106), Material = Enum.Material.Concrete } :: Surface,
	WetFloor = { Color = rgb(86, 92, 92), Material = Enum.Material.Concrete, Reflectance = 0.08 } :: Surface,
	MaintCeiling = { Color = rgb(124, 124, 118), Material = Enum.Material.Concrete } :: Surface,
	Pipe = { Color = rgb(92, 84, 72), Material = Enum.Material.CorrodedMetal } :: Surface,
	Machine = { Color = rgb(70, 76, 72), Material = Enum.Material.DiamondPlate } :: Surface,
	Vent = { Color = rgb(60, 60, 58), Material = Enum.Material.DiamondPlate, CanCollide = false } :: Surface,
	-- Lightly tinted window glass (side-lane centre walls): see-through, solid to walk into.
	TintedGlass = {
		Color = rgb(56, 66, 72),
		Material = Enum.Material.Glass,
		Transparency = 0.68,
		Reflectance = 0.1,
		CastShadow = false,
	} :: Surface,
	Water = {
		Color = rgb(34, 52, 50),
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		Reflectance = 0.25,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	} :: Surface,
	-- Bases: dark panels, team colour comes from strips and lights
	BaseWall = { Color = rgb(40, 43, 50), Material = Enum.Material.Metal } :: Surface,
	BaseFloor = { Color = rgb(52, 54, 58), Material = Enum.Material.DiamondPlate } :: Surface,
	BaseCeiling = { Color = rgb(34, 36, 40), Material = Enum.Material.Metal } :: Surface,
	Pedestal = { Color = rgb(30, 32, 36), Material = Enum.Material.Metal } :: Surface,
	-- Hinges
	BlastDoor = { Color = rgb(64, 62, 56), Material = Enum.Material.DiamondPlate } :: Surface,
	Hazard = { Color = rgb(190, 150, 40), Material = Enum.Material.SmoothPlastic } :: Surface,
	-- Fixtures (lamp parts never cast shadows so the light inside them is not occluded)
	TubeOn = {
		Color = rgb(255, 238, 200),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	} :: Surface,
	TubeOff = {
		Color = rgb(96, 94, 88),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CastShadow = false,
	} :: Surface,
	Housing = {
		Color = rgb(150, 146, 134),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CastShadow = false,
	} :: Surface,
	ExitSign = {
		Color = rgb(60, 255, 120),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	} :: Surface,
	Bulb = {
		Color = rgb(255, 196, 130),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	} :: Surface,
	Cage = {
		Color = rgb(30, 30, 30),
		Material = Enum.Material.DiamondPlate,
		Transparency = 0.55,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	} :: Surface,
	Invisible = {
		Color = rgb(0, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	} :: Surface,
}

-- Environmental detail (World/Detail.luau). Decoration never collides, never takes bullets
-- (CanQuery false) and small pieces cast no shadow. Only `FilingCabinet` is solid (tall + shallow,
-- so it is neither cover nor a jump spot). Muted, realistic tones only.
local function deco(color: Color3, mat: Enum.Material, extra: { [string]: any }?): Surface
	local s: Surface =
		{ Color = color, Material = mat, CanCollide = false, CanQuery = false, CastShadow = false }
	if extra then
		for k, v in extra do
			(s :: any)[k] = v
		end
	end
	return s
end

Style.Detail = {
	-- Office trim
	Baseboard = deco(rgb(74, 64, 48), Enum.Material.SmoothPlastic),
	Wainscot = deco(rgb(158, 143, 94), PLASTER),
	ChairRail = deco(rgb(132, 116, 82), Enum.Material.Wood),
	Pilaster = deco(rgb(176, 162, 108), PLASTER, { CastShadow = true }),
	StainLight = deco(rgb(120, 104, 66), Enum.Material.SmoothPlastic, { Transparency = 0.55 }),
	StainDark = deco(rgb(84, 72, 46), Enum.Material.SmoothPlastic, { Transparency = 0.45 }),
	BoardFrame = deco(rgb(88, 82, 72), Enum.Material.Metal),
	Cork = deco(rgb(128, 98, 64), Enum.Material.Fabric),
	Paper = deco(rgb(212, 208, 194), Enum.Material.SmoothPlastic),
	PaperYellow = deco(rgb(206, 196, 150), Enum.Material.SmoothPlastic),
	FireCabinet = deco(rgb(112, 40, 34), Enum.Material.Metal),
	FireGlass = deco(rgb(150, 160, 162), Enum.Material.Glass, { Transparency = 0.55 }),
	Extinguisher = deco(rgb(120, 34, 28), Enum.Material.SmoothPlastic),
	Radiator = deco(rgb(170, 166, 152), Enum.Material.Metal),
	RadiatorCap = deco(rgb(132, 128, 116), Enum.Material.Metal),
	FilingCabinet = {
		Color = rgb(108, 110, 106),
		Material = Enum.Material.Metal,
	} :: Surface,
	DrawerLine = deco(rgb(58, 60, 58), Enum.Material.SmoothPlastic),
	CoolerBody = deco(rgb(196, 194, 186), Enum.Material.SmoothPlastic),
	CoolerBottle = deco(rgb(150, 172, 180), Enum.Material.Glass, { Transparency = 0.35 }),
	ClockRim = deco(rgb(44, 44, 44), Enum.Material.SmoothPlastic),
	ClockFace = deco(rgb(220, 216, 204), Enum.Material.SmoothPlastic),
	ClockHand = deco(rgb(24, 24, 24), Enum.Material.SmoothPlastic),
	CeilingHole = deco(rgb(16, 15, 13), Enum.Material.SmoothPlastic),
	CeilingStain = deco(rgb(140, 122, 84), Enum.Material.SmoothPlastic, { Transparency = 0.35 }),
	CeilingTile = deco(rgb(196, 190, 166), TILES, { CastShadow = true }),
	-- Electrical / services
	PanelGrey = deco(rgb(98, 100, 98), Enum.Material.Metal),
	PanelDark = deco(rgb(52, 54, 54), Enum.Material.Metal),
	Conduit = deco(rgb(112, 112, 106), Enum.Material.Metal),
	Bracket = deco(rgb(62, 62, 60), Enum.Material.Metal),
	Cable = deco(rgb(28, 28, 28), Enum.Material.SmoothPlastic),
	IndicatorGreen = deco(rgb(70, 150, 90), Enum.Material.Neon),
	IndicatorAmber = deco(rgb(160, 110, 40), Enum.Material.Neon),
	IndicatorRed = deco(rgb(150, 50, 40), Enum.Material.Neon),
	GrilleFrame = deco(rgb(70, 70, 68), Enum.Material.Metal),
	GrilleSlat = deco(rgb(40, 40, 40), Enum.Material.Metal),
	Duct = deco(rgb(124, 126, 124), Enum.Material.Metal),
	DuctFlange = deco(rgb(98, 100, 98), Enum.Material.Metal),
	-- Maintenance
	MaintPaint = deco(rgb(104, 118, 108), Enum.Material.Concrete),
	PaintLine = deco(rgb(150, 124, 50), Enum.Material.SmoothPlastic),
	HazardYellow = deco(rgb(168, 134, 42), Enum.Material.SmoothPlastic),
	HazardBlack = deco(rgb(30, 30, 30), Enum.Material.SmoothPlastic),
	KickRail = deco(rgb(110, 110, 106), Enum.Material.Metal),
	Grating = deco(rgb(46, 46, 44), Enum.Material.DiamondPlate),
	Streak = deco(rgb(38, 36, 30), Enum.Material.SmoothPlastic, { Transparency = 0.5 }),
	Rust = deco(rgb(92, 62, 40), Enum.Material.CorrodedMetal, { Transparency = 0.4 }),
	-- Base (spawn / lockers / passage)
	BaseRib = deco(rgb(50, 54, 62), Enum.Material.Metal, { CastShadow = true }),
	BaseKick = deco(rgb(30, 32, 36), Enum.Material.DiamondPlate),
	BaseSeam = deco(rgb(22, 24, 28), Enum.Material.SmoothPlastic),
	-- Signs (text drawn with a SurfaceGui on the plate)
	SignOffice = deco(rgb(200, 196, 184), Enum.Material.SmoothPlastic),
	SignMaint = deco(rgb(44, 46, 46), Enum.Material.Metal),
	SignBase = deco(rgb(34, 36, 40), Enum.Material.Metal),
}

-- Zone "Off" (LightDirector): tube stays Neon but nearly black so the client can fade smoothly.
Style.ZoneOffColor = rgb(40, 39, 36)

-- Broken fixture look: dark, glassy, slightly see-through (the part also tilts a few degrees).
Style.Broken = { Color = rgb(44, 42, 38), Material = Enum.Material.Glass, Transparency = 0.25 }

-- Global brightness of every map light (1 = the preset values). 0.75 = the map's default is 25%
-- dimmer; LightDirector then varies zones / single lamps around this. Fills are exempt (NoScale).
Style.LightScale = 0.75

Style.Light = {
	-- Weak sickly fluorescents. Non-shadow SurfaceLights facing down keep light mostly in-corridor.
	-- (Long Hall / atrium are a narrow, densely lit lane: kept a bit weaker so they don't outshine
	-- the wide side lanes.)
	HallTube = { Color = rgb(255, 228, 170), Brightness = 0.72, Range = 16, Angle = 115 } :: LightPreset,
	HallTubeShadow = {
		Color = rgb(255, 228, 170),
		Brightness = 0.95,
		Range = 18,
		Angle = 120,
		Shadows = true,
	} :: LightPreset,
	CorridorTube = { Color = rgb(255, 232, 180), Brightness = 0.75, Range = 16, Angle = 115 } :: LightPreset,
	DimTube = { Color = rgb(240, 225, 180), Brightness = 0.6, Range = 18, Angle = 125 } :: LightPreset,
	-- Doorway lamps: the only real light in dark rooms. Shadow-casting so doorways cut silhouettes.
	ExitLamp = { Color = rgb(130, 255, 160), Brightness = 1.6, Range = 16, Angle = 120, Shadows = true } :: LightPreset,
	CageLamp = { Color = rgb(255, 190, 120), Brightness = 2.2, Range = 18, Angle = 115, Shadows = true } :: LightPreset,
	Shaft = { Color = rgb(170, 200, 225), Brightness = 1.6, Range = 16, Angle = 45, Shadows = true } :: LightPreset,
	-- Hanging industrial lamps down the north sniper gallery (some cast shadows)
	TunnelBulb = { Color = rgb(255, 180, 110), Brightness = 0.9, Range = 11 } :: LightPreset,
	-- Fill: faint cold bounce so dark rooms are never pure black (close-range enemies stay visible
	-- even with every lamp shot out). Tune Brightness first if rooms read too dark on phones.
	Fill = { Color = rgb(110, 122, 145), Brightness = 0.16, Range = 26, NoScale = true } :: LightPreset,
	-- Base and spawn emergency lights (unbreakable)
	Emergency = { Color = rgb(255, 238, 215), Brightness = 0.7, Range = 14 } :: LightPreset,
	TeamFlood = { Color = rgb(255, 255, 255), Brightness = 0.9, Range = 20 } :: LightPreset, -- Color replaced per team
	PedestalSpot = { Color = rgb(255, 255, 255), Brightness = 2.6, Range = 18, Angle = 70, Shadows = true } :: LightPreset,
	Vending = { Color = rgb(120, 170, 255), Brightness = 0.6, Range = 9 } :: LightPreset,
	StatusOpen = { Color = rgb(90, 255, 120), Brightness = 0.5, Range = 7 } :: LightPreset,
	StatusSealed = { Color = rgb(255, 60, 40), Brightness = 0.9, Range = 9 } :: LightPreset,
}

-- Indoor haze. Kept light: the side lanes have ~110-stud sightlines, and a thick haze washed their
-- far walls into a flat dark grey (worst on the Open Office's light plaster).
Style.Atmosphere = {
	Density = 0.18,
	Offset = 0,
	Color = rgb(38, 36, 30),
	Decay = rgb(22, 20, 16),
	Glare = 0,
	Haze = 0.3,
}

Style.Bloom = { Intensity = 0.55, Size = 22, Threshold = 0.92 }
Style.ColorCorrection = { Saturation = -0.12, Contrast = 0.08, TintColor = rgb(255, 248, 232) }

-- Built-in particle textures shipped with the client (no asset ids required).
Style.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

return Style

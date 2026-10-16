--!strict
-- Team flags (the objective). Israeli flag design - white field, two horizontal stripes and a Star
-- of David - in each team's colour: Blue = the flag's own blue, Red = a red variant.
-- The design is drawn with a SurfaceGui (stripes = frames, star = six rotated line frames) on both
-- sides of a thin cloth part, so it stays crisp at any distance and needs no uploaded image.
--
--   FlagModel.World(team)          pole + flag for the station / dropped position. Its pivot is the
--                                   point CoreSystem places (CORE_OFFSET above the floor/pedestal).
--   FlagModel.AttachCarry(torso, team, name) -> BasePart   short pole + trailing flag on the back.

local FlagModel = {}

FlagModel.Colors = {
	Blue = Color3.fromRGB(0, 56, 184),
	Red = Color3.fromRGB(196, 30, 36),
} :: { [string]: Color3 }

local WHITE = Color3.fromRGB(244, 244, 240)
local POLE = Color3.fromRGB(70, 72, 76)

-- Canvas in "flag units": 220 wide x 160 tall (the real flag's 11:8).
local CANVAS = Vector2.new(440, 320)

local function colorFor(team: string): Color3
	return FlagModel.Colors[team] or Color3.fromRGB(200, 200, 200)
end

local function frame(parent: Instance, color: Color3, pos: Vector2, size: Vector2, rotation: number?)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(pos.X, pos.Y)
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.Rotation = rotation or 0
	f.Parent = parent
end

local function line(parent: Instance, color: Color3, a: Vector2, b: Vector2, width: number)
	local d = b - a
	local mid = (a + b) / 2
	frame(parent, color, mid, Vector2.new(d.Magnitude + width * 0.9, width), math.deg(math.atan2(d.Y, d.X)))
end

-- Draw the flag design on one face of `part`.
local function paint(part: BasePart, face: Enum.NormalId, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Design" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS
	gui.LightInfluence = 0.75
	gui.Brightness = 1.2
	gui.Parent = part

	local w, h = CANVAS.X, CANVAS.Y
	local u = h / 160 -- one flag unit in pixels
	frame(gui, WHITE, Vector2.new(w / 2, h / 2), Vector2.new(w, h))
	-- Stripes: 25 units tall, 15 units from the top and bottom edges.
	frame(gui, color, Vector2.new(w / 2, (15 + 12.5) * u), Vector2.new(w, 25 * u))
	frame(gui, color, Vector2.new(w / 2, h - (15 + 12.5) * u), Vector2.new(w, 25 * u))
	-- Star of David: two interlaced triangles, outline only.
	local center = Vector2.new(w / 2, h / 2)
	local r = 30 * u
	local width = 5.5 * u
	for _, start in { -90, 90 } do
		local pts = {}
		for k = 0, 2 do
			local ang = math.rad(start + k * 120)
			table.insert(pts, center + Vector2.new(math.cos(ang), math.sin(ang)) * r)
		end
		for k = 1, 3 do
			line(gui, color, pts[k], pts[k % 3 + 1], width)
		end
	end
end

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis (X) -> vertical

-- World flag. Built around the origin (= the pivot); the pole foot is `footDrop` below it.
function FlagModel.World(team: string, footDrop: number): Model
	local color = colorFor(team)
	local model = Instance.new("Model")
	model.Name = "Flag_" .. team
	model:SetAttribute("Team", team)

	local pivot = newPart("Pivot", Vector3.new(0.2, 0.2, 0.2), color, Enum.Material.SmoothPlastic)
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CFrame = CFrame.identity
	pivot.Parent = model

	local poleLength = 7.6
	local pole = newPart("Pole", Vector3.new(poleLength, 0.22, 0.22), POLE, Enum.Material.Metal)
	pole.Shape = Enum.PartType.Cylinder
	pole.Anchored = true
	pole.CFrame = CFrame.new(0, -footDrop + poleLength / 2, 0) * VERTICAL
	pole.Parent = model

	local top = -footDrop + poleLength
	local finial =
		newPart("Finial", Vector3.new(0.42, 0.42, 0.42), Color3.fromRGB(150, 140, 110), Enum.Material.Metal)
	finial.Shape = Enum.PartType.Ball
	finial.Anchored = true
	finial.CFrame = CFrame.new(0, top + 0.15, 0)
	finial.Parent = model

	local clothSize = Vector3.new(4.4, 3.2, 0.06)
	local cloth = newPart("Cloth", clothSize, WHITE, Enum.Material.Fabric)
	cloth.Anchored = true
	cloth.CFrame = CFrame.new(0.11 + clothSize.X / 2 + 0.02, top - 0.2 - clothSize.Y / 2, 0)
	cloth.Parent = model
	paint(cloth, Enum.NormalId.Front, color)
	paint(cloth, Enum.NormalId.Back, color)
	light(cloth, color, 14, 1.6)

	model.PrimaryPart = pivot
	return model
end

-- Carried flag: short pole on the carrier's back with the flag trailing behind (visible from the
-- sides and behind). Returns the pole (named `name`); the cloth is parented under it.
function FlagModel.AttachCarry(torso: BasePart, team: string, name: string): BasePart
	local color = colorFor(team)
	local back = torso.Size.Z * 0.5 + 0.2 -- characters face -Z, so +Z is the back

	local poleLength = 4.6
	local pole = newPart(name, Vector3.new(poleLength, 0.16, 0.16), POLE, Enum.Material.Metal)
	pole.Shape = Enum.PartType.Cylinder
	pole.Massless = true
	pole.CFrame = torso.CFrame * CFrame.new(0.35, 1.2, back) * VERTICAL
	local poleWeld = Instance.new("WeldConstraint")
	poleWeld.Part0 = torso
	poleWeld.Part1 = pole
	poleWeld.Parent = pole

	-- Cloth in the torso's YZ plane, trailing backwards from the top of the pole.
	local clothSize = Vector3.new(0.05, 1.7, 2.4)
	local cloth = newPart("Cloth", clothSize, WHITE, Enum.Material.Fabric)
	cloth.Massless = true
	local poleTop = 1.2 + poleLength / 2
	cloth.CFrame = torso.CFrame
		* CFrame.new(0.35, poleTop - 0.15 - clothSize.Y / 2, back + 0.08 + clothSize.Z / 2)
	local clothWeld = Instance.new("WeldConstraint")
	clothWeld.Part0 = pole
	clothWeld.Part1 = cloth
	clothWeld.Parent = cloth
	paint(cloth, Enum.NormalId.Right, color)
	paint(cloth, Enum.NormalId.Left, color)
	light(cloth, color, 16, 1.8)
	cloth.Parent = pole
	return pole
end

return FlagModel

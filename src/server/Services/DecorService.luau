--!strict
-- Swaps handmade decoration (Facility.Decor, models tagged "DecorSlot") for Creator Store models.
-- Each model is loaded once (InsertService), cleaned (every script removed, anchored, no touch
-- events), scaled and placed, then the handmade piece is removed. Anything that fails keeps the
-- handmade piece.
--   Floor kinds (Plant, Drum, WetSign): scaled to a height, stood on the slot's floor spot.
--   Paintings (slot Kind "Painting", attribute Art): hung flat on the wall where the handmade print
--   was (attribute WallNormal), picture side out, each painting used once.
--
-- Roblox only lets a game load models its owner has in their inventory: click "Get" on each store
-- page first (links in the comments). 0 / empty = keep the handmade version.

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoreAssets = require(script.Parent.Parent:WaitForChild("Systems"):WaitForChild("StoreAssets"))
local HorrorSpots = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HorrorSpots"))

local DecorService = {}

-- AssetIds: several = alternated between the slots of that kind.
type Spec = { AssetIds: { number }, Height: number, Solid: boolean }
-- Width = true: Height is the picture's width instead (for a narrow wall).
type PaintingSpec = { AssetId: number, Height: number, Flip: boolean?, Reuse: boolean?, Width: boolean? }
-- Size: target height in studs, or with Span = true the largest horizontal side (flat things).
-- Yaw: extra turn in degrees if the model's front isn't its pivot's look direction.
-- YawBlue: Blue-half (unmirrored) yaw instead of Yaw, when the halves should differ.
-- RedTint: in the Red half, recolour the model's blue parts / lights / particles red.
type PropSpec = {
	AssetId: number,
	Size: number,
	Span: boolean?,
	Solid: boolean,
	Yaw: number?,
	YawBlue: number?,
	RedTint: boolean?,
}

DecorService.Assets = {
	-- Realistic potted plants (2026-10-13; the old "Potted Plant" 8704290264 floated, removed):
	-- https://create.roblox.com/store/asset/11900728265 "Fiddle-leaf fig potted plant" (harht)
	-- https://create.roblox.com/store/asset/5244125861  "Office Plant" (Wiixle)
	Plant = { AssetIds = { 11900728265, 5244125861 }, Height = 5, Solid = false },
	-- https://create.roblox.com/store/asset/13304723548 "Rusty Barrel" (2BeeSupreme, verified)
	Drum = { AssetIds = { 13304723548 }, Height = 3.2, Solid = true },
	-- https://create.roblox.com/store/asset/2414969986  "Caution Wet Floor Sign" (Robloxian1036)
	WetSign = { AssetIds = { 2414969986 }, Height = 2.4, Solid = false },
} :: { [string]: Spec }

-- Owner's paintings (inventory, 2026-10-13 / 16). Height in studs. Flip = picture faced the wall.
-- Reuse = hung in both halves (where Decor puts it: office / lab / atrium, owner 2026-10-16).
DecorService.Paintings = {
	Scream = { AssetId = 24734328, Height = 2.6 }, -- "Model 10" (The Scream), Long Hall
	-- (office + lab pictures 80% bigger, owner 2026-10-16)
	SeekEyes = { AssetId = 12549097995, Height = 3.96, Reuse = true }, -- "doors seek eye painting" (lab)
	SpongeBob = { AssetId = 108835817655664, Height = 4.68, Reuse = true }, -- "Picture Frame Sponge Bob ..." (office, x2)
	LabRules = { AssetId = 14629433802, Height = 2.6, Reuse = true }, -- "Science Lab Rules" (lab)
	NickiMinaj = { AssetId = 9615253224, Height = 4.32, Reuse = true }, -- "Nickiinaj frame picture" (office)
	-- "Framed Map": Blue office only, beside the wardrobe; 7.56 wide (+80%, owner 2026-10-16)
	FramedMap = { AssetId = 1921239131, Height = 7.56, Width = true },
	OldSoldier = { AssetId = 12496894931, Height = 4.32, Reuse = true }, -- "Old Soldier Picture" (lab)
	OldPicture = { AssetId = 10219026994, Height = 2.4, Reuse = true }, -- "Old Picture1" (atrium)
} :: { [string]: PaintingSpec }

-- Owner's own pictures (shift/pictures), shown as a Decal on a handmade frame (Decor imagePrint).
-- Upload each file to Roblox (Creator Hub > Decals, or Studio's Asset Manager) and put its id here:
-- a Decal id or its Image id both work. 0 = the frame stays a plain print.
DecorService.Images = {
	KeepCalm = 140318168772884, -- decal "office": office.jpg ("Keep calm and keep up the good work"), both offices
	AlienTuxedo = 84760537125619, -- decal "Alien": 14446676_c3p0lincoln-22x28-vert.jpg (arms crossed), Blue lab
	AlienSuit = 80347366742349, -- decal "Alien2": 61KcgQ+ETRL._AC_SX679_.jpg (grey suit), Red lab
} :: { [string]: number }

-- Owner's office / lab props (inventory, added 2026-10-15), placed at Decor "Prop" spots.
-- Where the owner added several of the same thing, one is used; the others are listed as swaps.
DecorService.Props = {
	-- Open Office
	Desk = { AssetId = 10823681576, Size = 8, Span = true, Solid = true }, -- "Office Desk" (monitor + chair)
	Laptop = { AssetId = 5847437396, Size = 1.1, Span = true, Solid = false }, -- "Officers Laptop & Home Laptop"
	Phone = { AssetId = 14131359412, Size = 0.7, Span = true, Solid = false }, -- "Office Phone"
	Papers = { AssetId = 65449859, Size = 0.9, Span = true, Solid = false }, -- "Office Papers"
	Printer = { AssetId = 12778926198, Size = 6.84, Solid = true }, -- "Office Printer" (floor copier)
	Lockers = { AssetId = 6427509769, Size = 6.2, Solid = true }, -- "FNaF Office Lockers"
	Wardrobe = { AssetId = 127981598253870, Size = 7.2, Solid = true }, -- "[2024] Wardrobe(free ver.)"
	Bookshelf = { AssetId = 9914694425, Size = 9.45, Solid = true }, -- "Bookshelf (With Books)", +35%
	-- "Office Trashcan" (grey mesh). Swap: 106165079565489 "Trash Bin Decor Under Desk Office Bin".
	Trash = { AssetId = 16276659824, Size = 1.3, Solid = false },
	-- Maintenance Gallery (lab)
	-- "lab mesh" (long bench: cabinet, microscopes, monitor). Swap: 4583681595 "Lab table".
	LabBench = { AssetId = 11845770500, Size = 17.6, Span = true, Solid = true },
	-- "Alien Lab Tube": Red half turned 270 deg left; Blue half (near the Blue spawn) a further 180.
	-- Blue liquid; red in the Red half (RedTint).
	LabTube = { AssetId = 10269668024, Size = 7, Solid = true, Yaw = 270, YawBlue = 90, RedTint = true },
	-- Break room vending machines (replace the handmade ones; same 7-stud height), one per half.
	VendingSnack = { AssetId = 10904552162, Size = 7, Solid = true }, -- "Snack Vending Machine Mesh PBR"
	VendingPepsi = { AssetId = 18596171564, Size = 7, Solid = true }, -- "Pepsi Vending Machine Mesh"
	-- Break room kitchen (both halves)
	Microwave = { AssetId = 9587284235, Size = 1.8, Span = true, Solid = false }, -- "Sleek Kitchen Microwave"
	Blender = { AssetId = 107438231, Size = 1.2, Solid = false }, -- "Household Blender"
	WaterDispenser = { AssetId = 10904549519, Size = 7, Solid = true }, -- "Water Dispenser Mesh PBR" (vending height)
	-- same model in the Open Office, 20% bigger (owner, 2026-10-16)
	OfficeWaterDispenser = { AssetId = 10904549519, Size = 8.4, Solid = true },
} :: { [string]: PropSpec }

local function noCollide(model: Model, solid: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = solid
			d.CanQuery = solid
			d.CanTouch = false
		end
	end
end

-- Drop a model that still hovers: cast up from under the floor at its centre against its own
-- parts; the first hit is its real underside.
local function settle(model: Model, floor: Vector3)
	local parts = {}
	local was: { [BasePart]: boolean } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			table.insert(parts, d)
			was[d] = d.CanQuery
			d.CanQuery = true
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local lo, hi = HorrorSpots.VisibleBounds(model)
	local lowest = math.huge
	local c = (lo + hi) / 2
	local r = math.min(hi.X - lo.X, hi.Z - lo.Z) * 0.2
	for _, off in
		{
			Vector3.zero,
			Vector3.new(r, 0, 0),
			Vector3.new(-r, 0, 0),
			Vector3.new(0, 0, r),
			Vector3.new(0, 0, -r),
		}
	do
		local hit = workspace:Raycast(
			Vector3.new(c.X, floor.Y - 1, c.Z) + off,
			Vector3.new(0, hi.Y - floor.Y + 2, 0),
			params
		)
		if hit then
			lowest = math.min(lowest, hit.Position.Y)
		end
	end
	for part, q in was do
		part.CanQuery = q
	end
	-- Capped, so a pot with an open bottom (ray hits the soil inside) can't sink into the floor.
	local gap = lowest - floor.Y
	if lowest < math.huge and gap > 0.05 and gap < (hi.Y - lo.Y) * 0.3 then
		model:PivotTo(model:GetPivot() - Vector3.new(0, gap, 0))
		print(`[Decor] {model.Name} was floating {string.format("%.2f", gap)} studs: lowered onto the floor`)
	end
end

local kindCount: { [string]: number } = {}

local function placeFloor(slotModel: Model, kind: string, spec: Spec): boolean
	local n = (kindCount[kind] or 0) + 1
	kindCount[kind] = n
	local base = StoreAssets.Load(spec.AssetIds[(n - 1) % #spec.AssetIds + 1])
		or StoreAssets.Load(spec.AssetIds[1])
	if not base then
		return false
	end
	local model = base:Clone()
	local slotCF, slotSize = slotModel:GetBoundingBox()
	local floor = slotCF.Position - Vector3.new(0, slotSize.Y / 2, 0)

	StoreAssets.ScaleTo(model, spec.Height)
	noCollide(model, spec.Solid)
	-- A little random turn (so repeats don't look cloned), then stand the visible parts on the slot's
	-- floor spot (handmade piece's bottom centre) and drop anything still hovering.
	local turn = CFrame.Angles(0, math.rad((slotModel:GetFullName():len() * 47) % 360), 0)
	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(pivot.Position) * turn * pivot.Rotation)
	local lo, hi = HorrorSpots.VisibleBounds(model)
	local bottom = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	model:PivotTo(model:GetPivot() + (floor - bottom))
	model.Parent = slotModel.Parent
	settle(model, floor)
	model.Name = slotModel.Name
	slotModel:Destroy()
	return true
end

-- World direction the picture side faces (decal / texture / SurfaceGui face), or a guess from the
-- thinnest axis of the biggest part. Second result: how it was found (for the log).
local function pictureFront(model: Model): (Vector3, string)
	for _, d in model:GetDescendants() do
		local parent = d.Parent
		if parent and parent:IsA("BasePart") and (d:IsA("Decal") or d:IsA("SurfaceGui")) then
			local faceId = (d :: any).Face :: Enum.NormalId
			return parent.CFrame:VectorToWorldSpace(Vector3.FromNormalId(faceId)), "decal"
		end
	end
	local best: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			if not best or d.Size.Magnitude > best.Size.Magnitude then
				best = d
			end
		end
	end
	if not best then
		return Vector3.new(0, 0, -1), "none"
	end
	local size = best.Size
	if size.X <= size.Y and size.X <= size.Z then
		return best.CFrame.RightVector, "guess"
	elseif size.Y <= size.X and size.Y <= size.Z then
		return best.CFrame.UpVector, "guess"
	end
	return -best.CFrame.LookVector, "guess"
end

local usedPaintings: { [string]: boolean } = {}

local function placePainting(slotModel: Model): boolean
	local art = slotModel:GetAttribute("Art")
	local normal = slotModel:GetAttribute("WallNormal")
	local spec = type(art) == "string" and DecorService.Paintings[art] or nil
	if not spec or typeof(normal) ~= "Vector3" or (usedPaintings[art :: string] and not spec.Reuse) then
		return false
	end
	local base = StoreAssets.Load(spec.AssetId)
	if not base then
		return false
	end
	usedPaintings[art :: string] = true
	local model = base:Clone()
	noCollide(model, false)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end

	-- Turn the picture side to face out of the wall (rotation about the vertical only).
	local front, how = pictureFront(model)
	if spec.Flip then
		front = -front
	end
	local flat = Vector3.new(front.X, 0, front.Z)
	if flat.Magnitude < 0.3 then
		-- Lying flat: stand it up first (picture up -> picture toward -Z), then turn.
		local pivot = model:GetPivot()
		local tilt = if front.Y > 0
			then CFrame.Angles(-math.pi / 2, 0, 0)
			else CFrame.Angles(math.pi / 2, 0, 0)
		model:PivotTo(CFrame.new(pivot.Position) * tilt * pivot.Rotation)
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local angle = math.atan2(flat:Cross(normal).Y, flat:Dot(normal))
	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, angle, 0) * pivot.Rotation)
	StoreAssets.ScaleTo(model, spec.Height, spec.Width) -- (turned flat to the wall: widest side = width)

	-- Same centre as the handmade print, back flat against the wall.
	local slo, shi = HorrorSpots.VisibleBounds(slotModel)
	local lo, hi = HorrorSpots.VisibleBounds(model)
	local slotBack = math.min(slo:Dot(normal), shi:Dot(normal))
	local back = math.min(lo:Dot(normal), hi:Dot(normal))
	local offset = (slo + shi) / 2 - (lo + hi) / 2
	offset -= normal * offset:Dot(normal)
	model:PivotTo(model:GetPivot() + offset + normal * (slotBack - back))
	model.Name = "Painting_" .. art
	model.Parent = slotModel.Parent
	print(`[Decor] painting {art} hung (picture side: {how})`)
	slotModel:Destroy()
	return true
end

-- Blue-ish colours (cyan .. violet, not grey) turned to the same shade of red.
-- (less saturated than a straight hue swap so the aliens inside stay visible: -10%, -10%, then
-- +5%, owner 2026-10-16)
local RED_SATURATION = 0.85
local function reddened(c: Color3): Color3
	local h, s, val = c:ToHSV()
	if s < 0.2 or h < 0.42 or h > 0.8 then
		return c
	end
	return Color3.fromHSV(0.0, s * RED_SATURATION, val)
end

local function tintRed(model: Model): number
	local changed = 0
	local function seq(cs: ColorSequence): ColorSequence
		local keys = {}
		for _, k in cs.Keypoints do
			table.insert(keys, ColorSequenceKeypoint.new(k.Time, reddened(k.Value)))
		end
		return ColorSequence.new(keys)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local c = reddened(d.Color)
			if c ~= d.Color then
				d.Color = c
				changed += 1
			end
		elseif d:IsA("Light") then
			d.Color = reddened(d.Color)
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			(d :: any).Color = seq((d :: any).Color)
		elseif d:IsA("Decal") then -- (Texture inherits Decal)
			d.Color3 = reddened(d.Color3)
		elseif d:IsA("SpecialMesh") then
			local vc = d.VertexColor
			local c = reddened(Color3.new(math.min(vc.X, 1), math.min(vc.Y, 1), math.min(vc.Z, 1)))
			d.VertexColor = Vector3.new(c.R, c.G, c.B)
		end
	end
	return changed
end

-- A store prop at a Decor "Prop" spot: turned to face the room, scaled, stood on the spot (back
-- against the wall when AgainstWall), then dropped if it still hovers.
local function placeProp(slotModel: Model): boolean
	local key = slotModel:GetAttribute("Prop")
	local facing = slotModel:GetAttribute("Facing")
	local spec = type(key) == "string" and DecorService.Props[key] or nil
	if not spec or typeof(facing) ~= "Vector3" then
		return false
	end
	local base = StoreAssets.Load(spec.AssetId)
	if not base then
		return false
	end
	local model = base:Clone()
	noCollide(model, spec.Solid)
	StoreAssets.ScaleTo(model, spec.Size, spec.Span)
	if spec.RedTint and slotModel:GetAttribute("Mirror") == true then
		local n = tintRed(model)
		if n == 0 then
			warn(`[Decor] {key}: no blue parts found to tint red (textured liquid?)`)
		end
	end

	-- Turn about the vertical so the model's front (pivot look direction, + Yaw) faces `facing`.
	local pivot = model:GetPivot()
	local look = pivot.LookVector
	local front = Vector3.new(look.X, 0, look.Z)
	front = if front.Magnitude > 0.1 then front.Unit else Vector3.new(0, 0, -1)
	-- Yaw turns left (counter-clockwise from above); mirrored in the Red half so both halves match.
	local mirror = slotModel:GetAttribute("Mirror") == true
	local yaw = if mirror then -(spec.Yaw or 0) else (spec.YawBlue or spec.Yaw or 0)
	local angle = math.atan2(front:Cross(facing).Y, front:Dot(facing)) + math.rad(yaw)
	model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, angle, 0) * pivot.Rotation)

	-- Spot: explicit attribute (handmade slots), else the Decor marker's position.
	local spotAttr = slotModel:GetAttribute("Spot")
	local spot = if typeof(spotAttr) == "Vector3"
		then spotAttr
		else slotModel:GetBoundingBox().Position - Vector3.new(0, 0.05, 0)
	local lo, hi = HorrorSpots.VisibleBounds(model)
	local target = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local move = spot - target
	if slotModel:GetAttribute("AgainstWall") then
		-- Back (the side opposite `facing`) 0.05 off the wall plane through the spot.
		local back = math.min(lo:Dot(facing), hi:Dot(facing))
		local centre = target:Dot(facing)
		move += facing * ((spot:Dot(facing) + 0.05) - back - (spot:Dot(facing) - centre))
	end
	model:PivotTo(model:GetPivot() + move)
	model.Name = "Prop_" .. key -- before parenting: clients find props by name (lab-tube hum)
	model.Parent = slotModel.Parent
	settle(model, spot)
	print(`[Decor] prop {key} placed`)
	slotModel:Destroy()
	return true
end

-- Decal id -> its image (a Decal asset loads as a model holding the Decal); else use the id as is.
local textures: { [number]: string } = {}
local function textureFor(id: number): string
	local cached = textures[id]
	if cached then
		return cached
	end
	local texture = "rbxassetid://" .. tostring(id)
	local ok, loaded = pcall(InsertService.LoadAsset, InsertService, id)
	if ok and loaded then
		local decal = loaded:FindFirstChildWhichIsA("Decal", true)
		if decal and decal.Texture ~= "" then
			texture = decal.Texture
		end
		loaded:Destroy()
	end
	textures[id] = texture
	return texture
end

local function applyImage(art: Instance)
	local key = art:GetAttribute("Image")
	local normal = art:GetAttribute("ImageFace")
	local id = type(key) == "string" and DecorService.Images[key] or nil
	if not art:IsA("BasePart") or not id or id == 0 or typeof(normal) ~= "Vector3" then
		return
	end
	local decal = Instance.new("Decal")
	decal.Name = "Image"
	decal.Texture = textureFor(id)
	decal.Face = Enum.NormalId.Front
	-- the frame parts are axis-aligned: pick the face pointing out of the wall
	if math.abs(normal.X) > 0.5 then
		decal.Face = if normal.X > 0 then Enum.NormalId.Right else Enum.NormalId.Left
	else
		decal.Face = if normal.Z > 0 then Enum.NormalId.Back else Enum.NormalId.Front
	end
	decal.Parent = art
	print(`[Decor] image {key} applied`)
end

function DecorService:Init() end

function DecorService:Start()
	task.spawn(function()
		local facility = workspace:WaitForChild("Facility", 60)
		if not facility then
			return
		end
		for _, art in CollectionService:GetTagged("DecorImage") do
			local ok, err = pcall(applyImage, art)
			if not ok then
				warn("[Decor] " .. tostring(err))
			end
		end
		local swapped, kept = 0, 0
		for _, inst in CollectionService:GetTagged("DecorSlot") do
			local kind = inst:GetAttribute("Kind")
			if inst:IsA("Model") and type(kind) == "string" then
				local ok, placed
				if kind == "Painting" then
					ok, placed = pcall(placePainting, inst)
				elseif kind == "Prop" then
					ok, placed = pcall(placeProp, inst)
				else
					local spec = DecorService.Assets[kind]
					if spec and #spec.AssetIds > 0 then
						ok, placed = pcall(placeFloor, inst, kind, spec)
					else
						continue
					end
				end
				if ok and placed then
					swapped += 1
				else
					if not ok then
						warn("[Decor] " .. tostring(placed))
					end
					kept += 1
				end
			end
		end
		if swapped + kept > 0 then
			print(`[Decor] store models placed: {swapped}, handmade kept: {kept}`)
		end
	end)
end

return DecorService

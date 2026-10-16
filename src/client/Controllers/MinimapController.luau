--!strict
-- Minimap (top-left, follows you, north-up) and the full map ([M]). Both are drawn from the live
-- facility geometry (walls, floors, solid cover, blast doors) plus room names (Facility.MapRooms).
-- The map is turned so your own base is always on the left.
--
-- What shows (Tuning.Map):
--   you (arrow) and teammates (dots)              always
--   enemies                                       only where they last fired, for RevealSeconds
--   both flag stations                            always
--   a dropped flag                                always (blinking)
--   your team's carrier                           always (ring)
--   the enemy carrying YOUR flag                  a pulse every CarrierRevealInterval seconds
--   pings                                         PingSeconds; also a marker in the world
-- Pinging: middle mouse / [Z] pings where you aim; with the full map open, click to ping.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local UI = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UI:WaitForChild("UIKit"))
local Theme = require(UI:WaitForChild("Theme"))
local MatchStore = require(UI:WaitForChild("MatchStore"))

local MinimapController = {}

local player = Players.LocalPlayer

-- Facility bounds (Layout): x +-187, z +-81.
local HALF_X, HALF_Z = 187, 81
local MINI_SIZE = 168 -- px (reference resolution)
local PING_SOUND = 82041413720379 -- yours: "UI Ping 1" (was PSE "Synth ... Ding" 9126073318)

local COLORS = {
	Floor = Color3.fromRGB(46, 50, 56),
	Wall = Color3.fromRGB(196, 200, 206),
	LowWall = Color3.fromRGB(120, 126, 134),
	Cover = Color3.fromRGB(92, 98, 106),
	DoorClosed = Color3.fromRGB(200, 90, 70),
	Label = Color3.fromRGB(150, 156, 164),
	Ping = Theme.Colors.Amber,
	Self = Color3.fromRGB(240, 242, 244),
}

type Rect = { X0: number, Z0: number, X1: number, Z1: number }
type Layer = {
	Root: Frame, -- holds the canvas (clipped for the minimap)
	Canvas: Frame,
	Scale: number, -- px per stud
	Dynamic: Frame,
	Pool: { Frame },
	Used: number,
	Doors: { [BasePart]: Frame },
}

local mini: Layer? = nil
local full: Layer? = nil
local fullOpen = false
local flip = 1 -- -1 for Red (rotate 180 deg so your base is on the left)
local builtFor: string? = nil

local reveals: { [string]: { Position: Vector3, At: number, Team: string? } } = {}
local pings: {
	[string]: { Position: Vector3, At: number, Marker: BillboardGui?, Anchor: Attachment?, World: Model? },
} =
	{}

-- World (x, z) -> canvas px.
local function toCanvas(layer: Layer, x: number, z: number): (number, number)
	return (flip * x + HALF_X) * layer.Scale, (HALF_Z - flip * z) * layer.Scale
end

local function fromCanvas(layer: Layer, u: number, v: number): Vector3
	local x = u / layer.Scale - HALF_X
	local z = HALF_Z - v / layer.Scale
	return Vector3.new(flip * x, 1, flip * z)
end

local function rectOf(part: BasePart): Rect
	local h = part.Size / 2
	local p = part.Position
	-- Parts are axis-aligned boxes or Y-rotated by 90 deg at most; use the world-space extents.
	local cf = part.CFrame
	local ex = math.abs(cf.RightVector.X) * h.X
		+ math.abs(cf.UpVector.X) * h.Y
		+ math.abs(cf.LookVector.X) * h.Z
	local ez = math.abs(cf.RightVector.Z) * h.X
		+ math.abs(cf.UpVector.Z) * h.Y
		+ math.abs(cf.LookVector.Z) * h.Z
	return { X0 = p.X - ex, Z0 = p.Z - ez, X1 = p.X + ex, Z1 = p.Z + ez }
end

local function drawRect(
	layer: Layer,
	parent: Instance,
	r: Rect,
	color: Color3,
	transparency: number,
	z: number
): Frame
	local ax, ay = toCanvas(layer, r.X0, r.Z0)
	local bx, by = toCanvas(layer, r.X1, r.Z1)
	local minPx = 1
	return UIKit.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(math.min(ax, bx), math.min(ay, by)),
		Size = UDim2.fromOffset(math.max(minPx, math.abs(bx - ax)), math.max(minPx, math.abs(by - ay))),
		ZIndex = z,
		Parent = parent,
	})
end

local function isCover(part: BasePart): boolean
	return part.CanCollide and part.Size.Y >= 2.5 and part.Transparency < 0.9
end

-- Static layer: floors, walls, cover, labels.
local function drawStatic(layer: Layer, facility: Instance)
	local structure = facility:FindFirstChild("Structure")
	local props = facility:FindFirstChild("Props")
	if structure then
		for _, part in structure:GetChildren() do
			if part:IsA("BasePart") and part.Name == "Floor" then
				drawRect(layer, layer.Canvas, rectOf(part), COLORS.Floor, 0.15, 1)
			end
		end
		for _, part in structure:GetChildren() do
			if part:IsA("BasePart") and part.Name == "Wall" then
				local bottom = part.Position.Y - part.Size.Y / 2
				local top = part.Position.Y + part.Size.Y / 2
				if bottom < 1 then -- skip lintels above doors (they'd draw doorways shut)
					local low = top < 6 -- window sills / vent walls
					drawRect(
						layer,
						layer.Canvas,
						rectOf(part),
						if low then COLORS.LowWall else COLORS.Wall,
						0,
						3
					)
				end
			end
		end
	end
	if props then
		for _, part in props:GetChildren() do
			if part:IsA("BasePart") and isCover(part) then
				local wood = part.Name == "WoodDoor"
				drawRect(
					layer,
					layer.Canvas,
					rectOf(part),
					if wood then COLORS.LowWall else COLORS.Cover,
					0.1,
					2
				)
			end
		end
	end
	local rooms = facility:FindFirstChild("MapRooms")
	if rooms then
		local size = if layer == full then Theme.TextSize.Tiny else 8
		for _, value in rooms:GetChildren() do
			if value:IsA("Vector3Value") then
				local u, v = toCanvas(layer, value.Value.X, value.Value.Z)
				-- The label box is the room's own footprint (wrapping / shrinking to fit), so names of
				-- neighbouring rooms can't run into each other.
				local footprint = value:GetAttribute("Size")
				local w, h = 120, 12
				if typeof(footprint) == "Vector3" then
					w = math.max(footprint.X * layer.Scale - 4, 16)
					h = math.max(footprint.Z * layer.Scale - 4, 10)
				end
				local label = UIKit.text(string.upper(value.Name), {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(u, v),
					Size = UDim2.fromOffset(w, h),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextScaled = true,
					TextWrapped = true,
					FontFace = Theme.Fonts.Medium,
					TextColor3 = COLORS.Label,
					TextTransparency = 0.15,
					TextStrokeTransparency = 0.5,
					ZIndex = 4,
					Parent = layer.Canvas,
				})
				local cap = Instance.new("UITextSizeConstraint")
				cap.MaxTextSize = size -- never bigger than before
				cap.MinTextSize = 5
				cap.Parent = label
			end
		end
	end
	-- Blast doors / shutters: drawn live (closed = red bar).
	local hinges = facility:FindFirstChild("Hinges")
	if hinges then
		for _, d in hinges:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Panel" or d.Name == "Shutter") then
				layer.Doors[d] = drawRect(layer, layer.Canvas, rectOf(d), COLORS.DoorClosed, 0, 4)
			end
		end
	end
end

local function newLayer(parent: Instance, scale: number, clip: boolean): Layer
	local root = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = clip,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	local canvas = UIKit.new("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(2 * HALF_X * scale, 2 * HALF_Z * scale),
		Parent = root,
	})
	local dynamic = UIKit.new("Frame", {
		Name = "Dynamic",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = canvas,
	})
	return { Root = root, Canvas = canvas, Scale = scale, Dynamic = dynamic, Pool = {}, Used = 0, Doors = {} }
end

-- Dynamic icons (pooled squares; rotated 45 deg = diamond).
local function icon(layer: Layer, x: number, z: number, size: number, color: Color3, opts: { [string]: any }?)
	layer.Used += 1
	local f = layer.Pool[layer.Used]
	if not f then
		f = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			ZIndex = 12,
			Parent = layer.Dynamic,
		}, { UIKit.corner(UDim.new(0.5, 0)), UIKit.stroke(Theme.Colors.Black, 0.3, 1) })
		layer.Pool[layer.Used] = f
	end
	local o = opts or {}
	local u, v = toCanvas(layer, x, z)
	f.Position = UDim2.fromOffset(u, v)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = o.Transparency or 0
	f.Rotation = o.Rotation or 0
	local corner = f:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = if o.Square then UDim.new(0, 1) else UDim.new(0.5, 0)
	end
	local stroke = f:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = o.StrokeColor or Theme.Colors.Black
		stroke.Thickness = o.StrokeThickness or 1
		stroke.Transparency = o.StrokeTransparency or 0.3
	end
	f.Visible = true
end

local function beginFrame(layer: Layer)
	layer.Used = 0
end

local function endFrame(layer: Layer)
	for i = layer.Used + 1, #layer.Pool do
		layer.Pool[i].Visible = false
	end
end

-- Characters ------------------------------------------------------------------------------------

local function modelTeam(model: Instance?): string?
	local team = model and model:GetAttribute("Team")
	return if type(team) == "string" then team else nil
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(model: Model): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function allCharacters(): { Model }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(out, p.Character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, m in bots:GetChildren() do
			if m:IsA("Model") then
				table.insert(out, m)
			end
		end
	end
	return out
end

local function findShooter(name: string): Model?
	local p = Players:FindFirstChild(name)
	if p and p:IsA("Player") and p.Character then
		return p.Character
	end
	local bots = workspace:FindFirstChild("Bots")
	local m = bots and bots:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

-- Pings -------------------------------------------------------------------------------------------

local function clearPing(name: string)
	local old = pings[name]
	if old then
		if old.Marker then
			old.Marker:Destroy()
		end
		if old.Anchor then
			old.Anchor:Destroy()
		end
		if old.World then
			old.World:Destroy()
		end
		pings[name] = nil
	end
end

local function showPing(name: string, position: Vector3)
	clearPing(name)
	local anchor = Instance.new("Attachment")
	anchor.Name = "PingAnchor"
	anchor.WorldPosition = position + Vector3.new(0, 1.5, 0)
	anchor.Parent = workspace.Terrain
	local gui = UIKit.new("BillboardGui", {
		Name = "Ping_" .. name,
		Adornee = anchor,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(180, 60),
		Parent = UIKit.getPlayerGui(),
	})
	local pop = Instance.new("UIScale")
	pop.Scale = 0.3
	pop.Parent = gui
	UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(90, 3),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 45,
		BackgroundColor3 = COLORS.Ping,
		BorderSizePixel = 0,
		Parent = gui,
	}, { UIKit.stroke(Theme.Colors.Black, 0.2, 1) })
	local label = UIKit.mono("", {
		Name = "Distance",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 28),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 18,
		TextColor3 = COLORS.Ping,
		TextStrokeTransparency = 0.4,
		Parent = gui,
	})
	label:SetAttribute("Owner", name)
	-- In the world too: a thin light column and a ring on the spot, so the pinged place is easy to
	-- find in the actual facility (not only on the map). Client-only, no collision, gone with the ping.
	local world = Instance.new("Model")
	world.Name = "PingWorld_" .. name
	local function piece(partName: string, size: Vector3, cf: CFrame, transparency: number): Part
		local p = Instance.new("Part")
		p.Name = partName
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.CFrame = cf
		p.Color = COLORS.Ping
		p.Material = Enum.Material.Neon
		p.Transparency = transparency
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = world
		return p
	end
	local up = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis (X) pointing up
	piece("Column", Vector3.new(7, 0.18, 0.18), CFrame.new(position + Vector3.new(0, 3.5, 0)) * up, 0.45)
	piece("Ring", Vector3.new(0.05, 2.4, 2.4), CFrame.new(position + Vector3.new(0, 0.04, 0)) * up, 0.55)
	world.Parent = workspace
	pings[name] = { Position = position, At = os.clock(), Marker = gui, Anchor = anchor, World = world }
	-- Quick pop-in so a new ping catches the eye.
	UIKit.tween(pop, 0.18, { Scale = 1 })

	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(PING_SOUND)
	s.Volume = 0.6
	s.Parent = SoundService
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

local pingRemote: RemoteEvent? = nil

-- Pings show on our own screen immediately (no round trip); the server relays them to the team and
-- its echo back to us is ignored.
local lastSent = -math.huge

local function sendPing(position: Vector3)
	local now = os.clock()
	if now - lastSent < Tuning.Map.PingCooldown then
		return
	end
	lastSent = now
	showPing(player.Name, position)
	if pingRemote then
		pingRemote:FireServer(position)
	end
end

local function pingAtCrosshair()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local cf = camera.CFrame
	local hit = workspace:Raycast(cf.Position, cf.LookVector * 400, params)
	if hit then
		sendPing(hit.Position)
	end
end

-- Build -------------------------------------------------------------------------------------------

local miniHolder: Frame
local fullHolder: Frame
local fullPanel: Frame

local function rebuild()
	local facility = workspace:FindFirstChild("Facility")
	if not facility then
		return
	end
	local team = MatchStore.localTeam()
	flip = if team == "Red" then -1 else 1
	builtFor = team or "?"
	if mini then
		mini.Root:Destroy()
	end
	if full then
		full.Root:Destroy()
	end
	mini = newLayer(miniHolder, MINI_SIZE / (2 * Tuning.Map.MiniRadius), true)
	full = newLayer(fullHolder, 2.4, false)
	drawStatic(mini :: Layer, facility)
	drawStatic(full :: Layer, facility)
end

local function drawDynamic(layer: Layer, now: number)
	beginFrame(layer)
	local myTeam = MatchStore.localTeam()
	local enemy = Theme.enemyOf(myTeam)
	local small = if layer == full then 7 else 5

	-- Flag stations (always) and flags not at home.
	for team, home in MatchStore.HomePositions do
		icon(layer, home.X, home.Z, small + 4, Theme.teamColor(team), {
			Square = true,
			StrokeColor = Theme.Colors.White,
			StrokeTransparency = 0.2,
		})
	end
	for team, core in MatchStore.Cores do
		local c = core :: any
		if c.State == "Dropped" and typeof(c.Position) == "Vector3" then
			local blink = math.floor(now * 3) % 2 == 0
			icon(layer, c.Position.X, c.Position.Z, small + 4, Theme.teamColor(team), {
				Square = true,
				Rotation = 45,
				Transparency = if blink then 0 else 0.5,
				StrokeColor = Theme.Colors.White,
				StrokeThickness = 2,
			})
		elseif c.State == "Carried" and typeof(c.Position) == "Vector3" and team == myTeam then
			-- An enemy has our flag: pulse its position now and then.
			local interval = Tuning.Map.CarrierRevealInterval
			local shown = interval <= 0 or (now % interval) < Tuning.Map.CarrierRevealSeconds
			if shown then
				icon(layer, c.Position.X, c.Position.Z, small + 6, Theme.teamColor(enemy), {
					StrokeColor = Theme.teamColor(team),
					StrokeThickness = 2,
					StrokeTransparency = 0,
				})
			end
		end
	end

	-- Teammates (always) and the carrier ring.
	local enemyFlag = enemy and (MatchStore.Cores[enemy] :: any)
	local carrierId = enemyFlag and enemyFlag.State == "Carried" and enemyFlag.CarrierUserId or nil
	for _, model in allCharacters() do
		if model ~= player.Character and modelTeam(model) == myTeam and alive(model) then
			local root = rootOf(model)
			if root then
				local p = Players:GetPlayerFromCharacter(model)
				local carrying = model:GetAttribute("CarryingCore") ~= nil
					or (p ~= nil and carrierId == p.UserId)
				icon(layer, root.Position.X, root.Position.Z, small, Theme.teamColor(myTeam), {
					StrokeColor = if carrying then Theme.Colors.White else Theme.Colors.Black,
					StrokeThickness = if carrying then 2 else 1,
					StrokeTransparency = if carrying then 0 else 0.3,
				})
			end
		end
	end

	-- Enemies where they last fired.
	for name, r in reveals do
		local age = now - r.At
		if age > Tuning.Map.RevealSeconds then
			reveals[name] = nil
		else
			icon(layer, r.Position.X, r.Position.Z, small, Theme.teamColor(r.Team), {
				Transparency = math.clamp(age / Tuning.Map.RevealSeconds, 0, 0.8),
			})
		end
	end

	-- Pings.
	for _, pg in pings do
		if now - pg.At <= Tuning.Map.PingSeconds then
			icon(
				layer,
				pg.Position.X,
				pg.Position.Z,
				math.floor((small + 3) * 1.5 + 0.5),
				COLORS.Ping,
				{ Square = true, Rotation = 45 }
			)
		end
	end

	-- You: a chevron-like marker (diamond + direction tick).
	local character = player.Character
	local root = character and rootOf(character)
	if root then
		local look = root.CFrame.LookVector
		local heading = math.deg(math.atan2(flip * look.X, flip * look.Z))
		icon(layer, root.Position.X, root.Position.Z, small + 2, COLORS.Self, {
			Square = true,
			Rotation = 45,
			StrokeColor = Theme.teamColor(myTeam),
			StrokeThickness = 2,
			StrokeTransparency = 0,
		})
		local tip = root.Position + Vector3.new(look.X, 0, look.Z).Unit * (if layer == full then 4 else 6)
		icon(layer, tip.X, tip.Z, 3, COLORS.Self, { Square = true, Rotation = heading })
	end

	-- Blast doors: closed = drawn.
	for part, frame in layer.Doors do
		frame.Visible = part.Parent ~= nil and (part.Position.Y - part.Size.Y / 2) < 1
	end
	endFrame(layer)
end

local function setFullOpen(open: boolean)
	fullOpen = open
	fullPanel.Visible = open
end

function MinimapController:Init() end

function MinimapController:Start()
	local gui = UIKit.screenGui("ShiftMap", 7)
	UIKit.autoScale(gui)
	local overlay = UIKit.screenGui("ShiftMapFull", 19)
	UIKit.autoScale(overlay)

	local frame = UIKit.panel({
		Name = "Minimap",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(MINI_SIZE, MINI_SIZE),
		ClipsDescendants = true,
		Parent = gui,
	})
	miniHolder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	UIKit.mono("[M] MAP", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -2),
		Size = UDim2.fromOffset(60, 12),
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.TextFaint,
		ZIndex = 20,
		Parent = frame,
	})

	fullPanel = UIKit.panel({
		Name = "FullMap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2 * HALF_X * 2.4 + 24, 2 * HALF_Z * 2.4 + 44),
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = overlay,
	})
	UIKit.text("FACILITY MAP  ·  CLICK TO PING  ·  [M] CLOSE", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 16),
		TextSize = Theme.TextSize.Caption,
		FontFace = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		Parent = fullPanel,
	})
	fullHolder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.fromOffset(2 * HALF_X * 2.4, 2 * HALF_Z * 2.4),
		Parent = fullPanel,
	})
	-- Modal button over the map: frees the mouse (CursorController) and takes ping clicks.
	local clickArea: TextButton = UIKit.new("TextButton", {
		Name = "PingArea",
		BackgroundTransparency = 1,
		Text = "",
		Modal = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = fullHolder,
	})
	clickArea.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local layer = full
			if not layer then
				return
			end
			local rel = Vector2.new(input.Position.X, input.Position.Y) - fullHolder.AbsolutePosition
			local scale = fullHolder.AbsoluteSize.X / (2 * HALF_X * layer.Scale)
			sendPing(fromCanvas(layer, rel.X / scale, rel.Y / scale))
		end
	end)

	pingRemote = Remotes.Get("Ping")
	Remotes.Get("PingShown").OnClientEvent:Connect(function(name: string, _team: string, position: Vector3)
		if type(name) == "string" and typeof(position) == "Vector3" and name ~= player.Name then
			showPing(name, position)
		end
	end)

	Remotes.Get("ShotFx").OnClientEvent:Connect(function(shooterName: string, origin: Vector3)
		if type(shooterName) ~= "string" or typeof(origin) ~= "Vector3" then
			return
		end
		local model = findShooter(shooterName)
		local team = modelTeam(model)
		if team and team ~= MatchStore.localTeam() then
			reveals[shooterName] = { Position = origin, At = os.clock(), Team = team }
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			setFullOpen(not fullOpen)
		elseif
			input.KeyCode == Enum.KeyCode.Y
			or input.KeyCode == Enum.KeyCode.Z
			or input.UserInputType == Enum.UserInputType.MouseButton3
		then
			pingAtCrosshair()
		end
	end)

	task.spawn(function()
		workspace:WaitForChild("Facility", 60)
		task.wait(1) -- let the map finish replicating
		rebuild()
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local visible = MatchStore.Phase ~= "Ended"
		frame.Visible = visible
		if not visible and fullOpen then
			setFullOpen(false)
		end
		if not mini or not full then
			return
		end
		local team = MatchStore.localTeam()
		if team and team ~= builtFor then
			rebuild()
			return
		end
		-- Expire pings (world markers + distance text).
		local character = player.Character
		local root = character and rootOf(character)
		for name, pg in pings do
			if now - pg.At > Tuning.Map.PingSeconds then
				clearPing(name)
			elseif root and pg.Marker then
				local label = pg.Marker:FindFirstChild("Distance")
				if label and label:IsA("TextLabel") then
					label.Text =
						string.format("%dm", math.floor((pg.Position - root.Position).Magnitude / 3.57 + 0.5))
				end
			end
		end

		local m = mini :: Layer
		if root then
			local u, v = toCanvas(m, root.Position.X, root.Position.Z)
			m.Canvas.Position = UDim2.fromOffset(MINI_SIZE / 2 - u, MINI_SIZE / 2 - v)
		end
		drawDynamic(m, now)
		if fullOpen then
			drawDynamic(full :: Layer, now)
		end
	end)
end

return MinimapController

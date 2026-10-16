--!strict
-- Stages the creepy moments the server picks (HorrorService). Everything here is local: only this
-- player sees it, nothing collides or takes bullets, and nothing appears right in your face.
--   Corner        the backrooms figure stands in a room corner at the edge of your view; the moment
--                 you look at it: a sting and it's gone
--   Glimpse       the figure flashes in a far corner straight ahead for a split second + sting
--   Blackout      (your zone's lights just went off) a dread swell + maybe a laugh; the figure in
--                 the last flicker is a shared apparition (server) so everyone there sees it
--   Voice         a faint "help me" from behind a wall behind you
--   Laugh         a distant laugh somewhere off in the dark
-- Shared apparitions (workspace.SharedHorror) are placed by the SERVER so everyone nearby sees the
-- same figure; this controller only reports "I looked straight at it" (ScareSeen) and the server
-- then makes it vanish with a sting for everyone.
-- Studio only: J asks the server for the next scare kind in turn (prints to Output) to test them.
--   Watcher       the backrooms figure stands at the far end of the dark room, at the edge of your
--                 view, faint breathing; it is gone the moment you look straight at it or approach
--   Wheelchair    appears beside / behind you; each time you look away and back it has rolled a
--                 little closer (creak), twice at most
--   Teeth         a grin floating at head height in the dark for a couple of seconds, a whisper,
--                 then it fades
--   WallSkeleton  silently appears on a wall off to your side and stays a while
--   Blood         a splat on the floor behind you ("was that there before?")

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HorrorSpots = require(Shared:WaitForChild("HorrorSpots"))

local HorrorController = {}

local SOUNDS = {
	Breath = 9113984056, -- PSE "Creature Mix Weird Deep Monster Breathing 3"
	Whisper = 9126213744, -- PSE "Whisper Bursts Eerie Unintelligible Phrases"
	Creak = 9120655502, -- PSE "Wheelchair 1"
	-- Owner's inventory (Creator Store audio, added 2026-10-12)
	Sting = 4737106301, -- "creepy sound for horror games"
	Help = 130217845488127, -- "pls help me creepy"
	Laugh = 91272160888434, -- "Creepy Ghost Female Laughing"
	Dread = 135718281689163, -- "creepy_demonic_metallic_loop"
}

local player = Players.LocalPlayer
local rng = Random.new()
local folder: Folder
local busy = false

local function template(kind: string): Model?
	local props = ReplicatedStorage:FindFirstChild("HorrorProps")
	local t = props and props:FindFirstChild(kind)
	return if t and t:IsA("Model") then t else nil
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folder }
	for _, c in CollectionService:GetTagged("Combatant") do
		table.insert(exclude, c)
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	for _, name in { "Bots", "Cores", "CombatSmoke", "CombatGrenades", "SharedHorror" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	return params
end

local function eye(): CFrame?
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame else nil
end

local function flatLook(cf: CFrame): Vector3
	return HorrorSpots.FlatLook(cf)
end

local function findWall(minAng: number, maxAng: number, minD: number, maxD: number): RaycastResult?
	local cf = eye()
	return if cf then HorrorSpots.FindWall(cf, rayParams(), rng, minAng, maxAng, minD, maxD) else nil
end

local function floorAt(pos: Vector3): Vector3?
	return HorrorSpots.FloorAt(pos, rayParams())
end

local function clear(from: Vector3, to: Vector3): boolean
	return HorrorSpots.Clear(from, to, rayParams())
end

local function findCorner(minAng: number, maxAng: number, minD: number, maxD: number): Vector3?
	local cf = eye()
	return if cf then HorrorSpots.FindCorner(cf, rayParams(), rng, minAng, maxAng, minD, maxD) else nil
end

-- Put a model's bounding-box centre at `cf` (orientation included).
local function setCenter(model: Model, cf: CFrame)
	local box = model:GetBoundingBox()
	model:PivotTo(cf * box:ToObjectSpace(model:GetPivot()))
end

-- Visible bottom on the floor, facing `face` (or a random way).
local function standOn(model: Model, floor: Vector3, face: Vector3?)
	HorrorSpots.StandOn(model, floor, face, rng)
end

local function spawnProp(kind: string): Model?
	local t = template(kind)
	if not t then
		return nil
	end
	local m = t:Clone()
	m.Parent = folder
	return m
end

local function sound(name: string, at: Vector3, volume: number, maxDistance: number, looped: boolean?): Sound?
	local id = SOUNDS[name]
	if not id or id == 0 then
		return nil
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.Position = at
	holder.Parent = folder
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume
	s.Looped = looped == true
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = maxDistance
	s.Parent = holder
	s:Play()
	if not looped then
		task.delay(8, function()
			holder:Destroy()
		end)
	end
	return s
end

-- A faint cold glow on a figure so it reads in the dark for the moment it's there.
local function haunt(model: Model, brightness: number)
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if part then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 165, 190)
		light.Brightness = brightness
		light.Range = 9
		light.Shadows = false
		light.Parent = part
	end
end

-- Low 2D dread bed: fades in, holds, fades out.
local function dread(seconds: number, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(SOUNDS.Dread)
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	TweenService:Create(s, TweenInfo.new(1), { Volume = volume }):Play()
	task.delay(math.max(seconds - 1.5, 0.5), function()
		TweenService:Create(s, TweenInfo.new(1.5), { Volume = 0 }):Play()
		task.delay(1.6, function()
			s:Destroy()
		end)
	end)
end

local function fadeOut(model: Model, seconds: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			TweenService:Create(d, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			task.delay(seconds * 0.8, function()
				d.Enabled = false
			end)
		end
	end
	task.delay(seconds + 0.1, function()
		model:Destroy()
	end)
end

-- Facing (dot), distance and line of sight to `at`. The line-of-sight raycast only runs when
-- `minDot` is given and the player faces the point that closely (every caller only uses `los`
-- together with that same facing test), and within `maxDist` when given.
local function viewInfo(at: Vector3, minDot: number?, maxDist: number?): (number, number, boolean)
	local cf = eye()
	if not cf then
		return -1, math.huge, false
	end
	local to = at - cf.Position
	local dist = to.Magnitude
	local dot = if dist > 0.01 then cf.LookVector:Dot(to.Unit) else 1
	local los = minDot ~= nil
		and dot > minDot
		and (maxDist == nil or dist < maxDist)
		and clear(cf.Position, at)
	return dot, dist, los
end

-- Runs `tick(dt) -> keepGoing` every frame until it returns false or `limit` seconds pass.
local function every(limit: number, tick: (number) -> boolean, done: () -> ())
	local started = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if os.clock() - started > limit or not tick(dt) then
			conn:Disconnect()
			done()
		end
	end)
end

-- Scares ---------------------------------------------------------------------------------------

local scares: { [string]: () -> boolean } = {}

scares.Watcher = function(): boolean
	local hit = findWall(12, 35, 16, 55)
	local cf = eye()
	if not hit or not cf then
		return false
	end
	local floor = floorAt(hit.Position + hit.Normal * 2)
	local model = floor and spawnProp("Watcher")
	if not floor or not model then
		return false
	end
	standOn(model, floor, cf.Position)
	local center = floor + Vector3.new(0, 4, 0)
	local breath = sound("Breath", center, 0.45, 45, true)
	haunt(model, 0.25)
	dread(6, 0.18)
	local seen = 0
	every(8, function(dt)
		local dot, dist, los = viewInfo(center, 0.985)
		seen = if dot > 0.985 and los then seen + dt else 0
		return seen < 0.3 and dist > 10
	end, function()
		if breath and breath.Parent then
			(breath.Parent :: Instance):Destroy()
		end
		model:Destroy()
		if rng:NextNumber() < 0.4 then
			sound("Laugh", center, 0.3, 45)
		else
			sound("Whisper", center, 0.25, 30)
		end
	end)
	return true
end

scares.Corner = function(): boolean
	local cf = eye()
	local floor = findCorner(22, 42, 12, 40)
	local model = floor and spawnProp("Watcher")
	if not cf or not floor or not model then
		return false
	end
	standOn(model, floor, cf.Position)
	haunt(model, 0.35)
	local center = floor + Vector3.new(0, 4, 0)
	local looked = 0
	every(10, function(dt)
		local dot, dist, los = viewInfo(center, 0.96)
		looked = if dot > 0.96 and los then looked + dt else 0
		return looked < 0.08 and dist > 8
	end, function()
		-- Looked at (or walked up to): sting, and it's gone almost at once.
		local _, dist = viewInfo(center)
		if looked >= 0.08 or dist <= 8 then
			sound("Sting", center, 0.55, 60)
			task.delay(0.12, function()
				model:Destroy()
			end)
		else
			model:Destroy()
		end
	end)
	return true
end

scares.Glimpse = function(): boolean
	local cf = eye()
	local floor = findCorner(0, 18, 18, 50)
	if not floor then
		local hit = findWall(0, 15, 18, 50)
		floor = hit and floorAt(hit.Position + hit.Normal * 2)
	end
	local model = floor and spawnProp("Watcher")
	if not cf or not floor or not model then
		return false
	end
	standOn(model, floor, cf.Position)
	haunt(model, 0.5)
	sound("Sting", floor + Vector3.new(0, 4, 0), 0.6, 70)
	task.delay(rng:NextNumber(0.3, 0.45), function()
		model:Destroy()
	end)
	return true
end

-- The figure itself is shared (server, workspace.SharedHorror); here only the sound: a dread swell
-- as the lights die and sometimes a laugh from the dark afterwards.
scares.Blackout = function(): boolean
	dread(5, 0.2)
	task.delay(1, function()
		local cf = eye()
		if cf and rng:NextNumber() < 0.5 then
			sound("Laugh", cf.Position + flatLook(cf) * 25 + Vector3.new(0, 2, 0), 0.25, 50)
		end
	end)
	return true
end

-- A faint call for help from the far side of a wall behind you.
scares.Voice = function(): boolean
	local cf = eye()
	if not cf then
		return false
	end
	local hit = findWall(110, 180, 5, 30)
	local at = if hit
		then hit.Position - hit.Normal * 3 + Vector3.new(0, 1, 0)
		else cf.Position - flatLook(cf) * 18
	sound("Help", at, 0.45, 40)
	return true
end

-- A laugh somewhere off in the dark, not close.
scares.Laugh = function(): boolean
	local cf = eye()
	if not cf then
		return false
	end
	local hit = findWall(40, 180, 20, 60)
	local at = if hit
		then hit.Position + hit.Normal * 1
		else cf.Position + (CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)).LookVector * 30
	sound("Laugh", at, 0.35, 70)
	return true
end

scares.Wheelchair = function(): boolean
	local hit = findWall(100, 170, 8, 26)
	local cf = eye()
	if not hit or not cf then
		return false
	end
	local floor = floorAt(hit.Position + hit.Normal * 1.6)
	local model = floor and spawnProp("Wheelchair")
	if not floor or not model then
		return false
	end
	local pos = floor :: Vector3
	standOn(model, pos, cf.Position)
	local noticed, moves, hidden = false, 0, 0
	every(30, function(dt)
		local dot, dist, los = viewInfo(pos + Vector3.new(0, 1.5, 0), 0.75)
		local visible = dot > 0.75 and los
		if visible and not noticed then
			noticed = true
			sound("Creak", pos, 0.35, 35)
		end
		hidden = if visible then 0 else hidden + dt
		if noticed and hidden > 1.5 and moves < 2 then
			local me = eye()
			if me then
				local toward = Vector3.new(me.Position.X - pos.X, 0, me.Position.Z - pos.Z)
				if toward.Magnitude > 9 then
					local nextFloor = floorAt(pos + toward.Unit * 3)
					if nextFloor then
						pos = nextFloor
						standOn(model, pos, me.Position)
					end
				end
			end
			moves += 1
			noticed = false
		end
		return dist > 6 and dist < 70
	end, function()
		model:Destroy()
	end)
	return true
end

scares.Teeth = function(): boolean
	local hit = findWall(0, 45, 14, 40)
	local cf = eye()
	if not hit or not cf then
		return false
	end
	local floor = floorAt(hit.Position + hit.Normal * 2.5)
	local model = floor and spawnProp("Teeth")
	if not floor or not model then
		return false
	end
	local center = (floor :: Vector3) + Vector3.new(0, 5.2, 0)
	setCenter(model, CFrame.lookAt(center, Vector3.new(cf.Position.X, center.Y, cf.Position.Z)))
	sound("Whisper", center, 0.3, 40)
	task.delay(2.5, function()
		fadeOut(model, 1)
	end)
	return true
end

scares.WallSkeleton = function(): boolean
	local hit = findWall(25, 75, 10, 30)
	if not hit then
		return false
	end
	local model = spawnProp("WallSkeleton")
	local floor = floorAt(hit.Position + hit.Normal * 1)
	if not model or not floor then
		if model then
			model:Destroy()
		end
		return false
	end
	local _, size = model:GetBoundingBox()
	local center = Vector3.new(hit.Position.X, floor.Y + 1.2 + size.Y / 2, hit.Position.Z)
		+ hit.Normal * (math.min(size.X, size.Z) / 2 + 0.05)
	setCenter(model, CFrame.lookAt(center, center + hit.Normal))
	every(45, function()
		local _, dist = viewInfo(center)
		return dist < 70
	end, function()
		model:Destroy()
	end)
	return true
end

scares.Blood = function(): boolean
	local cf = eye()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not cf or not root or not root:IsA("BasePart") then
		return false
	end
	local look = flatLook(cf)
	for _ = 1, 8 do
		local ang = math.rad(rng:NextNumber(120, 180) * (if rng:NextNumber() < 0.5 then -1 else 1))
		local dir = (CFrame.Angles(0, ang, 0) * CFrame.new(Vector3.zero, look)).LookVector
		local spot = root.Position + dir * rng:NextNumber(4, 10)
		local floor = floorAt(spot)
		if floor and clear(root.Position, floor + Vector3.new(0, 0.5, 0)) then
			local model = spawnProp("Blood")
			if not model then
				return false
			end
			standOn(model, floor, nil)
			every(60, function()
				local _, dist = viewInfo(floor :: Vector3)
				return dist < 70
			end, function()
				model:Destroy()
			end)
			return true
		end
	end
	return false
end

-- Shared apparitions: report the first time this player looks straight at one.
local reported: { [Instance]: boolean } = {}
local looking: { [Instance]: number } = {}

local function watchShared(dt: number)
	local shared = workspace:FindFirstChild("SharedHorror")
	if not shared then
		return
	end
	for _, model in shared:GetChildren() do
		if model:IsA("Model") and not reported[model] then
			local lo, hi = HorrorSpots.VisibleBounds(model)
			local dot, dist, los = viewInfo((lo + hi) / 2, 0.96, 90)
			if dot > 0.96 and los and dist < 90 then
				looking[model] = (looking[model] or 0) + dt
				if looking[model] >= 0.08 then
					reported[model] = true
					Remotes.Get("ScareSeen"):FireServer(model:GetAttribute("ScareId"))
				end
			else
				looking[model] = 0
			end
		end
	end
	for model in reported do
		if model.Parent == nil then
			reported[model] = nil
			looking[model] = nil
		end
	end
	-- Figures that despawned without ever being reported (otherwise kept referenced forever).
	for model in looking do
		if model.Parent == nil then
			looking[model] = nil
		end
	end
end

function HorrorController:Init() end

function HorrorController:Start()
	folder = Instance.new("Folder")
	folder.Name = "ClientHorror"
	folder.Parent = workspace

	local studio = RunService:IsStudio()
	Remotes.Get("Scare").OnClientEvent:Connect(function(kind: string, forced: boolean?)
		local stage = type(kind) == "string" and scares[kind] or nil
		if not stage or (busy and not forced) then
			return
		end
		busy = true
		local ok, result = pcall(stage)
		if not ok then
			warn("[Horror] " .. tostring(result))
		elseif result == false and kind ~= "Voice" and kind ~= "Laugh" then
			-- No spot for the model here: something you hear instead.
			if studio then
				print(`[Horror] {kind}: no spot in view here, played a sound instead`)
			end
			pcall(if rng:NextNumber() < 0.5 then scares.Voice else scares.Laugh)
		elseif studio then
			print(`[Horror] {kind}: staged`)
		end
		task.delay(3, function()
			busy = false
		end)
	end)

	RunService.RenderStepped:Connect(watchShared)

	if studio then
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.J then
				Remotes.Get("HorrorTest"):FireServer()
			end
		end)
	end
end

return HorrorController

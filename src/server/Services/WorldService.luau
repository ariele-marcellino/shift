--!strict
-- WorldService: builds "Level 0 - Office Annex" in Init (so other services can query it in Start)
-- and owns lamps, shift hinges, darkness queries and the bot nav graph. Contract: TEST_CONTRACT §4.
--
-- API
--   :BreakLamp(lampId) -> boolean            persistent until :ResetMatch()
--   :ResetMatch()                            lamps, hinges, power, shift sequence back to start
--   :PeekNextShift() -> {Title, Detail}      what the next :ApplyNextShift() will do
--   :ApplyNextShift() -> {Title, Detail}     balanced, mirrored; never cuts the last route to a Core
--   :GetSnapshot() -> MapSnapshot            FacilityReport.MapSnapshot (+ Rooms, hinge Rotation)
--   :GetNavPoints() -> { {Id, Position, Links, Dark} }   links listed in both directions
--   :IsDark(position) -> boolean
--   :GetSpawns(team) -> { CFrame }           floor level, facing out of the spawn room
--   :GetPedestal(team) -> CFrame             top surface centre of the Core pedestal
--   :GetLightState() -> { [zoneId]: "On"|"Dim"|"Off" }   dynamic light zones (v2, LightDirector)
--   :IsInSpawnRoom(team, position) -> boolean
--   :GetSniperSpots(team) -> { CFrame }       raised perches at the base end of each side lane
--                                            (feet position on the perch, looking down the lane)
--   extras: :GetBrokenLamps(), :GetTotalLamps(), :GetShiftHistory(), :IsInWater(pos),
--           :GetSafePosition(pos)
--   signals: .LampBroken(lampId, position), .ShiftApplied(info), .LightChanged(zoneId, state)
--   Re-read GetNavPoints() after ShiftApplied / LightChanged / LampBroken (Dark flags are live).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local WorldFolder = (script.Parent :: Instance).Parent:WaitForChild("World")
local Style = require(WorldFolder:WaitForChild("Style"))
local Pieces = require(WorldFolder:WaitForChild("Pieces"))
local Lamps = require(WorldFolder:WaitForChild("Lamps"))
local Hinges = require(WorldFolder:WaitForChild("Hinges"))
local NavGraph = require(WorldFolder:WaitForChild("NavGraph"))
local Regions = require(WorldFolder:WaitForChild("Regions"))
local Layout = require(WorldFolder:WaitForChild("Layout"))
local ZFightFix = require(WorldFolder:WaitForChild("ZFightFix"))
local LightDirector = require(WorldFolder:WaitForChild("LightDirector"))

export type ShiftInfo = { Title: string, Detail: string }

type ShiftStep = {
	Title: string,
	Detail: string,
	Hinges: { [string]: boolean }, -- hinge Kind -> open; applied to both halves (mirrored = fair)
	Power: { [string]: boolean }?,
}

-- Balanced loop: each step changes both halves identically; at most one lane is ever sealed.
local SEQUENCE: { ShiftStep } = {
	{
		Title = "SECTOR B LOCKDOWN",
		Detail = "Long Hall security doors sealed · Maintenance tunnels open",
		Hinges = { HallDoor = false, Tunnel = true },
	},
	{
		Title = "POWER FAILURE",
		Detail = "Long Hall centre lights down · Security doors released",
		Hinges = { HallDoor = true },
		Power = { HallCenter = false },
	},
	{
		Title = "SYSTEMS RESTORED",
		Detail = "Long Hall power restored · Maintenance tunnels sealed",
		Hinges = { Tunnel = false },
		Power = { HallCenter = true },
	},
}

local WorldService = {}

WorldService.LampBroken = Signal.new()
WorldService.ShiftApplied = Signal.new()
WorldService.LightChanged = Signal.new()
WorldService.Map = nil :: Folder?

local layout: Layout.Result? = nil
local shiftIndex = 0
local history: { ShiftInfo } = {}
local navCache: { NavGraph.NavPoint }? = nil

local function teamName(team: any): string
	if typeof(team) == "Instance" then
		return team.Name
	end
	return tostring(team)
end

local function setupLighting()
	-- The facility is fully indoors: don't light / reflect the outdoor skybox on its surfaces. With
	-- the Studio defaults (1 / 1) every wall picks up a grey sky reflection, which makes large plain
	-- plaster walls (Open Office) read as dark, metallic grey at a distance.
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	for key, value in Style.Atmosphere do
		(atmosphere :: any)[key] = value
	end
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChild("ShiftBloom") :: BloomEffect? or Instance.new("BloomEffect")
	bloom.Name = "ShiftBloom"
	bloom.Intensity = Style.Bloom.Intensity
	bloom.Size = Style.Bloom.Size
	bloom.Threshold = Style.Bloom.Threshold
	bloom.Parent = Lighting

	local cc = Lighting:FindFirstChild("ShiftGrade") :: ColorCorrectionEffect?
		or Instance.new("ColorCorrectionEffect")
	cc.Name = "ShiftGrade"
	cc.Saturation = Style.ColorCorrection.Saturation
	cc.Contrast = Style.ColorCorrection.Contrast
	cc.TintColor = Style.ColorCorrection.TintColor
	cc.Parent = Lighting
end

local function invalidate()
	navCache = nil
end

local function routesOk(isOpen: (string) -> boolean): boolean
	local l = layout :: Layout.Result
	return NavGraph.Reachable(l.SpawnNode.Blue, l.CoreNode.Red, isOpen)
		and NavGraph.Reachable(l.SpawnNode.Red, l.CoreNode.Blue, isOpen)
		and NavGraph.Reachable(l.SpawnNode.Blue, l.CoreNode.Blue, isOpen)
		and NavGraph.Reachable(l.SpawnNode.Red, l.CoreNode.Red, isOpen)
end

local broadcastLights: (changed: { [string]: LightDirector.ZoneState }) -> ()

function WorldService:Init()
	local existing = workspace:FindFirstChild("Facility")
	if existing then
		existing:Destroy()
	end
	-- Studio's starter Baseplate has its top at y = 0, exactly the facility floor height, which
	-- makes the whole floor z-fight (flicker). Sink it out of the way for this session.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.CFrame -= Vector3.new(0, 40, 0)
		baseplate.Transparency = 1
		baseplate.CanCollide = false
	end
	-- Studio's starter SpawnLocation sits at the map centre (white pad inside the atrium elevator).
	-- SHIFT spawns players itself, so remove any SpawnLocation.
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end
	-- Mood: a faint dark haze (far ends of long rooms fade into the dark) and a slightly desaturated,
	-- contrasty grade.
	local Lighting = game:GetService("Lighting")
	Lighting.FogColor = Color3.fromRGB(8, 9, 11)
	Lighting.FogStart = 45
	Lighting.FogEnd = 240
	local grade = Lighting:FindFirstChild("ShiftGrade") or Instance.new("ColorCorrectionEffect")
	grade.Name = "ShiftGrade"
	(grade :: ColorCorrectionEffect).Saturation = -0.18
	(grade :: ColorCorrectionEffect).Contrast = 0.1
	(grade :: ColorCorrectionEffect).Brightness = -0.03
	(grade :: ColorCorrectionEffect).TintColor = Color3.fromRGB(240, 238, 230)
	grade.Parent = Lighting
	setupLighting()
	layout = Layout.Build(workspace)
	WorldService.Map = (layout :: Layout.Result).Root

	-- Remove z-fighting anywhere in the built facility (coplanar same-facing faces flicker).
	-- Hinge parts and lamp fixtures move / get restored to stored CFrames, so they're never resized.
	local map = WorldService.Map :: Instance
	local function isProtected(part: BasePart): boolean
		if part:HasTag("BreakableLamp") then
			return true
		end
		local node: Instance? = part.Parent
		while node and node ~= map do
			if node.Name == "Hinges" or node.Name == "Lights" or node.Name == "Markers" then
				return true
			end
			node = node.Parent
		end
		return false
	end
	local zok, zfixed = pcall(ZFightFix.Run, map, isProtected)
	if zok then
		print(`[World] Z-fight pass adjusted {zfixed} coplanar faces`)
	else
		warn(`[World] Z-fight pass failed (map still fine, may flicker): {zfixed}`)
	end
	LightDirector.Init(broadcastLights)

	-- Sanity: with every hinge open the whole graph must be one connected piece, and the starting
	-- state must leave every Core reachable.
	local missing = NavGraph.Unreachable((layout :: Layout.Result).SpawnNode.Blue, function()
		return true
	end)
	if #missing > 0 then
		warn(`[World] Nav nodes unreachable with all hinges open: {table.concat(missing, ", ")}`)
	end
	if not routesOk(Hinges.IsOpen) then
		warn("[World] Initial hinge state cuts a route to a Core")
	end

	local stats = Pieces.Stats
	print(
		`[World] Office Annex built: {stats.Parts} parts, {stats.Lights} lights ({stats.ShadowLights} shadow), `
			.. `{#Lamps.BreakableList()} breakable lamps, {#Hinges.All()} hinges`
	)
end

-- Startup sightline check (V4): rays between every spawn point / pedestal / sample point of one
-- team's spawn + Core rooms and the other team's, plus both Long Hall ends. Any clear ray is a warning.
local function sightlineCheck()
	local l = layout :: Layout.Result
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { l.Root }
	pcall(function()
		(params :: any).RespectCanCollide = true
	end)

	local function samples(team: string): { Vector3 }
		local pts = {}
		for _, cf in l.Spawns[team] or {} do
			table.insert(pts, cf.Position + Vector3.new(0, 1.5, 0))
			table.insert(pts, cf.Position + Vector3.new(0, 4.5, 0))
		end
		local ped = l.Pedestals[team]
		if ped then
			table.insert(pts, ped.Position + Vector3.new(0, 1.4, 0))
		end
		local rooms = l.TeamRooms[team]
		if rooms then
			for _, room in { rooms.Spawn, rooms.Core } do
				local half = room.Size / 2 - Vector3.new(1, 0, 1)
				for _, fx in { -1, -0.5, 0, 0.5, 1 } do
					for _, fz in { -1, -0.5, 0, 0.5, 1 } do
						local base = Vector3.new(room.Center.X + fx * half.X, 0, room.Center.Z + fz * half.Z)
						table.insert(pts, base + Vector3.new(0, 4.5, 0))
					end
				end
			end
		end
		return pts
	end

	local clear: { string } = {}
	local tested = 0
	local function test(a: Vector3, b: Vector3, label: string)
		tested += 1
		local result = workspace:Raycast(a, b - a, params)
		if not result then
			table.insert(clear, `{label} {a} -> {b}`)
		end
	end
	local blue, red = samples("Blue"), samples("Red")
	for _, a in blue do
		for _, b in red do
			test(a, b, "base")
		end
	end
	local hb, hr = l.HallEnds.Blue, l.HallEnds.Red
	if hb and hr then
		for _, dz in { -5, 0, 5 } do
			for _, y in { 1.5, 4.5, 8 } do
				test(hb + Vector3.new(0, y, dz), hr + Vector3.new(0, y, -dz), "hall")
				test(hb + Vector3.new(0, y, dz), hr + Vector3.new(0, y, dz), "hall")
			end
		end
	end
	if #clear > 0 then
		warn(
			`[World] Sightline check: {#clear}/{tested} clear rays between opposing bases. First: {clear[1]}`
		)
		for i = 2, math.min(#clear, 5) do
			warn(`[World]   {clear[i]}`)
		end
	else
		print(`[World] Sightline check passed ({tested} rays, all blocked)`)
	end
end

function broadcastLights(changed: { [string]: LightDirector.ZoneState })
	-- Flicker events are cosmetic: send just them; light levels / darkness don't change.
	for _, state in changed do
		if (state :: string) == "Flicker" then
			Remotes.Get("LightState"):FireAllClients(changed)
			return
		end
	end
	invalidate()
	Remotes.Get("LightState"):FireAllClients(LightDirector.GetLevels())
	for zone, state in changed do
		WorldService.LightChanged:Fire(zone, state)
	end
end

-- Door validation: every door / window / vent must have wall on both sides of its frame (rays along
-- the wall plane hit a jamb) and be open through the middle; every doorway lamp must hang over one.
local function doorCheck()
	local l = layout :: Layout.Result
	local structure = l.Root:FindFirstChild("Structure")
	if not structure then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { structure }
	pcall(function()
		(params :: any).RespectCanCollide = true
	end)
	local problems = 0
	for _, door in Pieces.Doors do
		local reach = door.Width / 2 + 1.5
		for _, dir in { door.Along, -door.Along } do
			if not workspace:Raycast(door.Center, dir * reach, params) then
				problems += 1
				warn(`[World] Door {door.Name} not in a wall (no jamb towards {dir})`)
				break
			end
		end
		local normal = Vector3.new(door.Along.Z, 0, door.Along.X)
		if workspace:Raycast(door.Center - normal * 1.5, normal * 3, params) then
			problems += 1
			warn(`[World] Door {door.Name} is blocked by wall geometry`)
		end
	end
	for _, lamp in Pieces.DoorLamps do
		local found = false
		for _, door in Pieces.Doors do
			local d = door.Center - lamp.Door
			if math.abs(d.X) < 1.5 and math.abs(d.Z) < 1.5 then
				found = true
				break
			end
		end
		if not found then
			problems += 1
			warn(`[World] Door lamp {lamp.Name} has no doorway under it`)
		end
	end
	if problems == 0 then
		print(
			`[World] Door check passed ({#Pieces.Doors} doors/windows/vents, {#Pieces.DoorLamps} door lamps)`
		)
	end
end

function WorldService:Start()
	Remotes.Get("ClientReady").OnServerEvent:Connect(function(player)
		Remotes.Get("LightState"):FireClient(player, LightDirector.GetLevels())
	end)
	task.defer(sightlineCheck)
	task.defer(doorCheck)
	LightDirector.Start()
end

-- Lamps ---------------------------------------------------------------------------------------

function WorldService:BreakLamp(lampId: string): boolean
	if not Lamps.Break(lampId) then
		return false
	end
	invalidate()
	local lamp = Lamps.Get(lampId)
	WorldService.LampBroken:Fire(lampId, if lamp then lamp.Part.Position else Vector3.zero)
	return true
end

function WorldService:GetBrokenLamps(): { string }
	local list = {}
	for _, lamp in Lamps.BreakableList() do
		if lamp.Broken then
			table.insert(list, lamp.Id)
		end
	end
	return list
end

function WorldService:GetTotalLamps(): number
	return #Lamps.BreakableList()
end

-- Shifts --------------------------------------------------------------------------------------

function WorldService:PeekNextShift(): ShiftInfo
	local step = SEQUENCE[(shiftIndex % #SEQUENCE) + 1]
	return { Title = step.Title, Detail = step.Detail }
end

function WorldService:ApplyNextShift(): ShiftInfo
	local step = SEQUENCE[(shiftIndex % #SEQUENCE) + 1]
	shiftIndex += 1

	-- Planned states for both halves.
	local planned: { [string]: boolean } = {}
	for _, hinge in Hinges.All() do
		local want = step.Hinges[hinge.Kind]
		if want ~= nil then
			planned[hinge.Id] = want
		end
	end
	local function plannedOpen(id: string): boolean
		local p = planned[id]
		if p == nil then
			return Hinges.IsOpen(id)
		end
		return p
	end
	local detail = step.Detail
	if not routesOk(plannedOpen) then
		-- Never seal the last route to a Core: keep the openings, drop the closings.
		for id, open in planned do
			if not open then
				planned[id] = nil
			end
		end
		detail ..= " · Lockdown overridden"
		warn("[World] Shift would cut a route to a Core; sealing skipped")
	end

	-- Openings first, then closings (closings push combatants out of the sealing volumes).
	for _, wantOpen in { true, false } do
		for id, open in planned do
			local hinge = Hinges.Get(id)
			if hinge and open == wantOpen then
				Hinges.SetOpen(hinge, open, true)
			end
		end
	end
	if step.Power then
		for group, on in step.Power do
			Lamps.SetPower(group, on)
		end
	end
	invalidate()

	local info = { Title = step.Title, Detail = detail }
	table.insert(history, info)
	WorldService.ShiftApplied:Fire(info)
	return info
end

function WorldService:GetShiftHistory(): { ShiftInfo }
	return table.clone(history)
end

function WorldService:ResetMatch()
	Lamps.ResetAll()
	Hinges.ResetAll()
	LightDirector.Reset()
	shiftIndex = 0
	history = {}
	invalidate()
end

-- Queries -------------------------------------------------------------------------------------

function WorldService:GetSnapshot()
	local l = layout :: Layout.Result
	local lamps = {}
	for _, lamp in Lamps.BreakableList() do
		table.insert(lamps, { Id = lamp.Id, Position = lamp.OnCFrame.Position, Broken = lamp.Broken })
	end
	local hinges = {}
	for _, hinge in Hinges.All() do
		-- Size is already world-axis aligned, so Rotation is 0 (kept for the UI's generic drawer).
		table.insert(
			hinges,
			{ Id = hinge.Id, Position = hinge.Position, Size = hinge.Size, Open = hinge.Open, Rotation = 0 }
		)
	end
	local rooms = {}
	for _, room in l.Rooms do
		table.insert(rooms, { Name = room.Name, Center = room.Center, Size = room.Size, Dark = room.Dark })
	end
	return {
		Lamps = lamps,
		Hinges = hinges,
		Rooms = rooms,
		Bounds = { Min = l.Bounds.Min, Max = l.Bounds.Max },
	}
end

function WorldService:GetNavPoints(): { NavGraph.NavPoint }
	if not navCache then
		navCache = NavGraph.Build(Hinges.IsOpen, Regions.IsDark)
	end
	return navCache :: { NavGraph.NavPoint }
end

-- Dark, or lit only by lamps below `threshold` of their default output (horror director only).
function WorldService:IsGloomy(position: Vector3, threshold: number): boolean
	return Regions.IsGloomy(position, threshold)
end

function WorldService:IsDark(position: Vector3): boolean
	if typeof(position) ~= "Vector3" then
		return false
	end
	return Regions.IsDark(position)
end

function WorldService:GetSniperSpots(team: any): { CFrame }
	local l = layout :: Layout.Result
	return table.clone(l.SniperSpots[teamName(team)] or {})
end

-- Spawn elevator for a team: { Pad, PadSize, Arrivals, Leaves, Shaft, ShaftSize } (see Layout).
function WorldService:GetElevator(team: any): any
	local l = layout :: Layout.Result
	return l.Elevators[teamName(team)]
end

function WorldService:GetLightState(): { [string]: string }
	return LightDirector.GetState()
end

function WorldService:IsInSpawnRoom(team: any, position: Vector3): boolean
	if typeof(position) ~= "Vector3" or not layout then
		return false
	end
	local rooms = (layout :: Layout.Result).TeamRooms[teamName(team)]
	if not rooms then
		return false
	end
	local room = rooms.Spawn
	local d = position - room.Center
	return math.abs(d.X) <= room.Size.X / 2
		and math.abs(d.Z) <= room.Size.Z / 2
		and position.Y > -2
		and position.Y < room.Size.Y + 2
end

function WorldService:IsInWater(position: Vector3): boolean
	if typeof(position) ~= "Vector3" then
		return false
	end
	return Regions.IsInWater(position)
end

function WorldService:GetSafePosition(position: Vector3): Vector3
	return Hinges.SafePosition(position)
end

function WorldService:GetSpawns(team: any): { CFrame }
	local l = layout :: Layout.Result
	return table.clone(l.Spawns[teamName(team)] or {})
end

function WorldService:GetPedestal(team: any): CFrame
	local l = layout :: Layout.Result
	return l.Pedestals[teamName(team)] or CFrame.new(0, 3, 0)
end

return WorldService

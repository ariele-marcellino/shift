--!strict
-- Client-side ambience: fluorescent flicker on every light with attribute Flicker = true (tag
-- "FlickerLight"), a facility-wide brownout when a shift lands, and the local ambient sound bed.
--
-- Flicker is subtle and capped: a slow (< 1 Hz) hum wobble plus rare short dips, never more than two
-- dips per second. LocalPlayer attribute Setting_ReduceFlicker = true holds every light steady.
-- Server state always wins: disabled, Broken or unpowered lights are never touched.
--
-- v2 dynamic lights: the server LightDirector broadcasts LightState { [zoneId]: level } (0 = off,
-- ~1 = default; older string states "On"|"Dim"|"Off" are still understood). Single lamps also drift
-- (attribute "Scale"); those changes fade slowly (Tuning.LightEvents.Drift.FadeSeconds).
-- The server sets the final light state at once; here we animate the change on every light tagged
-- "ZoneLight" with that Zone attribute (fade for Dim/On, a short stutter for Off / power-up; a plain
-- fade with Setting_ReduceFlicker), then write the same final values the server set. Flicker lights
-- scale by their "Level" attribute so a dimmed zone keeps flickering at the dim level.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local AmbienceController = {}

-- Ambient sound ids: none verified yet. 0 = skipped (no errors). Fill with licensed/verified ids.
AmbienceController.Sounds = {
	Hvac = 9125446278, -- PSE "Command Room Tone Deep Air Conditioning Hum"; -- 2D loop: distant ventilation bed
	-- 3D loops on the ceiling tubes wherever they cluster (or parts tagged "HumSource"); alternated so
	-- neighbouring tubes don't buzz identically. Owner's inventory (added 2026-10-12); was PSE
	-- "Light Bulb Buzz 2" 9116267264.
	Hum = 137406302438919, -- "Kane Pixels Backrooms Hum Buzz"
	Hum2 = 91401313775616, -- "light sound backrooms"
	ShiftChime = 9116395089, -- PSE "Magic Glows Soft Clusters Of Chiming Hits 4"; -- PA chime when a shift is announced
	Brownout = 9117869243, -- PSE "Power Down 1"; -- electrical thunk when the shift applies
}

local UPDATE_HZ = 30
local CULL_DISTANCE = 160
local MIN_DIP_GAP = 0.5 -- seconds between dip starts -> flicker never exceeds 2 Hz
local ZONE_OFF_COLOR = Color3.fromRGB(40, 39, 36) -- matches server Style.ZoneOffColor
local LEVELS = { On = 1, Dim = 0.35, Off = 0 } -- legacy string states (server now sends numbers)
local LIGHT_EVENTS = (Tuning :: any).LightEvents or {}
local FADE_SECONDS = LIGHT_EVENTS.FadeSeconds or 0.6
local DRIFT_FADE_SECONDS = (LIGHT_EVENTS.Drift and LIGHT_EVENTS.Drift.FadeSeconds) or 1.5
-- Light hum: one looped emitter per cluster of ceiling tubes. A tube counts as "dense" when at
-- least HUM_MIN_TUBES tubes (itself included) are within HUM_NEIGHBOUR studs; emitters are picked
-- among dense tubes at least HUM_SPACING apart, so every well-lit area hums continuously.
local MAX_HUM_SOURCES = 90
local HUM_NEIGHBOUR = 20
local HUM_MIN_TUBES = 3
local HUM_SPACING = 20
-- Bases (owner, 2026-10-16): the light hum is heard as soon as you walk into either team's base -
-- spawn room, flag room and its two wings - at a moderate level. Blue-half positions (the Red base
-- is the mirror, x -> -x); full volume within BASE_HUM.RollOffMin studs of each.
local BASE_HUM_SPOTS = {
	Vector3.new(-174, 10.5, -16), -- spawn room
	Vector3.new(-174, 10.5, 16),
	Vector3.new(-144, 10.5, 0), -- flag room
	Vector3.new(-144, 10.5, -33), -- south wing
	Vector3.new(-144, 10.5, 33), -- north wing
}
local BASE_HUM = { Volume = 0.28, RollOffMin = 12, RollOffMax = 34 }

type Entry = {
	Light: Light,
	Part: BasePart?,
	Base: number,
	OnColor: Color3?,
	Seed: number,
	NextDip: number,
	DipStart: number,
	DipLength: number,
	DipDepth: number,
	SecondDip: boolean,
	LastFactor: number,
}

local entries: { [Light]: Entry } = {}
local rng = Random.new()
local reduceFlicker = false
local brownoutUntil = 0

local function partOf(light: Light): BasePart?
	local parent = light.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end
	return nil
end

local function track(inst: Instance)
	if not inst:IsA("Light") or entries[inst] then
		return
	end
	if inst:GetAttribute("Flicker") ~= true then
		return
	end
	local part = partOf(inst)
	local base = inst:GetAttribute("BaseBrightness")
	local onColor = if part then part:GetAttribute("OnColor") else nil
	local now = os.clock()
	entries[inst] = {
		Light = inst,
		Part = part,
		Base = if type(base) == "number" then base else inst.Brightness,
		OnColor = if typeof(onColor) == "Color3" then onColor else nil,
		Seed = rng:NextNumber(0, 1000),
		NextDip = now + rng:NextNumber(1, 10),
		DipStart = -1,
		DipLength = 0,
		DipDepth = 1,
		SecondDip = false,
		LastFactor = 1,
	}
end

local function untrack(inst: Instance)
	entries[inst :: any] = nil
end

local function isLive(e: Entry): boolean
	local light = e.Light
	return light.Parent ~= nil
		and light.Enabled
		and light:GetAttribute("Broken") ~= true
		and light:GetAttribute("Powered") ~= false
		and ((light:GetAttribute("Level") :: number?) or 1) > 0
end

local function scaleOf(light: Light): number
	local scale = light:GetAttribute("Scale")
	return if type(scale) == "number" then scale else 1
end

-- Zone level x the lamp's own drift scale (what the server's Brightness = Base * this).
local function levelOf(light: Light): number
	local level = light:GetAttribute("Level")
	return (if type(level) == "number" then level else 1) * scaleOf(light)
end

local function fixtureColor(onColor: Color3, value: number): Color3
	if value >= 1 then
		return onColor
	end
	return ZONE_OFF_COLOR:Lerp(onColor, math.clamp(0.4 + 0.6 * value, 0, 1))
end

local function write(e: Entry, factor: number)
	local value = factor * levelOf(e.Light)
	if math.abs(value - e.LastFactor) < 0.01 then
		return
	end
	e.LastFactor = value
	e.Light.Brightness = e.Base * value
	if e.Part and e.OnColor then
		-- Tube glass dims with its light so a dip reads on the fixture too.
		e.Part.Color = fixtureColor(e.OnColor, value)
	end
end

-- Zone transitions --------------------------------------------------------------------------------

type Transition = {
	Light: Light,
	Part: BasePart?,
	OnColor: Color3?,
	Base: number,
	From: number,
	To: number,
	Start: number,
	Duration: number,
}

local transitions: { [Light]: Transition } = {}
local zoneLevels: { [string]: number } = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

local function curve(tr: Transition, t: number): number
	local from, to = tr.From, tr.To
	if reduceFlicker or (from > 0 and to > 0) then
		return lerp(from, to, t)
	end
	if to <= 0 then
		-- Brown out, one last blip, dark.
		if t < 0.45 then
			return lerp(from, from * 0.3, t / 0.45)
		elseif t < 0.6 then
			return from * 0.85
		end
		return 0
	end
	-- Fluorescent strike: dark, strike, drop, warm up.
	if t < 0.15 then
		return 0
	elseif t < 0.3 then
		return to * 0.7
	elseif t < 0.45 then
		return to * 0.1
	end
	return lerp(to * 0.6, to, (t - 0.45) / 0.55)
end

local function lightUsable(light: Light): boolean
	return light.Parent ~= nil
		and light:GetAttribute("Broken") ~= true
		and light:GetAttribute("Powered") ~= false
end

local function finishTransition(tr: Transition)
	local light = tr.Light
	transitions[light] = nil
	if not lightUsable(light) then
		return
	end
	local level = levelOf(light)
	light.Brightness = tr.Base * level
	light.Enabled = level > 0
	if tr.Part and tr.OnColor then
		tr.Part.Color = fixtureColor(tr.OnColor, level)
	end
	local e = entries[light]
	if e then
		e.LastFactor = -1
	end
end

local function startTransition(light: Light, from: number, to: number, duration: number)
	local part = partOf(light)
	local base = light:GetAttribute("BaseBrightness")
	local onColor = if part then part:GetAttribute("OnColor") else nil
	transitions[light] = {
		Light = light,
		Part = part,
		OnColor = if typeof(onColor) == "Color3" then onColor else nil,
		Base = if type(base) == "number" then base else light.Brightness,
		From = from,
		To = to,
		Start = os.clock(),
		Duration = duration,
	}
end

local function startZoneTransition(zone: string, from: number, to: number)
	for _, inst in CollectionService:GetTagged("ZoneLight") do
		if inst:IsA("Light") and inst:GetAttribute("Zone") == zone and lightUsable(inst) then
			local scale = scaleOf(inst)
			startTransition(inst, from * scale, to * scale, FADE_SECONDS)
		end
	end
end

-- Per-lamp drift: fade from the old scale to the new one (slow, no flicker).
local lastScale: { [Light]: number } = {}

local function watchDrift(inst: Instance)
	if not inst:IsA("Light") or lastScale[inst] then
		return
	end
	local light = inst :: Light
	lastScale[light] = scaleOf(light)
	light:GetAttributeChangedSignal("Scale"):Connect(function()
		local old = lastScale[light] or 1
		local new = scaleOf(light)
		lastScale[light] = new
		local level = light:GetAttribute("Level")
		local zoneLevel = if type(level) == "number" then level else 1
		if lightUsable(light) and zoneLevel > 0 and not transitions[light] then
			startTransition(light, old * zoneLevel, new * zoneLevel, DRIFT_FADE_SECONDS)
		end
	end)
end

-- Zone flicker events ("Flicker" in LightState): a short, gentle stutter of every light in the zone
-- (about 3 dips in 2 s, i.e. under 2 Hz), then back to its level. The zone's state doesn't change.
-- Skipped with Setting_ReduceFlicker.
local FLICKER_PATTERN = { { 0, 0.25 }, { 0.3, 1 }, { 0.85, 0.1 }, { 1.1, 0.9 }, { 1.65, 0.3 }, { 1.85, 1 } }
local FLICKER_SECONDS = 2
type Flicker = { Light: Light, Part: BasePart?, OnColor: Color3?, Base: number, Start: number }
local flickers: { [Light]: Flicker } = {}

local function startZoneFlicker(zone: string)
	if reduceFlicker then
		return
	end
	local now = os.clock()
	for _, inst in CollectionService:GetTagged("ZoneLight") do
		if
			inst:IsA("Light")
			and inst:GetAttribute("Zone") == zone
			and lightUsable(inst)
			and levelOf(inst) > 0
			and not transitions[inst]
		then
			local part = partOf(inst)
			local base = inst:GetAttribute("BaseBrightness")
			local onColor = if part then part:GetAttribute("OnColor") else nil
			flickers[inst] = {
				Light = inst,
				Part = part,
				OnColor = if typeof(onColor) == "Color3" then onColor else nil,
				Base = if type(base) == "number" then base else inst.Brightness,
				Start = now + rng:NextNumber(0, 0.12), -- tubes don't stutter in perfect sync
			}
		end
	end
end

local function stepFlickers(now: number)
	for light, f in flickers do
		local t = now - f.Start
		if not lightUsable(light) or transitions[light] then
			flickers[light] = nil
		elseif t >= FLICKER_SECONDS then
			flickers[light] = nil
			local level = levelOf(light)
			light.Brightness = f.Base * level
			if f.Part and f.OnColor then
				f.Part.Color = fixtureColor(f.OnColor, level)
			end
			local e = entries[light]
			if e then
				e.LastFactor = -1
			end
		elseif t >= 0 then
			local factor = 1
			for _, step in FLICKER_PATTERN do
				if t >= step[1] then
					factor = step[2]
				end
			end
			local value = factor * levelOf(light)
			light.Brightness = f.Base * value
			if f.Part and f.OnColor then
				f.Part.Color = fixtureColor(f.OnColor, value)
			end
		end
	end
end

local function onLightState(state: any)
	if type(state) ~= "table" then
		return
	end
	for zone, newState in state do
		if type(zone) == "string" and newState == "Flicker" then
			startZoneFlicker(zone)
		elseif type(zone) == "string" then
			local level = if type(newState) == "number" then newState else LEVELS[newState]
			if type(level) == "number" then
				local prev = zoneLevels[zone]
				zoneLevels[zone] = level
				if prev ~= nil and math.abs(prev - level) > 1e-3 then
					startZoneTransition(zone, prev, level)
				end
			end
		end
	end
end

local function stepTransitions(now: number)
	for light, tr in transitions do
		if not lightUsable(light) then
			transitions[light] = nil
		else
			local t = (now - tr.Start) / tr.Duration
			if t >= 1 then
				finishTransition(tr)
			else
				local value = curve(tr, t)
				light.Enabled = true
				light.Brightness = tr.Base * value
				if tr.Part and tr.OnColor then
					tr.Part.Color = fixtureColor(tr.OnColor, value)
				end
			end
		end
	end
end

local function factorFor(e: Entry, now: number): number
	if now < brownoutUntil then
		return if reduceFlicker then 0.6 else 0.15 + 0.1 * math.noise(now * 1.5, e.Seed)
	end
	if reduceFlicker then
		return 1
	end
	-- Slow mains-hum wobble (well under 1 Hz).
	local f = 0.93 + 0.07 * math.noise(now * 0.6, e.Seed, 0.5)
	-- Rare dips: one short drop, sometimes followed by a second one 0.5 s later.
	if e.DipStart < 0 and now >= e.NextDip then
		e.DipStart = now
		e.DipLength = rng:NextNumber(0.08, 0.2)
		e.DipDepth = rng:NextNumber(0.25, 0.55)
		e.SecondDip = rng:NextNumber() < 0.35
	end
	if e.DipStart >= 0 then
		local t = now - e.DipStart
		if t < e.DipLength then
			f *= e.DipDepth
		elseif t >= MIN_DIP_GAP and e.SecondDip then
			e.SecondDip = false
			e.DipStart = now
			e.DipLength = rng:NextNumber(0.06, 0.14)
			f *= e.DipDepth
		elseif t >= e.DipLength then
			e.DipStart = -1
			e.NextDip = now + rng:NextNumber(4, 14)
		end
	end
	return f
end

-- Ceiling tubes (parts carrying a SurfaceLight) in dense clusters, spaced HUM_SPACING apart.
local function denseTubes(): { BasePart }
	local map = workspace:FindFirstChild("Facility")
	if not map then
		return {}
	end
	local tubes: { BasePart } = {}
	for _, d in map:GetDescendants() do
		local parent = d.Parent
		if d:IsA("SurfaceLight") and parent and parent:IsA("BasePart") then
			table.insert(tubes, parent)
		end
	end
	-- Flat positions read once (property reads inside the O(n^2) loop were the startup cost).
	local flats = table.create(#tubes)
	for i, tube in tubes do
		local p = tube.Position
		flats[i] = Vector3.new(p.X, 0, p.Z)
	end
	local picked: { BasePart } = {}
	local pickedFlat: { Vector3 } = {}
	for i, tube in tubes do
		local here = flats[i]
		local near = 0
		for _, other in flats do
			if (other - here).Magnitude <= HUM_NEIGHBOUR then
				near += 1
			end
		end
		if near >= HUM_MIN_TUBES then
			local clear = true
			for _, p in pickedFlat do
				if (p - here).Magnitude < HUM_SPACING then
					clear = false
					break
				end
			end
			if clear then
				table.insert(picked, tube)
				table.insert(pickedFlat, here)
			end
		end
	end
	return picked
end

-- Lab tubes (store props "Prop_LabTube", placed by the server shortly after the map loads) buzz
-- louder than the ceiling hum: a closer, stronger loop on each tube, so the hum swells as you walk
-- up to them.
local LAB_TUBE_HUM = { Volume = 0.55, RollOffMin = 3, RollOffMax = 24 }

local function addLabTubeHum(model: Instance)
	local id = AmbienceController.Sounds.Hum
	if
		id == 0
		or not model:IsA("Model")
		or model.Name ~= "Prop_LabTube"
		or model:FindFirstChild("LabHum", true)
	then
		return
	end
	-- Biggest visible part = the glass body.
	local body: BasePart? = nil
	for _, d in model:GetDescendants() do
		if
			d:IsA("BasePart")
			and d.Transparency < 0.98
			and (not body or d.Size.Magnitude > body.Size.Magnitude)
		then
			body = d
		end
	end
	if not body then
		return
	end
	local hum = Instance.new("Sound")
	hum.Name = "LabHum"
	hum.SoundId = "rbxassetid://" .. tostring(id)
	hum.Looped = true
	hum.Volume = LAB_TUBE_HUM.Volume
	hum.RollOffMinDistance = LAB_TUBE_HUM.RollOffMin
	hum.RollOffMaxDistance = LAB_TUBE_HUM.RollOffMax
	hum.PlaybackSpeed = rng:NextNumber(0.96, 1.04) -- neighbouring tubes don't phase identically
	hum.TimePosition = rng:NextNumber(0, 2)
	hum.Parent = body
	hum:Play()
end

local function watchLabTubes()
	local map = workspace:FindFirstChild("Facility")
	if not map then
		return
	end
	for _, d in map:GetDescendants() do
		addLabTubeHum(d)
	end
	map.DescendantAdded:Connect(function(d)
		if d:IsA("Model") and d.Name == "Prop_LabTube" then
			task.defer(addLabTubeHum, d) -- let its parts replicate first
		end
	end)
end

local function startSounds()
	local ids = AmbienceController.Sounds
	if ids.Hvac ~= 0 then
		local bed = Instance.new("Sound")
		bed.Name = "AmbientHvac"
		bed.SoundId = "rbxassetid://" .. tostring(ids.Hvac)
		bed.Looped = true
		bed.Volume = 0.25
		bed.Parent = SoundService
		bed:Play()
	end
	watchLabTubes()
	if ids.Hum ~= 0 then
		local count = 0
		local sources = CollectionService:GetTagged("HumSource")
		if #sources == 0 then
			sources = denseTubes()
		end
		for _, source in sources do
			if count >= MAX_HUM_SOURCES then
				break
			end
			if source:IsA("BasePart") then
				count += 1
				local hum = Instance.new("Sound")
				hum.Name = "Hum"
				local humId = if count % 2 == 0 and ids.Hum2 ~= 0 then ids.Hum2 else ids.Hum
				hum.SoundId = "rbxassetid://" .. tostring(humId)
				hum.Looped = true
				hum.Volume = 0.351 -- +25%, +20%, then +30% (owner, 2026-10-16; was 0.18)
				hum.RollOffMinDistance = 4
				hum.RollOffMaxDistance = 30
				hum.Parent = source
				hum:Play()
			end
		end
		-- base hum emitters (local, invisible), both teams' bases
		local folder = Instance.new("Folder")
		folder.Name = "BaseHum"
		folder.Parent = workspace
		for i, spot in BASE_HUM_SPOTS do
			for _, side in { 1, -1 } do
				local anchor = Instance.new("Part")
				anchor.Name = "BaseHumSource"
				anchor.Anchored = true
				anchor.CanCollide = false
				anchor.CanQuery = false
				anchor.CanTouch = false
				anchor.Transparency = 1
				anchor.Size = Vector3.one * 0.2
				anchor.Position = Vector3.new(spot.X * side, spot.Y, spot.Z)
				anchor.Parent = folder
				local hum = Instance.new("Sound")
				hum.Name = "Hum"
				local humId = if i % 2 == 0 and ids.Hum2 ~= 0 then ids.Hum2 else ids.Hum
				hum.SoundId = "rbxassetid://" .. tostring(humId)
				hum.Looped = true
				hum.Volume = BASE_HUM.Volume
				hum.RollOffMinDistance = BASE_HUM.RollOffMin
				hum.RollOffMaxDistance = BASE_HUM.RollOffMax
				hum.Parent = anchor
				hum:Play()
			end
		end
	end
end

local function playOneShot(id: number, volume: number)
	if id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	task.delay(8, function()
		s:Destroy()
	end)
end

function AmbienceController:Init()
	local player = Players.LocalPlayer
	local function readSetting()
		reduceFlicker = player:GetAttribute("Setting_ReduceFlicker") == true
	end
	readSetting()
	player:GetAttributeChangedSignal("Setting_ReduceFlicker"):Connect(readSetting)
end

function AmbienceController:Start()
	for _, inst in CollectionService:GetTagged("FlickerLight") do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal("FlickerLight"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("FlickerLight"):Connect(untrack)
	-- Attribute-only lights (no tag) inside the facility are picked up too.
	task.spawn(function()
		local map = workspace:WaitForChild("Facility", 30)
		if map then
			for _, inst in map:GetDescendants() do
				track(inst)
			end
		end
	end)

	Remotes.Get("LightState").OnClientEvent:Connect(onLightState)
	for _, inst in CollectionService:GetTagged("ZoneLight") do
		watchDrift(inst)
	end
	CollectionService:GetInstanceAddedSignal("ZoneLight"):Connect(watchDrift)
	CollectionService:GetInstanceRemovedSignal("ZoneLight"):Connect(function(inst)
		lastScale[inst :: any] = nil
	end)

	Remotes.Get("ShiftAnnounce").OnClientEvent:Connect(function(payload: any)
		playOneShot(AmbienceController.Sounds.ShiftChime, 0.6)
		local seconds = if type(payload) == "table" and type(payload.Seconds) == "number"
			then payload.Seconds
			else 5
		task.delay(math.clamp(seconds, 0, 15), function()
			brownoutUntil = os.clock() + 0.6
			playOneShot(AmbienceController.Sounds.Brownout, 0.5)
		end)
	end)

	task.delay(2, startSounds)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / UPDATE_HZ then
			return
		end
		acc = 0
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		stepTransitions(now)
		stepFlickers(now)
		for light, e in entries do
			if light.Parent == nil then
				entries[light] = nil
			elseif transitions[light] or flickers[light] then
				continue
			elseif isLive(e) then
				local part = e.Part
				if part and (part.Position - camPos).Magnitude > CULL_DISTANCE then
					continue
				end
				write(e, factorFor(e, now))
			else
				-- Server turned it off or it broke: forget our local value so a restore starts clean.
				e.LastFactor = -1
			end
		end
	end)
end

return AmbienceController

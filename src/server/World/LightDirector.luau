--!strict
-- Dynamic lights (TEST_CONTRACT V4): zones randomly switch On / Dim / Off per Tuning.LightEvents.
--   * Zones come from lamps registered with a Zone ("B.Hall", "R.Hall", "C.Junction", ...).
--     Base/spawn emergency lights and dark-room fills are never in a zone, so they never change.
--   * Mirror = true: "B.X" and "R.X" form one group and always share a state (fair for both teams).
--   * Never fewer than MinLitShare of the groups On. Non-On states revert after a random duration.
--   * Broken lamps stay broken (Lamps keeps Broken independent of the zone level).
--   * Every state change rolls a random brightness inside that state's range (Tuning Levels), so an
--     "On" zone is sometimes a bit brighter, sometimes duller; the default sits at 1 (= the already
--     dim Style.LightScale).
--   * Drift: every few seconds 1-3 single lamps (and their mirror twin) slide to their own random
--     brightness, mostly in the middle (Hall / Atrium / Junction), so the map never sits still.
-- The server sets the final light state immediately; clients animate the transition (fade / flicker)
-- from the LightState broadcast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local Lamps = require(script.Parent.Lamps)

export type ZoneState = "On" | "Dim" | "Off"
type Group = { Key: string, Zones: { string }, State: ZoneState, Level: number, RevertAt: number }

local LightDirector = {}

local cfg = (Tuning :: any).LightEvents or {}
local LEVEL_RANGES: { [string]: { number } } = cfg.Levels or { On = { 1, 1 }, Dim = { 0.35, 0.35 } }
local DRIFT = cfg.Drift or {}
local INTERVAL_MIN = cfg.IntervalMin or 8
local INTERVAL_MAX = cfg.IntervalMax or 18
local PER_CHANGE = cfg.ZonesPerChange or { 1, 2 }
local WEIGHTS = cfg.StateWeights or { On = 50, Dim = 30, Off = 20 }
local DURATION_MIN = cfg.DurationMin or 8
local DURATION_MAX = cfg.DurationMax or 25
local MIN_LIT_SHARE = cfg.MinLitShare or 0.4
local MIRROR = cfg.Mirror ~= false
local ZONE_WEIGHTS: { [string]: number } = cfg.ZoneWeights or {}
local FLICKER_MIN = cfg.FlickerIntervalMin or 12
local FLICKER_MAX = cfg.FlickerIntervalMax or 30

-- Pick weight of a group ("Atrium", "C.Junction" -> "Junction"); 1 when not listed.
local function weightOf(key: string): number
	local name = string.match(key, "^%a%.(.+)$") or key
	return ZONE_WEIGHTS[name] or 1
end

local rng = Random.new()
local groups: { Group } = {}
local states: { [string]: ZoneState } = {}
local onChanged: ((changed: { [string]: ZoneState }) -> ())? = nil
local running = false

local function groupKey(zone: string): string
	if MIRROR then
		local prefix, rest = string.match(zone, "^(%a)%.(.+)$")
		if (prefix == "B" or prefix == "R") and rest then
			return rest
		end
	end
	return zone
end

local function rollLevel(state: ZoneState): number
	if state == "Off" then
		return 0
	end
	local range = LEVEL_RANGES[state] or { 1, 1 }
	return rng:NextNumber(range[1], range[2] or range[1])
end

local function setGroup(group: Group, state: ZoneState, changed: { [string]: ZoneState })
	group.State = state
	group.Level = rollLevel(state)
	for _, zone in group.Zones do
		states[zone] = state
		Lamps.SetZoneLevel(zone, group.Level)
		changed[zone] = state
	end
end

local function onCount(): number
	local n = 0
	for _, g in groups do
		if g.State == "On" then
			n += 1
		end
	end
	return n
end

local function pickState(): ZoneState
	local total = (WEIGHTS.On or 0) + (WEIGHTS.Dim or 0) + (WEIGHTS.Off or 0)
	local roll = rng:NextNumber(0, math.max(total, 1e-6))
	if roll < (WEIGHTS.Off or 0) then
		return "Off"
	elseif roll < (WEIGHTS.Off or 0) + (WEIGHTS.Dim or 0) then
		return "Dim"
	end
	return "On"
end

local function emit(changed: { [string]: ZoneState })
	if next(changed) ~= nil and onChanged then
		(onChanged :: any)(changed)
	end
end

-- One director step: revert expired groups, then change 1-2 groups.
local function step(now: number, doChange: boolean)
	local changed: { [string]: ZoneState } = {}
	for _, g in groups do
		if g.State ~= "On" and now >= g.RevertAt then
			setGroup(g, "On", changed)
		end
	end
	if doChange and #groups > 0 then
		local count = rng:NextInteger(PER_CHANGE[1] or 1, PER_CHANGE[2] or PER_CHANGE[1] or 1)
		-- Weighted random order (Efraimidis-Spirakis): heavier groups tend to come first.
		local order = table.clone(groups)
		local keys: { [Group]: number } = {}
		for _, g in order do
			keys[g] = rng:NextNumber() ^ (1 / weightOf(g.Key))
		end
		table.sort(order, function(a, b)
			return keys[a] > keys[b]
		end)
		local minOn = math.ceil(MIN_LIT_SHARE * #groups)
		for _, g in order do
			if count <= 0 then
				break
			end
			local state = pickState()
			-- On -> On re-rolls the brightness (a lit zone drifts brighter / duller).
			if state ~= g.State or state == "On" then
				-- Darkening an On group must keep the On share at or above MinLitShare.
				if g.State ~= "On" or state == "On" or onCount() - 1 >= minOn then
					setGroup(g, state, changed)
					g.RevertAt = now + rng:NextNumber(DURATION_MIN, DURATION_MAX)
					count -= 1
				end
			end
		end
	end
	emit(changed)
end

function LightDirector.Init(callback: (changed: { [string]: ZoneState }) -> ())
	onChanged = callback
	table.clear(groups)
	table.clear(states)
	local byKey: { [string]: Group } = {}
	for _, zone in Lamps.Zones() do
		local key = groupKey(zone)
		local g = byKey[key]
		if not g then
			g = { Key = key, Zones = {}, State = "On", Level = 1, RevertAt = 0 }
			byKey[key] = g
			table.insert(groups, g)
		end
		table.insert(g.Zones, zone)
		states[zone] = "On"
	end
end

-- Drift ----------------------------------------------------------------------------------------

type DriftLamp = { Ids: { string }, Weight: number }
local driftLamps: { DriftLamp } = {}

local function buildDrift()
	table.clear(driftLamps)
	local weights: { [string]: number } = DRIFT.ZoneWeights or {}
	local byKey: { [string]: DriftLamp } = {}
	for _, lamp in Lamps.All() do
		local zone = lamp.Zone
		if zone and #lamp.Lights > 0 then
			-- "B.Hall.T3" and "R.Hall.T3" drift together (mirror fairness).
			local key = if MIRROR then (string.match(lamp.Id, "^[BR]%.(.+)$") or lamp.Id) else lamp.Id
			local entry = byKey[key]
			if not entry then
				local zoneName = string.match(zone, "^%a%.(.+)$") or zone
				entry = { Ids = {}, Weight = weights[zoneName] or 1 }
				byKey[key] = entry
				table.insert(driftLamps, entry)
			end
			table.insert(entry.Ids, lamp.Id)
		end
	end
end

local function driftStep()
	if #driftLamps == 0 then
		return
	end
	local total = 0
	for _, d in driftLamps do
		total += d.Weight
	end
	local per = DRIFT.LampsPerStep or { 1, 3 }
	local range = DRIFT.Scale or { 0.5, 1.15 }
	for _ = 1, rng:NextInteger(per[1], per[2] or per[1]) do
		local roll = rng:NextNumber(0, total)
		for _, d in driftLamps do
			roll -= d.Weight
			if roll <= 0 then
				local scale = if rng:NextNumber() < (DRIFT.ResetChance or 0.3)
					then 1
					else rng:NextNumber(range[1], range[2] or range[1])
				for _, id in d.Ids do
					Lamps.SetScale(id, scale)
				end
				break
			end
		end
	end
end

function LightDirector.Start()
	if running then
		return
	end
	running = true
	task.spawn(function()
		local nextChange = os.clock() + rng:NextNumber(INTERVAL_MIN, INTERVAL_MAX)
		local nextFlicker = os.clock() + rng:NextNumber(FLICKER_MIN, FLICKER_MAX)
		local driftMin, driftMax = DRIFT.IntervalMin or 0, DRIFT.IntervalMax or 0
		local nextDrift = os.clock() + rng:NextNumber(driftMin, driftMax)
		buildDrift()
		while running do
			task.wait(1)
			local now = os.clock()
			if driftMax > 0 and now >= nextDrift then
				nextDrift = now + rng:NextNumber(driftMin, driftMax)
				driftStep()
			end
			-- Flicker event: one lit group stutters briefly (clients animate; levels don't change).
			if now >= nextFlicker and #groups > 0 then
				nextFlicker = now + rng:NextNumber(FLICKER_MIN, FLICKER_MAX)
				local lit = {}
				local total = 0
				for _, g in groups do
					if g.State ~= "Off" then
						table.insert(lit, g)
						total += weightOf(g.Key)
					end
				end
				local roll = rng:NextNumber(0, math.max(total, 1e-6))
				for _, g in lit do
					roll -= weightOf(g.Key)
					if roll <= 0 then
						local event = {}
						for _, zone in g.Zones do
							event[zone] = "Flicker"
						end
						emit(event :: any)
						break
					end
				end
			end
			local doChange = now >= nextChange
			if doChange then
				nextChange = now + rng:NextNumber(INTERVAL_MIN, INTERVAL_MAX)
			end
			step(now, doChange)
		end
	end)
end

-- Everything back On (match reset). Lamps.ResetAll already restores levels; this syncs our state.
function LightDirector.Reset()
	local changed: { [string]: ZoneState } = {}
	for _, g in groups do
		g.State = "On"
		g.Level = 1
		for _, zone in g.Zones do
			states[zone] = "On"
			changed[zone] = "On"
		end
	end
	emit(changed)
end

function LightDirector.GetState(): { [string]: ZoneState }
	return table.clone(states)
end

-- Zone brightness for clients: { [zoneId]: level } (0 = off, ~1 = default).
function LightDirector.GetLevels(): { [string]: number }
	local levels = {}
	for _, g in groups do
		for _, zone in g.Zones do
			levels[zone] = g.Level
		end
	end
	return levels
end

function LightDirector.GroupCount(): number
	return #groups
end

return LightDirector

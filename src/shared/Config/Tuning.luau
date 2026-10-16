--!strict
-- Every gameplay number for the SHIFT test build, in one place. Coordinator-owned; workstreams read
-- these and may propose changes in their report (don't hard-code duplicates).

local Tuning = {}

Tuning.Match = {
	TeamSize = 3, -- 3v3; bots fill empty slots
	CaptureLimit = 3,
	MatchSeconds = 7 * 60, -- a match (first to 3 captures) lasts at most 7 minutes
	WarmupSeconds = 10,
	EndSeconds = 15, -- end screen / facility report, then a new match starts
	RespawnBase = 3, -- v2: flat 3 s respawn
	RespawnPerStreak = 0,
	RespawnMax = 3,
	SpawnProtection = 2, -- seconds of no damage after spawning (cancelled by firing)
}

-- Deploy menu + matchmaking (LobbyService / Matchmaker). Public servers are "quick play": you join
-- a running 3v3 (bots fill). FIND MATCH queues you (and your squad) across all servers; the
-- matchmaker builds a match of real players (squads stay on one team) on a fresh reserved server.
-- With too few players online: after PartialAfterSeconds a match may start with bots filling the
-- gaps; after SearchSeconds the search gives up and you play here with bots.
Tuning.Matchmaking = {
	MaxSquad = 3, -- = TeamSize
	SearchSeconds = 60,
	PartialAfterSeconds = 25, -- then at least one real squad per side is enough
	StudioSearchSeconds = 8, -- Studio can't queue or teleport: a short fake search, then bots
	TicketSeconds = 30, -- queue entry lifetime (refreshed every few seconds while searching)
	ResultSeconds = 90,
	LeaderSeconds = 8, -- matchmaker lease (one server builds matches at a time)
	PollSeconds = 2,
	MatchWarmupSeconds = 25, -- first warmup on a match server: time for everyone to arrive
	SwitchTeamCooldown = 10,
}

Tuning.Slide = {
	-- Sprint + C/Ctrl: burst that eases from Speed to EndSpeed over Seconds; you stand back up after.
	Speed = 44,
	EndSpeed = 16,
	Seconds = 0.75,
	Cooldown = 1.2, -- from slide start
	CameraDrop = 1.6, -- studs the first-person camera lowers during the slide
}

Tuning.Core = {
	ReturnSeconds = 20, -- dropped Core auto-returns
	PickupRadius = 5,
	CaptureRadius = 6,
	ShiftWarningSeconds = 5, -- announcement before the shift applies after a capture
	RedropSeconds = 2, -- after dropping the flag on purpose (X), you can't grab it back this long
}

Tuning.Movement = {
	-- v2: speed depends on the weapon in hand (knife fastest). Slowest applicable value wins.
	Knife = 20,
	AK = 16,
	Sniper = 14,
	Grenade = 16, -- holding a frag/smoke ready to throw
	Aiming = 10, -- AK aiming down sights
	SniperScoped = 7,
	Crouch = 8,
	Wading = 10, -- in the flooded Maintenance section
	Carrier = 18, -- v2: carrier is locked to the knife; slightly slower than a free knife-runner
	SprintBonus = 6, -- hold Shift: knife 26, AK 22, sniper 20. Not while aiming/scoped/crouching/carrying/wading
	SprintCarrier = false, -- the Core carrier can't sprint (keeps chases fair)
}

Tuning.AK = {
	Damage = 21, -- 5 body shots (100 HP); was 26 (owner, 2026-10-16)
	HeadMultiplier = 4, -- 84: two headshots (no longer a one-shot since the damage drop)
	LimbMultiplier = 0.8,
	RPM = 600,
	Magazine = 20, -- was 30
	Reserve = 100, -- refilled on respawn (5 spare mags)
	ReloadSeconds = 2.4,
	Range = 400,
	FalloffStart = 80, -- studs; damage lerps to 70% at Range
	-- Recoil: vertical climb per shot (degrees), horizontal wander amplitude, recovery speed
	RecoilVertical = 0.55,
	RecoilHorizontal = 0.35,
	RecoilRecovery = 11, -- camera returns ~95% within RecoilResetSeconds after the last shot
	RecoilResetSeconds = 0.35, -- pause this long and the spray pattern restarts at shot 1
	-- Fixed, learnable spray pattern (degrees {up, right}) applied as camera kick AFTER shot n, and so
	-- to the next bullet: shots 1-3 near-accurate, 4-9 climb, then left, right, left, right.
	RecoilPattern = {
		{ 0.12, 0 },
		{ 0.18, 0.02 },
		{ 0.35, -0.02 },
		{ 0.75, 0.05 },
		{ 0.8, 0.08 },
		{ 0.78, -0.04 },
		{ 0.72, 0.06 },
		{ 0.65, 0 },
		{ 0.55, -0.05 },
		{ 0.35, -0.45 },
		{ 0.3, -0.5 },
		{ 0.25, -0.45 },
		{ 0.2, -0.4 },
		{ 0.15, -0.35 },
		{ 0.12, 0.5 },
		{ 0.1, 0.6 },
		{ 0.1, 0.6 },
		{ 0.08, 0.55 },
		{ 0.08, 0.45 },
		{ 0.06, 0.35 },
		{ 0.06, -0.3 },
		{ 0.05, -0.4 },
		{ 0.05, -0.4 },
		{ 0.05, -0.35 },
		{ 0.04, -0.3 },
		{ 0.04, 0.3 },
		{ 0.04, 0.35 },
		{ 0.04, 0.3 },
		{ 0.03, 0.25 },
		{ 0.03, 0.2 },
	},
	-- Accuracy (degrees, cone half-angle), CS-style: standing still + recovered = pinpoint first shot.
	SpreadStanding = 0, -- standing still (speed < StillSpeed), hip or ADS
	StillSpeed = 2, -- studs/s below which you count as standing
	SpreadRun = 3.2, -- extra at full AK run speed (scales with speed; sprint/slide go past it)
	SpreadAir = 6, -- extra while airborne
	SpreadPerShot = 0.28, -- bloom added per shot while spraying (first 3 shots add ~1/3 of it)
	SpreadBloomMax = 1.8,
	AccuracyRecoverySeconds = 0.35, -- bloom fully decays after this long without firing
	AimSpreadMultiplier = 0.45, -- ADS scales movement/air/bloom inaccuracy
	CrouchSpreadMultiplier = 0.75,
	-- legacy v1 values (UI fallbacks only)
	SpreadHip = 2.2, -- degrees
	SpreadAim = 0.25,
	SpreadMoving = 1.5, -- extra while moving
	EquipSeconds = 0.45, -- draw / holster time
	MuzzleLightRange = 18,
	MuzzleLightSeconds = 0.06,
}

Tuning.Smoke = {
	PerLife = 1,
	FuseSeconds = 1.2,
	DurationSeconds = 16, -- was 12
	Radius = 16, -- was 11 (particle sizes scale with it in Combat/Smoke)
	ThrowSpeed = 75,
}

-- v2 weapons ---------------------------------------------------------------------------------------

-- Primary weapons selectable in the loadout menu (order = menu order).
Tuning.Primaries = { "AK", "Sniper" }

Tuning.Sniper = { -- bolt-action, AWP-style; display name below (generic, no real brand)
	DisplayName = "BOLT-7 SNIPER",
	Damage = 100, -- one-shot to the head (150), body and arms (100); was 115 (owner, 2026-10-16)
	HeadMultiplier = 1.5,
	LimbMultiplier = 1, -- arms: 115, one-shot
	LegMultiplier = 0.7, -- legs / feet: 70, the only non-lethal hit
	RPM = 45, -- ~1.33 s bolt cycle
	Magazine = 5,
	Reserve = 20,
	ReloadSeconds = 3.4,
	Range = 900,
	FalloffStart = 900,
	SpreadHip = 9, -- unscoped is a gamble (even standing)
	SpreadScoped = 0, -- scoped + standing still: pinpoint
	SpreadMoving = 6, -- extra at full sniper run speed (scales with speed)
	SpreadAir = 12,
	StillSpeed = 2,
	ScopeFOV = 18,
	ScopeInSeconds = 0.22,
	EquipSeconds = 0.9,
	RecoilVertical = 4, -- one big kick per shot
	MuzzleLightRange = 24,
	MuzzleLightSeconds = 0.08,
}

Tuning.Knife = {
	Damage = 55, -- front slash: 2 hits
	BackstabDamage = 150, -- from behind (target facing away, > 110° from attacker): instant kill
	Range = 6,
	Cooldown = 0.5,
	EquipSeconds = 0.25,
}

Tuning.Frag = {
	PerLife = 2, -- frags per life (was 1; owner 2026-10-16)
	FuseSeconds = 2.8, -- from release; bounces
	Radius = 24.4, -- damage radius: +25% (was 19.5; 39 before that; owner 2026-10-16)
	VisualRadius = 39, -- size of the flash light / camera-shake reach (kept when the damage radius halved)
	MaxDamage = 220, -- at the centre (was 170); lethal from full health within ~18 studs
	MinDamage = 60, -- at the edge (was 40)
	ThrowSpeed = 75, -- full-strength launch speed (was 70 under full gravity: a flat line drive)
	SelfDamage = true,
	TeamDamage = false,
}

-- Hold-to-charge grenade throws (frag + smoke): hold fire / G / T, release to throw. Strength
-- grows from MinStrength (a tap) to 1 over ChargeSeconds; launch speed = ThrowSpeed * strength.
-- A throw stronger than GlassBreakStrength shatters breakable window glass it flies into.
Tuning.Throw = {
	ChargeSeconds = 1,
	MinStrength = 0.3,
	GlassBreakStrength = 0.5,
	-- COD-style arc (Shared/Lob): launched this many degrees above the crosshair, under this
	-- gravity instead of workspace.Gravity (196.2). Full-strength level throw: apex ~3 studs over
	-- your eyes, lands ~60 studs out.
	LaunchAngle = 15,
	Gravity = 60,
}

-- Wallbanging: only parts tagged "Penetrable" (thin drywall, wooden doors, cubicle panels).
Tuning.Penetration = {
	AK = { MaxWalls = 1, MaxThickness = 1.2, DamageMultiplier = 0.55 },
	Sniper = { MaxWalls = 2, MaxThickness = 2.5, DamageMultiplier = 0.75 }, -- per wall
}

-- v2 dynamic lighting: lights in zones randomly go on, dim or off during a match (server-driven,
-- synced for everyone, mirrored between team halves so it stays fair).
Tuning.LightEvents = {
	-- Toned down for now (was: Interval 6-14 s, 1-2 zones, weights On 45 / Dim 35 / Off 20, Levels
	-- On 0.8-1.15 / Dim 0.25-0.5, MinLitShare 0.4, Drift Scale 0.45-1.2). Zones never go fully Off.
	IntervalMin = 12, -- seconds between changes
	IntervalMax = 24,
	ZonesPerChange = { 1, 1 },
	StateWeights = { On = 70, Dim = 30, Off = 0 },
	-- Each change rolls a random brightness in its state's range (1 = default, which is already 25%
	-- dimmer than the presets: Style.LightScale). Off is always 0.
	Levels = { On = { 0.95, 1.05 }, Dim = { 0.7, 0.85 } },
	DurationMin = 8, -- how long a non-On state lasts before reverting
	DurationMax = 25,
	MinLitShare = 0.75, -- at least 75% of zones On at any time
	FadeSeconds = 0.6, -- dim/brighten transition (Off can snap with a flicker)
	Mirror = true,
	-- How likely each zone is to be picked for a change (1 = normal). The centre gets more events so
	-- it dims / goes dark as often as the side lanes.
	ZoneWeights = { Atrium = 2.5, Junction = 2.5, Hall = 2, Break = 1.5, Records = 1.5, Dist = 2 },
	FlickerIntervalMin = 12, -- every 12-30 s one lit area briefly stutters (gentle, < 2 Hz)
	FlickerIntervalMax = 30,
	-- Single lamps (+ their mirror twin) slowly slide to their own brightness every few seconds.
	-- The middle drifts most so it is never steady.
	Drift = {
		IntervalMin = 2,
		IntervalMax = 5,
		LampsPerStep = { 1, 3 },
		Scale = { 0.9, 1.05 }, -- x the zone level
		ResetChance = 0.3, -- chance a picked lamp goes back to its plain zone level
		FadeSeconds = 1.6,
		ZoneWeights = { Hall = 4, Atrium = 4, Junction = 4, Dist = 1.5 },
	},
}

-- Hitboxes + hit registration (CS/Valorant-style, favor-the-shooter within limits).
Tuning.Hitbox = {
	HeadScale = 1.15, -- head hitbox is slightly generous
	BodyScale = 1.0,
	LimbScale = 1.05,
	ClaimTolerance = 0.9, -- studs a client-claimed hit point may sit outside the rewound hitbox
	RayTolerance = 0.75, -- studs the claimed point may sit off the shot ray
	MaxRewindSeconds = 0.25, -- lag compensation cap
	FacingToleranceDegrees = 75, -- shot direction vs. shooter's body facing (flat)
}

Tuning.Flashlight = {
	Range = 45,
	Angle = 38,
	Brightness = 3,
}

-- Minimap (top-left) and full map [M]. Teammates always show; enemies only for a moment after
-- they fire; flag stations always; a dropped flag always; the enemy carrying YOUR flag pulses
-- every CarrierRevealInterval seconds (0 = shown constantly).
Tuning.Map = {
	MiniRadius = 64, -- studs from you to the minimap edge
	RevealSeconds = 3, -- an enemy shot stays on the map this long (last seen, fading)
	CarrierRevealInterval = 5,
	CarrierRevealSeconds = 1.5,
	PingSeconds = 7,
	PingCooldown = 0.25, -- per player (client + server; server allows a little jitter)
}

-- Occasional creepy moments in dark rooms (HorrorService / HorrorController). Seen only by the one
-- player, never block or affect play; the game stays capture the flag, so they are rare.
Tuning.Horror = {
	Enabled = false, -- OFF for now (user, 2026-10-13): no figures / scare sounds. Ambient hum + HVAC stay.
	DarkSeconds = 2, -- you must have been standing in the dark / gloom this long
	GloomLevel = 0.55, -- lamps below this share of their default output count as "gloom"
	CheckSeconds = 3, -- how often the director rolls for each player in the gloom
	Chance = 0.4, -- per roll
	FirstDelay = 30, -- no scares in a player's first 30 s
	CooldownMin = 35, -- then roughly one every 35 - 70 s per player (sound-only ones count less)
	CooldownMax = 70,
	CalmSeconds = 8, -- not within this long of taking damage or firing
	-- Your zone's lights just went off around you: chance of a figure caught in the last flicker.
	BlackoutChance = 0.45,
	BlackoutRadius = 28, -- you must be this close to one of the zone's lamps
	-- Shared apparitions (seen by everyone nearby): one every SharedMin..SharedMax seconds, placed in
	-- view of a random player who is in the gloom; gone when someone looks at it or after SharedLife.
	SharedMin = 45,
	SharedMax = 90,
	SharedLife = 12,
}

Tuning.Health = {
	Max = 100,
	RegenDelay = 6, -- seconds after last damage
	RegenPerSecond = 12,
}

Tuning.Bots = {
	SniperChance = 0.34, -- share of bots that pick the sniper
	-- TEST (Studio only): no bots on a team that has a real player, so the enemy bots can walk in and
	-- capture your flag. Set false (or delete) when done testing.
	TestNoTeammateBots = true,

	ReactionSeconds = 0.45,
	AimErrorDegrees = 3.2,
	BurstShots = { 3, 6 },
	ViewDistanceLit = 160,
	ViewDistanceDark = 45, -- in dark rooms bots only see close targets (or flashlights / muzzle flash)
	Names = { "Unit-07", "Unit-12", "Unit-21", "Unit-33", "Unit-48", "Unit-56" },
}

Tuning.Teams = {
	Blue = { Name = "Blue", Color = Color3.fromRGB(70, 140, 255) },
	Red = { Name = "Red", Color = Color3.fromRGB(235, 80, 70) },
}

return Tuning

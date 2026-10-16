--!strict
-- Match-event stingers (2D, local): your Core taken / returned, enemy Core taken, captures for and
-- against, victory / defeat. Driven by MatchState diffs and FacilityReport. All ids were verified
-- public via the Roblox catalog API (PSE = ProSoundEffects, APM = APMOfficial, Roblox's licensed
-- sound partners). 0 = silent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local MatchStore = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("MatchStore"))

local GameSoundsController = {}

GameSoundsController.Sounds = {
	EnemyCoreTaken = { Id = 9117297453, Volume = 0.8, Pitch = 1 }, -- PSE "Phasey Synth Power Up High Pitched Rise 2" (your team grabbed the enemy flag)
	OurCoreReturned = { Id = 9126073318, Volume = 0.55, Pitch = 1.2 }, -- PSE "Synth ... Ding"
	WeCaptured = { Id = 135165335432475, Volume = 0.9, Pitch = 1 }, -- yours: "Success Correct Sound"
	WeCapturedSting = { Id = 1848016523, Volume = 0.55, Pitch = 1 }, -- APM "Global Success StingA", layered under it
	-- Call of Duty clips removed (copyright, 2026-10-16): "Let's Do This" 7362982103 (match start),
	-- "Get him out of here" 81131811220434 (carrier killed; silent until an announcer line exists).
	-- Round start (warmup -> live): the announcer laugh, then Wolverine right after it ends.
	MatchStart = { Id = 8343056948, Volume = 0.9, Pitch = 1 }, -- yours: "Mortal Kombat X - Announcer Laugh"
	MatchStartFollow = { Id = 94303877385803, Volume = 0.9, Pitch = 1 }, -- yours: '"Lets go bub" - Wolverine'
	CarrierKilled = { Id = 0, Volume = 0.8, Pitch = 1 }, -- your team kills the enemy carrier
	TheyCaptured = { Id = 9117869243, Volume = 0.6, Pitch = 0.9 }, -- PSE "Power Down 1"
	Victory = { Id = 1836473422, Volume = 0.6, Pitch = 1 }, -- APM "Victory Fanfare Sting"
	Defeat = { Id = 300751476, Volume = 0.8, Pitch = 1 }, -- yours: '"You lose" sound effect' (was APM "Loser" 1844442574)
	-- You died (only you hear it; others near you hear the character's body-fall "Died" sound).
	YouDied = { Id = 4649069508, Volume = 0.8, Pitch = 1 }, -- yours: "8bit death sound"
	-- Neither team won (no Winner in the report). Licensed APM sting; swap for your own if you like.
	Draw = { Id = 1841824498, Volume = 0.6, Pitch = 1 }, -- APM "Unmasked (sting)"
	-- Last 5 s of a live match: a 5-4-3-2-1-0 count (starts at 5 s left; not if the match ends early).
	EndCountdown = { Id = 357644762, Volume = 0.9, Pitch = 1 }, -- yours: "tf2 announcer countdown 5-0"
}

-- Flag loops, driven by the flag state in MatchState: the alarm loops while the enemy carries
-- YOUR flag, the fast clock while YOUR team carries theirs. Both stop the moment nobody carries
-- it any more (carrier killed or dropped it, captured, returned) and restart if it's picked up again.
GameSoundsController.Loops = {
	-- MaxSeconds: stops after this long even if the flag is still carried; FadeSeconds: how long the
	-- fade-out at the end takes (default 0.4). Alarm and clock: 13 s with a slow 3 s fade (owner, 2026-10-16).
	OurFlagCarried = { Id = 15185048184, Volume = 0.45, Pitch = 1, MaxSeconds = 13, FadeSeconds = 3 }, -- yours: "Loop alarm sound"
	EnemyFlagCarried = { Id = 139804031181000, Volume = 0.5, Pitch = 1, MaxSeconds = 13, FadeSeconds = 3 }, -- yours: "FAST CLOCK SFX"
}

-- Character sounds: replaces the SoundIds of Roblox's default character sounds (created by the
-- built-in RbxCharacterSounds script in each character's HumanoidRootPart). 0 = keep the default.
GameSoundsController.CharacterSoundIds = {
	-- Footsteps: handled by FootstepController (the default looping "Running" sound is muted there).
	Died = 9113480915, -- replaces Roblox's "oof"; PSE "Body Fall Thud 2"
} :: { [string]: number }

-- Announcer voice lines (PA style). Files are in shift/audio/announcer/<key>.wav; after uploading
-- them to Roblox, put each asset id here (0 = silent). Every player hears each flag event phrased
-- for their own team.
GameSoundsController.Announcer = {
	shift_our_flag_taken = 0, -- "Warning. Your flag has been taken."
	shift_we_have_enemy_flag = 0, -- "Your team has the enemy flag. Bring it back to base."
	shift_you_have_flag = 0, -- "You have the enemy flag. Bring it back to base."
	shift_our_flag_captured = 0, -- "Your flag has been captured."
	shift_we_captured = 0, -- "Your team captured the enemy flag."
	shift_our_flag_returned = 0, -- "Your flag has been returned."
	shift_enemy_flag_dropped = 0, -- "The enemy flag has been dropped."
	shift_our_flag_dropped = 0, -- "Your flag has been dropped. Return it."
} :: { [string]: number }

-- Low-health heartbeat: loops while you're alive at or below LowHealth (same threshold as the red
-- health bar), louder and faster the lower you are.
GameSoundsController.Heartbeat = { Id = 139481207162657, LowHealth = 35, Volume = 0.9 } -- yours: "Heartbeat"

local COUNTDOWN_AT = 5 -- seconds left when the end countdown starts

local player = Players.LocalPlayer

-- One line at a time; at most 2 waiting (older ones are dropped so lines stay current).
local announceQueue: { string } = {}
local announcing = false

local function playAnnouncer(key: string)
	local id = GameSoundsController.Announcer[key]
	if not id or id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "Announcer_" .. key
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = 1
	-- PA speaker: cut lows and highs, a touch of distortion and a big-hall reverb.
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = -20
	eq.MidGain = 4
	eq.HighGain = -8
	eq.Parent = s
	local dist = Instance.new("DistortionSoundEffect")
	dist.Level = 0.12
	dist.Parent = s
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.DecayTime = 1.1
	reverb.WetLevel = -9
	reverb.Parent = s
	s.Parent = SoundService
	s:Play()
	local done = false
	s.Ended:Once(function()
		done = true
	end)
	local started = os.clock()
	while not done and os.clock() - started < 6 do
		task.wait(0.05)
	end
	s:Destroy()
end

local function announce(key: string)
	if (GameSoundsController.Announcer[key] or 0) == 0 then
		return
	end
	table.insert(announceQueue, key)
	while #announceQueue > 2 do
		table.remove(announceQueue, 1)
	end
	if announcing then
		return
	end
	announcing = true
	task.spawn(function()
		while #announceQueue > 0 do
			playAnnouncer(table.remove(announceQueue, 1) :: string)
			task.wait(0.15)
		end
		announcing = false
	end)
end

local function overrideFootsteps(character: Model)
	local ids = GameSoundsController.CharacterSoundIds
	local function apply(sound: Instance)
		local id = ids[sound.Name]
		if sound:IsA("Sound") and id and id ~= 0 then
			sound.SoundId = "rbxassetid://" .. tostring(id)
		end
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		apply(child)
	end
	root.ChildAdded:Connect(apply)
end

local function watchPlayer(p: Player)
	if p.Character then
		task.spawn(overrideFootsteps, p.Character)
	end
	p.CharacterAdded:Connect(overrideFootsteps)
end

local function play(name: string): Sound?
	local def = GameSoundsController.Sounds[name]
	if not def or def.Id == 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "Stinger_" .. name
	s.SoundId = "rbxassetid://" .. tostring(def.Id)
	s.Volume = def.Volume
	s.PlaybackSpeed = def.Pitch
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(15, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end

-- Plays `first`, then `next` right after the AUDIBLE part of `first`: as soon as its loudness has
-- risen and then stayed near silent for QUIET_HOLD seconds (so trailing silence in the file doesn't
-- leave a gap), or when it ends, or after `maxWait` s at the latest.
local QUIET_LEVEL = 4 -- PlaybackLoudness (0..1000) counted as silence
local LOUD_LEVEL = 25 -- it has to have been at least this loud first
local QUIET_HOLD = 0.12
local function playThen(first: string, nextName: string, maxWait: number)
	local s = play(first)
	if not s then
		play(nextName)
		return
	end
	task.spawn(function()
		local done = false
		s.Ended:Once(function()
			done = true
		end)
		local started = os.clock()
		local wasLoud = false
		local quietSince: number? = nil
		while not done and s.Parent and os.clock() - started < maxWait do
			local level = s.PlaybackLoudness
			if level >= LOUD_LEVEL then
				wasLoud = true
				quietSince = nil
			elseif wasLoud and level <= QUIET_LEVEL then
				quietSince = quietSince or os.clock()
				if os.clock() - (quietSince :: number) >= QUIET_HOLD then
					break -- the laughter is over; the rest of the file is silence
				end
			else
				quietSince = nil
			end
			RunService.Heartbeat:Wait()
		end
		play(nextName)
	end)
end

-- Sound while playing; false = on, but its MaxSeconds ran out (don't restart until it goes off).
local loops: { [string]: Sound | false } = {}

local function setLoop(name: string, on: boolean)
	local def: any = GameSoundsController.Loops[name]
	local s = loops[name]
	if on and s == nil and def and def.Id ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = "Loop_" .. name
		sound.SoundId = "rbxassetid://" .. tostring(def.Id)
		sound.Volume = def.Volume
		sound.PlaybackSpeed = def.Pitch
		sound.Looped = true
		sound.Parent = SoundService
		sound:Play()
		loops[name] = sound
		local max = def.MaxSeconds
		if type(max) == "number" then
			local fade = if type(def.FadeSeconds) == "number" then def.FadeSeconds else 0.4
			task.delay(math.max(0, max - fade), function()
				if loops[name] == sound then
					TweenService:Create(
						sound,
						TweenInfo.new(fade, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{ Volume = 0 }
					):Play()
				end
			end)
			task.delay(max, function()
				if loops[name] == sound then
					sound:Destroy()
					loops[name] = false
				end
			end)
		end
	elseif not on and s ~= nil then
		if s then
			s:Stop()
			s:Destroy()
		end
		loops[name] = nil
	end
end

local function myTeam(): string?
	local team = player.Team
	if team then
		return team.Name
	end
	local character = player.Character
	local attr = character and character:GetAttribute("Team")
	return if type(attr) == "string" then attr else nil
end

local function otherTeam(team: string): string
	return if team == "Blue" then "Red" else "Blue"
end

-- Local character: low-health heartbeat + your death sound.
local function watchHeartbeat()
	local cfg = GameSoundsController.Heartbeat
	local beat = Instance.new("Sound")
	beat.Name = "Heartbeat"
	beat.SoundId = "rbxassetid://" .. tostring(cfg.Id)
	beat.Looped = true
	beat.Volume = 0
	beat.Parent = SoundService
	local conn: RBXScriptConnection? = nil
	local function update(health: number)
		if cfg.Id == 0 then
			return
		end
		if health > 0 and health <= cfg.LowHealth then
			local severity = 1 - health / cfg.LowHealth -- 0 at the threshold, 1 near death
			beat.Volume = cfg.Volume * (0.55 + 0.45 * severity)
			beat.PlaybackSpeed = 1 + 0.25 * severity
			if not beat.IsPlaying then
				beat:Play()
			end
		elseif beat.IsPlaying then
			beat:Stop()
		end
	end
	local function watch(character: Model)
		if conn then
			conn:Disconnect()
			conn = nil
		end
		beat:Stop()
		local hum = character:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum.Died:Once(function()
				play("YouDied")
			end)
			update(hum.Health)
			conn = hum.HealthChanged:Connect(function(h: number)
				update(h)
			end)
		end
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

-- End-of-match countdown: once per live match, when the local timer reaches COUNTDOWN_AT.
local function watchCountdown()
	local played = false
	MatchStore.PhaseChanged:Connect(function()
		played = false
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			if MatchStore.Phase == "Live" and MatchStore.HasState then
				local left = MatchStore.timeLeft()
				if not played and left > 0 and left <= COUNTDOWN_AT then
					played = true
					play("EndCountdown")
				end
			end
		end
	end)
end

function GameSoundsController:Init() end

function GameSoundsController:Start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	watchHeartbeat()
	watchCountdown()

	local last: any = nil

	Remotes.Get("MatchState").OnClientEvent:Connect(function(state: any)
		if type(state) ~= "table" then
			return
		end
		local prev = last
		last = state
		local mine = myTeam()

		-- Flag loops follow the current state (no diff needed).
		local live = state.Phase == "Live" and mine ~= nil
		local allCores = if type(state.Cores) == "table" then state.Cores else {}
		local function carried(team: string?): boolean
			local core = team and allCores[team]
			return type(core) == "table" and core.State == "Carried"
		end
		setLoop("OurFlagCarried", live and carried(mine))
		setLoop("EnemyFlagCarried", live and mine ~= nil and carried(otherTeam(mine :: string)))

		if prev and prev.Phase ~= "Live" and state.Phase == "Live" then
			playThen("MatchStart", "MatchStartFollow", 6)
		end
		if not prev or not mine or state.Phase ~= "Live" or prev.Phase ~= "Live" then
			return
		end
		local enemy = otherTeam(mine)
		local score, prevScore = state.Score or {}, prev.Score or {}
		local cores, prevCores = state.Cores or {}, prev.Cores or {}

		local weScored = (score[mine] or 0) > (prevScore[mine] or 0)
		local theyScored = (score[enemy] or 0) > (prevScore[enemy] or 0)
		if weScored then
			play("WeCaptured")
			play("WeCapturedSting")
			announce("shift_we_captured")
		end
		if theyScored then
			play("TheyCaptured")
			announce("shift_our_flag_captured")
		end

		local ours, prevOurs = cores[mine], prevCores[mine]
		local theirs, prevTheirs = cores[enemy], prevCores[enemy]
		if type(ours) == "table" and type(prevOurs) == "table" then
			if prevOurs.State == "Home" and ours.State == "Carried" then
				announce("shift_our_flag_taken") -- (the alarm is the OurFlagCarried loop)
			elseif prevOurs.State == "Carried" and ours.State == "Dropped" then
				announce("shift_our_flag_dropped")
			elseif prevOurs.State ~= "Home" and ours.State == "Home" and not theyScored then
				play("OurCoreReturned")
				announce("shift_our_flag_returned")
			end
		end
		if type(theirs) == "table" and type(prevTheirs) == "table" then
			if theirs.State == "Carried" and prevTheirs.State ~= "Carried" then
				-- Picked up from the pedestal or off the floor.
				if prevTheirs.State == "Home" then
					play("EnemyCoreTaken")
				end
				announce(
					if theirs.CarrierUserId == player.UserId
						then "shift_you_have_flag"
						else "shift_we_have_enemy_flag"
				)
			elseif prevTheirs.State == "Carried" and theirs.State == "Dropped" then
				announce("shift_enemy_flag_dropped")
			end
		end
	end)

	Remotes.Get("KillFeed").OnClientEvent:Connect(function(entry: any)
		if type(entry) == "table" and entry.CarrierKill == true and entry.KillerTeam == myTeam() then
			play("CarrierKilled")
		end
	end)

	Remotes.Get("FacilityReport").OnClientEvent:Connect(function(report: any)
		if type(report) ~= "table" then
			return
		end
		local mine = myTeam()
		if not mine then
			return -- unknown team: no stinger
		end
		if type(report.Winner) ~= "string" then
			play("Draw")
			return
		end
		play(if report.Winner == mine then "Victory" else "Defeat")
	end)
end

return GameSoundsController

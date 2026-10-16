--!strict
-- Match loop (Warmup -> Live -> Ended + FacilityReport -> WorldService:ResetMatch()), scoring,
-- Core events and announcements, capture -> ShiftAnnounce -> WorldService:ApplyNextShift(),
-- respawns, stats, and MatchState broadcasts (4x/s while a Core is away from home, else 1x/s).

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ModeFolder = script.Parent.Parent.Systems.Mode
local Types = require(ModeFolder.Types)
local Deps = require(ModeFolder.Deps)
local Stats = require(ModeFolder.Stats)
local Movement = require(ModeFolder.Movement)
local Spawner = require(ModeFolder.Spawner)
local Loadouts = require(ModeFolder.Loadouts)
local CoreSystem = require(ModeFolder.CoreSystem)
local TeamService = require(script.Parent.TeamService)

type Combatant = Types.Combatant
type Phase = "Warmup" | "Live" | "Ended"

local MatchService = {}

local TICK = 0.1

local phase: Phase = "Warmup"
local phaseEndsAt = 0
local endRequested = false
local winner: string? = nil
local score = { Blue = 0, Red = 0 }
local shifts: { { Title: string, Detail: string } } = {}
local matchId = 0
local dirty = true
local lastBroadcast = 0
local lastReport: { [string]: any }? = nil
local shiftQueue = 0
local shiftRunning = false

local remotes: { [string]: RemoteEvent } = {}

local function remote(name: string): RemoteEvent
	local r = remotes[name]
	if not r then
		r = Remotes.Get(name)
		remotes[name] = r
	end
	return r
end

local function getBotService(): any
	local module = script.Parent:FindFirstChild("BotService")
	if not module then
		return nil
	end
	local ok, result = pcall(require :: any, module)
	return if ok then result else nil
end

local function logEvent(player: Player?, name: string, value: number?)
	if not player then
		return
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

---------------------------------------------------------------------------------------------------
-- Public API (used by BotService and possibly UI/Combat)

function MatchService:GetPhase(): Phase
	return phase
end

function MatchService:GetScore(): { Blue: number, Red: number }
	return { Blue = score.Blue, Red = score.Red }
end

function MatchService:GetCore(team: string): Types.CoreState
	return CoreSystem.Get(team)
end

function MatchService:GetHomePosition(team: string): Vector3
	return CoreSystem.HomePosition(team)
end

function MatchService:MarkDirty()
	dirty = true
end

---------------------------------------------------------------------------------------------------
-- Messaging

local function announceTeam(team: string, text: string, kind: string)
	for _, player in Players:GetPlayers() do
		local c = TeamService:GetByPlayer(player)
		if c and c.Team == team then
			remote("Announce"):FireClient(player, text, kind)
		end
	end
end

local function announceAll(text: string, kind: string)
	remote("Announce"):FireAllClients(text, kind)
end

local function announceTo(c: Combatant?, text: string, kind: string)
	if c and c.Player then
		remote("Announce"):FireClient(c.Player, text, kind)
	end
end

local function currentIds(): { [string]: boolean }
	local ids = {}
	for _, c in TeamService:GetAll() do
		ids[c.Id] = true
	end
	return ids
end

local function buildState(): { [string]: any }
	return {
		Phase = phase,
		TimeLeft = math.max(0, math.ceil(phaseEndsAt - os.clock())),
		Score = { Blue = score.Blue, Red = score.Red },
		CaptureLimit = Tuning.Match.CaptureLimit,
		Cores = { Blue = CoreSystem.InfoFor("Blue"), Red = CoreSystem.InfoFor("Red") },
		Players = Stats.Rows(currentIds()), -- live scoreboard: { Name, Team, Kills, Deaths, Captures, Returns, Bot }
	}
end

local function broadcast()
	dirty = false
	lastBroadcast = os.clock()
	remote("MatchState"):FireAllClients(buildState())
end

---------------------------------------------------------------------------------------------------
-- Shifts: queue so back-to-back captures each get their own 5 s warning.

local function runShifts(forMatch: number)
	if shiftRunning then
		return
	end
	shiftRunning = true
	while shiftQueue > 0 and matchId == forMatch and phase == "Live" do
		shiftQueue -= 1
		local preview = Deps.PeekNextShift()
		local seconds = Tuning.Core.ShiftWarningSeconds
		remote("ShiftAnnounce"):FireAllClients({
			Seconds = seconds,
			Title = if preview then preview.Title else "FACILITY SHIFT",
			Detail = if preview then preview.Detail else `Facility shift in {seconds}`,
		})
		task.wait(seconds)
		if matchId ~= forMatch or phase ~= "Live" then
			break
		end
		local info = Deps.ApplyNextShift()
		CoreSystem.RelocateDropped(Deps.SafePosition)
		table.insert(shifts, info)
		announceAll(if info.Detail ~= "" then `{info.Title} · {info.Detail}` else info.Title, "Info")
		local bots = getBotService()
		if bots and bots.InvalidateNav then
			bots:InvalidateNav()
		end
	end
	shiftQueue = 0
	shiftRunning = false
end

---------------------------------------------------------------------------------------------------
-- Core events

local function onCoreEvent(kind: string, coreTeam: string, by: Combatant?, deliberate: boolean?)
	local thieves = TeamService:Enemy(coreTeam)
	dirty = true
	if kind == "Taken" then
		announceTeam(coreTeam, `{thieves} has your Flag!`, "Bad")
		announceTeam(thieves, `{if by then by.Name else "Your team"} has the {coreTeam} Flag`, "Good")
		announceTo(by, "You have the Flag - knife only, run it home", "Info")
	elseif kind == "Dropped" then
		announceTeam(coreTeam, "Your Flag was dropped - touch it to return it", "Good")
		if deliberate and by then
			announceTeam(thieves, `{by.Name} dropped the {coreTeam} Flag - pick it up`, "Info")
		else
			announceTeam(thieves, `{coreTeam} Flag dropped`, "Bad")
		end
	elseif kind == "Returned" then
		if by then
			Stats.Add(by, "Returns")
		end
		announceTeam(coreTeam, "Flag returned", "Good")
		announceTeam(thieves, `{coreTeam} Flag returned`, "Info")
	elseif kind == "NeedHome" then
		announceTo(by, "Your Flag must be home to capture", "Info")
	elseif kind == "Captured" then
		if phase ~= "Live" then
			return
		end
		local scorer = thieves
		score[scorer] += 1
		if by then
			Stats.Add(by, "Captures")
			logEvent(by.Player, "CoreCaptured")
		end
		announceTeam(scorer, `{if by then by.Name else scorer} captured the {coreTeam} Flag!`, "Good")
		announceTeam(coreTeam, `{scorer} captured your Flag`, "Bad")
		if score[scorer] >= Tuning.Match.CaptureLimit then
			winner = scorer
			endRequested = true
		else
			shiftQueue += 1
			task.spawn(runShifts, matchId)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Deaths and kills

local function onDied(c: Combatant, _model: Model, position: Vector3)
	CoreSystem.OnCombatantDown(c, position, true)
	if phase == "Live" then
		Stats.Add(c, "Deaths")
	end
	c.Streak += 1
	local seconds = Spawner.RespawnTime(c) -- v2: flat Tuning.Match respawn (3 s)
	if c.Player then
		remote("RespawnTimer"):FireClient(c.Player, seconds)
	end
	Spawner.ScheduleRespawn(c, seconds)
	dirty = true
end

local function onKill(victimModel: Model, killerModel: Model?, _headshot: boolean?)
	if phase ~= "Live" then
		return
	end
	local victim = TeamService:GetByModel(victimModel)
	local killer = TeamService:GetByModel(killerModel)
	if victim and killer and killer ~= victim and killer.Team ~= victim.Team then
		Stats.Add(killer, "Kills")
		killer.Streak = 0
		dirty = true
	end
end

---------------------------------------------------------------------------------------------------
-- Match end

local function buildReport(): { [string]: any }
	local snapshot = Deps.GetSnapshot()
	local broken = {}
	for _, lamp in snapshot.Lamps do
		if type(lamp) == "table" and lamp.Broken then
			table.insert(broken, tostring(lamp.Id))
		end
	end
	return {
		Winner = winner,
		Score = { Blue = score.Blue, Red = score.Red },
		BrokenLamps = broken,
		TotalLamps = #snapshot.Lamps,
		Shifts = table.clone(shifts),
		Mvp = Stats.Mvp(),
		Players = Stats.Rows(),
		MapSnapshot = snapshot,
	}
end

local function finishMatch()
	if winner == nil and score.Blue ~= score.Red then
		winner = if score.Blue > score.Red then "Blue" else "Red"
	end
	local report = buildReport()
	lastReport = report
	remote("FacilityReport"):FireAllClients(report)
	if winner then
		announceAll(`{winner} wins {score.Blue}-{score.Red}`, "Info")
	else
		announceAll(`Draw {score.Blue}-{score.Red}`, "Info")
	end
	for _, c in TeamService:GetAll() do
		if c.Player then
			logEvent(c.Player, if c.Team == winner then "MatchWon" else "MatchLost")
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Loop

local function setPhase(newPhase: Phase, seconds: number)
	phase = newPhase
	phaseEndsAt = os.clock() + seconds
	endRequested = false
	dirty = true
end

local lastMovementPass = 0

local function step()
	CoreSystem.Step(phase == "Live")
	local now = os.clock()
	if now - lastMovementPass >= 0.25 then
		lastMovementPass = now
		for _, c in TeamService:GetAll() do
			if c.Alive and c.Model then
				Movement.UpdateWading(c.Model)
				Movement.Apply(c.Model)
			end
		end
	end
	local interval = if CoreSystem.AnyMoving() then 0.25 else 1
	if dirty or now - lastBroadcast >= interval then
		broadcast()
	end
end

local function runPhase()
	while os.clock() < phaseEndsAt and not endRequested do
		local ok, err = pcall(step)
		if not ok then
			warn("[Mode] Match step failed: " .. tostring(err))
		end
		task.wait(TICK)
	end
end

local function resetForNewMatch()
	matchId += 1
	score = { Blue = 0, Red = 0 }
	shifts = {}
	winner = nil
	shiftQueue = 0
	lastReport = nil
	for _, c in TeamService:GetAll() do
		c.Streak = 0
	end
	Stats.Reset(TeamService:GetAll())
	CoreSystem.ResetAll()
	local bots = getBotService()
	if bots and bots.InvalidateNav then
		bots:InvalidateNav()
	end
end

local function matchLoop()
	while true do
		resetForNewMatch()
		setPhase("Warmup", Tuning.Match.WarmupSeconds)
		Spawner.RespawnAll()
		announceAll(
			`{Tuning.Match.TeamSize}v{Tuning.Match.TeamSize} · first to {Tuning.Match.CaptureLimit} captures`,
			"Info"
		)
		runPhase()

		resetForNewMatch()
		setPhase("Live", Tuning.Match.MatchSeconds)
		Spawner.RespawnAll()
		announceAll("Match live - steal their Flag", "Info")
		runPhase()

		setPhase("Ended", Tuning.Match.EndSeconds)
		finishMatch()
		broadcast()
		runPhase()

		Deps.ResetMatch()
	end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

function MatchService:Init()
	Players.CharacterAutoLoads = false
	for _, name in { "MatchState", "Announce", "ShiftAnnounce", "FacilityReport", "RespawnTimer" } do
		remote(name)
	end
end

local function onMemberAdded(c: Combatant)
	if c.Player then
		Spawner.BindPlayer(c.Player)
	end
	Stats.Ensure(c)
	Spawner.Spawn(c)
	dirty = true
end

local function onMemberRemoved(c: Combatant)
	local model = c.Model
	local root = Spawner.RootOf(model)
	local position = if root then root.Position else CoreSystem.Get(c.Team).Position
	c.Alive = false
	CoreSystem.OnCombatantDown(c, position, false)
	if c.IsBot and model then
		model:Destroy()
	end
	Loadouts.Forget(c)
	dirty = true
end

function MatchService:Start()
	Deps.EnsureFallbackWorld()
	CoreSystem.ResetAll()

	CoreSystem.Event:Connect(onCoreEvent)
	Spawner.Died:Connect(onDied)
	Deps.ConnectOnDeath(onKill)
	TeamService.MemberAdded:Connect(onMemberAdded)
	TeamService.MemberRemoved:Connect(onMemberRemoved)

	-- Firing cancels spawn protection.
	remote("Fire").OnServerEvent:Connect(function(player)
		Spawner.CancelProtection(player.Character)
	end)

	-- Carrier drops the flag on purpose (a teammate can pick it up).
	remote("DropFlag").OnServerEvent:Connect(function(player)
		local c = TeamService:GetByPlayer(player)
		if c then
			CoreSystem.DropBy(c)
		end
	end)

	remote("ClientReady").OnServerEvent:Connect(function(player)
		remote("MatchState"):FireClient(player, buildState())
		local c = TeamService:GetByPlayer(player)
		if c then
			Loadouts.Send(c)
		end
		if phase == "Ended" and lastReport then
			remote("FacilityReport"):FireClient(player, lastReport)
		end
	end)

	Loadouts.Start(function(player: Player)
		return TeamService:GetByPlayer(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		TeamService:AddPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		TeamService:RemovePlayer(player)
	end)

	TeamService:Rebalance() -- bots for every empty slot
	for _, player in Players:GetPlayers() do
		task.spawn(TeamService.AddPlayer, TeamService, player)
	end

	task.spawn(matchLoop)
end

return MatchService

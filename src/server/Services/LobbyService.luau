--!strict
-- Deploy menu + squads + FIND MATCH (client: LobbyController).
--
-- Server kinds:
--   Quick  public server: join the running 3v3 (bots fill); PLAY deploys you, FIND MATCH queues.
--   Private VIP server: same as Quick.
--   Match  reserved server built by the Matchmaker: players arrive with { MatchId, Team } teleport
--          data, their team is fixed, nobody else can join; QUICK PLAY sends you back to a public
--          server.
--
-- Until a player presses PLAY they are not on the roster, so a bot keeps their slot and the match
-- carries on. Squads (up to Tuning.Matchmaking.MaxSquad) form on the server; the leader (or a solo
-- player) presses FIND MATCH and the whole squad is queued. If no match is found within
-- SearchSeconds (or matchmaking is unavailable, e.g. in Studio) the squad is deployed here, together,
-- with bots filling the gaps.
--
-- Remotes: Lobby (client -> server, { Action = ... }), LobbyState (server -> client, the menu state).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Systems = script.Parent.Parent:WaitForChild("Systems")
local Matchmaker = require(Systems:WaitForChild("Matchmaking"):WaitForChild("Matchmaker"))
local Loadouts = require(Systems:WaitForChild("Mode"):WaitForChild("Loadouts"))
local TeamService = require(script.Parent.TeamService)

local LobbyService = {}

local CFG = Tuning.Matchmaking
local IS_MATCH = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local IS_VIP = game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
local MODE = if IS_MATCH then "Match" elseif IS_VIP then "Private" else "Quick"
local ACTION_GAP = 0.25

type Search = {
	Status: string, -- "Searching" | "Found" | "NoMatch" | "Failed"
	Ticket: any?,
	Started: number,
	Deadline: number,
	Message: string?,
}
type Squad = { Id: number, Leader: Player, Members: { Player }, Search: Search? }

local squads: { [number]: Squad } = {}
local squadOf: { [Player]: Squad } = {}
local fixedTeam: { [Player]: string } = {}
local lastAction: { [Player]: number } = {}
local lastSwitch: { [Player]: number } = {}
local notice: { [Player]: string } = {} -- one-off message for the menu (search ended, ...)
local nextSquadId = 0

---------------------------------------------------------------------------------------------------
-- State

local function teamInfo(): { [string]: any }
	local info = {}
	for _, team in TeamService.TEAMS do
		local real, bots = 0, 0
		for _, c in TeamService:GetTeam(team) do
			if c.IsBot then
				bots += 1
			else
				real += 1
			end
		end
		info[team] = { Real = real, Bots = bots, Size = Tuning.Match.TeamSize }
	end
	return info
end

local function stateFor(player: Player, teams: { [string]: any }): { [string]: any }
	local c = TeamService:GetByPlayer(player)
	local squad = squadOf[player]
	local squadInfo = nil
	if squad then
		local members = {}
		for _, m in squad.Members do
			table.insert(members, { UserId = m.UserId, Name = m.DisplayName })
		end
		squadInfo = { Id = squad.Id, LeaderId = squad.Leader.UserId, Members = members }
	end
	local open = {}
	if MODE ~= "Match" then
		for _, s in squads do
			if s ~= squad and #s.Members < CFG.MaxSquad and s.Search == nil then
				table.insert(open, { Id = s.Id, Leader = s.Leader.DisplayName, Count = #s.Members })
			end
		end
	end
	local search = nil
	if squad and squad.Search then
		local s = squad.Search
		search = {
			Status = s.Status,
			Remaining = math.max(0, math.ceil(s.Deadline - os.clock())),
			Message = s.Message,
		}
	end
	local msg = notice[player]
	notice[player] = nil
	return {
		Mode = MODE,
		Deployed = c ~= nil,
		MyTeam = if c then c.Team else nil,
		FixedTeam = fixedTeam[player],
		Teams = teams,
		Squad = squadInfo,
		OpenSquads = open,
		Search = search,
		CanSearch = MODE ~= "Match"
			and (squad == nil or squad.Leader == player)
			and not (squad and squad.Search),
		Matchmaking = Matchmaker.Available(),
		Studio = RunService:IsStudio(),
		Notice = msg,
	}
end

local function push(player: Player)
	Remotes.Get("LobbyState"):FireClient(player, stateFor(player, teamInfo()))
end

local function pushAll()
	local teams = teamInfo()
	for _, p in Players:GetPlayers() do
		Remotes.Get("LobbyState"):FireClient(p, stateFor(p, teams))
	end
end

---------------------------------------------------------------------------------------------------
-- Deploy

-- Team for a deploying player: fixed (match server) > picked > a squad mate's team > automatic.
local function deploy(player: Player, wanted: string?)
	if TeamService:GetByPlayer(player) then
		return
	end
	local fixed = fixedTeam[player]
	if fixed then
		TeamService:AddPlayer(player, fixed, true)
		return
	end
	local squad = squadOf[player]
	if (wanted == nil or wanted == "Auto") and squad then
		for _, m in squad.Members do
			local mc = m ~= player and TeamService:GetByPlayer(m)
			if mc and TeamService:RealCount(mc.Team) < Tuning.Match.TeamSize then
				wanted = mc.Team
				break
			end
		end
	end
	if wanted == "Blue" or wanted == "Red" then
		if TeamService:RealCount(wanted) >= Tuning.Match.TeamSize then
			wanted = nil -- full: automatic
		end
	else
		wanted = nil
	end
	TeamService:AddPlayer(player, wanted, false)
end

-- Deploy a whole squad here, on one team when there's room for all of them.
local function deploySquad(squad: Squad)
	local team: string? = nil
	local need = #squad.Members
	for _, t in TeamService.TEAMS do
		if Tuning.Match.TeamSize - TeamService:RealCount(t) >= need then
			if team == nil or TeamService:RealCount(t) < TeamService:RealCount(team) then
				team = t
			end
		end
	end
	for _, m in squad.Members do
		if m.Parent == Players then
			deploy(m, team)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Squads

local function stopSearch(squad: Squad, cancelTicket: boolean)
	local s = squad.Search
	if s and cancelTicket and s.Ticket then
		Matchmaker.Cancel(s.Ticket.Id)
	end
	squad.Search = nil
end

local function leaveSquad(player: Player)
	local squad = squadOf[player]
	if not squad then
		return
	end
	stopSearch(squad, true) -- the squad changed: its queue entry no longer matches it
	squadOf[player] = nil
	local i = table.find(squad.Members, player)
	if i then
		table.remove(squad.Members, i)
	end
	if #squad.Members == 0 then
		squads[squad.Id] = nil
	elseif squad.Leader == player then
		squad.Leader = squad.Members[1]
	end
end

local function createSquad(player: Player): Squad
	leaveSquad(player)
	nextSquadId += 1
	local squad: Squad = { Id = nextSquadId, Leader = player, Members = { player }, Search = nil }
	squads[squad.Id] = squad
	squadOf[player] = squad
	return squad
end

local function joinSquad(player: Player, id: any)
	local squad = type(id) == "number" and squads[id] or nil
	if not squad or squad.Search or #squad.Members >= CFG.MaxSquad or squadOf[player] == squad then
		return
	end
	leaveSquad(player)
	table.insert(squad.Members, player)
	squadOf[player] = squad
end

---------------------------------------------------------------------------------------------------
-- Search

local function findMatch(player: Player)
	if MODE == "Match" then
		return
	end
	local squad = squadOf[player] or createSquad(player)
	if squad.Leader ~= player or squad.Search then
		return
	end
	local now = os.clock()
	local seconds = if Matchmaker.Available() then CFG.SearchSeconds else CFG.StudioSearchSeconds
	local search: Search = { Status = "Searching", Ticket = nil, Started = now, Deadline = now + seconds }
	squad.Search = search
	if Matchmaker.Available() then
		local ids = {}
		for _, m in squad.Members do
			table.insert(ids, m.UserId)
		end
		local ticket = Matchmaker.NewTicket(ids)
		if Matchmaker.Enqueue(ticket) then
			search.Ticket = ticket
		else
			search.Deadline = now -- queue unavailable: fall back at once
		end
	else
		search.Message = "Matchmaking runs in the published game only"
	end
end

local function endSearchHere(squad: Squad, message: string)
	stopSearch(squad, true)
	for _, m in squad.Members do
		notice[m] = message
	end
	deploySquad(squad)
end

local function pollSearches()
	local changed = false
	local now = os.clock()
	for _, squad in squads do
		local s = squad.Search
		if not s or s.Status ~= "Searching" then
			continue
		end
		changed = true -- the countdown moves
		local ticket = s.Ticket
		if ticket then
			local result = Matchmaker.PollResult(ticket.Id)
			if result then
				s.Status = "Found"
				s.Message = "Match found - joining"
				local travellers = {}
				for _, m in squad.Members do
					if m.Parent == Players then
						table.insert(travellers, m)
					end
				end
				pushAll()
				if not Matchmaker.Teleport(travellers, result) then
					endSearchHere(squad, "Couldn't join the match - playing here")
				end
				continue
			end
			Matchmaker.Refresh(ticket.Id)
		end
		if now >= s.Deadline then
			endSearchHere(
				squad,
				if ticket then "No opponents found - playing here with bots" else "Playing here with bots"
			)
		end
	end
	if changed then
		pushAll()
	end
end

---------------------------------------------------------------------------------------------------
-- Actions

local function onAction(player: Player, msg: any)
	if type(msg) ~= "table" or type(msg.Action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_GAP then
		return
	end
	lastAction[player] = now
	local action = msg.Action
	if action == "Deploy" then
		Loadouts.Preset(player, msg.Primary)
		deploy(player, msg.Team)
	elseif action == "SwitchTeam" then
		if MODE ~= "Match" and now - (lastSwitch[player] or 0) >= CFG.SwitchTeamCooldown then
			if TeamService:SwitchTeam(player) then
				lastSwitch[player] = now
			else
				notice[player] = "The other team is full"
			end
		end
	elseif MODE == "Match" then
		if action == "QuickPlay" then
			Matchmaker.ToQuickPlay(player)
		end
	elseif action == "CreateSquad" then
		createSquad(player)
	elseif action == "JoinSquad" then
		joinSquad(player, msg.Id)
	elseif action == "LeaveSquad" then
		leaveSquad(player)
	elseif action == "FindMatch" then
		findMatch(player)
	elseif action == "CancelSearch" then
		local squad = squadOf[player]
		if squad and squad.Leader == player and squad.Search then
			stopSearch(squad, true)
		end
	elseif action == "PlayWithBots" then
		local squad = squadOf[player]
		if squad and squad.Search then
			if squad.Leader == player then
				endSearchHere(squad, "Playing here with bots")
			end
		else
			deploy(player, nil)
		end
	end
	pushAll()
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local function onPlayerAdded(player: Player)
	if IS_MATCH then
		local data = player:GetJoinData().TeleportData
		if type(data) == "table" and (data.Team == "Blue" or data.Team == "Red") then
			fixedTeam[player] = data.Team
		end
	end
	push(player)
end

function LobbyService:Init()
	Matchmaker.Init()
end

function LobbyService:Start()
	Remotes.Get("Lobby").OnServerEvent:Connect(onAction)
	Remotes.Get("ClientReady").OnServerEvent:Connect(push)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		leaveSquad(player)
		fixedTeam[player] = nil
		lastAction[player] = nil
		lastSwitch[player] = nil
		notice[player] = nil
		pushAll()
	end)
	TeamService.RosterChanged:Connect(pushAll)
	-- A teleport that couldn't start: back to the menu here, with bots.
	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, message: string)
		warn("[Lobby] teleport failed for", player.Name, message)
		notice[player] = "Couldn't join the match - playing here"
		local squad = squadOf[player]
		if squad then
			stopSearch(squad, false)
		end
		deploy(player, nil)
		pushAll()
	end)
	Matchmaker.Start()
	task.spawn(function()
		while true do
			task.wait(CFG.PollSeconds)
			local ok, err = pcall(pollSearches)
			if not ok then
				warn("[Lobby] search poll failed:", err)
			end
		end
	end)
end

return LobbyService

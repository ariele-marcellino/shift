--!strict
-- Cross-server matchmaking for FIND MATCH (Roblox MemoryStore, shared by every SHIFT server).
--
--   Tickets (sorted map, sort key = queue time): one per searching squad
--       { Id, Users = { userId }, Size, Server = JobId, At = unix seconds, Claimed?, ClaimedAt? }
--     The owning server refreshes its ticket every PollSeconds (it expires TicketSeconds after the
--     last refresh, so a crashed server's ticket disappears on its own) and removes it on cancel.
--   Results (sorted map): ticket Id -> { AccessCode, Team, MatchId } once matched; the owning server
--     polls it and teleports the squad.
--   Leader lock: one server at a time (a lease of LeaderSeconds, renewed while alive) reads the
--     queue and builds matches: 3v3 from the oldest tickets, a squad always on one team, the next
--     ticket going to the side with more room. A full 3v3 starts at once; once the oldest ticket
--     has waited PartialAfterSeconds, a match with at least one squad per side starts too (bots
--     fill the empty slots). Tickets are claimed atomically before a match is committed, so two
--     leaders (a lease hand-over race) can never put the same squad in two matches.
--
-- Everything is pcall-guarded: MemoryStore / TeleportService are unavailable in Studio and can
-- fail on a live server; callers then fall back to playing locally with bots.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Matchmaker = {}

export type Ticket = {
	Id: string,
	Users: { number },
	Size: number,
	Server: string,
	At: number,
	Claimed: string?,
	ClaimedAt: number?,
}
export type Result = { AccessCode: string, Team: string, MatchId: string }

local CFG = Tuning.Matchmaking
local TEAM = Tuning.Match.TeamSize
local CLAIM_STALE = 20 -- a claim older than this (leader died mid-commit) is ignored

local tickets: MemoryStoreSortedMap? = nil
local results: MemoryStoreSortedMap? = nil
local lock: MemoryStoreSortedMap? = nil
local available = false

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function log(...: any)
	print("[Matchmaker]", ...)
end

-- MemoryStore + reserved servers only work in a published game (not in Studio).
function Matchmaker.Available(): boolean
	return available
end

function Matchmaker.Init()
	if RunService:IsStudio() then
		return -- Studio: no queue / teleports; LobbyService fakes a short search, then bots
	end
	local ok, err = pcall(function()
		tickets = MemoryStoreService:GetSortedMap("SHIFT_MM_Tickets_v1")
		results = MemoryStoreService:GetSortedMap("SHIFT_MM_Results_v1")
		lock = MemoryStoreService:GetSortedMap("SHIFT_MM_Lock_v1")
	end)
	available = ok
	if not ok then
		warn("[Matchmaker] MemoryStore unavailable:", err)
	end
end

---------------------------------------------------------------------------------------------------
-- Owner side (the server the squad is on)

function Matchmaker.NewTicket(userIds: { number }): Ticket
	return {
		Id = HttpService:GenerateGUID(false),
		Users = userIds,
		Size = #userIds,
		Server = game.JobId,
		At = now(),
	}
end

function Matchmaker.Enqueue(t: Ticket): boolean
	local map = tickets
	if not map then
		return false
	end
	local ok, err = pcall(function()
		map:SetAsync(t.Id, t, CFG.TicketSeconds, t.At)
	end)
	if not ok then
		warn("[Matchmaker] enqueue failed:", err)
	end
	return ok
end

-- Keep a queued ticket alive (never re-creates one that a match already consumed).
function Matchmaker.Refresh(id: string)
	local map = tickets
	if not map then
		return
	end
	pcall(function()
		map:UpdateAsync(id, function(old: any)
			if old == nil then
				return nil -- consumed or cancelled: don't bring it back
			end
			if old.Claimed and now() - (old.ClaimedAt or 0) > CLAIM_STALE then
				old.Claimed, old.ClaimedAt = nil, nil -- leader died mid-commit: queue it again
			end
			return old
		end, CFG.TicketSeconds)
	end)
end

function Matchmaker.Cancel(id: string)
	local map = tickets
	if map then
		pcall(function()
			map:RemoveAsync(id)
		end)
	end
end

function Matchmaker.PollResult(id: string): Result?
	local map = results
	if not map then
		return nil
	end
	local ok, value = pcall(function()
		return map:GetAsync(id)
	end)
	if ok and type(value) == "table" and type(value.AccessCode) == "string" then
		pcall(function()
			map:RemoveAsync(id)
		end)
		return value :: Result
	end
	return nil
end

-- Send matched players to their match server. Returns false if the teleport couldn't start.
function Matchmaker.Teleport(players: { Player }, result: Result): boolean
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = result.AccessCode
		options:SetTeleportData({ MatchId = result.MatchId, Team = result.Team })
		TeleportService:TeleportAsync(game.PlaceId, players, options)
	end)
	if not ok then
		warn("[Matchmaker] teleport failed:", err)
	end
	return ok
end

-- From a match server back to quick play (a public server).
function Matchmaker.ToQuickPlay(player: Player): boolean
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		warn("[Matchmaker] back to quick play failed:", err)
	end
	return ok
end

---------------------------------------------------------------------------------------------------
-- Leader side (builds matches for everyone)

local function tryLead(): boolean
	local map = lock
	if not map then
		return false
	end
	local ok, holder = pcall(function()
		return map:UpdateAsync("leader", function(current: any)
			if current == nil or current == game.JobId then
				return game.JobId
			end
			return nil -- someone else holds the lease
		end, CFG.LeaderSeconds)
	end)
	return ok and holder == game.JobId
end

-- Pick tickets for one match from `queue` (oldest first). Returns { [ticketId] = team } or nil.
local function pick(queue: { Ticket }): { [string]: string }?
	if #queue == 0 then
		return nil
	end
	local room = { Blue = TEAM, Red = TEAM }
	local chosen: { [string]: string } = {}
	local sides = { Blue = 0, Red = 0 }
	for _, t in queue do
		-- the side with more room first; a squad never splits
		local first = if room.Blue >= room.Red then "Blue" else "Red"
		local second = if first == "Blue" then "Red" else "Blue"
		local side = if t.Size <= room[first] then first elseif t.Size <= room[second] then second else nil
		if side then
			chosen[t.Id] = side
			room[side] -= t.Size
			sides[side] += 1
			if room.Blue == 0 and room.Red == 0 then
				return chosen -- full 3v3
			end
		end
	end
	local waited = now() - queue[1].At
	if waited >= CFG.PartialAfterSeconds and sides.Blue > 0 and sides.Red > 0 then
		return chosen -- real players on both sides; bots fill the rest
	end
	return nil
end

-- Claim every chosen ticket; on any failure release the ones already claimed.
local function claim(chosen: { [string]: string }, matchId: string): boolean
	local map = tickets :: MemoryStoreSortedMap
	local got: { string } = {}
	for id in chosen do
		local ok, value = pcall(function()
			return map:UpdateAsync(id, function(old: any)
				if old == nil then
					return nil
				end
				if old.Claimed and now() - (old.ClaimedAt or 0) <= CLAIM_STALE then
					return nil -- another match is taking it
				end
				old.Claimed, old.ClaimedAt = matchId, now()
				return old
			end, CFG.TicketSeconds)
		end)
		if ok and type(value) == "table" and value.Claimed == matchId then
			table.insert(got, id)
		else
			for _, gid in got do
				pcall(function()
					map:UpdateAsync(gid, function(old: any)
						if old and old.Claimed == matchId then
							old.Claimed, old.ClaimedAt = nil, nil
							return old
						end
						return nil
					end, CFG.TicketSeconds)
				end)
			end
			return false
		end
	end
	return true
end

local function commit(chosen: { [string]: string }): boolean
	local matchId = HttpService:GenerateGUID(false)
	if not claim(chosen, matchId) then
		return false
	end
	local okReserve, code = pcall(function()
		return (TeleportService:ReserveServer(game.PlaceId))
	end)
	if not okReserve or type(code) ~= "string" then
		warn("[Matchmaker] ReserveServer failed:", code)
		return false -- claims go stale and the tickets re-queue (Refresh)
	end
	local res = results :: MemoryStoreSortedMap
	local map = tickets :: MemoryStoreSortedMap
	for id, team in chosen do
		pcall(function()
			res:SetAsync(id, { AccessCode = code, Team = team, MatchId = matchId }, CFG.ResultSeconds)
		end)
		pcall(function()
			map:RemoveAsync(id)
		end)
	end
	local count = 0
	for _ in chosen do
		count += 1
	end
	log(`match {matchId} built from {count} squad(s)`)
	return true
end

local function buildMatches()
	local map = tickets
	if not map then
		return
	end
	local ok, items = pcall(function()
		return map:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if not ok or type(items) ~= "table" then
		return
	end
	local queue: { Ticket } = {}
	for _, item in items do
		local t = item.value
		if
			type(t) == "table"
			and type(t.Size) == "number"
			and t.Size >= 1
			and t.Size <= TEAM
			and not (t.Claimed and now() - (t.ClaimedAt or 0) <= CLAIM_STALE)
		then
			table.insert(queue, t :: Ticket)
		end
	end
	while #queue > 0 do
		local chosen = pick(queue)
		if not chosen or not commit(chosen) then
			return
		end
		local rest: { Ticket } = {}
		for _, t in queue do
			if not chosen[t.Id] then
				table.insert(rest, t)
			end
		end
		queue = rest
	end
end

-- Runs forever on every server; only the lease holder builds matches.
function Matchmaker.Start()
	if not available then
		return
	end
	task.spawn(function()
		while true do
			if tryLead() then
				local ok, err = pcall(buildMatches)
				if not ok then
					warn("[Matchmaker] build failed:", err)
				end
			end
			task.wait(CFG.PollSeconds)
		end
	end)
end

return Matchmaker

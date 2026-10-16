--!strict
-- Client-side copy of the latest MatchState plus things the UI derives from the event stream:
--   * smooth match timer (TimeLeft counted down locally between 1-4 Hz updates)
--   * each team's Core home position (for the Facility Report map)
--   * live per-name stats (kills/deaths from KillFeed, captures from score changes credited to the
--     last carrier) for the Tab scoreboard. The authoritative totals arrive in FacilityReport.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

export type CoreInfo = {
	State: string, -- "Home" | "Carried" | "Dropped"
	CarrierName: string?,
	CarrierUserId: number?,
	Position: Vector3,
	ReturnIn: number?,
}

export type Stats = { Kills: number, Deaths: number, Captures: number, Team: string? }

local MatchStore = {}

MatchStore.Phase = "Warmup" :: string
MatchStore.TimeLeft = 0
MatchStore.ReceivedAt = os.clock()
MatchStore.Score = { Blue = 0, Red = 0 } :: { [string]: number }
MatchStore.CaptureLimit = Tuning.Match.CaptureLimit
MatchStore.Cores = {} :: { [string]: CoreInfo }
MatchStore.CoreReceivedAt = os.clock()
MatchStore.HomePositions = {} :: { [string]: Vector3 }
MatchStore.Stats = {} :: { [string]: Stats }
MatchStore.HasState = false

MatchStore.Changed = Signal.new() -- (MatchStore)
MatchStore.PhaseChanged = Signal.new() -- (newPhase, oldPhase)
MatchStore.Captured = Signal.new() -- (team, carrierName?)
MatchStore.KillFeed = Signal.new() -- (entry)
MatchStore.StatsChanged = Signal.new()

local lastCarrier: { [string]: string? } = {}

function MatchStore.timeLeft(): number
	return math.max(0, MatchStore.TimeLeft - (os.clock() - MatchStore.ReceivedAt))
end

-- Seconds until a dropped Core returns, counted down locally.
function MatchStore.returnIn(team: string): number?
	local core = MatchStore.Cores[team]
	if not core or core.State ~= "Dropped" or type(core.ReturnIn) ~= "number" then
		return nil
	end
	return math.max(0, core.ReturnIn - (os.clock() - MatchStore.CoreReceivedAt))
end

function MatchStore.localTeam(): string?
	local player = Players.LocalPlayer
	local character = player.Character
	local attr = character and character:GetAttribute("Team")
	if type(attr) == "string" then
		return attr
	end
	if player.Team then
		return player.Team.Name
	end
	return nil
end

-- True if `name` is the local player (KillFeed may use Name or DisplayName).
function MatchStore.isMe(name: string?): boolean
	local p = Players.LocalPlayer
	return name ~= nil and (name == p.Name or name == p.DisplayName)
end

-- KillFeed / report use DisplayName for players while CoreInfo.CarrierName is the model name
-- (Player.Name). Normalise everything to the display name so stats don't split.
function MatchStore.canonical(name: string): string
	local p = Players:FindFirstChild(name)
	if p and p:IsA("Player") then
		return p.DisplayName
	end
	return name
end

local function stat(name: string, team: string?): Stats
	local s = MatchStore.Stats[name]
	if not s then
		s = { Kills = 0, Deaths = 0, Captures = 0, Team = team }
		MatchStore.Stats[name] = s
	end
	if team then
		s.Team = team
	end
	return s
end

function MatchStore.resetStats()
	table.clear(MatchStore.Stats)
	MatchStore.StatsChanged:Fire()
end

local function onMatchState(data: any)
	if type(data) ~= "table" then
		return
	end
	local oldPhase = MatchStore.Phase
	local oldScore = table.clone(MatchStore.Score)
	local hadState = MatchStore.HasState

	if type(data.Phase) == "string" then
		MatchStore.Phase = data.Phase
	end
	if type(data.TimeLeft) == "number" then
		MatchStore.TimeLeft = data.TimeLeft
		MatchStore.ReceivedAt = os.clock()
	end
	if type(data.Score) == "table" then
		MatchStore.Score = {
			Blue = tonumber(data.Score.Blue) or 0,
			Red = tonumber(data.Score.Red) or 0,
		}
	end
	if type(data.CaptureLimit) == "number" then
		MatchStore.CaptureLimit = data.CaptureLimit
	end
	if type(data.Cores) == "table" then
		for _, team in { "Blue", "Red" } do
			local c = data.Cores[team]
			if type(c) == "table" and typeof(c.Position) == "Vector3" then
				MatchStore.Cores[team] = c :: any
				if c.State == "Home" then
					MatchStore.HomePositions[team] = c.Position
				elseif c.State == "Carried" and type(c.CarrierName) == "string" then
					lastCarrier[team] = c.CarrierName
				end
			end
		end
		MatchStore.CoreReceivedAt = os.clock()
	end
	MatchStore.HasState = true

	if oldPhase ~= MatchStore.Phase then
		if MatchStore.Phase == "Live" or MatchStore.Phase == "Warmup" then
			MatchStore.resetStats()
		end
		MatchStore.PhaseChanged:Fire(MatchStore.Phase, oldPhase)
	end

	-- Credit captures to whoever last carried the enemy Core.
	if hadState and MatchStore.Phase ~= "Warmup" then
		for _, team in { "Blue", "Red" } do
			if (MatchStore.Score[team] or 0) > (oldScore[team] or 0) then
				local enemy = if team == "Blue" then "Red" else "Blue"
				local name = lastCarrier[enemy]
				if name then
					stat(MatchStore.canonical(name), team).Captures += 1
					MatchStore.StatsChanged:Fire()
				end
				lastCarrier[enemy] = nil
				MatchStore.Captured:Fire(team, name)
			end
		end
	end

	MatchStore.Changed:Fire(MatchStore)
end

local function onKillFeed(entry: any)
	if type(entry) ~= "table" then
		return
	end
	if type(entry.Killer) == "string" and entry.Killer ~= "" and entry.Killer ~= entry.Victim then
		stat(entry.Killer, entry.KillerTeam).Kills += 1
	end
	if type(entry.Victim) == "string" then
		stat(entry.Victim, entry.VictimTeam).Deaths += 1
	end
	MatchStore.StatsChanged:Fire()
	MatchStore.KillFeed:Fire(entry)
end

Remotes.Get("MatchState").OnClientEvent:Connect(onMatchState)
Remotes.Get("KillFeed").OnClientEvent:Connect(onKillFeed)

return MatchStore

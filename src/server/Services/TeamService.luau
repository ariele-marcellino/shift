--!strict
-- Teams (Blue/Red), the combatant roster (players + bots) and balancing.
-- Every team always has Tuning.Match.TeamSize slots; real players take slots and bots fill the rest.
-- Players join a team when they DEPLOY from the menu (LobbyService), not when they connect: until
-- then a bot keeps their slot. A deploying player goes to the team they picked (or were matched
-- into), else to a team with a friend / the person they followed when that team has room, else to
-- the team with fewer real players; one bot on that team is removed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeamsService = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Types = require(script.Parent.Parent.Systems.Mode.Types)
local TeamCollision =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("TeamCollision"))
type Combatant = Types.Combatant

local TeamService = {}

TeamService.TEAMS = { "Blue", "Red" }
TeamService.MemberAdded = Signal.new() -- (c: Combatant)
TeamService.MemberRemoved = Signal.new() -- (c: Combatant)
TeamService.RosterChanged = Signal.new() -- ()

local members: { [string]: Combatant } = {}
local byPlayer: { [Player]: Combatant } = {}
local byModel: { [Model]: Combatant } = {}
local teamObjects: { [string]: Team } = {}
local pendingPlayers: { [Player]: boolean } = {}
local botCounter = 0
local rng = Random.new()

function TeamService:Init()
	for _, name in TeamService.TEAMS do
		local team = TeamsService:FindFirstChild(name)
		if not team or not team:IsA("Team") then
			local newTeam = Instance.new("Team")
			newTeam.Name = name
			newTeam.TeamColor = BrickColor.new((Tuning.Teams :: any)[name].Color)
			newTeam.AutoAssignable = false
			newTeam.Parent = TeamsService
			team = newTeam
		end
		teamObjects[name] = team :: Team
	end
end

function TeamService:Enemy(team: string): string
	return if team == "Blue" then "Red" else "Blue"
end

-- Roster sorted by Id, cached until a member joins or leaves (called many times a second).
local sortedAll: { Combatant }? = nil

local function sortedMembers(): { Combatant }
	if not sortedAll then
		local list = {}
		for _, c in members do
			table.insert(list, c)
		end
		table.sort(list, function(a, b)
			return a.Id < b.Id
		end)
		sortedAll = list
	end
	return sortedAll :: { Combatant }
end

function TeamService:GetAll(): { Combatant }
	return table.clone(sortedMembers()) -- callers get their own list
end

function TeamService:GetTeam(team: string): { Combatant }
	local list = {}
	for _, c in sortedMembers() do
		if c.Team == team then
			table.insert(list, c)
		end
	end
	return list
end

function TeamService:GetByPlayer(player: Player): Combatant?
	return byPlayer[player]
end

function TeamService:GetByModel(model: Instance?): Combatant?
	if model == nil or not model:IsA("Model") then
		return nil
	end
	return byModel[model :: Model]
end

function TeamService:BindModel(c: Combatant, model: Model)
	if c.Model and byModel[c.Model] == c then
		byModel[c.Model] = nil
	end
	c.Model = model
	byModel[model] = c
	TeamCollision.ApplyCharacter(model, c.Team) -- spawn barriers block only the other team
end

function TeamService:UnbindModel(model: Model)
	byModel[model] = nil
end

local function realCount(team: string): number
	local n = 0
	for _, c in members do
		if c.Team == team and not c.IsBot then
			n += 1
		end
	end
	return n
end

local function addMember(c: Combatant)
	members[c.Id] = c
	sortedAll = nil
	if c.Player then
		byPlayer[c.Player] = c
	end
	TeamService.MemberAdded:Fire(c)
end

local function removeMember(c: Combatant)
	if members[c.Id] ~= c then
		return
	end
	members[c.Id] = nil
	sortedAll = nil
	c.Removed = true
	if c.Player then
		byPlayer[c.Player] = nil
	end
	if c.Model and byModel[c.Model] == c then
		byModel[c.Model] = nil
	end
	TeamService.MemberRemoved:Fire(c)
end

local function nextBotName(): string
	local used: { [string]: boolean } = {}
	for _, c in members do
		used[c.Name] = true
	end
	for _, name in Tuning.Bots.Names do
		if not used[name] then
			return name
		end
	end
	return `Unit-{60 + botCounter}`
end

local function addBot(team: string)
	botCounter += 1
	addMember({
		Id = string.format("B%03d", botCounter),
		Name = nextBotName(),
		Team = team,
		Player = nil,
		IsBot = true,
		Model = nil,
		Alive = false,
		Streak = 0,
		SpawnToken = 0,
		Removed = false,
		Role = nil,
	})
end

-- Pick the bot that hurts least to remove: not carrying a Core, preferably dead.
local function pickBotToRemove(bots: { Combatant }): Combatant
	local best = bots[1]
	local bestScore = -math.huge
	for _, bot in bots do
		local score = 0
		local model = bot.Model
		if model and model:GetAttribute("CarryingCore") ~= nil then
			score -= 100
		end
		if not bot.Alive then
			score += 10
		end
		if score > bestScore then
			best = bot
			bestScore = score
		end
	end
	return best
end

function TeamService:Rebalance()
	local size = Tuning.Match.TeamSize
	for _, team in TeamService.TEAMS do
		local bots = {}
		local real = 0
		for _, c in members do
			if c.Team == team then
				if c.IsBot then
					table.insert(bots, c)
				else
					real += 1
				end
			end
		end
		local want = math.max(0, size - real)
		if Tuning.Bots.TestNoTeammateBots and real > 0 and RunService:IsStudio() then
			want = 0 -- TEST: leave the player's team without bots (Tuning.Bots.TestNoTeammateBots)
		end
		while #bots > want do
			local victim = pickBotToRemove(bots)
			table.remove(bots, table.find(bots, victim) :: number)
			removeMember(victim)
		end
		for _ = #bots + 1, want do
			addBot(team)
		end
	end
	TeamService.RosterChanged:Fire()
end

-- Friend / follow based team preference. Yields (IsFriendsWith is a web call).
local function preferredTeam(player: Player): string?
	local votes: { [string]: number } = { Blue = 0, Red = 0 }
	local followed = player.FollowUserId
	for _, other in Players:GetPlayers() do
		local c = byPlayer[other]
		if other ~= player and c then
			if followed ~= 0 and other.UserId == followed then
				votes[c.Team] += 10
			else
				local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
				if ok and isFriend then
					votes[c.Team] += 1
				end
			end
		end
	end
	local size = Tuning.Match.TeamSize
	local best: string? = nil
	for _, team in TeamService.TEAMS do
		if votes[team] > 0 and realCount(team) < size then
			if best == nil or votes[team] > votes[best] then
				best = team
			end
		end
	end
	return best
end

local function smallerTeam(): string
	local blue, red = realCount("Blue"), realCount("Red")
	if blue ~= red then
		return if blue < red then "Blue" else "Red"
	end
	return if rng:NextNumber() < 0.5 then "Blue" else "Red"
end

function TeamService:RealCount(team: string): number
	return realCount(team)
end

-- Adds a deploying player to a team (yields briefly for the friends check). `wanted`: the team they
-- picked or were matched into; `fixed` = true (match servers) keeps it even if it's full.
function TeamService:AddPlayer(player: Player, wanted: string?, fixed: boolean?): Combatant?
	if byPlayer[player] or pendingPlayers[player] then
		return byPlayer[player]
	end
	pendingPlayers[player] = true
	local team = if wanted == "Blue" or wanted == "Red"
		then wanted
		else (preferredTeam(player) or smallerTeam())
	pendingPlayers[player] = nil
	if player.Parent ~= Players then
		return nil
	end
	-- Re-check after the yield: if the team filled up meanwhile, fall back to balance.
	if not fixed and realCount(team) >= Tuning.Match.TeamSize then
		team = smallerTeam()
	end

	player.Team = teamObjects[team]
	player.Neutral = false
	local c: Combatant = {
		Id = "P" .. tostring(player.UserId),
		Name = player.DisplayName,
		Team = team,
		Player = player,
		IsBot = false,
		Model = nil,
		Alive = false,
		Streak = 0,
		SpawnToken = 0,
		Removed = false,
		Role = nil,
	}
	addMember(c)
	TeamService:Rebalance()
	return c
end

-- Move a deployed player to the other team (drops a carried flag; respawns them there). False if
-- the other team has no free slot for a real player.
function TeamService:SwitchTeam(player: Player): boolean
	local c = byPlayer[player]
	if not c then
		return false
	end
	local target = TeamService:Enemy(c.Team)
	if realCount(target) >= Tuning.Match.TeamSize then
		return false
	end
	removeMember(c)
	local added = TeamService:AddPlayer(player, target, true)
	return added ~= nil
end

function TeamService:RemovePlayer(player: Player)
	pendingPlayers[player] = nil
	local c = byPlayer[player]
	if c then
		removeMember(c)
		TeamService:Rebalance()
	end
end

return TeamService

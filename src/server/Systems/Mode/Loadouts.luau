--!strict
-- v2 primary weapon choice (AK / Sniper). Players pick via SelectLoadout(primary) (validated
-- against Tuning.Primaries, rate-limited); bots pick randomly with Tuning.Bots.SniperChance.
-- A choice applies immediately when the player is alive, inside their own spawn room and within
-- APPLY_WINDOW seconds of spawning; otherwise on the next spawn. LoadoutState
-- { Primary, Options, AppliesNow } goes to the player on change, on ClientReady and on spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Types = require(script.Parent.Types)
local Deps = require(script.Parent.Deps)

type Combatant = Types.Combatant

local Loadouts = {}

local APPLY_WINDOW = 10
local MIN_INTERVAL = 0.4 -- seconds between accepted requests per player
local BURST_LIMIT = 8 -- requests per 10 s window

local choices: { [string]: string } = {} -- combatant Id (players: "P<userId>") -> primary
local lastRequest: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local windowStart: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local windowCount: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local rng = Random.new()

local function isValid(primary: any): boolean
	return type(primary) == "string" and table.find(Tuning.Primaries, primary) ~= nil
end

function Loadouts.Get(c: Combatant): string
	local choice = choices[c.Id]
	if choice then
		return choice
	end
	if c.IsBot then
		choice = if rng:NextNumber() < Tuning.Bots.SniperChance then "Sniper" else "AK"
	else
		choice = Tuning.Primaries[1]
	end
	assert(choice, "no primary")
	choices[c.Id] = choice
	return choice
end

function Loadouts.Forget(c: Combatant)
	if c.IsBot then
		choices[c.Id] = nil
	end
end

-- Would a change made right now apply immediately?
function Loadouts.CanApplyNow(c: Combatant): boolean
	local model = c.Model
	if not c.Alive or not model or c.SpawnedAt == nil then
		return false
	end
	if os.clock() - (c.SpawnedAt :: number) > APPLY_WINDOW then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	return Deps.IsInSpawnRoom(c.Team, root.Position)
end

function Loadouts.Send(c: Combatant, appliesNow: boolean?)
	local player = c.Player
	if not player then
		return
	end
	Remotes.Get("LoadoutState"):FireClient(player, {
		Primary = Loadouts.Get(c),
		Options = table.clone(Tuning.Primaries),
		AppliesNow = if appliesNow == nil then Loadouts.CanApplyNow(c) else appliesNow,
	})
end

-- Called by Spawner right after a (re)spawn: tell the player, and again when the window closes.
function Loadouts.OnSpawned(c: Combatant)
	if not c.Player then
		return
	end
	Loadouts.Send(c)
	local spawnedAt = c.SpawnedAt
	task.delay(APPLY_WINDOW + 0.1, function()
		if c.SpawnedAt == spawnedAt and not c.Removed then
			Loadouts.Send(c, false)
		end
	end)
end

local function allowRequest(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < MIN_INTERVAL then
		return false
	end
	if now - (windowStart[player] or -math.huge) > 10 then
		windowStart[player] = now
		windowCount[player] = 0
	end
	windowCount[player] = (windowCount[player] or 0) + 1
	if (windowCount[player] :: number) > BURST_LIMIT then
		return false
	end
	lastRequest[player] = now
	return true
end

-- getCombatant: resolves a Player to their roster entry (TeamService:GetByPlayer).
function Loadouts.Start(getCombatant: (Player) -> Combatant?)
	Remotes.Get("SelectLoadout").OnServerEvent:Connect(function(player: Player, primary: any)
		if not allowRequest(player) or not isValid(primary) then
			return
		end
		local c = getCombatant(player)
		if not c then
			return
		end
		local changed = choices[c.Id] ~= primary
		choices[c.Id] = primary
		local appliesNow = changed and Loadouts.CanApplyNow(c)
		if appliesNow and c.Model then
			Deps.GiveLoadout(c.Model, primary)
		end
		Loadouts.Send(c, if changed then appliesNow else nil)
	end)
end

return Loadouts

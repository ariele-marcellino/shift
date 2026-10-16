--!strict
-- Bot lifecycle and the shared think loop (10 Hz for all bots, perception staggered at 5 Hz).
-- TeamService decides how many bots exist; Spawner spawns them through the factory installed here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Systems = script.Parent.Parent.Systems
local Types = require(Systems.Mode.Types)
local Spawner = require(Systems.Mode.Spawner)
local Deps = require(Systems.Mode.Deps)
local Loadouts = require(Systems.Mode.Loadouts)
local BotBody = require(Systems.Bots.BotBody)
local BotBrain = require(Systems.Bots.BotBrain)
local Navigator = require(Systems.Bots.Navigator)
local Perception = require(Systems.Bots.Perception)
local WorldRay = require(Systems.Bots.WorldRay)
local TeamService = require(script.Parent.TeamService)

type Combatant = Types.Combatant

local BotService = {}

local TICK = 0.1
local ROLE_ORDER: { [number]: { string } } = {
	[1] = { "defender" },
	[2] = { "attacker", "defender" },
	[3] = { "attacker", "defender", "roamer" },
}

local brains: { [Combatant]: BotBrain.State } = {}
local lastErrorAt = 0

local function getMatch(): any
	return require(script.Parent.MatchService) :: any
end

local function assignRoles()
	for _, team in TeamService.TEAMS do
		local bots = {}
		for _, c in TeamService:GetTeam(team) do
			if c.IsBot then
				table.insert(bots, c)
			end
		end
		-- Riflemen take the attacker slot first; snipers prefer defender / roamer (hold angles).
		table.sort(bots, function(a, b)
			local sa, sb = Loadouts.Get(a) == "Sniper", Loadouts.Get(b) == "Sniper"
			if sa ~= sb then
				return sb
			end
			return a.Id < b.Id
		end)
		local order = ROLE_ORDER[math.min(#bots, 3)] or {}
		for i, bot in bots do
			bot.Role = order[i] or (if i % 2 == 0 then "roamer" else "attacker")
		end
	end
end

local function dropBrain(c: Combatant)
	local st = brains[c]
	if st then
		brains[c] = nil
		BotBrain.Destroy(st)
	end
end

local function onSpawned(c: Combatant, model: Model)
	if not c.IsBot then
		return
	end
	dropBrain(c)
	local st = BotBrain.new(c, model)
	if not st then
		warn(`[Bots] {c.Name}: body has no Humanoid/root; brain not started`)
		return
	end
	brains[c] = st
	local humanoid = st.Humanoid
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth and brains[c] == st then
			BotBrain.OnDamaged(st)
		end
		lastHealth = health
	end)
end

local function onDied(c: Combatant, model: Model)
	if not c.IsBot then
		return
	end
	dropBrain(c)
	-- Clear the corpse if it was already replaced; otherwise the respawn (Spawner) replaces it.
	task.delay(4, function()
		if model.Parent and (c.Model ~= model or c.Removed) then
			model:Destroy()
		end
	end)
end

function BotService:InvalidateNav()
	Navigator.Invalidate()
end

function BotService:GetRole(c: Combatant): string?
	return c.Role
end

function BotService:Init()
	Spawner.BotsFolder()
	Spawner.BotFactory = function(c: Combatant): Model?
		return BotBody.Create(c.Name)
	end
end

local function tick(now: number, refreshFilter: boolean)
	if refreshFilter then
		WorldRay.Refresh()
	end
	local match = getMatch()
	local phase = if match and match.GetPhase then match:GetPhase() else "Warmup"
	for c, st in brains do
		if c.Removed or not c.Alive or st.Model.Parent == nil or st.Humanoid.Health <= 0 then
			dropBrain(c)
		else
			local ok, err = pcall(BotBrain.Step, st, now, phase)
			if not ok and now - lastErrorAt > 5 then
				lastErrorAt = now
				warn(`[Bots] {c.Name} step failed: {err}`)
			end
		end
	end
end

function BotService:Start()
	Spawner.Spawned:Connect(onSpawned)
	Spawner.Died:Connect(onDied)
	TeamService.RosterChanged:Connect(assignRoles)
	TeamService.MemberRemoved:Connect(function(c: Combatant)
		dropBrain(c)
	end)
	assignRoles()

	-- v2 dynamic lights / shifts: re-read the nav graph (Dark flags, links) when World says so.
	for _, signalName in { "LightChanged", "ShiftApplied", "LampBroken", "NavChanged" } do
		Deps.ConnectWorldSignal(signalName, function()
			Navigator.Invalidate()
		end)
	end

	-- Muzzle flashes from players reveal them to bots in the dark.
	Remotes.Get("Fire").OnServerEvent:Connect(function(player)
		Perception.NoteShot(player.Character)
	end)

	task.spawn(function()
		local lastFilter = 0
		while true do
			task.wait(TICK)
			local now = os.clock()
			local refresh = now - lastFilter >= 0.5
			if refresh then
				lastFilter = now
			end
			tick(now, refresh)
		end
	end)
end

return BotService

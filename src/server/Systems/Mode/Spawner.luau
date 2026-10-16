--!strict
-- Spawning for players and bots: spawn choice (away from enemies, not stacked), character setup
-- (attributes, Combatant tag, uniform, loadout, movement), spawn protection, death hook and
-- respawn timers. Players use LoadCharacter (CharacterAutoLoads is off); bot bodies come from
-- Spawner.BotFactory, which BotService installs.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Types = require(script.Parent.Types)
local Deps = require(script.Parent.Deps)
local Avatar = require(script.Parent.Avatar)
local Uniform = require(script.Parent.Uniform)
local Movement = require(script.Parent.Movement)
local Loadouts = require(script.Parent.Loadouts)
local TeamService = require(script.Parent.Parent.Parent.Services.TeamService)

type Combatant = Types.Combatant

local Spawner = {}

Spawner.Spawned = Signal.new() -- (c: Combatant, model: Model)
Spawner.Died = Signal.new() -- (c: Combatant, model: Model, position: Vector3)
Spawner.BotFactory = nil :: ((c: Combatant) -> Model?)?

local PROTECTION_NAME = "SpawnProtection"
local rng = Random.new()

local function botsFolder(): Folder
	local folder = workspace:FindFirstChild("Bots")
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Bots"
		newFolder.Parent = workspace
		folder = newFolder
	end
	return folder :: Folder
end
Spawner.BotsFolder = botsFolder

local function rootOf(model: Model?): BasePart?
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
Spawner.RootOf = rootOf

-- Spawn farthest from the nearest living enemy, avoiding teammates standing on the same spot.
local function chooseSpawn(c: Combatant): CFrame
	local spawns = Deps.GetSpawns(c.Team)
	local enemies, mates = {}, {}
	for _, other in TeamService:GetAll() do
		local root = if other.Alive then rootOf(other.Model) else nil
		if root and other ~= c then
			table.insert(if other.Team == c.Team then mates else enemies, root.Position)
		end
	end
	local best = spawns[1]
	local bestScore = -math.huge
	for _, cf in spawns do
		local nearestEnemy = 300
		for _, pos in enemies do
			nearestEnemy = math.min(nearestEnemy, (pos - cf.Position).Magnitude)
		end
		local crowd = 0
		for _, pos in mates do
			if (pos - cf.Position).Magnitude < 4 then
				crowd += 1
			end
		end
		local score = nearestEnemy - crowd * 60 + rng:NextNumber() * 15
		if score > bestScore then
			best = cf
			bestScore = score
		end
	end
	-- Spawn CFrames are assumed to be at floor level; lift the root above the floor.
	return best + Vector3.new(0, 3, 0)
end

function Spawner.Protect(model: Model)
	Spawner.CancelProtection(model)
	local field = Instance.new("ForceField")
	field.Name = PROTECTION_NAME
	field.Visible = false
	field.Parent = model
	model:SetAttribute("SpawnProtected", true)
	task.delay(Tuning.Match.SpawnProtection, function()
		if field.Parent == model then
			Spawner.CancelProtection(model)
		end
	end)
end

function Spawner.CancelProtection(model: Model?)
	if not model then
		return
	end
	local field = model:FindFirstChild(PROTECTION_NAME)
	if field then
		field:Destroy()
	end
	if model:GetAttribute("SpawnProtected") ~= nil then
		model:SetAttribute("SpawnProtected", nil)
	end
end

local function onDied(c: Combatant, model: Model)
	if c.Model ~= model or not c.Alive then
		return
	end
	c.Alive = false
	Spawner.CancelProtection(model)
	local root = rootOf(model)
	local position = if root then root.Position else model:GetPivot().Position
	Spawner.Died:Fire(c, model, position)
end

-- Shared setup for a fresh character / bot body. Yields briefly for players.
function Spawner.SetupCharacter(c: Combatant, model: Model)
	if c.Removed then
		return
	end
	local old = c.Model
	if old and old ~= model and c.IsBot then
		TeamService:UnbindModel(old)
		old:Destroy()
	end
	TeamService:BindModel(c, model)
	c.Alive = true
	c.SpawnedAt = os.clock()

	model:SetAttribute("Team", c.Team)
	model:SetAttribute("Bot", c.IsBot)
	model:SetAttribute("CarryingCore", nil)
	if c.IsBot then
		model:SetAttribute("Aiming", false)
		model:SetAttribute("Flashlight", false)
	end
	CollectionService:AddTag(model, "Combatant")

	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn(`[Mode] {c.Name} has no Humanoid`)
		return
	end
	-- Floating name tags would show enemies through walls and in the dark.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = Tuning.Health.Max
	humanoid.Health = Tuning.Health.Max

	Uniform.Apply(model, c.Team)

	local spawnCFrame = chooseSpawn(c)
	if c.IsBot then
		model:PivotTo(spawnCFrame)
		model.Parent = botsFolder()
		local root = rootOf(model)
		if root then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
	else
		local root = model:WaitForChild("HumanoidRootPart", 5)
		if not root or c.Model ~= model then
			return
		end
		task.wait() -- let the engine's default placement finish before moving
		if model.Parent then
			model:PivotTo(spawnCFrame)
		end
	end

	humanoid.Died:Once(function()
		onDied(c, model)
	end)
	Spawner.Protect(model)
	Deps.GiveLoadout(model, Loadouts.Get(c))
	Movement.Track(model)
	Loadouts.OnSpawned(c)
	Spawner.Spawned:Fire(c, model)
end

function Spawner.Spawn(c: Combatant)
	if c.Removed then
		return
	end
	c.SpawnToken += 1
	local player = c.Player
	if player then
		task.spawn(function()
			-- Same body for everyone (fair hitboxes); face / hair / hats stay personal.
			local desc = Avatar.DescriptionFor(player)
			local ok, err
			if desc then
				ok, err = pcall(player.LoadCharacterWithHumanoidDescription, player, desc)
			else
				ok, err = pcall(player.LoadCharacter, player)
			end
			if not ok and desc then
				warn(`[Mode] avatar load failed for {player.Name}, using default: {err}`)
				ok, err = pcall(player.LoadCharacter, player)
			end
			if not ok then
				warn(`[Mode] LoadCharacter failed for {player.Name}: {err}`)
			end
		end)
	else
		local factory = Spawner.BotFactory
		if not factory then
			warn("[Mode] No bot factory installed")
			return
		end
		local model = factory(c)
		if model then
			task.spawn(Spawner.SetupCharacter, c, model)
		end
	end
end

function Spawner.ScheduleRespawn(c: Combatant, seconds: number)
	local token = c.SpawnToken
	task.delay(seconds, function()
		if c.SpawnToken == token and not c.Removed and not c.Alive then
			Spawner.Spawn(c)
		end
	end)
end

function Spawner.RespawnTime(c: Combatant): number
	local m = Tuning.Match
	return math.min(m.RespawnMax, m.RespawnBase + math.max(0, c.Streak - 1) * m.RespawnPerStreak)
end

-- Fresh start for everyone (phase changes). Cancels pending respawn timers via SpawnToken.
function Spawner.RespawnAll()
	for _, c in TeamService:GetAll() do
		Spawner.Spawn(c)
	end
end

-- Hook a player's CharacterAdded so every LoadCharacter goes through SetupCharacter.
function Spawner.BindPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		local c = TeamService:GetByPlayer(player)
		if c then
			Spawner.SetupCharacter(c, character)
		end
	end)
	player.CharacterAppearanceLoaded:Connect(function(character)
		local c = TeamService:GetByPlayer(player)
		if c and c.Model == character then
			Uniform.Apply(character, c.Team)
		end
	end)
end

return Spawner

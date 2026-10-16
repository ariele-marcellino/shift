--!strict
-- Creepy moments (Tuning.Horror). The server only decides WHEN: a player who has stood in a dark or
-- dimmed area for a couple of seconds, isn't carrying a flag and hasn't fought recently gets a chance
-- every few seconds, with a per-player cooldown. Also: when the lights of the zone you're standing in
-- go off, there's a chance of a "Blackout" scare (a figure caught in the last flicker). Those
-- per-player scares are staged by the client (HorrorController): only that player sees them.
--
-- Shared apparitions: every Tuning.Horror.SharedMin..SharedMax seconds the server itself puts the
-- backrooms figure in a corner in view of one eligible player, in workspace.SharedHorror, so EVERY
-- player who looks that way sees the same figure. The first player to look straight at it (client
-- ScareSeen) makes it vanish with a sting everyone nearby hears. The Blackout figure is shared too.
-- Nothing collides or takes bullets.
--
-- Studio: J on the client (HorrorTest) runs the next scare kind in turn; Output logs every scare.
-- Or from the command bar (Server context while playing):
--   workspace:SetAttribute("HorrorTest", "Corner")   -- a kind from TEST_ORDER, or "next"
-- (runs for the first player in the game; the attribute is cleared after each run)
--
-- Props are the owner's Creator Store models, loaded once, cleaned (StoreAssets) and put in
-- ReplicatedStorage.HorrorProps for clients to clone. A kind whose model can't load is skipped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local StoreAssets = require(script.Parent.Parent:WaitForChild("Systems"):WaitForChild("StoreAssets"))
local WorldService = require(script.Parent.WorldService)
local CombatService = require(script.Parent.CombatService)
local Lamps = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("Lamps"))
local HorrorSpots = require(Shared:WaitForChild("HorrorSpots"))
local CollectionService = game:GetService("CollectionService")

local STUDIO = RunService:IsStudio()
local STING = 4737106301 -- "creepy sound for horror games" (owner's inventory)

local HorrorService = {}

type Prop = { AssetId: number, Size: number, Flat: boolean? }
-- Prop = model it needs (nil = sound only), Weight = pick weight, Cooldown = x the normal cooldown.
type Kind = { Prop: string?, Weight: number, Cooldown: number? }

-- Models (owner's Creator Store inventory). Size = height in studs (or floor span when Flat).
HorrorService.Props = {
	Watcher = { AssetId = 132200735579302, Size = 7.2 }, -- "Backrooms Monster"
	Wheelchair = { AssetId = 14739438162, Size = 3.4 }, -- "Horror Wheelchair" (credit: RushyenGaming)
	Teeth = { AssetId = 12614706168, Size = 1.1 }, -- "Horror Teeth"
	WallSkeleton = { AssetId = 7727704580, Size = 5.5 }, -- "Halloween Horror Skeleton"
	Blood = { AssetId = 1036525642, Size = 3.5, Flat = true }, -- "Blood"
} :: { [string]: Prop }

-- Scares the client knows how to stage (see HorrorController for what each one does).
-- "Blackout" is not in this pool: it only fires when your zone's lights go off.
HorrorService.Kinds = {
	Corner = { Prop = "Watcher", Weight = 4 }, -- figure in a corner, gone the moment you look
	Glimpse = { Prop = "Watcher", Weight = 3 }, -- figure flashes in a far corner ahead + sting
	Watcher = { Prop = "Watcher", Weight = 2 },
	Wheelchair = { Prop = "Wheelchair", Weight = 1.5 },
	Teeth = { Prop = "Teeth", Weight = 1.5 },
	WallSkeleton = { Prop = "WallSkeleton", Weight = 1 },
	Blood = { Prop = "Blood", Weight = 1 },
	Voice = { Weight = 2, Cooldown = 0.5 }, -- "help me" from behind a wall
	Laugh = { Weight = 1.5, Cooldown = 0.5 }, -- a distant laugh somewhere in the dark
} :: { [string]: Kind }

type PlayerState = { Dark: number, NextAt: number, LastRoll: number, CalmUntil: number }

local states: { [Player]: PlayerState } = {}
local loadedProps: { [string]: boolean } = {}
local rng = Random.new()

local function loadProps()
	local folder = Instance.new("Folder")
	folder.Name = "HorrorProps"
	for kind, prop in HorrorService.Props do
		local template = StoreAssets.Load(prop.AssetId)
		if template then
			local model = (template :: Model):Clone()
			StoreAssets.ScaleTo(model, prop.Size, prop.Flat)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CastShadow = true
				end
			end
			model.Name = kind
			model:SetAttribute("Flat", prop.Flat == true)
			model.Parent = folder
			loadedProps[kind] = true
		end
	end
	folder.Parent = ReplicatedStorage
	local names = {}
	for kind in loadedProps do
		table.insert(names, kind)
	end
	print(`[Horror] props ready: {#names} ({table.concat(names, ", ")})`)
end

local function usable(kind: Kind): boolean
	return kind.Prop == nil or loadedProps[kind.Prop] == true
end

local function pickKind(): string?
	local total = 0
	for _, kind in HorrorService.Kinds do
		if usable(kind) then
			total += kind.Weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, total)
	local last: string? = nil
	for name, kind in HorrorService.Kinds do
		if usable(kind) then
			last = name
			roll -= kind.Weight
			if roll <= 0 then
				return name
			end
		end
	end
	return last
end

local function cooldown(kindName: string): number
	local cfg = Tuning.Horror
	local kind = HorrorService.Kinds[kindName]
	return rng:NextNumber(cfg.CooldownMin, cfg.CooldownMax) * ((kind and kind.Cooldown) or 1)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and hum and hum.Health > 0 then
		return root
	end
	return nil
end

local function stateOf(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = { Dark = 0, NextAt = os.clock() + Tuning.Horror.FirstDelay, LastRoll = 0, CalmUntil = 0 }
		states[player] = s
	end
	return s
end

local function calm(model: Model?)
	local player = model and Players:GetPlayerFromCharacter(model)
	if player then
		stateOf(player).CalmUntil = os.clock() + Tuning.Horror.CalmSeconds
	end
end

-- Shared apparitions ----------------------------------------------------------------------------

type Figure = { Model: Model, Expires: number, Center: Vector3 }
local sharedFolder: Folder? = nil
local figures: { [number]: Figure } = {}
local nextFigureId = 0
local nextShared = 0

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for _, c in CollectionService:GetTagged("Combatant") do
		table.insert(exclude, c)
	end
	for _, name in { "Bots", "Cores", "CombatSmoke", "CombatGrenades", "SharedHorror", "ClientHorror" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	return params
end

-- Head-height view of a player (first person: the character faces where the camera looks).
local function eyeOf(player: Player): CFrame?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local head = (root.Parent :: Instance):FindFirstChild("Head")
	local pos = if head and head:IsA("BasePart")
		then head.Position
		else root.Position + Vector3.new(0, 1.5, 0)
	return CFrame.lookAt(pos, pos + HorrorSpots.FlatLook(root.CFrame))
end

local function playSting(at: Vector3, volume: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.Position = at
	holder.Parent = sharedFolder
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(STING)
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 70
	sound.Parent = holder
	sound:Play()
	task.delay(8, function()
		holder:Destroy()
	end)
end

local function vanish(id: number, sting: boolean)
	local f = figures[id]
	if not f then
		return
	end
	figures[id] = nil
	if sting then
		playSting(f.Center, 0.6)
		-- A split second so the sting lands while it's still there.
		task.delay(0.12, function()
			f.Model:Destroy()
		end)
	else
		f.Model:Destroy()
	end
end

-- Put the figure in view of `player` (a corner if possible). Returns true if placed.
local function spawnFigure(
	player: Player,
	minAng: number,
	maxAng: number,
	minD: number,
	maxD: number,
	life: number
): boolean
	local props = ReplicatedStorage:FindFirstChild("HorrorProps")
	local template = props and props:FindFirstChild("Watcher")
	local eye = eyeOf(player)
	if not template or not template:IsA("Model") or not eye or not sharedFolder then
		return false
	end
	local floor = HorrorSpots.FindSpot(eye, rayParams(), rng, minAng, maxAng, minD, maxD)
	if not floor then
		return false
	end
	local model = (template :: Model):Clone()
	HorrorSpots.StandOn(model, floor, eye.Position, rng)
	local lo, hi = HorrorSpots.VisibleBounds(model)
	local glowAt = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if glowAt then
		-- Faint cold glow so it reads in the dark for the moment it's there.
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 165, 190)
		light.Brightness = 0.35
		light.Range = 9
		light.Parent = glowAt
	end
	nextFigureId += 1
	local id = nextFigureId
	model:SetAttribute("ScareId", id)
	model.Parent = sharedFolder
	figures[id] = { Model = model, Expires = os.clock() + life, Center = (lo + hi) / 2 }
	return true
end

local function stepFigures(now: number)
	for id, f in figures do
		if now >= f.Expires or f.Model.Parent == nil then
			vanish(id, false)
		else
			-- Walking right up to it also makes it go.
			for _, p in Players:GetPlayers() do
				local root = rootOf(p)
				if root and (root.Position - f.Center).Magnitude < 8 then
					vanish(id, true)
					break
				end
			end
		end
	end
end

local function eligible(player: Player, now: number): boolean
	local s = stateOf(player)
	local character = player.Character
	return rootOf(player) ~= nil
		and character ~= nil
		and now >= s.CalmUntil
		and character:GetAttribute("CarryingCore") == nil
end

local function trySharedApparition(now: number)
	local cfg = Tuning.Horror
	if now < nextShared or next(figures) ~= nil or not loadedProps.Watcher then
		return
	end
	local candidates = {}
	for _, player in Players:GetPlayers() do
		if eligible(player, now) and stateOf(player).Dark >= cfg.DarkSeconds then
			table.insert(candidates, player)
		end
	end
	if #candidates == 0 then
		return
	end
	local player = candidates[rng:NextInteger(1, #candidates)]
	if spawnFigure(player, 15, 45, 14, 45, cfg.SharedLife) then
		nextShared = now + rng:NextNumber(cfg.SharedMin, cfg.SharedMax)
		local s = stateOf(player)
		s.NextAt = math.max(s.NextAt, now + 15) -- don't stack a personal scare on top
		if STUDIO then
			print(`[Horror] shared apparition near {player.Name}`)
		end
	else
		nextShared = now + 5 -- no corner in view: try again shortly
	end
end

local function step(dt: number)
	local cfg = Tuning.Horror
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local s = stateOf(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then
			s.Dark = 0
			continue
		end
		local ok, dark = pcall(function()
			return WorldService:IsGloomy(root.Position, cfg.GloomLevel)
		end)
		s.Dark = if ok and dark then s.Dark + dt else 0
		if
			s.Dark >= cfg.DarkSeconds
			and now >= s.NextAt
			and now >= s.CalmUntil
			and now - s.LastRoll >= cfg.CheckSeconds
			and character:GetAttribute("CarryingCore") == nil
		then
			s.LastRoll = now
			if rng:NextNumber() < cfg.Chance then
				local kind = pickKind()
				if kind then
					s.NextAt = now + cooldown(kind)
					Remotes.Get("Scare"):FireClient(player, kind)
					if STUDIO then
						print(`[Horror] {player.Name}: {kind}`)
					end
				end
			end
		end
	end
	stepFigures(now)
	trySharedApparition(now)
end

-- The lights of `zone` just went off: players standing under them may catch a figure in the last
-- flicker.
local function onLightChanged(zone: string, state: string)
	local cfg = Tuning.Horror
	if state ~= "Off" or not loadedProps.Watcher then
		return
	end
	local positions = {}
	for _, lamp in Lamps.All() do
		if lamp.Zone == zone then
			table.insert(positions, lamp.Part.Position)
		end
	end
	local now = os.clock()
	local r2 = cfg.BlackoutRadius * cfg.BlackoutRadius
	local near = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and eligible(player, now) then
			for _, pos in positions do
				local dx, dz = pos.X - root.Position.X, pos.Z - root.Position.Z
				if dx * dx + dz * dz <= r2 then
					table.insert(near, player)
					break
				end
			end
		end
	end
	if #near == 0 or rng:NextNumber() >= cfg.BlackoutChance then
		return
	end
	-- One figure for everyone in the area, placed in view of one of them.
	local target = near[rng:NextInteger(1, #near)]
	if not spawnFigure(target, 0, 25, 12, 35, 0.9) then
		return
	end
	for _, player in near do
		local s = stateOf(player)
		s.NextAt = math.max(s.NextAt, now + cooldown("Blackout") * 0.5)
		Remotes.Get("Scare"):FireClient(player, "Blackout")
	end
	if STUDIO then
		print(`[Horror] blackout figure in {zone} ({#near} player(s) nearby)`)
	end
end

-- Studio test: J runs the next kind for that player, ignoring every condition.
local TEST_ORDER = {
	"Shared",
	"Blackout",
	"Corner",
	"Glimpse",
	"Watcher",
	"Wheelchair",
	"Teeth",
	"WallSkeleton",
	"Blood",
	"Voice",
	"Laugh",
}
local testIndex: { [Player]: number } = {}

local function runTest(player: Player, wanted: string?)
	local i = (testIndex[player] or 0) % #TEST_ORDER + 1
	if wanted then
		i = table.find(TEST_ORDER, wanted) or i
	end
	testIndex[player] = i
	local kind = TEST_ORDER[i]
	local note = ""
	if kind == "Shared" or kind == "Blackout" then
		local placed = spawnFigure(player, 10, 35, 10, 45, if kind == "Shared" then 12 else 0.9)
		note = if placed then "figure placed" else "no corner/wall in view here, try facing a room"
		if kind == "Blackout" then
			Remotes.Get("Scare"):FireClient(player, "Blackout", true)
		end
	else
		Remotes.Get("Scare"):FireClient(player, kind, true)
	end
	local props = {}
	for name in loadedProps do
		table.insert(props, name)
	end
	print(
		`[Horror] TEST {i}/{#TEST_ORDER} {kind} for {player.Name} {note} (props loaded: {table.concat(
			props,
			", "
		)})`
	)
end

function HorrorService:Init() end

function HorrorService:Start()
	if not Tuning.Horror.Enabled then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SharedHorror"
	folder.Parent = workspace
	sharedFolder = folder
	nextShared = os.clock() + Tuning.Horror.FirstDelay + rng:NextNumber(0, 20)
	task.spawn(loadProps)
	WorldService.LightChanged:Connect(onLightChanged)
	Remotes.Get("ScareSeen").OnServerEvent:Connect(function(_player, id)
		if type(id) == "number" then
			vanish(id, true)
		end
	end)
	if STUDIO then
		Remotes.Get("HorrorTest").OnServerEvent:Connect(function(player)
			runTest(player)
		end)
		workspace:GetAttributeChangedSignal("HorrorTest"):Connect(function()
			local value = workspace:GetAttribute("HorrorTest")
			local player = Players:GetPlayers()[1]
			if value == nil or not player then
				return
			end
			workspace:SetAttribute("HorrorTest", nil)
			if type(value) == "string" and value ~= "next" and not table.find(TEST_ORDER, value) then
				warn(`[Horror] unknown test kind "{value}"; use one of: {table.concat(TEST_ORDER, ", ")}`)
				return
			end
			runTest(player, if type(value) == "string" and value ~= "next" then value else nil)
		end)
	end
	-- Fighting keeps things calm: no scare right after shooting or being hurt.
	CombatService.Fired:Connect(function(model: Model)
		calm(model)
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			local hum = character:WaitForChild("Humanoid", 10)
			if hum and hum:IsA("Humanoid") then
				local last = hum.Health
				hum.HealthChanged:Connect(function(health)
					if health < last then
						calm(character)
					end
					last = health
				end)
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		testIndex[player] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.5 then
			step(acc)
			acc = 0
		end
	end)
end

return HorrorService

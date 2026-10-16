--!strict
-- Server-authoritative combat (v2): weapon slots, AK / BOLT-7 sniper, knife, frag + smoke grenades,
-- wallbangs, damage (head/body/limb + falloff), kills, regen, ammo, reloads, flashlights, lamps and
-- every combat feedback remote. Clients only send intents; everything is validated here.
--
-- Public API (Mode / Bots):
--   CombatService.OnDeath: Signal(victimModel, killerModel?, headshot, info)
--       info = { Weapon: string?, Wallbang: boolean, KillerName: string?, KillerTeam: string?,
--                KillerPlayer: Player? }  (killer data captured at damage time; frag kills still
--                credit a thrower who has since died / respawned)
--   CombatService.Fired: Signal(model)        -- shot / slash / throw (cancel spawn protection)
--   :GiveLoadout(model, primaryId?)           full ammo + grenades, primary in hand, light off
--   :GetPrimary(model) -> "AK" | "Sniper"
--   :EquipSlot(model, slot) -> boolean        "Primary" | "Knife" | "Frag" | "Smoke" (carrier rules)
--   :Resupply(model, kind) -> boolean         spawn magazine bag ("AK" | "Sniper"): refill reserves
--   :SetAiming(model, on)                     AK: Aiming; Sniper: Aiming + Scoped
--   :SetFlashlight(model, on)
--   :SetLookPitch(model, radians)
--   :BotFire(bot, targetPosition) -> boolean  AK or Sniper, rate/ammo/reload enforced
--   :ForceSlot(model, slot) -> boolean       ignores the carrier lock (Mode: "Knife" on pickup)
--   :BotMelee(bot, target: Model | Vector3) -> boolean  switches to knife if needed; true if hit
--   :BotThrowFrag(bot, position) -> boolean
--   :BotThrowSmoke(bot, position) -> boolean
--   :IsSmoked(a, b) -> boolean                a/b = Vector3, BasePart or Model
--   :SetEnabled(bool), :ResetMatch(), :GetAmmo(model)
--   :SetDrawn(model, drawn)                   v1 leftover, no-op (holster mechanic removed)
-- Attributes set: HeldWeapon, Scoped, Aiming, Flashlight, Crouching.
-- No damage outside MatchService phase "Live"; ForceField / SpawnProtected block damage.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local CombatFolder = (script.Parent :: Instance).Parent:WaitForChild("Systems"):WaitForChild("Combat")
local Combatants = require(CombatFolder:WaitForChild("Combatants"))
local Ballistics = require(CombatFolder:WaitForChild("Ballistics"))
local Smoke = require(CombatFolder:WaitForChild("Smoke"))
local Frag = require(CombatFolder:WaitForChild("Frag"))
local Lob = require(Shared:WaitForChild("Lob"))
local Gear = require(CombatFolder:WaitForChild("Gear"))
local Glass = require(CombatFolder:WaitForChild("Glass"))
local Hitboxes = require(CombatFolder:WaitForChild("Hitboxes"))
local SpawnBarriers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpawnBarriers"))

type State = Combatants.State
type Source = Combatants.Source
type Slot = Combatants.Slot

local HEAD_TOLERANCE = 6
local RELOAD_EARLY_GRACE = 0.2 -- client may finish its reload slightly before the server
local THROW_COOLDOWN = 1
local TOGGLE_COOLDOWN = 0.15
local KILL_CREDIT_SECONDS = 10
local REGEN_TICK = 0.25
local MELEE_LAG_SLACK = 1.5 -- extra studs for latency
local MELEE_CONE = math.rad(70)
local BACKSTAB_ANGLE = math.rad(110)
local SLOTS: { [string]: boolean } = { Primary = true, Knife = true, Frag = true, Smoke = true }
local AMMO_BAG_TAG = "AmmoBag" -- spawn magazine bags (Layout); attribute Weapon = "AK" | "Sniper"

local CombatService = {}
CombatService.OnDeath = Signal.new()
CombatService.Fired = Signal.new()

local enabled = true
local rng = Random.new()
local worldService: any = nil
local worldServiceTried = false
local matchService: any = nil
local matchServiceTried = false

local R = {
	ShotFx = Remotes.Get("ShotFx"),
	HitConfirm = Remotes.Get("HitConfirm"),
	Damaged = Remotes.Get("Damaged"),
	KillFeed = Remotes.Get("KillFeed"),
	AmmoSync = Remotes.Get("AmmoSync"),
}

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function finiteNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function finiteVector(v: any): boolean
	return typeof(v) == "Vector3" and finiteNumber(v.X) and finiteNumber(v.Y) and finiteNumber(v.Z)
end

local function lazyService(name: string): any
	local services = script.Parent
	local mod = services and services:FindFirstChild(name)
	if not mod then
		return nil, false
	end
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" then
		return result, true
	end
	warn(`[Combat] {name} unavailable:`, result)
	return nil, true
end

local function getWorldService(): any
	if not worldService and not worldServiceTried then
		worldService, worldServiceTried = lazyService("WorldService")
	end
	return worldService
end

-- Damage (and lamp breaking) only counts while the match is Live.
local function damageAllowed(): boolean
	if not enabled then
		return false
	end
	if not matchService and not matchServiceTried then
		matchService, matchServiceTried = lazyService("MatchService")
	end
	if matchService and type(matchService.GetPhase) == "function" then
		local ok, phase = pcall(matchService.GetPhase, matchService)
		if ok and (phase == "Warmup" or phase == "Ended") then
			return false
		end
	end
	return true
end

local function breakLamp(lampId: string)
	if not damageAllowed() then
		return
	end
	local ws = getWorldService()
	if ws and type(ws.BreakLamp) == "function" then
		task.spawn(function()
			local ok, err = pcall(ws.BreakLamp, ws, lampId)
			if not ok then
				warn("[Combat] BreakLamp failed:", err)
			end
		end)
	end
end

local function syncAmmo(state: State, force: boolean?)
	local player = state.Player
	if not player then
		return
	end
	local now = os.clock()
	if not force and now - state.LastSyncAt < 0.5 then
		return
	end
	state.LastSyncAt = now
	R.AmmoSync:FireClient(player, {
		Mag = state.Mag,
		Reserve = state.Reserve,
		Smokes = state.Smokes,
		Frags = state.Frags,
		Primary = state.Primary,
		Held = Combatants.WeaponFor(state),
	})
end

local function isCarrying(model: Model): boolean
	local c = model:GetAttribute("CarryingCore")
	return c ~= nil and c ~= false and c ~= ""
end

local function isProtected(model: Model): boolean
	return model:FindFirstChildOfClass("ForceField") ~= nil or model:GetAttribute("SpawnProtected") == true
end

local function positionOf(x: any): Vector3?
	if typeof(x) == "Vector3" then
		return x
	elseif typeof(x) == "Instance" then
		if x:IsA("BasePart") then
			return x.Position
		elseif x:IsA("Model") then
			local head = Combatants.Head(x)
			if head then
				return head.Position
			end
			return x:GetPivot().Position
		end
	end
	return nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else Vector3.new(0, 0, -1)
end

--------------------------------------------------------------------------------
-- reload
--------------------------------------------------------------------------------

local function finishReload(state: State)
	state.ReloadEndsAt = nil
	state.ReloadToken += 1
	local stats = Combatants.Stats(state.Primary)
	local take = math.min(stats.Magazine - state.Mag, state.Reserve)
	state.Mag += take
	state.Reserve -= take
	syncAmmo(state, true)
end

local function cancelReload(state: State)
	if state.ReloadEndsAt then
		state.ReloadEndsAt = nil
		state.ReloadToken += 1
		syncAmmo(state, true)
	end
end

local function startReload(state: State): boolean
	local stats = Combatants.Stats(state.Primary)
	if state.ReloadEndsAt or state.Mag >= stats.Magazine or state.Reserve <= 0 then
		return false
	end
	if not Combatants.IsAlive(state.Model) or state.Slot ~= "Primary" then
		return false
	end
	state.ReloadEndsAt = os.clock() + stats.ReloadSeconds
	state.ReloadToken += 1
	local token = state.ReloadToken
	task.delay(stats.ReloadSeconds, function()
		if state.ReloadToken == token and state.ReloadEndsAt and Combatants.Get(state.Model) == state then
			if Combatants.IsAlive(state.Model) then
				finishReload(state)
			end
		end
	end)
	return true
end

--------------------------------------------------------------------------------
-- slots
--------------------------------------------------------------------------------

local function slotAvailable(state: State, slot: Slot): boolean
	if slot == "Frag" then
		return state.Frags > 0
	elseif slot == "Smoke" then
		return state.Smokes > 0
	end
	return true
end

-- Puts a slot in hand. `force` skips the carrier lock (used by the carrier rule itself).
local function equip(state: State, slot: Slot, force: boolean?): boolean
	local model = state.Model
	if not force and isCarrying(model) and slot ~= "Knife" then
		return false
	end
	if not slotAvailable(state, slot) then
		return false
	end
	if state.Slot ~= slot then
		state.PrevSlot = state.Slot
		state.Slot = slot
		state.EquippedAt = os.clock()
		cancelReload(state)
	end
	local weapon = Combatants.WeaponFor(state, slot)
	model:SetAttribute("HeldWeapon", weapon)
	model:SetAttribute("Aiming", false)
	model:SetAttribute("Scoped", false)
	Gear.SetHeld(model, weapon)
	return true
end

-- After a grenade slot runs out, go back to something usable.
local function leaveEmptyGrenadeSlot(state: State)
	if (state.Slot == "Frag" or state.Slot == "Smoke") and not slotAvailable(state, state.Slot) then
		local back: Slot = state.PrevSlot
		if back == "Frag" or back == "Smoke" or not slotAvailable(state, back) then
			back = "Primary"
		end
		if isCarrying(state.Model) then
			back = "Knife"
		end
		equip(state, back, true)
	end
end

local function onCarryChanged(state: State)
	local model = state.Model
	if isCarrying(model) then
		if state.SlotBeforeCarry == nil then
			state.SlotBeforeCarry = state.Slot
		end
		equip(state, "Knife", true)
	elseif state.SlotBeforeCarry ~= nil then
		local back = state.SlotBeforeCarry :: Slot
		state.SlotBeforeCarry = nil
		if not slotAvailable(state, back) then
			back = "Primary"
		end
		equip(state, back, true)
	end
	syncAmmo(state, true)
end

--------------------------------------------------------------------------------
-- damage
--------------------------------------------------------------------------------

-- Legs / feet (hitbox "Bone" attribute, or the body part name itself).
local function isLeg(part: BasePart): boolean
	local bone = part:GetAttribute("Bone")
	local name = if type(bone) == "string" then bone else part.Name
	return string.find(name, "Leg", 1, true) ~= nil or string.find(name, "Foot", 1, true) ~= nil
end

local function applyDamage(source: Source, victim: Model, amount: number, headshot: boolean, from: Vector3)
	local vs = Combatants.Get(victim)
	if not vs or not damageAllowed() or not Combatants.IsAlive(victim) or isProtected(victim) then
		return
	end
	local self = source.Model == victim
	if self then
		if not (source.Weapon == "Frag" and Tuning.Frag.SelfDamage) then
			return
		end
	elseif source.Team ~= nil and source.Team == Combatants.Team(victim) then
		if not (source.Weapon == "Frag" and Tuning.Frag.TeamDamage) then
			return
		end
	end
	amount = math.max(1, math.floor(amount + 0.5))
	local humanoid = vs.Humanoid
	local newHealth = math.max(0, humanoid.Health - amount)
	local killed = newHealth <= 0
	local now = os.clock()
	vs.LastDamageAt = now
	vs.Killer = source
	vs.KillerHeadshot = headshot
	vs.KillerAt = now
	if killed then
		vs.CarrierAtDeath = isCarrying(victim)
	end

	if vs.Player then
		R.Damaged:FireClient(vs.Player, { Amount = amount, FromPosition = from, Health = newHealth })
	end
	if source.Player and not self then
		R.HitConfirm:FireClient(
			source.Player,
			{ Kind = if headshot then "Head" else "Body", Killed = killed }
		)
	end
	humanoid.Health = newHealth -- 0 triggers Died -> onDied
end

local function onDied(state: State)
	local model = state.Model
	local now = os.clock()
	local source = if state.Killer and now - state.KillerAt <= KILL_CREDIT_SECONDS then state.Killer else nil
	local headshot = source ~= nil and state.KillerHeadshot
	local carrier = state.CarrierAtDeath or isCarrying(model)
	cancelReload(state)
	if model:GetAttribute("Flashlight") then
		model:SetAttribute("Flashlight", false)
		Gear.SetFlashlight(model, false)
	end
	model:SetAttribute("Aiming", false)
	model:SetAttribute("Scoped", false)

	if source then
		R.KillFeed:FireAllClients({
			Killer = source.Name,
			KillerTeam = source.Team or "",
			Victim = Combatants.DisplayName(model),
			VictimTeam = Combatants.Team(model) or "",
			Headshot = headshot,
			CarrierKill = carrier,
			Weapon = source.Weapon,
			Wallbang = source.Wallbang,
		})
	end
	CombatService.OnDeath:Fire(model, if source then source.Model else nil, headshot, {
		Weapon = if source then source.Weapon else nil,
		Wallbang = source ~= nil and source.Wallbang,
		KillerName = if source then source.Name else nil,
		KillerTeam = if source then source.Team else nil,
		KillerPlayer = if source then source.Player else nil,
	})
end

--------------------------------------------------------------------------------
-- shooting
--------------------------------------------------------------------------------

local function sendShotFx(
	shooter: Model,
	origin: Vector3,
	hitPos: Vector3,
	hitKind: string?,
	weapon: string,
	walls: { Ballistics.Wall }
)
	local except = Players:GetPlayerFromCharacter(shooter)
	local wallPoints: { Vector3 } = {}
	for _, w in walls do
		table.insert(wallPoints, w.Entry)
		table.insert(wallPoints, w.Exit)
	end
	for _, player in Players:GetPlayers() do
		if player ~= except then
			R.ShotFx:FireClient(player, shooter.Name, origin, hitPos, hitKind, weapon, wallPoints)
		end
	end
end

local function maxTokens(primary: string): number
	return if primary == "Sniper" then 1 else 4 -- AK absorbs network jitter bunching shots
end

-- Shared gate for players and bots. Returns false (and why) if the shot is not allowed.
local function canShoot(state: State, now: number): (boolean, string?)
	local model = state.Model
	if not Combatants.IsAlive(model) then
		return false, "dead"
	end
	if state.Slot ~= "Primary" then
		return false, "not primary"
	end
	local stats = Combatants.Stats(state.Primary)
	if now - state.EquippedAt < stats.EquipSeconds * 0.6 then
		return false, "equipping"
	end
	if state.ReloadEndsAt then
		if now >= state.ReloadEndsAt - RELOAD_EARLY_GRACE then
			finishReload(state)
		else
			return false, "reloading"
		end
	end
	if state.Mag <= 0 then
		return false, "empty"
	end
	local interval = 60 / stats.RPM
	state.Tokens = math.min(maxTokens(state.Primary), state.Tokens + (now - state.TokenTime) / interval)
	state.TokenTime = now
	if state.Tokens < 0.9 then
		return false, "rate"
	end
	return true, nil
end

local debugRemote: RemoteEvent? = nil -- Studio only: echoes the accepted hit point to the shooter

-- claim: optional client hit claim { Target, Part, Position } (players only). Returns the hit point
-- and how it was resolved ("Claim" | "Recast" | "Miss") for the Studio debug view.
local function shoot(
	state: State,
	origin: Vector3,
	direction: Vector3,
	rewind: number,
	claim: any
): (Vector3, string)
	local model = state.Model
	local weapon = state.Primary
	local stats = Combatants.Stats(weapon)
	state.Tokens -= 1
	state.Mag -= 1
	CombatService.Fired:Fire(model)
	if weapon == "Sniper" then
		model:SetAttribute("Scoped", false) -- bolt cycle: unscope after every shot
		model:SetAttribute("Aiming", false)
	end

	local hit: Ballistics.Hit?, walls: { Ballistics.Wall } = nil, {}
	local mode = "Recast"
	if claim ~= nil then
		local claimed, _why, claimWalls =
			Ballistics.ValidateClaim(model, origin, direction, weapon, claim, rewind)
		if claimed then
			hit, walls, mode = claimed, claimWalls or {}, "Claim"
		end
	end
	if not hit then
		hit, walls = Ballistics.Resolve(model, origin, direction, rewind, weapon)
	end
	if not hit then
		mode = "Miss"
	end
	local hitPos = if hit then hit.Position else origin + direction * stats.Range
	local hitKind: string? = nil
	-- Enemy spawn barriers stop the bullet (own team shoots out freely).
	local barrierStop = SpawnBarriers.Blocked(origin, hitPos, SpawnBarriers.TeamOf(model))
	if barrierStop then
		hit, hitPos, hitKind = nil, barrierStop, "Barrier" -- clients draw a ricochet
	end
	if hit then
		if hit.Victim then
			hitKind = "Player"
			local zone = hit.Zone or "Body"
			local mult = if zone == "Head"
				then stats.HeadMultiplier
				elseif zone == "Limb" and isLeg(hit.Part) then (stats :: any).LegMultiplier
					or stats.LimbMultiplier
				elseif zone == "Limb" then stats.LimbMultiplier
				else 1
			local amount = stats.Damage * mult * Ballistics.Falloff(weapon, hit.Distance) * hit.Multiplier
			applyDamage(
				Combatants.Source(model, weapon, #hit.Walls > 0),
				hit.Victim,
				amount,
				zone == "Head",
				origin
			)
		elseif hit.Lamp then
			hitKind = "Lamp"
			breakLamp(hit.Lamp)
		else
			hitKind = "World"
		end
	end
	if hitKind ~= "Player" and Smoke.IsSmoked(origin, hitPos) then
		hitKind = hitKind or "Smoke"
	end
	sendShotFx(model, origin, hitPos, hitKind, weapon, walls)
	return hitPos, mode
end

local function onFire(player: Player, shotId: any, origin: any, direction: any, clientTime: any, claim: any)
	if not finiteNumber(shotId) or not finiteVector(origin) or not finiteVector(direction) then
		return
	end
	local model = player.Character
	local state = Combatants.Get(model)
	if not state or not model then
		return
	end
	if math.abs(direction.Magnitude - 1) > 0.02 then
		return
	end
	if shotId <= state.LastShotId then
		return
	end
	state.LastShotId = shotId
	local head = Combatants.Head(model)
	if not head or (origin - head.Position).Magnitude > HEAD_TOLERANCE then
		return
	end
	local now = os.clock()
	local ok, why = canShoot(state, now)
	if not ok then
		if why ~= "dead" then
			syncAmmo(state, false) -- client predicted a bullet we didn't accept
		end
		return
	end
	local rewind = 0
	if finiteNumber(clientTime) then
		rewind = workspace:GetServerTimeNow() - clientTime
	end
	if rewind <= 0 or rewind > 1 then
		rewind = player:GetNetworkPing()
	end
	rewind = math.clamp(rewind + 0.05, 0, Ballistics.MAX_REWIND_SECONDS) -- + client interpolation delay
	local hitPos, mode = shoot(state, origin, direction.Unit, rewind, claim)
	if debugRemote then
		debugRemote:FireClient(player, shotId, hitPos, mode)
	end
	if state.Mag <= 0 then
		syncAmmo(state, true)
	end
end

--------------------------------------------------------------------------------
-- knife
--------------------------------------------------------------------------------

-- Closest live enemy in a short frontal cone with line of sight. `prefer` wins if it qualifies.
-- A slash that hits no one: chip the breakable window in reach, if any (Glass.KNIFE_HITS to break).
local function slashGlass(head: BasePart, look: Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(Glass.TAG)
	local r = workspace:Raycast(head.Position, look * (Tuning.Knife.Range + MELEE_LAG_SLACK), params)
	if r and r.Instance:IsA("BasePart") then
		Glass.Hit(r.Instance, Glass.HITS_TO_BREAK / Glass.KNIFE_HITS)
	end
end

local function meleeAttack(state: State, prefer: Model?): boolean
	local model = state.Model
	local now = os.clock()
	local cfg = Tuning.Knife
	if not Combatants.IsAlive(model) or state.Slot ~= "Knife" then
		return false
	end
	if now - state.LastMeleeAt < cfg.Cooldown * 0.85 or now - state.EquippedAt < cfg.EquipSeconds * 0.6 then
		return false
	end
	state.LastMeleeAt = now
	CombatService.Fired:Fire(model)
	local root = Combatants.Root(model)
	local head = Combatants.Head(model)
	if not root or not head then
		return false
	end
	local look = flat(root.CFrame.LookVector)
	local myTeam = Combatants.Team(model)
	local best: Model? = nil
	local bestDist = math.huge
	for other in Combatants.All() do
		if other == model or not Combatants.IsAlive(other) then
			continue
		end
		if myTeam ~= nil and Combatants.Team(other) == myTeam then
			continue
		end
		local torso = Combatants.Torso(other)
		if not torso then
			continue
		end
		local delta = torso.Position - root.Position
		local dist = delta.Magnitude
		if dist > cfg.Range + MELEE_LAG_SLACK then
			continue
		end
		local angle = math.acos(math.clamp(look:Dot(flat(delta)), -1, 1))
		if angle > MELEE_CONE and dist > 2.5 then
			continue
		end
		if not Ballistics.Clear(head.Position, torso.Position, { model }) then
			continue
		end
		if SpawnBarriers.Blocked(head.Position, torso.Position, myTeam) then
			continue -- no knifing into an enemy spawn through its barrier
		end
		if other == prefer then
			best, bestDist = other, -1
			break
		end
		if dist < bestDist then
			best, bestDist = other, dist
		end
	end
	if not best then
		slashGlass(head, look)
		return false
	end
	local targetRoot = Combatants.Root(best)
	local backstab = false
	if targetRoot then
		local targetLook = flat(targetRoot.CFrame.LookVector)
		local toAttacker = flat(root.Position - targetRoot.Position)
		backstab = math.acos(math.clamp(targetLook:Dot(toAttacker), -1, 1)) > BACKSTAB_ANGLE
	end
	local amount = if backstab then cfg.BackstabDamage else cfg.Damage
	applyDamage(Combatants.Source(model, "Knife", false), best, amount, false, root.Position)
	return true
end

--------------------------------------------------------------------------------
-- grenades
--------------------------------------------------------------------------------

local function throwSmoke(
	state: State,
	origin: Vector3,
	direction: Vector3,
	strength: number,
	lead: number?
): boolean
	local now = os.clock()
	if not Combatants.IsAlive(state.Model) or isCarrying(state.Model) then
		return false
	end
	if state.Smokes <= 0 or now - state.LastSmokeAt < THROW_COOLDOWN then
		return false
	end
	state.LastSmokeAt = now
	state.Smokes -= 1
	cancelReload(state)
	CombatService.Fired:Fire(state.Model)
	Smoke.Throw(origin, direction, state.Model, strength, lead)
	leaveEmptyGrenadeSlot(state)
	syncAmmo(state, true)
	return true
end

local function throwFrag(
	state: State,
	origin: Vector3,
	direction: Vector3,
	strength: number,
	lead: number?
): boolean
	local now = os.clock()
	if not Combatants.IsAlive(state.Model) or isCarrying(state.Model) then
		return false
	end
	if state.Frags <= 0 or now - state.LastFragAt < THROW_COOLDOWN then
		return false
	end
	state.LastFragAt = now
	state.Frags -= 1
	cancelReload(state)
	CombatService.Fired:Fire(state.Model)
	local source = Combatants.Source(state.Model, "Frag", false)
	Frag.Throw(origin, direction, state.Model, strength, function(centre, victims, lamps)
		for _, v in victims do
			applyDamage(source, v.Model, v.Damage, false, centre)
		end
		for _, id in lamps do
			breakLamp(id)
		end
	end, lead)
	leaveEmptyGrenadeSlot(state)
	syncAmmo(state, true)
	return true
end

-- How far along its arc a player's grenade starts: their ping, so the server grenade appears where
-- their local ghost grenade already is (WeaponController), capped so lag can't teleport it far.
local function throwLead(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.25) else 0
end

local function validThrow(
	player: Player,
	origin: any,
	direction: any,
	strength: any
): (State?, Vector3, Vector3, number)
	local character = player.Character
	local state = Combatants.Get(character)
	if not state or not character or not finiteVector(origin) or not finiteVector(direction) then
		return nil, Vector3.zero, Vector3.zero, 1
	end
	if math.abs(direction.Magnitude - 1) > 0.02 then
		return nil, Vector3.zero, Vector3.zero, 1
	end
	local head = Combatants.Head(character)
	if not head or (origin - head.Position).Magnitude > HEAD_TOLERANCE then
		return nil, Vector3.zero, Vector3.zero, 1
	end
	-- charged throw strength (Tuning.Throw); missing / bad values throw at full strength
	local s = if type(strength) == "number" and strength == strength then strength else 1
	return state, origin, direction.Unit, math.clamp(s, Tuning.Throw.MinStrength, 1)
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

local function register(model: Model): State?
	local state = Combatants.Get(model)
	if state then
		return state
	end
	state = Combatants.Register(model)
	if not state then
		return nil
	end
	local s = state :: State
	table.insert(
		s.Connections,
		s.Humanoid.Died:Connect(function()
			onDied(s)
		end)
	)
	table.insert(
		s.Connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				Combatants.Unregister(model)
			end
		end)
	)
	table.insert(
		s.Connections,
		model:GetAttributeChangedSignal("CarryingCore"):Connect(function()
			onCarryChanged(s)
		end)
	)
	CombatService:GiveLoadout(model)
	return s
end

local function validPrimary(id: any): boolean
	return type(id) == "string" and table.find(Tuning.Primaries, id) ~= nil
end

function CombatService:GiveLoadout(model: Model, primaryId: string?)
	local state = register(model)
	if not state then
		return
	end
	if validPrimary(primaryId) then
		state.Primary = primaryId :: string
	elseif not validPrimary(state.Primary) then
		state.Primary = "AK"
	end
	local stats = Combatants.Stats(state.Primary)
	state.ReloadEndsAt = nil
	state.ReloadToken += 1
	state.Mag = stats.Magazine
	state.Reserve = stats.Reserve
	state.Smokes = Tuning.Smoke.PerLife
	state.Frags = Tuning.Frag.PerLife
	state.Tokens = maxTokens(state.Primary)
	state.TokenTime = os.clock()
	state.LastDamageAt = 0
	state.Killer = nil
	state.CarrierAtDeath = false
	state.SlotBeforeCarry = nil
	state.Humanoid.MaxHealth = Tuning.Health.Max
	if state.Humanoid.Health > 0 then
		state.Humanoid.Health = Tuning.Health.Max
	end
	Gear.Equip(model, state.Humanoid, state.Primary)
	Hitboxes.Build(model)
	model:SetAttribute("Flashlight", false)
	Gear.SetFlashlight(model, false)
	state.Slot = "Primary"
	state.PrevSlot = "Knife"
	equip(state, "Primary", true)
	state.EquippedAt = 0 -- spawning with the gun up: no equip delay
	if isCarrying(model) then
		onCarryChanged(state)
	end
	syncAmmo(state, true)
end

function CombatService:GetPrimary(model: Model): string
	local state = Combatants.Get(model)
	return if state then state.Primary else "AK"
end

function CombatService:EquipSlot(model: Model, slot: string): boolean
	local state = Combatants.Get(model)
	if not state or not SLOTS[slot] or not Combatants.IsAlive(model) then
		return false
	end
	local ok = equip(state, slot :: Slot, false)
	syncAmmo(state, true)
	return ok
end

-- Server-side slot change that ignores the carrier lock (Mode: "Knife" on Core pickup).
function CombatService:ForceSlot(model: Model, slot: string): boolean
	local state = Combatants.Get(model)
	if not state or not SLOTS[slot] then
		return false
	end
	if isCarrying(model) and state.SlotBeforeCarry == nil and state.Slot ~= slot then
		state.SlotBeforeCarry = state.Slot
	end
	local ok = equip(state, slot :: Slot, true)
	syncAmmo(state, true)
	return ok
end

function CombatService:SetDrawn(_model: Model, _drawn: boolean)
	-- v2: holster mechanic removed. Kept so older callers don't error.
end

function CombatService:SetAiming(model: Model, aiming: boolean)
	local state = Combatants.Get(model)
	local weapon = if state then Combatants.WeaponFor(state) else nil
	local ok = aiming and Combatants.IsAlive(model) and (weapon == "AK" or weapon == "Sniper")
	model:SetAttribute("Aiming", ok)
	model:SetAttribute("Scoped", ok and weapon == "Sniper")
end

function CombatService:SetFlashlight(model: Model, on: boolean)
	if on and not Combatants.IsAlive(model) then
		on = false
	end
	model:SetAttribute("Flashlight", on)
	Gear.SetFlashlight(model, on)
end

function CombatService:SetLookPitch(model: Model, pitch: number)
	if finiteNumber(pitch) then
		Gear.SetPitch(model, pitch)
	end
end

function CombatService:BotFire(bot: Model, targetPosition: Vector3): boolean
	local state = Combatants.Get(bot) or register(bot)
	if not state or not finiteVector(targetPosition) or isCarrying(bot) then
		return false
	end
	if state.Slot ~= "Primary" then
		equip(state, "Primary", false)
		return false
	end
	local now = os.clock()
	local ok, why = canShoot(state, now)
	if not ok then
		if why == "empty" then
			startReload(state)
		end
		return false
	end
	local head = Combatants.Head(bot)
	if not head then
		return false
	end
	local origin = head.Position
	local aim = targetPosition - origin
	if aim.Magnitude < 0.1 then
		return false
	end
	aim = aim.Unit
	Gear.SetPitch(bot, math.asin(math.clamp(aim.Y, -1, 1)))
	local extra
	if state.Primary == "Sniper" then
		extra = if bot:GetAttribute("Scoped") then Tuning.Sniper.SpreadScoped else 1.5
	else
		extra = if bot:GetAttribute("Aiming") then Tuning.AK.SpreadAim else Tuning.AK.SpreadHip * 0.5
	end
	shoot(state, origin, Ballistics.Cone(aim, Tuning.Bots.AimErrorDegrees + extra, rng), 0, nil)
	if state.Mag <= 0 then
		startReload(state)
	end
	return true
end

-- target: the enemy Model, or a position (the nearest enemy within 3 studs of it is preferred).
function CombatService:BotMelee(bot: Model, target: any): boolean
	local state = Combatants.Get(bot)
	if not state then
		return false
	end
	local prefer: Model? = nil
	if typeof(target) == "Instance" and target:IsA("Model") then
		prefer = target
	elseif finiteVector(target) then
		local best = 3
		for other in Combatants.All() do
			local torso = Combatants.Torso(other)
			if other ~= bot and torso and (torso.Position - target).Magnitude < best then
				best = (torso.Position - target).Magnitude
				prefer = other
			end
		end
	end
	if state.Slot ~= "Knife" then
		equip(state, "Knife", false)
		return false
	end
	return meleeAttack(state, prefer)
end

function CombatService:BotThrowFrag(bot: Model, position: Vector3): boolean
	local state = Combatants.Get(bot)
	local head = Combatants.Head(bot)
	if not state or not head or not finiteVector(position) then
		return false
	end
	local dir = position - head.Position
	if dir.Magnitude < 0.1 then
		return false
	end
	-- aim flat at the target; the lob (Shared/Lob) adds the arc and the strength sets the range
	local level = Vector3.new(dir.X, 0, dir.Z)
	local aim = if level.Magnitude > 0.1 then level.Unit else dir.Unit
	local strength = Lob.StrengthFor(head.Position, position, Tuning.Frag.ThrowSpeed)
	return throwFrag(state, head.Position, aim, strength)
end

function CombatService:BotThrowSmoke(bot: Model, position: Vector3): boolean
	local state = Combatants.Get(bot)
	local head = Combatants.Head(bot)
	if not state or not head or not finiteVector(position) then
		return false
	end
	local dir = position - head.Position
	if dir.Magnitude < 0.1 then
		return false
	end
	-- aim flat at the target; the lob (Shared/Lob) adds the arc and the strength sets the range
	local level = Vector3.new(dir.X, 0, dir.Z)
	local aim = if level.Magnitude > 0.1 then level.Unit else dir.Unit
	local strength = Lob.StrengthFor(head.Position, position, Tuning.Smoke.ThrowSpeed)
	return throwSmoke(state, head.Position, aim, strength)
end

function CombatService:IsSmoked(a: any, b: any): boolean
	local pa, pb = positionOf(a), positionOf(b)
	if not pa or not pb then
		return false
	end
	return Smoke.IsSmoked(pa, pb)
end

function CombatService:SetEnabled(on: boolean)
	enabled = on
end

function CombatService:ResetMatch()
	Smoke.Clear()
	Frag.Clear()
end

function CombatService:GetAmmo(model: Model): { [string]: any }?
	local state = Combatants.Get(model)
	if not state then
		return nil
	end
	return {
		Mag = state.Mag,
		Reserve = state.Reserve,
		Smokes = state.Smokes,
		Frags = state.Frags,
		Primary = state.Primary,
		Held = Combatants.WeaponFor(state),
	}
end

-- Spawn magazine bag: `kind` is the bag's weapon. Refills the spare magazines (reserve) of that
-- weapon if you carry it. True if anything changed.
function CombatService:Resupply(model: Model, kind: string): boolean
	local state = Combatants.Get(model)
	if not state or not Combatants.IsAlive(model) or state.Primary ~= kind then
		return false
	end
	local changed = false
	local stats = Combatants.Stats(state.Primary)
	if state.Reserve < stats.Reserve then
		state.Reserve = stats.Reserve
		changed = true
	end
	if changed then
		syncAmmo(state, true)
	end
	return changed
end

-- Hook the ProximityPrompt of every spawn magazine bag (built by Layout, now or later).
local function wireAmmoBag(bag: Instance)
	local kind = bag:GetAttribute("Weapon")
	local prompt = bag:FindFirstChildWhichIsA("ProximityPrompt", true)
	if type(kind) ~= "string" or not prompt then
		return
	end
	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		if character and CombatService:Resupply(character, kind) then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://9116357383" -- PSE "Machine Gun Bolt 3" (mags in)
				s.Volume = 0.7
				s.Parent = root
				s:Play()
				task.delay(2, function()
					s:Destroy()
				end)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	-- the default "Health" script regenerates on its own; Combat owns regen
	task.spawn(function()
		local regen = character:WaitForChild("Health", 5)
		if regen and regen:IsA("Script") then
			regen:Destroy()
		end
	end)
	character:WaitForChild("Humanoid", 10)
	if character.Parent and player.Character == character then
		register(character)
	end
end

local function onTagged(instance: Instance)
	if
		instance:IsA("Model")
		and instance:FindFirstChildOfClass("Humanoid")
		and instance:IsDescendantOf(workspace)
	then
		register(instance)
	end
end

function CombatService:Init()
	Hitboxes.Init()
	Ballistics.Ignore(Smoke.Init())
	Ballistics.Ignore(Frag.Init())

	-- Extra remotes not in the shared contract: look pitch + crouch (Mode reads `Crouching`).
	local net = Instance.new("Folder")
	net.Name = "CombatNet"
	local look = Instance.new("UnreliableRemoteEvent")
	look.Name = "Look"
	look.Parent = net
	local crouch = Instance.new("RemoteEvent")
	crouch.Name = "SetCrouch"
	crouch.Parent = net
	if RunService:IsStudio() then
		local dbg = Instance.new("RemoteEvent")
		dbg.Name = "DebugShot"
		dbg.Parent = net
		debugRemote = dbg
	end
	net.Parent = ReplicatedStorage

	local lastLook: { [Player]: number } = {}
	look.OnServerEvent:Connect(function(player: Player, pitch: any)
		local now = os.clock()
		if now - (lastLook[player] or 0) < 0.04 or not finiteNumber(pitch) then
			return
		end
		lastLook[player] = now
		local character = player.Character
		if character and Combatants.Get(character) then
			Gear.SetPitch(character, pitch)
		end
	end)
	crouch.OnServerEvent:Connect(function(player: Player, on: any)
		local character = player.Character
		local state = Combatants.Get(character)
		if type(on) ~= "boolean" or not state or not character then
			return
		end
		local now = os.clock()
		if now - state.LastToggleAt < TOGGLE_COOLDOWN * 0.5 then
			return
		end
		state.LastToggleAt = now
		Gear.SetCrouch(character, state.Humanoid, on and Combatants.IsAlive(character))
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastLook[player] = nil
	end)

	Remotes.Get("Fire").OnServerEvent:Connect(onFire)

	Remotes.Get("Reload").OnServerEvent:Connect(function(player: Player)
		local state = Combatants.Get(player.Character)
		if state then
			startReload(state)
		end
	end)

	Remotes.Get("EquipSlot").OnServerEvent:Connect(function(player: Player, slot: any)
		local character = player.Character
		if type(slot) == "string" and character and Combatants.Get(character) then
			CombatService:EquipSlot(character, slot)
		end
	end)

	Remotes.Get("Melee").OnServerEvent:Connect(function(player: Player)
		local state = Combatants.Get(player.Character)
		if state then
			meleeAttack(state, nil)
		end
	end)

	Remotes.Get("SetAiming").OnServerEvent:Connect(function(player: Player, aiming: any)
		local character = player.Character
		if type(aiming) == "boolean" and character and Combatants.Get(character) then
			CombatService:SetAiming(character, aiming)
		end
	end)

	Remotes.Get("SetFlashlight").OnServerEvent:Connect(function(player: Player, on: any)
		local character = player.Character
		if type(on) == "boolean" and character and Combatants.Get(character) then
			CombatService:SetFlashlight(character, on)
		end
	end)

	Remotes.Get("ThrowSmoke").OnServerEvent
		:Connect(function(player: Player, origin: any, direction: any, strength: any)
			local state, o, d, s = validThrow(player, origin, direction, strength)
			if state then
				throwSmoke(state, o, d, s, throwLead(player))
			end
		end)

	Remotes.Get("ThrowFrag").OnServerEvent
		:Connect(function(player: Player, origin: any, direction: any, strength: any)
			local state, o, d, s = validThrow(player, origin, direction, strength)
			if state then
				throwFrag(state, o, d, s, throwLead(player))
			end
		end)
end

function CombatService:Start()
	task.spawn(Gear.PreloadKnife) -- the owner's store karambit (yields on InsertService)
	for _, bag in CollectionService:GetTagged(AMMO_BAG_TAG) do
		wireAmmoBag(bag)
	end
	CollectionService:GetInstanceAddedSignal(AMMO_BAG_TAG):Connect(wireAmmoBag)
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(onTagged)
	for _, instance in CollectionService:GetTagged("Combatant") do
		task.spawn(onTagged, instance)
	end

	-- regen + lag-comp history
	local regenAccum = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		Combatants.SampleHistory(now)
		regenAccum += dt
		if regenAccum < REGEN_TICK then
			return
		end
		local step = regenAccum
		regenAccum = 0
		local h = Tuning.Health
		for _, state in Combatants.All() do
			local humanoid = state.Humanoid
			if
				humanoid.Health > 0
				and humanoid.Health < humanoid.MaxHealth
				and now - state.LastDamageAt >= h.RegenDelay
			then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + h.RegenPerSecond * step)
			end
		end
	end)
end

return CombatService

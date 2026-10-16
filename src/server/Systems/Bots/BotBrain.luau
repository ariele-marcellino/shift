--!strict
-- One bot's decisions, stepped by BotService at 10 Hz (perception 5 Hz, planning 2 Hz).
-- Priorities: carry Core home > return own dropped Core > chase own stolen Core > escort carrier >
-- grab dropped enemy Core > role default (attacker: enemy pedestal, defender: patrol home,
-- roamer: wander midfield). Snipers replace patrol/wander with holding a long sightline.
-- Fights with a reaction delay; AK in bursts, sniper single scoped shots, knife up close,
-- an occasional frag at a target that just ducked into cover. Never aims at heads on purpose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Types = require(script.Parent.Parent.Mode.Types)
local Deps = require(script.Parent.Parent.Mode.Deps)
local Spawner = require(script.Parent.Parent.Mode.Spawner)
local Loadouts = require(script.Parent.Parent.Mode.Loadouts)
local Perception = require(script.Parent.Perception)
local Navigator = require(script.Parent.Navigator)
local WorldRay = require(script.Parent.WorldRay)
local BotAnim = require(script.Parent.BotAnim)
local TeamService = require(script.Parent.Parent.Parent.Services.TeamService)

type Combatant = Types.Combatant

local BotBrain = {}

local PERCEIVE_EVERY = 0.2
local PLAN_EVERY = 0.5
local LOSE_TARGET_AFTER = 1.2
local MELEE_RANGE = Tuning.Knife.Range + 0.5
local SNIPER_EXTRA_REACTION = 0.35 -- snipers one-shot; give players a fair moment to react
local FRAG_CHANCE = 0.22 -- per "target just ducked into cover" event (frags are deadly in v2)
local EYE = Vector3.new(0, 2, 0)
local rng = Random.new()

export type State = {
	C: Combatant,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Nav: Navigator.Navigator,
	Anim: BotAnim.Anim,
	Align: AlignOrientation,
	Observer: Perception.Observer,
	Primary: string,
	IsSniper: boolean,
	Target: Combatant?,
	TargetPoint: Vector3?,
	TargetVisible: boolean,
	LastSeenAt: number,
	LastSeenPos: Vector3?,
	ReactAt: number,
	BurstLeft: number,
	NextBurstAt: number,
	WeaponReadyAt: number,
	NextMeleeAt: number,
	NextEquipAt: number,
	Scoping: boolean,
	FragUsed: boolean,
	FragRolled: boolean,
	NextPerceive: number,
	NextPlan: number,
	NextStrafe: number,
	NextLightCheck: number,
	LastDarkAt: number,
	RoamGoal: Vector3?,
	RoamUntil: number,
	HoldLook: Vector3?,
	RoamLook: Vector3?,
	PerchIndex: number,
	InvestigateUntil: number,
}

local function match(): any
	return require(script.Parent.Parent.Parent.Services.MatchService) :: any
end

local function equipSeconds(weapon: string): number
	if weapon == "Sniper" then
		return Tuning.Sniper.EquipSeconds
	elseif weapon == "Knife" then
		return Tuning.Knife.EquipSeconds
	end
	return Tuning.AK.EquipSeconds
end

function BotBrain.new(c: Combatant, model: Model): State?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "BotFacing"
	attachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = 1e6
	align.Responsiveness = 25
	align.Enabled = false
	align.Parent = root

	local primary = Loadouts.Get(c)
	local now = os.clock()
	return {
		C = c,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Nav = Navigator.new(humanoid, root),
		Anim = BotAnim.Setup(humanoid),
		Align = align,
		Observer = { Model = model, FlashlightOn = false, WideAwareUntil = 0 },
		Primary = primary,
		IsSniper = primary == "Sniper",
		Target = nil,
		TargetPoint = nil,
		TargetVisible = false,
		LastSeenAt = -math.huge,
		LastSeenPos = nil,
		ReactAt = math.huge,
		BurstLeft = 0,
		NextBurstAt = 0,
		WeaponReadyAt = now + equipSeconds(primary),
		NextMeleeAt = 0,
		NextEquipAt = 0,
		Scoping = false,
		FragUsed = false,
		FragRolled = true,
		NextPerceive = now + rng:NextNumber() * PERCEIVE_EVERY, -- stagger bots
		NextPlan = now + rng:NextNumber() * PLAN_EVERY,
		NextStrafe = 0,
		NextLightCheck = now,
		LastDarkAt = -math.huge,
		RoamGoal = nil,
		RoamUntil = 0,
		HoldLook = nil,
		RoamLook = nil,
		PerchIndex = 0,
		InvestigateUntil = 0,
	}
end

-- Called when the bot takes damage: briefly aware all around (it "feels" where shots come from).
function BotBrain.OnDamaged(st: State)
	st.Observer.WideAwareUntil = os.clock() + 2.5
	if st.IsSniper then
		st.RoamUntil = 0 -- a found sniper relocates
	end
end

local function rootOf(c: Combatant?): BasePart?
	return Spawner.RootOf(c and c.Model)
end

local function isCarrying(st: State): boolean
	return st.Model:GetAttribute("CarryingCore") ~= nil
end

local function held(st: State): string
	local value = st.Model:GetAttribute("HeldWeapon")
	return if type(value) == "string" then value else st.Primary
end

local function equip(st: State, slot: "Primary" | "Knife", now: number)
	if now < st.NextEquipAt then
		return
	end
	st.NextEquipAt = now + 0.6
	if Deps.EquipSlot(st.Model, slot) then
		st.WeaponReadyAt = now + equipSeconds(if slot == "Knife" then "Knife" else st.Primary)
	end
end

local function setScoping(st: State, on: boolean)
	if st.Scoping ~= on then
		st.Scoping = on
		Deps.SetAiming(st.Model, on)
	end
end

local function setFlashlight(st: State, on: boolean)
	if st.Observer.FlashlightOn == on then
		return
	end
	st.Observer.FlashlightOn = on
	if not Deps.SetFlashlight(st.Model, on) then
		st.Model:SetAttribute("Flashlight", on) -- Combat lacks a bot API; attribute only
	end
end

local function face(st: State, point: Vector3?)
	if point then
		local dir = point - st.Root.Position
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.1 then
			st.Humanoid.AutoRotate = false
			st.Align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
			st.Align.Enabled = true
			return
		end
	end
	st.Align.Enabled = false
	st.Humanoid.AutoRotate = true
end

---------------------------------------------------------------------------------------------------
-- Perception: pick the best visible enemy (our Core's carrier first, then the closest).

local function perceive(st: State, now: number)
	local myTeam = st.C.Team
	local best: Combatant?, bestPoint: Vector3?, bestScore = nil, nil, math.huge
	for _, enemy in TeamService:GetTeam(TeamService:Enemy(myTeam)) do
		local model = enemy.Model
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if
			enemy.Alive
			and model
			and humanoid
			and humanoid.Health > 0
			and model:GetAttribute("SpawnProtected") ~= true
		then
			local observer = st.Observer
			-- Keep tracking the current target all around for a moment (we just saw it).
			local tracking = enemy == st.Target and now - st.LastSeenAt < LOSE_TARGET_AFTER
			local savedWide = observer.WideAwareUntil
			if tracking then
				observer.WideAwareUntil = now + 0.01
			end
			local point = Perception.CanSee(observer, model, now)
			observer.WideAwareUntil = savedWide
			if point then
				local score = (point - st.Root.Position).Magnitude
				if model:GetAttribute("CarryingCore") == myTeam then
					score -= 1000
				end
				if enemy == st.Target then
					score -= 15 -- stickiness
				end
				if score < bestScore then
					best, bestPoint, bestScore = enemy, point, score
				end
			end
		end
	end

	if best then
		if best ~= st.Target then
			st.Target = best
			local reaction = Tuning.Bots.ReactionSeconds + rng:NextNumber() * 0.2
			if st.IsSniper then
				reaction += SNIPER_EXTRA_REACTION + Tuning.Sniper.ScopeInSeconds
			end
			st.ReactAt = now + reaction
			st.BurstLeft = 0
		end
		st.TargetVisible = true
		st.TargetPoint = bestPoint
		st.LastSeenAt = now
		st.LastSeenPos = bestPoint
		st.FragRolled = false
	else
		st.TargetVisible = false
		st.TargetPoint = nil
		if st.Target and now - st.LastSeenAt > LOSE_TARGET_AFTER then
			st.Target = nil
			st.ReactAt = math.huge
			if st.C.Role ~= "defender" and not st.IsSniper and st.LastSeenPos then
				st.InvestigateUntil = now + 4
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Planning

local function randomNodeNear(center: Vector3, radius: number): Vector3?
	local picks = {}
	for _, node in Navigator.Nodes() do
		if (node.Position - center).Magnitude <= radius then
			table.insert(picks, node.Position)
		end
	end
	return if #picks > 0 then picks[rng:NextInteger(1, #picks)] else nil
end

local function roamPoint(homeA: Vector3, homeB: Vector3): Vector3?
	local picks = {}
	for _, node in Navigator.Nodes() do
		if (node.Position - homeA).Magnitude > 40 and (node.Position - homeB).Magnitude > 40 then
			table.insert(picks, node.Position)
		end
	end
	if #picks == 0 then
		return (homeA + homeB) / 2 + Vector3.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20))
	end
	return picks[rng:NextInteger(1, #picks)]
end

-- Sniper hold spot: on our side of the map, with the longest clear sightline toward the enemy
-- side. Samples a handful of nodes (~100 rays), only when picking a new spot (every 20-35 s).
local function sniperSpot(st: State, ownHome: Vector3, enemyHome: Vector3): (Vector3?, Vector3?)
	local nodes = Navigator.Nodes()
	if #nodes == 0 then
		return nil, nil
	end
	local defender = st.C.Role == "defender"
	local candidates, targets = {}, {}
	for _, node in nodes do
		local dOwn = (node.Position - ownHome).Magnitude
		local dEnemy = (node.Position - enemyHome).Magnitude
		if defender then
			if dOwn <= 50 and dOwn > 8 then
				table.insert(candidates, node.Position)
			end
		elseif dOwn < dEnemy and dOwn > 25 then
			table.insert(candidates, node.Position)
		end
		if dEnemy < dOwn or (defender and dOwn > 30) then
			table.insert(targets, node.Position)
		end
	end
	if #candidates == 0 or #targets == 0 then
		return nil, nil
	end
	local bestSpot, bestLook, bestScore = nil, nil, -1
	for _ = 1, math.min(10, #candidates) do
		local spot = candidates[rng:NextInteger(1, #candidates)]
		local longest, look = 0, nil
		for _ = 1, math.min(8, #targets) do
			local t = targets[rng:NextInteger(1, #targets)]
			local d = (t - spot).Magnitude
			if d > longest and WorldRay.Clear(spot + EYE, t + EYE) then
				longest, look = d, t
			end
		end
		if longest > bestScore then
			bestSpot, bestLook, bestScore = spot, look, longest
		end
	end
	return bestSpot, bestLook
end

local function chooseGoal(st: State, now: number): Vector3?
	local Match = match()
	local myTeam = st.C.Team
	local enemyTeam = TeamService:Enemy(myTeam)
	local own = Match:GetCore(myTeam)
	local enemy = Match:GetCore(enemyTeam)
	local ownHome: Vector3 = Match:GetHomePosition(myTeam)
	local enemyHome: Vector3 = Match:GetHomePosition(enemyTeam)
	local pos = st.Root.Position
	local role = st.C.Role or "roamer"

	st.HoldLook = nil
	if isCarrying(st) then
		return ownHome
	end
	if own and own.State == "Dropped" and (role ~= "attacker" or (own.Position - pos).Magnitude < 60) then
		return own.Position
	end
	if own and own.State == "Carried" and (role ~= "attacker" or (own.Position - pos).Magnitude < 50) then
		-- The stolen Core glows and is marked on the HUD; fair to chase. Snipers only nearby.
		if not st.IsSniper or (own.Position - pos).Magnitude < 70 then
			return own.Position
		end
	end
	if
		enemy
		and enemy.State == "Carried"
		and enemy.Carrier ~= st.C
		and role ~= "defender"
		and not st.IsSniper
	then
		local carrierRoot = rootOf(enemy.Carrier)
		if carrierRoot then
			if (carrierRoot.Position - pos).Magnitude < 10 then
				return nil -- close enough: hold and cover
			end
			return carrierRoot.Position - carrierRoot.CFrame.LookVector * 6
		end
	end
	if enemy and enemy.State == "Dropped" and role ~= "defender" then
		return enemy.Position
	end
	if now < st.InvestigateUntil and st.LastSeenPos then
		return st.LastSeenPos
	end

	if role == "attacker" and not st.IsSniper then
		return enemyHome
	end

	if st.IsSniper then
		-- Hold a long angle; relocate every 20-35 s or when hit. Don't rush.
		if not st.RoamGoal or now > st.RoamUntil then
			local perches = Deps.GetSniperSpots(myTeam)
			if #perches > 0 then
				-- Alternate between World's perches (path to the perch node, then onto the spot).
				st.PerchIndex = st.PerchIndex % #perches + 1
				if st.PerchIndex == 1 and st.RoamGoal == nil then
					st.PerchIndex = rng:NextInteger(1, #perches)
				end
				local perch = perches[st.PerchIndex]
				st.RoamGoal = perch.Position
				st.RoamLook = perch.Position + perch.LookVector * 60
			else
				local spot, look = sniperSpot(st, ownHome, enemyHome)
				st.RoamGoal = spot or randomNodeNear(ownHome, 40) or ownHome
				st.RoamLook = look
			end
			st.RoamUntil = now + rng:NextNumber(20, 35)
		end
		st.HoldLook = st.RoamLook
		return st.RoamGoal
	end

	if not st.RoamGoal or now > st.RoamUntil or st.Nav:IsIdle() then
		if role == "defender" then
			st.RoamGoal = randomNodeNear(ownHome, 35)
				or ownHome + Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
			st.RoamUntil = now + rng:NextNumber(8, 14)
		else
			st.RoamGoal = roamPoint(ownHome, enemyHome)
			st.RoamUntil = now + rng:NextNumber(15, 25)
		end
	end
	return st.RoamGoal
end

---------------------------------------------------------------------------------------------------
-- Combat

local function melee(st: State, point: Vector3, now: number)
	if held(st) ~= "Knife" and not isCarrying(st) then
		equip(st, "Knife", now)
	end
	if now >= st.NextMeleeAt and now >= st.ReactAt then
		st.NextMeleeAt = now + Tuning.Knife.Cooldown + rng:NextNumber() * 0.25
		if Deps.BotMelee(st.Model, point) then
			Spawner.CancelProtection(st.Model)
		end
	end
end

local function shoot(st: State, point: Vector3, now: number)
	if held(st) ~= st.Primary then
		equip(st, "Primary", now)
		return
	end
	if now < st.WeaponReadyAt or now < st.ReactAt then
		return
	end
	if st.IsSniper then
		setScoping(st, true)
		if now < st.NextBurstAt then
			return
		end
		if Deps.BotFire(st.Model, point) then
			Perception.NoteShot(st.Model)
			Spawner.CancelProtection(st.Model)
			st.NextBurstAt = now + 60 / Tuning.Sniper.RPM + rng:NextNumber(0.3, 0.8)
			st.Scoping = false -- Combat unscopes after each shot; re-scope next time
		end
		return
	end

	if st.BurstLeft <= 0 then
		if now < st.NextBurstAt then
			return
		end
		local burst = Tuning.Bots.BurstShots
		st.BurstLeft = rng:NextInteger(burst[1], burst[2])
	end
	-- One call per 10 Hz tick = 600 RPM; Combat enforces the real rate, ammo and aim error.
	if Deps.BotFire(st.Model, point) then
		Perception.NoteShot(st.Model)
		Spawner.CancelProtection(st.Model)
	end
	st.BurstLeft -= 1
	if st.BurstLeft <= 0 then
		local dist = (point - st.Root.Position).Magnitude
		st.NextBurstAt = now + rng:NextNumber(0.3, 0.6) + math.clamp(dist / 200, 0, 0.5)
	end
end

local function fight(st: State, now: number)
	local point = st.TargetPoint
	if not point then
		return
	end
	local dist = (point - st.Root.Position).Magnitude
	if dist <= MELEE_RANGE then
		melee(st, point, now)
	elseif not isCarrying(st) then
		shoot(st, point, now)
	end
end

-- A target that just broke line of sight nearby may get a frag at its last known position.
local function maybeFrag(st: State, now: number)
	if st.FragUsed or st.FragRolled or st.TargetVisible or isCarrying(st) or not st.LastSeenPos then
		return
	end
	local since = now - st.LastSeenAt
	if since < 0.4 or since > 2.5 then
		return
	end
	st.FragRolled = true
	local dist = ((st.LastSeenPos :: Vector3) - st.Root.Position).Magnitude
	if dist < 12 or dist > 35 or rng:NextNumber() > FRAG_CHANCE then
		return
	end
	if Deps.BotThrowFrag(st.Model, st.LastSeenPos :: Vector3) then
		st.FragUsed = true
	end
end

local function strafe(st: State, now: number)
	if now < st.NextStrafe then
		return
	end
	st.NextStrafe = now + rng:NextNumber(1.2, 2.2)
	local point = st.TargetPoint
	if st.IsSniper or st.C.Role == "defender" or not point or rng:NextNumber() < 0.35 then
		st.Nav:Hold(nil)
		return
	end
	local toTarget = point - st.Root.Position
	local side = Vector3.new(-toTarget.Z, 0, toTarget.X)
	if side.Magnitude < 0.1 then
		st.Nav:Hold(nil)
		return
	end
	local dest = st.Root.Position
		+ side.Unit * rng:NextNumber(4, 8) * (if rng:NextNumber() < 0.5 then -1 else 1)
	if WorldRay.Clear(st.Root.Position, dest) then
		st.Nav:Hold(dest)
	else
		st.Nav:Hold(nil)
	end
end

---------------------------------------------------------------------------------------------------

function BotBrain.Step(st: State, now: number, phase: string)
	local velocity = st.Root.AssemblyLinearVelocity
	BotAnim.Update(st.Anim, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)

	if phase == "Ended" then
		if st.Nav.Goal then
			st.Nav:Stop()
		end
		setScoping(st, false)
		face(st, nil)
		return
	end

	-- Flashlight on in the dark, off a moment after leaving it (IsDark follows World's live lights).
	if now >= st.NextLightCheck then
		st.NextLightCheck = now + 0.5
		if Perception.IsModelInDark(st.Model, st.Root.Position, now) then
			st.LastDarkAt = now
			setFlashlight(st, true)
		elseif now - st.LastDarkAt > 2 then
			setFlashlight(st, false)
		end
	end

	if now >= st.NextPerceive then
		st.NextPerceive = now + PERCEIVE_EVERY
		perceive(st, now)
	end

	local carrying = isCarrying(st)
	local engaged = st.TargetVisible and st.Target ~= nil

	if phase == "Warmup" or phase == "Waiting" then
		-- Warmup / waiting for players: stay near spawn, look at threats, don't fight.
		if st.Nav.Goal then
			st.Nav:Stop()
		end
		face(st, st.TargetPoint)
		return
	end

	if engaged then
		face(st, st.TargetPoint)
		fight(st, now)
		if not carrying then
			strafe(st, now)
			return -- hold ground while fighting
		end
	else
		setScoping(st, false)
		maybeFrag(st, now)
		-- Back to the primary after a knife fight (carriers stay knife-locked by Combat).
		if not carrying and held(st) == "Knife" and now - st.LastSeenAt > 1 then
			equip(st, "Primary", now)
		end
		st.Nav:Resume()
		face(st, if st.HoldLook and st.Nav:IsIdle() then st.HoldLook else nil)
	end

	if now >= st.NextPlan then
		st.NextPlan = now + PLAN_EVERY
		local goal = chooseGoal(st, now)
		if goal then
			st.Nav:SetGoal(goal)
		elseif st.Nav.Goal ~= nil then
			st.Nav:Stop()
		end
	end
	st.Nav:Step(now)
end

function BotBrain.Destroy(st: State)
	st.Align:Destroy()
end

return BotBrain

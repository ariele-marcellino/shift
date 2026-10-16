--!strict
-- First-person weapons (v2): slots [1] Primary (AK or BOLT-7 sniper) / [2] Knife / [3] Frag /
-- [4] Smoke, quick-throws [G] frag / [T] smoke, [Q] last weapon, mouse wheel cycles. Client
-- prediction + feel only; the server validates everything and sets HeldWeapon / Scoped.
--
-- Public API (UI / MobileController):
--   :SetFiring(bool) (alias :Fire)  :SetAiming(bool)  :ToggleScope()  :Reload()
--   :EquipSlot("Primary"|"Knife"|"Frag"|"Smoke")  :SwapLast()  :CycleSlot(+1|-1)
--   :ThrowFrag()  :ThrowSmoke()  (full strength, instant)
--   :BeginThrow("Frag"|"Smoke")  :ReleaseThrow()  :CancelThrow()  (hold to charge, Tuning.Throw)
--   :Melee()  :ToggleFlashlight()  :ToggleCrouch()  :DropFlag() (X: drop the flag you carry)
--   .State = { Held (slot), HeldWeapon, Primary, Slots = {Primary=weapon, Knife=true, Frag=n,
--              Smoke=n}, Mag, Reserve (current primary), Smokes, Frags, Aiming, Scoped,
--              Spread (deg), Reloading, Crouched, Flashlight, Locked (carrying Core), Alive, Drawn }
--   .Changed: Signal()   .Hit: Signal(kind, killed)
-- Reads LocalPlayer attributes Setting_Sensitivity (0.2-3) and Setting_FOV (70-90) live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local SpawnBarriers = require(Shared:WaitForChild("SpawnBarriers"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Lob = require(Shared:WaitForChild("Lob"))

local WeaponFolder = (script.Parent :: Instance).Parent:WaitForChild("Weapon")
local Viewmodel = require(WeaponFolder:WaitForChild("Viewmodel"))
local Effects = require(WeaponFolder:WaitForChild("Effects"))
local Sounds = require(WeaponFolder:WaitForChild("Sounds"))
local Spring = require(WeaponFolder:WaitForChild("Spring"))
local ScopeOverlay = require(WeaponFolder:WaitForChild("ScopeOverlay"))
local AdsFocus = require(WeaponFolder:WaitForChild("AdsFocus"))
local HitScan = require(WeaponFolder:WaitForChild("HitScan"))
local HitDebug = require(WeaponFolder:WaitForChild("HitDebug"))
local AKModel = require(WeaponFolder:WaitForChild("AKModel"))
local SniperModel = require(WeaponFolder:WaitForChild("SniperModel"))
local KnifeModel = require(WeaponFolder:WaitForChild("KnifeModel"))
local GrenadeModel = require(WeaponFolder:WaitForChild("GrenadeModel"))

type Slot = "Primary" | "Knife" | "Frag" | "Smoke"

local AIM_FOV_SCALE = 0.78
local AIM_SENS_SCALE = 0.7
local MAX_PITCH = math.rad(80)
local SLOT_ORDER: { Slot } = { "Primary", "Knife", "Frag", "Smoke" }
local THROW_RELEASE = 0.18
local THROW_COOLDOWN = 1
local GHOST_SECONDS = 0.6 -- longest the local ghost grenade flies before the real one must show up

local player = Players.LocalPlayer

local WeaponController = {}
WeaponController.Changed = Signal.new()
WeaponController.Hit = Signal.new()
WeaponController.State = {
	Held = "Primary" :: string,
	HeldWeapon = "AK",
	Primary = "AK",
	Slots = { Primary = "AK", Knife = true, Frag = Tuning.Frag.PerLife, Smoke = Tuning.Smoke.PerLife } :: { [string]: any },
	Mag = Tuning.AK.Magazine,
	Reserve = Tuning.AK.Reserve,
	Smokes = Tuning.Smoke.PerLife,
	Frags = Tuning.Frag.PerLife,
	Aiming = false,
	Scoped = false,
	Spread = Tuning.AK.SpreadHip,
	Reloading = false,
	Crouched = false,
	Flashlight = false,
	Locked = false,
	Alive = false,
	Drawn = true, -- v1 compatibility (holster removed)
	ThrowCharge = 0, -- 0 = not charging, else current throw strength (Tuning.Throw); polled by the HUD
}
local State = WeaponController.State

local R = {
	Fire = Remotes.Get("Fire"),
	Reload = Remotes.Get("Reload"),
	EquipSlot = Remotes.Get("EquipSlot"),
	ThrowSmoke = Remotes.Get("ThrowSmoke"),
	ThrowFrag = Remotes.Get("ThrowFrag"),
	Melee = Remotes.Get("Melee"),
	SetFlashlight = Remotes.Get("SetFlashlight"),
	SetAiming = Remotes.Get("SetAiming"),
	DropFlag = Remotes.Get("DropFlag"),
}
local lookRemote: UnreliableRemoteEvent? = nil
local crouchRemote: RemoteEvent? = nil

local rng = Random.new()
local vms: { [string]: Viewmodel.Viewmodel } = {}
local vm: Viewmodel.Viewmodel
local shake = Spring.new(300, 20)
local lastShake = CFrame.identity

local dirty = false
local firing = false
local triggerUsed = false -- semi-auto / throw: one action per press
local aimHeld = false
local sentAiming = false
local nextShotAt = 0
local lastShotAt = 0
local lastSlashAt = 0
local lastThrowAt = 0
local hideGrenadeUntil = 0 -- the grenade has left the hand: hide the grenade viewmodel until then
-- Hold-to-charge throw in progress: the grenade kind, when it started, and what started it
-- ("Trigger" = fire with a grenade in hand: switching away cancels; "Key" = G / T / mobile buttons).
local charging: ("Frag" | "Smoke")? = nil
local chargeStart = 0
local chargeSource = "Key"
local burstIndex = 0
local bloom = 0
local shotId = 0
local reloadToken = 0
local lastLocalEquip = 0
local prevSlot: Slot = "Knife"
local pendingSlash = false
local recoilPending = Vector2.zero
local recoilAccum = Vector2.zero
local prePitch, preYaw = 0, 0
local lastLookSent, lastLookAt = 0, 0
local lastSensitivity = -1
local lastReconcile = 0

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local head: BasePart? = nil
local bodyParts: { BasePart } = {}

--------------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------------

local function set(key: string, value: any)
	if (State :: any)[key] ~= value then
		(State :: any)[key] = value
		dirty = true
	end
end

local function primaryStats(): any
	return if State.Primary == "Sniper" then Tuning.Sniper else Tuning.AK
end

local function weaponFor(slot: string): string
	return if slot == "Primary" then State.Primary else slot
end

local function slotFor(weapon: string): Slot
	if weapon == "AK" or weapon == "Sniper" then
		return "Primary"
	end
	return weapon :: Slot
end

local function refreshSlots()
	local slots = State.Slots
	if slots.Primary ~= State.Primary or slots.Frag ~= State.Frags or slots.Smoke ~= State.Smokes then
		slots.Primary = State.Primary
		slots.Frag = State.Frags
		slots.Smoke = State.Smokes
		dirty = true
	end
end

local function alive(): boolean
	return humanoid ~= nil and humanoid.Health > 0 and character ~= nil and character.Parent ~= nil
end

local function available(slot: string): boolean
	if slot == "Frag" then
		return State.Frags > 0
	elseif slot == "Smoke" then
		return State.Smokes > 0
	end
	return slot == "Primary" or slot == "Knife"
end

local function pitchYaw(cf: CFrame): (number, number)
	local look = cf.LookVector
	return math.asin(math.clamp(look.Y, -1, 1)), math.atan2(-look.X, -look.Z)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function rotateCamera(camera: Camera, dPitch: number, dYaw: number)
	local cf = camera.CFrame
	local pitch = pitchYaw(cf)
	dPitch = math.clamp(pitch + dPitch, -MAX_PITCH, MAX_PITCH) - pitch
	camera.CFrame = CFrame.new(cf.Position)
		* CFrame.Angles(0, dYaw, 0)
		* cf.Rotation
		* CFrame.Angles(dPitch, 0, 0)
end

local function cone(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local r = math.rad(degrees) * rng:NextNumber() -- centre-weighted, like CS
	local theta = rng:NextNumber() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(
		math.sin(theta) * r,
		math.cos(theta) * r,
		0
	)).LookVector
end

-- Local hit scan from the camera ray (same rules as the server: hitboxes, wallbangs).
local function localCast(origin: Vector3, direction: Vector3, weapon: string): HitScan.Result?
	local ignore: { Instance } = { Effects.Folder() }
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(ignore, camera)
	end
	if character then
		table.insert(ignore, character)
	end
	for _, name in { "CombatSmoke", "CombatGrenades", "HitDebug" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	return HitScan.Cast(origin, direction, weapon, ignore)
end

-- Where an enemy spawn barrier stops this shot (mirrors the server), or nil.
local function barrierStop(origin: Vector3, endPos: Vector3): Vector3?
	local team = character and character:GetAttribute("Team")
	return SpawnBarriers.Blocked(origin, endPos, if type(team) == "string" then team else nil)
end

--------------------------------------------------------------------------------
-- slots
--------------------------------------------------------------------------------

local function cancelReload()
	if State.Reloading then
		reloadToken += 1
		set("Reloading", false)
		vm:StopReload()
	end
end

local function showViewmodel(weapon: string)
	local nextVm = vms[weapon]
	if not nextVm then
		return
	end
	if vm and vm ~= nextVm then
		vm:SetVisible(false)
	end
	vm = nextVm
	vm:Draw()
end

-- Local equip. fromServer = following the server's HeldWeapon (no remote, ignores the lock).
local function equipLocal(slot: Slot, fromServer: boolean): boolean
	if not fromServer then
		if State.Locked and slot ~= "Knife" then
			return false
		end
		if not available(slot) or not alive() then
			return false
		end
	end
	local weapon = weaponFor(slot)
	if State.Held == slot and State.HeldWeapon == weapon then
		return true
	end
	cancelReload()
	if State.Held ~= slot then
		prevSlot = State.Held :: Slot
	end
	set("Held", slot)
	set("HeldWeapon", weapon)
	set("Aiming", false)
	set("Scoped", false)
	triggerUsed = true -- don't fire the new weapon with a trigger still held
	showViewmodel(weapon)
	Sounds.Play(if weapon == "Knife" then "Draw" else "Equip")
	if not fromServer then
		lastLocalEquip = os.clock()
		R.EquipSlot:FireServer(slot)
	end
	return true
end

-- After a grenade runs out, go back to a usable slot (server does the same).
local function leaveEmptyGrenade()
	if (State.Held == "Frag" or State.Held == "Smoke") and not available(State.Held) then
		local back: Slot = prevSlot
		if back == "Frag" or back == "Smoke" or not available(back) then
			back = "Primary"
		end
		if State.Locked then
			back = "Knife"
		end
		equipLocal(back, true)
	end
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

local function startReload(): boolean
	local stats = primaryStats()
	if not alive() or State.Reloading or State.Held ~= "Primary" then
		return false
	end
	if State.Mag >= stats.Magazine or State.Reserve <= 0 then
		return false
	end
	reloadToken += 1
	local token = reloadToken
	set("Reloading", true)
	vm:PlayReload()
	R.Reload:FireServer()
	local sniper = State.Primary == "Sniper"
	-- The sniper has one full reload clip (SniperReload); the AK uses mag out / in / bolt.
	Sounds.Play(if sniper then "SniperReload" else "MagOut")
	task.delay(stats.ReloadSeconds * 0.62, function()
		if reloadToken == token and not sniper then
			Sounds.Play("MagIn")
		end
	end)
	task.delay(stats.ReloadSeconds * 0.78, function()
		if reloadToken == token and not sniper then
			Sounds.Play("BoltRack")
		end
	end)
	task.delay(stats.ReloadSeconds, function()
		if reloadToken ~= token or not State.Reloading then
			return
		end
		local take = math.min(stats.Magazine - State.Mag, State.Reserve)
		set("Mag", State.Mag + take)
		set("Reserve", State.Reserve - take)
		set("Reloading", false)
	end)
	return true
end

local function canShoot(now: number): boolean
	return alive()
		and State.Held == "Primary"
		and not State.Reloading
		and vm.EquipAlpha < 0.02
		and vm.ThrowStart == nil
		and vm.BoltStart == nil
		and State.Mag > 0
		and now >= nextShotAt - 0.005
end

-- Shell rain: 10+ shots within ~1 s plays the shell-casing clatter once; a pause of SPRAY_GAP
-- seconds starts a new spray.
local SHELL_SHOTS = 10
local SHELL_WINDOW = 1.05
local SPRAY_GAP = 0.5
local recentShots: { number } = {}
local shellPlayed = false

local function countShot(now: number)
	if now - lastShotAt > SPRAY_GAP then
		table.clear(recentShots)
		shellPlayed = false
	end
	table.insert(recentShots, now)
	while recentShots[1] and now - recentShots[1] > SHELL_WINDOW do
		table.remove(recentShots, 1)
	end
	if not shellPlayed and #recentShots >= SHELL_SHOTS then
		shellPlayed = true
		Sounds.Play("ShellRain")
	end
end

local function shoot(camera: Camera, now: number)
	local weapon = State.Primary
	local stats = primaryStats()
	local sniper = weapon == "Sniper"
	-- bullets always leave the eye along the camera centre ray (+ spread); never from the muzzle
	local cf = camera.CFrame
	local origin = cf.Position
	local direction = cone(cf.LookVector, State.Spread)
	local result = localCast(origin, direction, weapon)
	local blockedAt =
		barrierStop(origin, if result then result.Position else origin + direction * stats.Range)
	if blockedAt then
		result = nil -- the enemy spawn barrier eats the shot (no hit claim)
	end
	local claim = nil
	if result and result.Victim and result.Hitbox then
		claim = { Target = result.Victim, Part = result.Hitbox.Name, Position = result.Position }
	end
	shotId += 1
	R.Fire:FireServer(shotId, origin, direction, workspace:GetServerTimeNow(), claim)
	local hitPos = blockedAt or (if result then result.Position else origin + direction * stats.Range)
	HitDebug.ClientShot(shotId, hitPos)

	set("Mag", State.Mag - 1)
	countShot(now)
	if now - lastShotAt > Tuning.AK.RecoilResetSeconds then
		burstIndex = 0
	end
	burstIndex += 1
	lastShotAt = now

	local aim = vm.AimAlpha
	local m = if State.Crouched then 0.85 else 1
	if sniper then
		recoilPending += Vector2.new(math.rad(stats.RecoilVertical * m), math.rad(rng:NextNumber(-0.6, 0.6)))
		vm:Kick(false, rng, 2.4, stats.MuzzleLightSeconds)
		shake:Impulse(Vector3.new(rng:NextNumber(10, 14), rng:NextNumber(-3, 3), rng:NextNumber(-8, 8)))
		Sounds.Play("SniperFire", rng:NextNumber(0.97, 1.03))
		-- unscope and work the bolt (re-scopes on its own if aim is still held)
		task.delay(0.15, function()
			if State.Held == "Primary" and State.Primary == "Sniper" and alive() then
				vm:PlayBolt()
				Sounds.Play("SniperBolt")
			end
		end)
		vm:CapAim(0.5)
	else
		-- bloom: the first 3 shots add only a third, then full per-shot bloom
		local n = burstIndex
		bloom = math.min(bloom + stats.SpreadPerShot * (if n <= 3 then 0.35 else 1), stats.SpreadBloomMax)
		-- fixed spray pattern: camera kick = where the next bullet goes
		local pattern = stats.RecoilPattern
		local step = pattern[math.min(n, #pattern)]
		recoilPending += Vector2.new(math.rad(step[1] * m), math.rad(-step[2] * m))
		vm:Kick(State.Aiming, rng, 1, stats.MuzzleLightSeconds)
		shake:Impulse(
			Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(-2, 2), rng:NextNumber(-6, 6)) * (1 - aim * 0.5)
		)
		Sounds.Play("Fire", rng:NextNumber(0.96, 1.04))
	end
	nextShotAt = math.max(nextShotAt + 60 / stats.RPM, now + (if sniper then 60 / stats.RPM else 0))
	Effects.OwnShot(vm.MuzzleWorld, weapon, if State.Aiming and not sniper then 0.55 else 1)

	-- visuals only start at the muzzle
	Effects.Tracer(vm.MuzzleWorld, hitPos)
	if blockedAt then
		Effects.BarrierHit(blockedAt, origin)
	end
	if result then
		local isPlayer = result.Victim ~= nil
		Effects.Impact(result.Position, result.Normal, if isPlayer then "Player" else "World", not isPlayer)
		if #result.Walls > 0 then
			local points = {}
			for _, w in result.Walls do
				table.insert(points, w.Entry)
				table.insert(points, w.Exit)
			end
			Effects.Walls(points, direction)
		end
	end

	if State.Mag <= 0 then
		task.delay(if sniper then 1.1 else 0.25, function()
			if State.Mag <= 0 and not State.Reloading and State.Held == "Primary" then
				startReload()
			end
		end)
	end
end

local function slash()
	local now = os.clock()
	if not alive() or State.Held ~= "Knife" or vm.EquipAlpha > 0.3 then
		return
	end
	if now - lastSlashAt < Tuning.Knife.Cooldown then
		return
	end
	lastSlashAt = now
	vm:PlaySlash()
	Sounds.Play("KnifeSlash", rng:NextNumber(0.95, 1.08))
	shake:Impulse(Vector3.new(0, rng:NextNumber(-3, 3), rng:NextNumber(-4, 4)))
	R.Melee:FireServer()
end

local function canThrow(kind: "Frag" | "Smoke", now: number): boolean
	local count = if kind == "Frag" then State.Frags else State.Smokes
	return alive()
		and workspace.CurrentCamera ~= nil
		and not State.Locked
		and count > 0
		and now - lastThrowAt >= THROW_COOLDOWN
end

local function chargeStrength(now: number): number
	local cfg = Tuning.Throw
	return math.clamp((now - chargeStart) / cfg.ChargeSeconds, cfg.MinStrength, 1)
end

local function cancelCharge()
	charging = nil
	State.ThrowCharge = 0
end

-- The thrower's own grenade, shown the instant it leaves the hand and flown with the same physics
-- as the server's (shared Lob: right-hand start, launch angle, gravity, bounce). The real grenade
-- arrives a ping later already that far along its arc (CombatService lead) and replaces it.
local function ghostGrenade(kind: "Frag" | "Smoke", origin: Vector3, direction: Vector3, strength: number)
	local ignore: { Instance } = { Effects.Folder() }
	if character then
		table.insert(ignore, character)
	end
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(ignore, camera)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local frag = kind == "Frag"
	local part = Instance.new("Part")
	part.Name = "GhostGrenade"
	if frag then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * 0.42
		part.Color = Color3.fromRGB(62, 72, 48)
	else
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.6, 0.32, 0.32)
		part.Color = Color3.fromRGB(78, 86, 66)
	end
	part.Material = Enum.Material.Metal
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CustomPhysicalProperties = Lob.Physics(if frag then 2.5 else 2)
	part.CFrame = CFrame.new(Lob.HandStart(origin, direction, params))
	part.Parent = Effects.Folder()
	local speed = (if frag then Tuning.Frag.ThrowSpeed else Tuning.Smoke.ThrowSpeed) * strength
	Lob.Launch(part, Lob.Velocity(direction, speed))
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), 0)

	local conn: RBXScriptConnection? = nil
	local function done()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if part.Parent then
			part:Destroy()
		end
	end
	local folder = workspace:FindFirstChild(if frag then "CombatGrenades" else "CombatSmoke")
	local realName = if frag then "FragGrenade" else "SmokeGrenade"
	if folder then
		conn = folder.ChildAdded:Connect(function(child)
			if
				child.Name == realName
				and child:IsA("BasePart")
				and (child.Position - part.Position).Magnitude < 25
			then
				done()
			end
		end)
	end
	task.delay(GHOST_SECONDS, done)
end

local function throw(kind: "Frag" | "Smoke", strength: number, pinPulled: boolean?)
	local now = os.clock()
	if not canThrow(kind, now) then
		return
	end
	lastThrowAt = now
	cancelReload()
	if kind == "Frag" then
		set("Frags", State.Frags - 1)
		if not pinPulled then
			Sounds.Play("FragPin")
		end
	else
		set("Smokes", State.Smokes - 1)
	end
	refreshSlots()
	vm:PlayThrow()
	Sounds.Play("Throw")
	local remote = if kind == "Frag" then R.ThrowFrag else R.ThrowSmoke
	task.delay(THROW_RELEASE, function()
		local cam = workspace.CurrentCamera
		if cam and alive() then
			local origin = cam.CFrame.Position
			local direction = cam.CFrame.LookVector -- the lob angle + hand offset come from Lob
			remote:FireServer(origin, direction, strength)
			hideGrenadeUntil = os.clock() + 0.6 -- it left the hand (the slot switches at 0.5 s)
			ghostGrenade(kind, origin, direction, strength)
		end
	end)
	task.delay(0.5, leaveEmptyGrenade)
end

local function beginCharge(kind: "Frag" | "Smoke", source: string)
	if charging or not canThrow(kind, os.clock()) then
		return
	end
	cancelReload()
	charging = kind
	chargeStart = os.clock()
	chargeSource = source
	State.ThrowCharge = Tuning.Throw.MinStrength
	if kind == "Frag" then
		Sounds.Play("FragPin")
	end
end

local function releaseCharge()
	local kind = charging
	if not kind then
		return
	end
	local strength = chargeStrength(os.clock())
	cancelCharge()
	throw(kind, strength, true)
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

function WeaponController:SetFiring(down: boolean)
	firing = down == true
	if firing then
		triggerUsed = false
		-- grenade in hand: hold fire to charge, release to throw
		if State.Held == "Frag" or State.Held == "Smoke" then
			triggerUsed = true
			beginCharge(State.Held :: any, "Trigger")
		end
	elseif chargeSource == "Trigger" then
		releaseCharge()
	end
end
WeaponController.Fire = WeaponController.SetFiring

function WeaponController:SetAiming(on: boolean)
	aimHeld = on == true
end

function WeaponController:ToggleScope()
	aimHeld = not aimHeld
end

function WeaponController:Reload()
	startReload()
end

function WeaponController:EquipSlot(slot: string): boolean
	if not table.find(SLOT_ORDER, slot :: any) then
		return false
	end
	return equipLocal(slot :: Slot, false)
end

function WeaponController:SwapLast(): boolean
	local target: Slot = prevSlot
	if target == State.Held or not available(target) then
		target = if State.Held == "Primary" then "Knife" else "Primary"
	end
	return equipLocal(target, false)
end

function WeaponController:CycleSlot(direction: number)
	local i = table.find(SLOT_ORDER, State.Held :: any) or 1
	for _ = 1, #SLOT_ORDER do
		i = (i - 1 + (if direction < 0 then -1 else 1)) % #SLOT_ORDER + 1
		if available(SLOT_ORDER[i]) then
			equipLocal(SLOT_ORDER[i], false)
			return
		end
	end
end

function WeaponController:ThrowFrag()
	throw("Frag", 1)
end

function WeaponController:ThrowSmoke()
	throw("Smoke", 1)
end

-- Drop the flag you carry where you stand (server checks you really carry it).
function WeaponController:DropFlag()
	local model = player.Character
	if model and model:GetAttribute("CarryingCore") ~= nil then
		R.DropFlag:FireServer()
	end
end

function WeaponController:BeginThrow(kind: string)
	if kind == "Frag" or kind == "Smoke" then
		beginCharge(kind, "Key")
	end
end

function WeaponController:ReleaseThrow()
	releaseCharge()
end

function WeaponController:CancelThrow()
	cancelCharge()
end

-- Knife attack from any weapon: switches to the knife first, then slashes.
function WeaponController:Melee()
	if State.Held == "Knife" then
		slash()
	elseif equipLocal("Knife", false) then
		pendingSlash = true
	end
end

function WeaponController:ToggleFlashlight()
	if not alive() then
		return
	end
	set("Flashlight", not State.Flashlight)
	Effects.SetFlashlight(State.Flashlight)
	Sounds.Play("FlashlightClick")
	R.SetFlashlight:FireServer(State.Flashlight)
end

function WeaponController:ToggleCrouch(): boolean
	if not alive() then
		return false
	end
	set("Crouched", not State.Crouched)
	if crouchRemote then
		crouchRemote:FireServer(State.Crouched)
	end
	return true
end

--------------------------------------------------------------------------------
-- character lifecycle
--------------------------------------------------------------------------------

local function applyPrimary(primary: any)
	if (primary ~= "AK" and primary ~= "Sniper") or primary == State.Primary then
		return
	end
	set("Primary", primary)
	refreshSlots()
	if State.Held == "Primary" then
		set("HeldWeapon", primary)
		showViewmodel(primary)
	end
end

local function followServerHeld(model: Model, force: boolean)
	local held = model:GetAttribute("HeldWeapon")
	if type(held) ~= "string" then
		return
	end
	if held == "AK" or held == "Sniper" then
		applyPrimary(held)
	end
	if held ~= State.HeldWeapon and (force or os.clock() - lastLocalEquip > 0.6) then
		equipLocal(slotFor(held), true)
	end
end

local function onCharacter(model: Model)
	character = model
	humanoid = model:WaitForChild("Humanoid", 10) :: Humanoid?
	rootPart = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	head = model:WaitForChild("Head", 10) :: BasePart?
	if character ~= model then
		return
	end
	table.clear(bodyParts)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(bodyParts, d)
		end
	end
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and character == model then
			table.insert(bodyParts, d)
		end
	end)

	reloadToken += 1
	cancelCharge()
	firing, aimHeld, pendingSlash = false, false, false
	burstIndex, bloom = 0, 0
	recoilPending, recoilAccum = Vector2.zero, Vector2.zero
	nextShotAt = 0
	prevSlot = "Knife"
	local stats = primaryStats()
	set("Mag", stats.Magazine)
	set("Reserve", stats.Reserve)
	set("Smokes", Tuning.Smoke.PerLife)
	set("Frags", Tuning.Frag.PerLife)
	set("Held", "Primary")
	set("HeldWeapon", State.Primary)
	set("Aiming", false)
	set("Scoped", false)
	set("Reloading", false)
	set("Crouched", false)
	set("Flashlight", false)
	set("Locked", false)
	set("Alive", true)
	refreshSlots()
	Effects.SetFlashlight(false)
	showViewmodel(State.Primary)
	followServerHeld(model, true)
	AdsFocus.RefreshQuality()

	model:GetAttributeChangedSignal("HeldWeapon"):Connect(function()
		if character == model then
			followServerHeld(model, State.Locked)
		end
	end)
	model:GetAttributeChangedSignal("CarryingCore"):Connect(function()
		if character ~= model then
			return
		end
		local c = model:GetAttribute("CarryingCore")
		local locked = c ~= nil and c ~= false and c ~= ""
		set("Locked", locked)
		if locked then
			firing = false
			equipLocal("Knife", true) -- the server forces it too
		end
	end)
	if humanoid then
		humanoid.Died:Connect(function()
			if character ~= model then
				return
			end
			firing = false
			cancelReload()
			set("Alive", false)
			set("Aiming", false)
			set("Scoped", false)
			set("Flashlight", false)
			set("Crouched", false)
			Effects.SetFlashlight(false)
			ScopeOverlay.SetVisible(false)
		end)
	end
end

--------------------------------------------------------------------------------
-- per frame
--------------------------------------------------------------------------------

local function preCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- remove last frame's temporary shake so the camera scripts see the true aim
	if lastShake ~= CFrame.identity then
		camera.CFrame = camera.CFrame * lastShake:Inverse()
		lastShake = CFrame.identity
	end
	prePitch, preYaw = pitchYaw(camera.CFrame)
end

local function settingNumber(name: string, default: number, lo: number, hi: number): number
	local v = player:GetAttribute(name)
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(v, lo, hi)
end

local function postCamera(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or not vm then
		return
	end
	local now = os.clock()
	local isAlive = alive()
	local weapon = State.HeldWeapon
	local sniper = weapon == "Sniper"
	local gun = weapon == "AK" or sniper

	-- 1. player's own aim input this frame (pulling down cancels accumulated climb)
	local pitchNow, yawNow = pitchYaw(camera.CFrame)
	local inPitch = pitchNow - prePitch
	local inYaw = wrapAngle(yawNow - preYaw)
	local ax, ay = recoilAccum.X, recoilAccum.Y
	if ax > 0 and inPitch < 0 then
		ax = math.max(0, ax + inPitch)
	end
	if ay ~= 0 and math.sign(inYaw) == -math.sign(ay) then
		ay = if ay > 0 then math.max(0, ay + inYaw) else math.min(0, ay + inYaw)
	end
	recoilAccum = Vector2.new(ax, ay)

	-- 2. apply recoil smoothly, recover when not firing
	if recoilPending.Magnitude > 1e-5 then
		local step = recoilPending * (1 - math.exp(-dt * (if sniper then 22 else 35)))
		rotateCamera(camera, step.X, step.Y)
		recoilPending -= step
		recoilAccum += step
	end
	if now - lastShotAt > 0.1 and recoilAccum.Magnitude > 1e-5 then
		local back = recoilAccum * (1 - math.exp(-dt * Tuning.AK.RecoilRecovery))
		rotateCamera(camera, -back.X, -back.Y)
		recoilAccum -= back
	end

	-- 3. movement sample
	local speed, velY, grounded = 0, 0, true
	if rootPart and humanoid then
		local v = rootPart.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
		velY = v.Y
		grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	end

	-- 4. aiming / scope (sniper can't stay scoped through the bolt cycle)
	local wantAim = aimHeld
		and isAlive
		and gun
		and not State.Reloading
		and vm.ThrowStart == nil
		and vm.EquipAlpha < 0.5
		and not (sniper and vm.BoltStart ~= nil)
	set("Aiming", wantAim)
	if wantAim ~= sentAiming then
		sentAiming = wantAim
		R.SetAiming:FireServer(wantAim)
		if wantAim then
			Sounds.Play(if sniper then "ScopeIn" else "AimIn")
		end
	end
	local aim = vm.AimAlpha
	local scopedView = sniper and aim > 0.85
	set("Scoped", sniper and wantAim)
	ScopeOverlay.SetVisible(scopedView and isAlive)

	-- 5. spread (CS-style): standing still + recovered = pinpoint; movement/air add a lot
	local spread = 0
	if gun then
		local st = if sniper then Tuning.Sniper else Tuning.AK
		local runSpeed = if sniper then Tuning.Movement.Sniper else Tuning.Movement.AK
		local moving = if speed > st.StillSpeed
			then math.clamp((speed - st.StillSpeed) / math.max(runSpeed - st.StillSpeed, 1), 0, 1.6)
			else 0
		if sniper then
			spread = st.SpreadHip + (st.SpreadScoped - st.SpreadHip) * aim + st.SpreadMoving * moving
			if not grounded then
				spread += st.SpreadAir
			end
		else
			if now - lastShotAt > 60 / st.RPM then
				bloom = math.max(0, bloom - dt * st.SpreadBloomMax / st.AccuracyRecoverySeconds)
			end
			local inaccuracy = st.SpreadRun * moving + (if grounded then 0 else st.SpreadAir) + bloom
			inaccuracy *= 1 + (st.AimSpreadMultiplier - 1) * aim
			spread = st.SpreadStanding + inaccuracy
		end
		if State.Crouched then
			spread *= if sniper then 0.8 else st.CrouchSpreadMultiplier
		end
	end
	if math.abs(spread - State.Spread) > 0.05 then
		dirty = true
	end
	State.Spread = spread

	-- 6. trigger
	if pendingSlash and State.Held == "Knife" and vm.EquipAlpha < 0.3 then
		pendingSlash = false
		slash()
	end
	if firing and isAlive then
		if gun then
			if not (sniper and triggerUsed) then
				if canShoot(now) then
					if not sniper and nextShotAt < now - 60 / Tuning.AK.RPM then
						nextShotAt = now
					end
					repeat
						shoot(camera, now)
						triggerUsed = true
					until sniper or not canShoot(now)
				elseif State.Mag <= 0 and not State.Reloading and not triggerUsed then
					triggerUsed = true
					Sounds.Play("Dry")
					startReload()
				end
			end
		elseif weapon == "Knife" then
			slash()
		elseif (weapon == "Frag" or weapon == "Smoke") and not triggerUsed then
			triggerUsed = true
			beginCharge(weapon :: any, "Trigger")
		end
	end
	if charging then
		if not isAlive or State.Locked or (chargeSource == "Trigger" and State.Held ~= charging) then
			cancelCharge() -- died / locked / switched weapon: nothing thrown, grenade kept
		else
			State.ThrowCharge = chargeStrength(now)
		end
	end

	-- 7. temporary camera shake (removed again before the camera scripts run next frame)
	local s = shake:Update(dt)
	lastShake = CFrame.Angles(math.rad(s.X) * 0.25, math.rad(s.Y) * 0.25, math.rad(s.Z) * 0.25)
	camera.CFrame = camera.CFrame * lastShake

	-- 8. FOV + sensitivity from settings (live)
	local baseFov = settingNumber("Setting_FOV", 70, 70, 90)
	local fov = if sniper
		then baseFov + (Tuning.Sniper.ScopeFOV - baseFov) * aim
		elseif gun then baseFov * (1 + (AIM_FOV_SCALE - 1) * aim)
		else baseFov
	camera.FieldOfView = fov
	local sens = settingNumber("Setting_Sensitivity", 1, 0.2, 3)
	sens *= if sniper then fov / baseFov elseif gun then 1 + (AIM_SENS_SCALE - 1) * aim else 1
	if math.abs(sens - lastSensitivity) > 0.005 then
		lastSensitivity = sens
		pcall(function()
			UserInputService.MouseDeltaSensitivity = sens
		end)
	end

	-- 9. viewmodel (hidden when dead, scoped, or the camera is not in first person)
	local firstPerson = isAlive and head ~= nil and (camera.CFrame.Position - head.Position).Magnitude < 2.5
	local thrown = (weapon == "Frag" or weapon == "Smoke") and now < hideGrenadeUntil
	vm:SetVisible(firstPerson and not scopedView and not thrown)
	vm:Update({
		Camera = camera.CFrame,
		Dt = dt,
		AimTarget = if wantAim then 1 else 0,
		Speed = speed,
		VelocityY = velY,
		Grounded = grounded,
		Crouching = State.Crouched,
	})
	Effects.Update(dt, camera.CFrame)
	AdsFocus.Update(if isAlive and weapon == "AK" then vm.AimAlpha else 0, dt)

	-- 10. own body hidden; own server-side flashlight hidden (the local one follows the camera)
	if character then
		for _, p in bodyParts do
			if p.LocalTransparencyModifier ~= 1 then
				p.LocalTransparencyModifier = 1
			end
		end
		local att = head and head:FindFirstChild("FlashlightAttachment")
		local light = att and att:FindFirstChild("Flashlight")
		if light and light:IsA("SpotLight") and light.Enabled then
			light.Enabled = false
		end
		-- 11. safety net: converge on the server's HeldWeapon if a correction was missed
		if now - lastReconcile > 1 then
			lastReconcile = now
			followServerHeld(character, false)
		end
	end

	-- 12. replicate look pitch (~10 Hz) so others see the beam / gun follow the aim
	if lookRemote and isAlive and now - lastLookAt > 0.1 then
		local pitch = pitchYaw(camera.CFrame)
		if math.abs(pitch - lastLookSent) > 0.03 then
			lastLookSent, lastLookAt = pitch, now
			lookRemote:FireServer(pitch)
		end
	end

	if dirty then
		dirty = false
		WeaponController.Changed:Fire()
	end
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function call(fn: () -> ()): () -> ()
	return fn
end

local KEY_ACTIONS: { [Enum.KeyCode]: () -> () } = {
	[Enum.KeyCode.One] = call(function()
		WeaponController:EquipSlot("Primary")
	end),
	[Enum.KeyCode.Two] = call(function()
		WeaponController:EquipSlot("Knife")
	end),
	[Enum.KeyCode.Three] = call(function()
		WeaponController:EquipSlot("Frag")
	end),
	[Enum.KeyCode.Four] = call(function()
		WeaponController:EquipSlot("Smoke")
	end),
	[Enum.KeyCode.Q] = call(function()
		WeaponController:SwapLast()
	end),
	[Enum.KeyCode.G] = call(function()
		WeaponController:BeginThrow("Frag")
	end),
	[Enum.KeyCode.T] = call(function()
		WeaponController:BeginThrow("Smoke")
	end),
	[Enum.KeyCode.V] = call(function()
		WeaponController:Melee()
	end),
	[Enum.KeyCode.X] = call(function()
		WeaponController:DropFlag()
	end),
	[Enum.KeyCode.F7] = call(function()
		HitDebug.Toggle() -- Studio only (no-op in live games)
	end),
	[Enum.KeyCode.R] = call(function()
		WeaponController:Reload()
	end),
	[Enum.KeyCode.F] = call(function()
		WeaponController:ToggleFlashlight()
	end),
	-- Crouch is Ctrl only; C is the slide key (SprintController).
	[Enum.KeyCode.LeftControl] = call(function()
		WeaponController:ToggleCrouch()
	end),
	-- gamepad
	[Enum.KeyCode.ButtonX] = call(function()
		WeaponController:Reload()
	end),
	[Enum.KeyCode.ButtonY] = call(function()
		WeaponController:SwapLast()
	end),
	[Enum.KeyCode.ButtonR1] = call(function()
		WeaponController:BeginThrow("Frag")
	end),
	[Enum.KeyCode.ButtonL1] = call(function()
		WeaponController:BeginThrow("Smoke")
	end),
	[Enum.KeyCode.ButtonR3] = call(function()
		WeaponController:Melee()
	end),
	[Enum.KeyCode.DPadUp] = call(function()
		WeaponController:ToggleFlashlight()
	end),
	[Enum.KeyCode.DPadDown] = call(function()
		WeaponController:DropFlag()
	end),
	[Enum.KeyCode.DPadRight] = call(function()
		WeaponController:CycleSlot(1)
	end),
	[Enum.KeyCode.DPadLeft] = call(function()
		WeaponController:CycleSlot(-1)
	end),
	[Enum.KeyCode.ButtonB] = call(function()
		WeaponController:ToggleCrouch()
	end),
}

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		WeaponController:SetFiring(true)
	elseif t == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		WeaponController:SetAiming(true)
	else
		local action = KEY_ACTIONS[input.KeyCode]
		if action then
			action()
		end
	end
end

-- Quick-throw keys: press starts charging, release throws.
local THROW_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.G] = true,
	[Enum.KeyCode.T] = true,
	[Enum.KeyCode.ButtonR1] = true,
	[Enum.KeyCode.ButtonL1] = true,
}

local function onInputEnded(input: InputObject)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		WeaponController:SetFiring(false)
	elseif t == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		WeaponController:SetAiming(false)
	elseif THROW_KEYS[input.KeyCode] and chargeSource == "Key" then
		WeaponController:ReleaseThrow()
	end
end

local function onInputChanged(input: InputObject, processed: boolean)
	if not processed and input.UserInputType == Enum.UserInputType.MouseWheel and input.Position.Z ~= 0 then
		WeaponController:CycleSlot(if input.Position.Z > 0 then -1 else 1)
	end
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

function WeaponController:Init()
	Effects.Init()
	ScopeOverlay.Init()
	AdsFocus.Init()
	HitDebug.Init()
	local parent = workspace.CurrentCamera or workspace
	vms.AK = Viewmodel.new(parent, AKModel.Build())
	vms.Sniper = Viewmodel.new(parent, SniperModel.Build())
	vms.Knife = Viewmodel.new(parent, KnifeModel.Build())
	-- swap to the owner's store karambit once the server has loaded and published it
	task.spawn(function()
		local store = ReplicatedStorage:WaitForChild("StoreModels", 60)
		local template = store and store:WaitForChild("Karambit", 60)
		if not template or not template:IsA("Model") then
			return
		end
		local ok, built = pcall(KnifeModel.FromStore, template)
		if not ok then
			warn("[Weapon] store karambit viewmodel failed:", built)
			return
		end
		local old = vms.Knife
		vms.Knife = Viewmodel.new(workspace.CurrentCamera or workspace, built)
		if vm == old then
			showViewmodel("Knife") -- holding the knife right now: show the new one
		end
		old:SetVisible(false)
		old.Built.Model:Destroy()
	end)
	vms.Frag = Viewmodel.new(parent, GrenadeModel.Build("Frag"))
	vms.Smoke = Viewmodel.new(parent, GrenadeModel.Build("Smoke"))
	vm = vms.AK
	Effects.OnExplosion = function(position: Vector3)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local d = (camera.CFrame.Position - position).Magnitude
		local k = math.clamp(1 - d / (Tuning.Frag.VisualRadius * 3), 0, 1)
		if k > 0 then
			shake:Impulse(
				Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 30 * k
			)
		end
	end
end

function WeaponController:Start()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.WindowFocusReleased:Connect(function()
		firing = false
		aimHeld = false
	end)

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			for _, v in vms do
				v.Built.Model.Parent = camera
			end
		end
	end)

	Remotes.Get("AmmoSync").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		applyPrimary(data.Primary)
		if type(data.Mag) == "number" then
			if State.Reloading and data.Mag > State.Mag then
				reloadToken += 1 -- server finished the reload first
				set("Reloading", false)
			end
			set("Mag", data.Mag)
		end
		if type(data.Reserve) == "number" then
			set("Reserve", data.Reserve)
		end
		if type(data.Smokes) == "number" then
			set("Smokes", data.Smokes)
		end
		if type(data.Frags) == "number" then
			set("Frags", data.Frags)
		end
		refreshSlots()
	end)

	Remotes.Get("ShotFx").OnClientEvent
		:Connect(function(shooterId: any, origin: any, hitPos: any, hitKind: any, weapon: any, walls: any)
			if
				type(shooterId) == "string"
				and typeof(origin) == "Vector3"
				and typeof(hitPos) == "Vector3"
			then
				Effects.RemoteShot(
					shooterId,
					origin,
					hitPos,
					if type(hitKind) == "string" then hitKind else nil,
					if type(weapon) == "string" then weapon else nil,
					if type(walls) == "table" then walls else nil
				)
			end
		end)

	Remotes.Get("HitConfirm").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		local kind = if data.Kind == "Head" then "Head" else "Body"
		if data.Killed then
			Sounds.Play("Kill")
		end
		if State.HeldWeapon == "Knife" then
			Sounds.Play("KnifeHit")
		end
		local hitScale = if State.HeldWeapon == "Sniper" then Sounds.SniperHitScale else 1
		Sounds.Play(if kind == "Head" then "HitHead" else "HitBody", nil, hitScale)
		WeaponController.Hit:Fire(kind, data.Killed == true)
	end)

	Remotes.Get("Damaged").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		local amount = if type(data.Amount) == "number" then data.Amount else 20
		local k = math.clamp(amount / 26, 0.3, 3)
		shake:Impulse(Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-10, 10)) * k)
		vm:Impact(rng:NextNumber(-4, 4) * k)
		Sounds.Play("Hurt")
	end)

	-- extra remotes created by CombatService (not in the shared contract)
	task.spawn(function()
		local net = ReplicatedStorage:WaitForChild("CombatNet", 30)
		if net then
			lookRemote = net:WaitForChild("Look", 10) :: UnreliableRemoteEvent?
			crouchRemote = net:WaitForChild("SetCrouch", 10) :: RemoteEvent?
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	local priority = Enum.RenderPriority.Camera.Value
	RunService:BindToRenderStep("WeaponPreCamera", priority - 1, preCamera)
	RunService:BindToRenderStep("WeaponPostCamera", priority + 1, postCamera)
end

return WeaponController

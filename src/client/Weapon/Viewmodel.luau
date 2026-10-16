--!strict
-- Places one first-person viewmodel (built by ModelKit) every frame. Layers, in order:
--   camera * (hip <-> aim) * sway * bob * landing dip * kick spring * equip pose * action pose
-- then per-group offsets (mag, bolt, left arm) and the muzzle flash. One BulkMoveTo per frame.
-- Actions: reload (rifle + sniper), bolt cycle (sniper), slash (knife), throw (any).

local ModelKit = require(script.Parent:WaitForChild("ModelKit"))
local Spring = require(script.Parent:WaitForChild("Spring"))

local HIDDEN = CFrame.new(0, -1e5, 0)
local NO_OFFSET = CFrame.new()
local BOLT_SECONDS = 0.95
local SLASH_SECONDS = 0.38
local THROW_SECONDS = 0.6

local Viewmodel = {}
Viewmodel.__index = Viewmodel

export type Viewmodel = typeof(setmetatable(
	{} :: {
		Built: ModelKit.Built,
		Profile: ModelKit.Profile,
		Parts: { BasePart },
		CFrames: { CFrame },
		Sway: Spring.Spring,
		KickPos: Spring.Spring,
		KickRot: Spring.Spring,
		Land: Spring.Spring,
		BobPhase: number,
		Time: number,
		AimAlpha: number, -- eased 0..1 (drives FOV, spread, scope)
		AimProgress: number, -- linear 0..1 timeline behind AimAlpha
		AimWasIn: boolean,
		Settle: Spring.Spring,
		FlashAimed: boolean,
		EquipAlpha: number, -- 1 = lowered (drawing), 0 = ready
		ReloadStart: number?,
		BoltStart: number?,
		SlashStart: number?,
		SlashSide: number,
		ThrowStart: number?,
		FlashUntil: number,
		FlashRoll: number,
		LastCamera: CFrame?,
		Visible: boolean,
		MuzzleWorld: Vector3,
		LastVelY: number,
	},
	Viewmodel
))

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0 -> 1 over [a, b], held at 1 until c, back to 0 over [c, d]
local function hump(t: number, a: number, b: number, c: number, d: number): number
	if t <= a or t >= d then
		return 0
	elseif t < b then
		return smooth((t - a) / (b - a))
	elseif t <= c then
		return 1
	end
	return 1 - smooth((t - c) / (d - c))
end

function Viewmodel.new(parent: Instance, built: ModelKit.Built): Viewmodel
	built.Model.Parent = parent
	local parts = {}
	local cframes = {}
	for i, e in built.Entries do
		parts[i] = e.Part
		cframes[i] = HIDDEN
	end
	local self = setmetatable({
		Built = built,
		Profile = built.Profile,
		Parts = parts,
		CFrames = cframes,
		Sway = Spring.new(120, 14),
		KickPos = Spring.new(420, 26),
		KickRot = Spring.new(380, 24),
		Land = Spring.new(160, 16),
		BobPhase = 0,
		Time = 0,
		AimAlpha = 0,
		AimProgress = 0,
		AimWasIn = false,
		Settle = Spring.new(260, 15),
		FlashAimed = false,
		EquipAlpha = 1,
		ReloadStart = nil,
		BoltStart = nil,
		SlashStart = nil,
		SlashSide = 1,
		ThrowStart = nil,
		FlashUntil = 0,
		FlashRoll = 0,
		LastCamera = nil,
		Visible = true,
		MuzzleWorld = Vector3.zero,
		LastVelY = 0,
	}, Viewmodel)
	self:SetVisible(false)
	return self
end

function Viewmodel.Busy(self: Viewmodel): boolean
	return self.EquipAlpha > 0.02
		or self.ReloadStart ~= nil
		or self.BoltStart ~= nil
		or self.ThrowStart ~= nil
end

-- strength 1 = AK shot; sniper uses ~2.5. Aimed: little push-back, mostly a muzzle-up pitch so the
-- front post visibly lifts out of the rear notch and the spring brings it back.
function Viewmodel.Kick(self: Viewmodel, aiming: boolean, rng: Random, strength: number, flashSeconds: number)
	local pos = Vector3.new(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0.1, 0.4), 2.6) * strength
	local rot = Vector3.new(2.4, rng:NextNumber(-0.7, 0.7), rng:NextNumber(-1.4, 1.4)) * strength
	if aiming then
		pos *= 0.3
		rot *= Vector3.new(0.75, 0.3, 0.2)
	end
	self.KickPos:Impulse(pos)
	self.KickRot:Impulse(rot)
	self.FlashUntil = os.clock() + flashSeconds
	self.FlashRoll = rng:NextNumber(0, math.pi * 2)
	self.FlashAimed = aiming
	for i, p in self.Built.Petals do
		local show = not aiming and (rng:NextNumber() < 0.75 or i == 1)
		p.Transparency = if show then 0.1 else 1
	end
end

-- Caps the aim (sniper bolt cycle drops out of the scope).
function Viewmodel.CapAim(self: Viewmodel, value: number)
	self.AimProgress = math.min(self.AimProgress, value)
	self.AimAlpha = math.min(self.AimAlpha, value)
end

function Viewmodel.Impact(self: Viewmodel, strength: number)
	self.KickRot:Impulse(Vector3.new(0, 0, strength))
end

function Viewmodel.Draw(self: Viewmodel)
	self.EquipAlpha = 1
	self.ReloadStart, self.BoltStart, self.SlashStart, self.ThrowStart = nil, nil, nil, nil
	self.AimAlpha = 0
	self.AimProgress = 0
	self.AimWasIn = false
	self.LastCamera = nil
end

function Viewmodel.PlayReload(self: Viewmodel)
	self.ReloadStart = os.clock()
	self.BoltStart = nil
end

function Viewmodel.StopReload(self: Viewmodel)
	self.ReloadStart = nil
end

function Viewmodel.PlayBolt(self: Viewmodel)
	self.BoltStart = os.clock()
end

function Viewmodel.PlaySlash(self: Viewmodel)
	self.SlashStart = os.clock()
	self.SlashSide = -self.SlashSide
end

function Viewmodel.PlayThrow(self: Viewmodel)
	self.ThrowStart = os.clock()
end

function Viewmodel.SetVisible(self: Viewmodel, visible: boolean)
	if self.Visible == visible then
		return
	end
	self.Visible = visible
	if not visible then
		for i in self.CFrames do
			self.CFrames[i] = HIDDEN
		end
		workspace:BulkMoveTo(self.Parts, self.CFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

export type Input = {
	Camera: CFrame,
	Dt: number,
	AimTarget: number, -- 0..1
	Speed: number, -- horizontal studs/s
	VelocityY: number,
	Grounded: boolean,
	Crouching: boolean,
}

local function reloadPose(self: Viewmodel, t: number): (CFrame, CFrame, CFrame, CFrame)
	local tilt = hump(t, 0, 0.12, 0.78, 0.95)
	local rack = hump(t, 0.76, 0.81, 0.83, 0.88)
	local gunAnim = CFrame.new(-0.12 * tilt, 0.08 * tilt, 0.05 * tilt)
		* CFrame.Angles(math.rad(12 * tilt - 4 * rack), math.rad(-8 * tilt), math.rad(-28 * tilt))
	local rockOut = hump(t, 0.12, 0.2, 0.22, 0.3)
	local drop = if t < 0.22 then 0 elseif t < 0.4 then smooth((t - 0.22) / 0.18) else 0
	local away = if t >= 0.4 and t < 0.56 then 1 else 0
	local rise = if t >= 0.56 and t < 0.7 then 1 - smooth((t - 0.56) / 0.14) else 0
	local rockIn = hump(t, 0.66, 0.7, 0.71, 0.76)
	local down = drop * 1.4 + away * 2 + rise * 1.2
	local pivot = self.Profile.MagPivot or NO_OFFSET
	local magCF = pivot
		* CFrame.new(0, -down, down * 0.2)
		* CFrame.Angles(math.rad(-18 * rockOut - 14 * rockIn - 25 * rise), 0, 0)
		* pivot:Inverse()
	local grab = hump(t, 0.1, 0.22, 0.7, 0.8)
	local leftCF = CFrame.new(0.02, -0.18 * grab - down * 0.6, 0.55 * grab)
		* CFrame.Angles(math.rad(-20 * grab), 0, math.rad(-10 * grab))
	local boltCF = CFrame.new(0, 0, 0.32 * rack)
	return gunAnim, magCF, leftCF, boltCF
end

-- Sniper bolt: lift, pull back, push forward, lock down. Returns gun tilt + bolt offset.
local function boltPose(t: number): (CFrame, CFrame)
	local tilt = hump(t, 0, 0.12, 0.8, 1)
	local lift = hump(t, 0.12, 0.25, 0.68, 0.8)
	local back = hump(t, 0.25, 0.42, 0.45, 0.62)
	local pivot = CFrame.new(0.08, 0.06, 0.25)
	local boltCF = pivot
		* CFrame.new(0, 0, 0.38 * back)
		* CFrame.Angles(0, 0, math.rad(65 * lift))
		* pivot:Inverse()
	local gunAnim = CFrame.new(-0.05 * tilt, 0.05 * tilt, 0.08 * tilt)
		* CFrame.Angles(math.rad(6 * tilt + 3 * back), math.rad(-6 * tilt), math.rad(-14 * tilt))
	return gunAnim, boltCF
end

function Viewmodel.Update(self: Viewmodel, input: Input)
	local dt = math.min(input.Dt, 0.1)
	self.Time += dt
	local now = os.clock()
	local profile = self.Profile

	-- timed ADS: ease-out going in (fast start, soft landing), ease-in-out coming out
	local rifle = profile.Kind == "Rifle"
	local inSeconds = profile.AimInSeconds or 0.18
	local outSeconds = profile.AimOutSeconds or 0.14
	local entering = input.AimTarget > self.AimProgress
	if entering then
		self.AimProgress = math.min(input.AimTarget, self.AimProgress + dt / inSeconds)
	else
		self.AimProgress = math.max(input.AimTarget, self.AimProgress - dt / outSeconds)
	end
	local ap = self.AimProgress
	self.AimAlpha = if entering then 1 - (1 - ap) ^ 3 else smooth(ap)
	-- settle: a small overshoot the moment the sights land
	if ap >= 1 and not self.AimWasIn and rifle then
		self.Settle:Impulse(Vector3.new(-1.6, 0, 0.6))
	end
	self.AimWasIn = ap >= 1
	self.EquipAlpha = math.max(0, self.EquipAlpha - dt / math.max(profile.EquipSeconds, 0.05))
	local aim = self.AimAlpha
	local hideForAim = aim > 0.55
	if profile.AimHide and hideForAim ~= self.AimHidden then
		self.AimHidden = hideForAim
		for _, e in self.Built.Entries do
			if table.find(profile.AimHide, e.Part.Name) then
				e.Part.LocalTransparencyModifier = if hideForAim then 1 else 0
			end
		end
	end
	local equip = smooth(self.EquipAlpha)
	local still = 1 - aim * (if rifle then 0.93 else 0.8)
	-- entry roll/dip: peaks mid-transition, zero at both ends
	local transit = math.sin(math.pi * ap) * (if rifle then 1 else 0)
	local rollSign = if entering then 1 else -0.5
	local settle = self.Settle:Update(dt)
	local aimMotion = CFrame.new(0, -0.025 * transit + settle.X * 0.05, 0)
		* CFrame.Angles(math.rad(settle.X * 6), 0, math.rad(-7 * transit * rollSign + settle.Z * 15))

	-- sway: gun lags behind camera rotation
	local cam = input.Camera
	if self.LastCamera then
		local delta = self.LastCamera:ToObjectSpace(cam)
		local rx, ry = delta:ToEulerAnglesYXZ()
		self.Sway:Impulse(Vector3.new(-rx, -ry, 0) * 9)
	end
	self.LastCamera = cam
	local sway = self.Sway:Update(dt)
	sway = Vector3.new(math.clamp(sway.X, -0.25, 0.25), math.clamp(sway.Y, -0.25, 0.25), 0)
		* (1 - aim * (if rifle then 0.85 else 0.7))

	-- bob: figure-8 driven by move speed, plus idle breathing
	local moveAlpha = if input.Grounded then math.clamp(input.Speed / 16, 0, 1.3) else 0
	self.BobPhase += dt * (4 + input.Speed * 0.42)
	local p = self.BobPhase
	local bobAmp = moveAlpha * still * (if input.Crouching then 0.6 else 1)
	local bob = CFrame.new(math.sin(p) * 0.045 * bobAmp, -math.abs(math.cos(p)) * 0.04 * bobAmp, 0)
		* CFrame.Angles(0, 0, math.sin(p) * math.rad(1.6) * bobAmp)
	local breathe = CFrame.new(0, math.sin(self.Time * 1.7) * 0.006 * still, 0)

	-- landing dip
	if input.Grounded and self.LastVelY < -20 then
		self.Land:Impulse(Vector3.new(0, math.clamp(self.LastVelY * 0.04, -2.5, 0), 0))
	end
	self.LastVelY = input.VelocityY
	local land = self.Land:Update(dt)
	local airY = if input.Grounded then 0 else math.clamp(-input.VelocityY * 0.002, -0.05, 0.05)

	-- recoil kick
	local kp = self.KickPos:Update(dt)
	local kr = self.KickRot:Update(dt)
	local kick = CFrame.new(kp.X * 0.03, kp.Y * 0.02, kp.Z * 0.035)
		* CFrame.Angles(math.rad(kr.X * 1.6), math.rad(kr.Y), math.rad(kr.Z * 1.5))

	-- actions
	local magCF, boltCF, leftCF, gunAnim = NO_OFFSET, NO_OFFSET, NO_OFFSET, NO_OFFSET
	if self.ReloadStart then
		local t = (now - self.ReloadStart) / (profile.ReloadSeconds or 2)
		if t >= 1 then
			self.ReloadStart = nil
		else
			gunAnim, magCF, leftCF, boltCF = reloadPose(self, t)
			if profile.Kind == "Sniper" then
				local _, b = boltPose(math.clamp((t - 0.72) / 0.25, 0, 1))
				boltCF = b
			end
		end
	end
	if self.BoltStart then
		local t = (now - self.BoltStart) / BOLT_SECONDS
		if t >= 1 then
			self.BoltStart = nil
		else
			gunAnim, boltCF = boltPose(t)
		end
	end
	if self.SlashStart then
		local t = (now - self.SlashStart) / SLASH_SECONDS
		if t >= 1 then
			self.SlashStart = nil
		else
			local wind = hump(t, 0, 0.18, 0.2, 0.32)
			local swing = if t < 0.2
				then 0
				elseif t < 0.5 then smooth((t - 0.2) / 0.3)
				else 1 - smooth((t - 0.5) / 0.5)
			local s = self.SlashSide
			gunAnim = CFrame.new(0.25 * wind * s - 0.65 * swing * s, 0.15 * wind - 0.2 * swing, -0.35 * swing)
				* CFrame.Angles(
					math.rad(-10 * swing),
					math.rad(25 * wind * s - 70 * swing * s),
					math.rad(-40 * swing * s)
				)
		end
	end
	if self.ThrowStart then
		local t = (now - self.ThrowStart) / THROW_SECONDS
		if t >= 1 then
			self.ThrowStart = nil
		else
			if profile.Kind == "Grenade" then
				-- overhand: wind back, then out of view forward
				local back = hump(t, 0, 0.3, 0.32, 0.45)
				local out = if t < 0.32 then 0 else smooth((t - 0.32) / 0.25)
				gunAnim = CFrame.new(0.2 * back, 0.45 * back + 0.3 * out, 0.4 * back - 1.4 * out)
					* CFrame.Angles(math.rad(50 * back - 60 * out), 0, 0)
			else
				local dip = hump(t, 0, 0.2, 0.55, 1)
				gunAnim = CFrame.new(0.15 * dip, -0.35 * dip, 0.1 * dip)
					* CFrame.Angles(math.rad(-25 * dip), math.rad(15 * dip), math.rad(-15 * dip))
				local swing = hump(t, 0.05, 0.3, 0.35, 0.7)
				leftCF = CFrame.new(-0.3 * swing, 0.5 * swing, -0.4 * swing)
					* CFrame.Angles(math.rad(50 * swing), 0, 0)
			end
		end
	end

	local base = if profile.Aim then profile.Hip:Lerp(profile.Aim, aim) else profile.Hip
	local crouchTilt = if input.Crouching then CFrame.Angles(0, 0, math.rad(-4) * still) else NO_OFFSET
	-- no drift layer: the iron sights must sit exactly on the camera ray (that's where bullets go)
	local gun = cam
		* base
		* aimMotion
		* CFrame.Angles(sway.X, sway.Y, sway.Y * 0.8)
		* CFrame.new(sway.Y * -0.15, sway.X * 0.15, 0)
		* bob
		* breathe
		* CFrame.new(0, land.Y * 0.04 + airY, 0)
		* kick
		* crouchTilt
		* NO_OFFSET:Lerp(profile.Lowered, equip)
		* gunAnim

	local groups: { [string]: CFrame } = {
		Gun = gun,
		RightArm = gun,
		Mag = gun * magCF,
		Bolt = gun * boltCF,
		LeftArm = gun * leftCF,
	}
	local muzzle = gun * (profile.Muzzle or NO_OFFSET)
	self.MuzzleWorld = muzzle.Position
	local flashOn = now < self.FlashUntil and self.Visible
	groups.Flash = if flashOn then muzzle * CFrame.Angles(0, 0, self.FlashRoll) else HIDDEN

	if not self.Visible then
		return
	end
	for i, e in self.Built.Entries do
		self.CFrames[i] = groups[e.Group] * e.Local
	end
	for _, f in self.Built.FlashParts do
		if f.Name == "FlashCore" or f.Name == "FlashPlume" then
			local hide = not flashOn or (self.FlashAimed and f.Name == "FlashPlume")
			f.Transparency = if hide then 1 elseif self.FlashAimed then 0.5 else 0.05
		end
	end
	workspace:BulkMoveTo(self.Parts, self.CFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

return Viewmodel

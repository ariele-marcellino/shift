--!strict
-- Weapon sound ids. 0 = no sound yet: every play call silently skips it. A string is used as-is
-- (e.g. a built-in rbxasset:// path). Filled ids were verified public via the Roblox catalog API;
-- PSE = ProSoundEffects, APM = APMOfficial (Roblox's licensed sound partners).

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.Ids = {
	Fire = 9113180776, -- PSE "Assault Rifle 9", cut to one shot (Sounds.MaxSeconds). Your 6 s "AK 47 Gun Sound Effects" (72690535286909) was a long clip.
	FireDistant = 0, -- optional far "crack/boom" layered for remote shots > 60 studs
	SniperFire = 138705939667182, -- yours: "Awp_Fire" (was PSE 9112912106 pitched down)
	SniperBolt = 9116357355, -- PSE "Machine Gun Bolt 2"
	ScopeIn = 139333852575036, -- yours: "scope_sniper"
	SniperReload = 5931578290, -- yours: "AWP Reload" (full sniper reload)
	KnifeSlash = 129582509517716, -- yours: "Knife swing" (every swing; was PSE 9119697796)
	KnifeHit = 108673879396403, -- yours: "Knife Stab" (knife hits a player; was "melee knife hit 1" 124216736896680)
	Equip = 81102724493720, -- yours: "cs go equip gun sound effect"
	FragPin = 9114659662, -- PSE "Grenade Pull Pin 1"
	FragExplode = 134825578212679, -- yours: "Grenade Explosion_01" (was built-in impact_explosion_03)
	Dry = 9117048600, -- PSE "Nail Gun Clicking 2"
	-- (Call of Duty "M1911 Reloading Sound" 205151554 removed: copyright, 2026-10-16.)
	MagOut = 9116357621, -- PSE "Machine Gun Bolt 4" (AK reload start)
	MagIn = 9116357383, -- PSE "Machine Gun Bolt 3"
	BoltRack = 95399549465513, -- yours: "ak47_bolt" (was PSE 9116357621)
	Draw = 9116190959, -- PSE "Knife Fast Scraping Draws Pull Out 17" (knife out)
	Holster = 0,
	AimIn = 139333852575036, -- yours: "scope_sniper" (same as ScopeIn: AK aim uses it too)
	Throw = 113843307673576, -- yours: "grenade_throw"
	SmokePop = 127104120528034, -- yours: "smoke_stack_hiss" (was PSE 9116496074)
	FlashlightClick = 9114481274, -- PSE "Flashlight Switch Plastic Slides On Off 13"
	HitBody = 9114313981, -- PSE "Enamel Hit 15"
	HitHead = 138750331387064, -- yours: "rust_headshot" (was PSE 9126073001)
	Kill = 116995124869046, -- yours: "warzone kill sound" (was Roblox "Notification High" 17208361335)
	ImpactWorld = 0,
	ImpactPlayer = 0,
	Hurt = 0, -- local player took damage
	-- Shell casings raining down: once per spray when 10+ shots land within ~1 s (WeaponController).
	ShellRain = 76122229198747, -- yours: ".50BMG_Shell-2"
	Ricochet = 9118168612, -- PSE "Ricochet Metal 1" (bullet deflected by an enemy spawn barrier)
} :: { [string]: number | string }

-- Base playback speed per sound (pitch), multiplied with any per-play pitch. Lower = deeper.
Sounds.Pitch = {} :: { [string]: number }

-- Hard cap on how long a sound plays (fades out over the last 0.05 s). Keeps every AK bullet a
-- single short shot even if the file has a long tail.
Sounds.MaxSeconds = {
	Fire = 0.4,
} :: { [string]: number }

Sounds.Volume = {
	ScopeIn = 0.966, -- +15% then +40% (owner, 2026-10-16; default 0.6)
	AimIn = 0.966,
	Fire = 0.9,
	SniperFire = 1,
	FragExplode = 1,
	FireDistant = 0.7,
	HitHead = 0.8,
	HitBody = 0.6,
	Kill = 0.9, -- -10% (owner, 2026-10-16)
	ShellRain = 1.89, -- +50%, +40%, then +50% (owner, 2026-10-16; default 0.6)
	Ricochet = 0.7,
} :: { [string]: number }

-- Hit sounds (HitBody / HitHead) when the hit came from the sniper: -15% (owner, 2026-10-16).
Sounds.SniperHitScale = 0.85

local TweenService = game:GetService("TweenService")

local cache: { [string]: Sound } = {}

local function capLength(name: string, s: Sound)
	local max = Sounds.MaxSeconds[name]
	if not max then
		return
	end
	task.delay(max, function()
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(0.05), { Volume = 0 }):Play()
			task.delay(0.06, function()
				s:Stop()
			end)
		end
	end)
end

local function template(name: string): Sound?
	local id = Sounds.Ids[name]
	if not id or id == 0 or id == "" then
		return nil
	end
	local s = cache[name]
	if not s then
		local created = Instance.new("Sound")
		created.Name = name
		created.SoundId = if type(id) == "string" then id else "rbxassetid://" .. tostring(id)
		created.Volume = Sounds.Volume[name] or 0.6
		cache[name] = created
		s = created
	end
	return s
end

-- 2D sound (UI / own gun). pitch and volumeScale (x the configured volume) optional.
function Sounds.Play(name: string, pitch: number?, volumeScale: number?)
	local t = template(name)
	if not t then
		return
	end
	local s = t:Clone()
	s.PlaybackSpeed = (pitch or 1) * (Sounds.Pitch[name] or 1)
	s.Volume = t.Volume * (volumeScale or 1)
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	capLength(name, s)
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- 3D sound at a world position (needs an anchor part supplied by Effects).
function Sounds.PlayAt(name: string, anchor: BasePart, position: Vector3, pitch: number?, rolloffMax: number?)
	local t = template(name)
	if not t then
		return
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = anchor
	local s = t:Clone()
	s.PlaybackSpeed = (pitch or 1) * (Sounds.Pitch[name] or 1)
	s.RollOffMaxDistance = rolloffMax or 300
	s.RollOffMinDistance = 8
	s.Parent = att
	s:Play()
	capLength(name, s)
	task.delay(6, function()
		att:Destroy()
	end)
end

-- Looping 3D sound attached to a part for `seconds` (fades out over the last `fade` seconds) or
-- until the part is destroyed. Used for the smoke hiss, which lasts as long as the cloud.
function Sounds.LoopOn(name: string, part: BasePart, seconds: number, fade: number?)
	local t = template(name)
	if not t then
		return
	end
	local s = t:Clone()
	s.Looped = true
	s.PlaybackSpeed = Sounds.Pitch[name] or 1
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 200
	s.Parent = part
	s:Play()
	local fadeSeconds = fade or 1.5
	task.delay(math.max(0, seconds - fadeSeconds), function()
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(fadeSeconds), { Volume = 0 }):Play()
			task.delay(fadeSeconds, function()
				s:Destroy()
			end)
		end
	end)
end

return Sounds

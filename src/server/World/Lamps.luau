--!strict
-- Registry of every switchable fixture: breakable lamps (tag "BreakableLamp", attribute LampId) and
-- unbreakable powered tubes (so a corridor power failure can switch them). State is plain instance
-- properties + attributes, so it replicates to late joiners automatically.
--
-- Attributes written (on the fixture part AND each light): Broken (bool), Powered (bool),
-- Level (number, LightDirector zone level), Scale (number, LightDirector per-lamp drift) and Zone
-- (string, static). Final brightness = BaseBrightness * Level * Scale.
-- The client AmbienceController never flickers a light that is disabled or Broken.

local CollectionService = game:GetService("CollectionService")

local Style = require(script.Parent.Style)

export type Lamp = {
	Id: string,
	Part: BasePart,
	Lights: { Light },
	Emitters: { ParticleEmitter },
	Breakable: boolean,
	PowerGroup: string?,
	Zone: string?, -- LightDirector zone id ("B.Hall", "C.Junction", ...)
	Level: number, -- zone level: ~1 On, Dim level, 0 Off
	Scale: number, -- per-lamp drift on top of the zone level (1 = none)
	Broken: boolean,
	Powered: boolean,
	OnColor: Color3,
	OnMaterial: Enum.Material,
	OnTransparency: number,
	OnCFrame: CFrame,
	Sparks: ParticleEmitter?,
	Glass: ParticleEmitter?,
	Token: number, -- bumps on every state change so delayed effects can bail out
}

local Lamps = {}

local byId: { [string]: Lamp } = {}
local order: { Lamp } = {}

-- Sound ids: none verified yet. 0 = skipped (no errors). Fill in with a licensed/verified asset id.
Lamps.Sounds = {
	-- A small fixture breaking + an electrical spark (matches the spark/glass effect). Both PSE,
	-- verified public. Was Roblox "glassbreak.wav" 12222005 (a big window crash: didn't fit).
	Break = 9119913393, -- PSE "Taillight Break 2"
	Spark = 9116275998, -- PSE "Lightning Flashes Quick Electrical Bursts 13"
}

local function makeBreakFx(part: BasePart): (ParticleEmitter, ParticleEmitter)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "BreakSparks"
	sparks.Enabled = false
	sparks.Rate = 0
	sparks.Texture = Style.Textures.Sparkle
	sparks.Lifetime = NumberRange.new(0.25, 0.7)
	sparks.Speed = NumberRange.new(8, 18)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.Acceleration = Vector3.new(0, -45, 0)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 40))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.EmissionDirection = Enum.NormalId.Bottom
	sparks.Parent = part

	local glass = Instance.new("ParticleEmitter")
	glass.Name = "BreakGlass"
	glass.Enabled = false
	glass.Rate = 0
	glass.Texture = Style.Textures.Sparkle
	glass.Lifetime = NumberRange.new(0.6, 1.1)
	glass.Speed = NumberRange.new(3, 9)
	glass.SpreadAngle = Vector2.new(70, 70)
	glass.Acceleration = Vector3.new(0, -70, 0)
	glass.Size = NumberSequence.new(0.18)
	glass.Rotation = NumberRange.new(0, 360)
	glass.RotSpeed = NumberRange.new(-300, 300)
	glass.Color = ColorSequence.new(Color3.fromRGB(220, 230, 235))
	glass.LightEmission = 0.2
	glass.LightInfluence = 0.6
	glass.EmissionDirection = Enum.NormalId.Bottom
	glass.Parent = part
	return sparks, glass
end

local function setAttrs(lamp: Lamp)
	lamp.Part:SetAttribute("Broken", lamp.Broken)
	lamp.Part:SetAttribute("Powered", lamp.Powered)
	lamp.Part:SetAttribute("Level", lamp.Level)
	lamp.Part:SetAttribute("Scale", lamp.Scale)
	for _, light in lamp.Lights do
		light:SetAttribute("Broken", lamp.Broken)
		light:SetAttribute("Powered", lamp.Powered)
		light:SetAttribute("Level", lamp.Level)
		light:SetAttribute("Scale", lamp.Scale)
	end
end

-- Push the lamp's current state into its instances.
local function apply(lamp: Lamp)
	lamp.Token += 1
	-- Attributes first: the client checks Broken before touching a light, and replication keeps order.
	setAttrs(lamp)
	local lit = lamp.Powered and not lamp.Broken and lamp.Level > 0
	local value = math.max(lamp.Level * lamp.Scale, 0)
	local part = lamp.Part
	if lamp.Broken then
		part.Color = Style.Broken.Color
		part.Material = Style.Broken.Material
		part.Transparency = Style.Broken.Transparency
		-- A broken tube hangs slightly askew.
		local tilt = if lamp.Id:len() % 2 == 0 then 7 else -7
		part.CFrame = lamp.OnCFrame * CFrame.Angles(math.rad(tilt * 0.4), 0, math.rad(tilt))
	elseif lamp.Powered and lamp.Level <= 0 then
		-- Zone switched off: stays Neon but near-black so the client fade looks continuous.
		part.Color = Style.ZoneOffColor
		part.Material = lamp.OnMaterial
		part.Transparency = lamp.OnTransparency
		part.CFrame = lamp.OnCFrame
	elseif not lit then
		part.Color = Style.Surf.TubeOff.Color
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = lamp.OnTransparency
		part.CFrame = lamp.OnCFrame
	else
		part.Color = if value >= 1
			then lamp.OnColor
			else Style.ZoneOffColor:Lerp(lamp.OnColor, 0.4 + 0.6 * value)
		part.Material = lamp.OnMaterial
		part.Transparency = lamp.OnTransparency
		part.CFrame = lamp.OnCFrame
	end
	for _, light in lamp.Lights do
		local base = (light:GetAttribute("BaseBrightness") :: number?) or light.Brightness
		light.Brightness = base * value
		light.Enabled = lit
	end
	for _, emitter in lamp.Emitters do
		emitter.Enabled = lit
	end
	local gui = part:FindFirstChildOfClass("SurfaceGui")
	if gui then
		gui.Enabled = lit
	end
end

export type RegisterArgs = {
	Id: string,
	Part: BasePart,
	Lights: { Light },
	Emitters: { ParticleEmitter }?,
	Breakable: boolean,
	PowerGroup: string?,
	Zone: string?,
}

function Lamps.Register(args: RegisterArgs): Lamp
	assert(byId[args.Id] == nil, "Duplicate lamp id " .. args.Id)
	local part = args.Part
	local lamp: Lamp = {
		Id = args.Id,
		Part = part,
		Lights = args.Lights,
		Emitters = args.Emitters or {},
		Breakable = args.Breakable,
		PowerGroup = args.PowerGroup,
		Zone = args.Zone,
		Level = 1,
		Scale = 1,
		Broken = false,
		Powered = true,
		OnColor = part.Color,
		OnMaterial = part.Material,
		OnTransparency = part.Transparency,
		OnCFrame = part.CFrame,
		Sparks = nil,
		Glass = nil,
		Token = 0,
	}
	part:SetAttribute("LampId", args.Id)
	if args.Zone then
		part:SetAttribute("Zone", args.Zone)
	end
	for _, light in args.Lights do
		light:SetAttribute("LampId", args.Id)
		if args.Zone then
			light:SetAttribute("Zone", args.Zone)
			CollectionService:AddTag(light, "ZoneLight")
		end
	end
	if args.Breakable then
		CollectionService:AddTag(part, "BreakableLamp")
		lamp.Sparks, lamp.Glass = makeBreakFx(part)
	end
	byId[args.Id] = lamp
	table.insert(order, lamp)
	setAttrs(lamp)
	return lamp
end

function Lamps.Get(id: string): Lamp?
	return byId[id]
end

function Lamps.All(): { Lamp }
	return order
end

function Lamps.IsLit(id: string): boolean
	local lamp = byId[id]
	return lamp ~= nil and lamp.Powered and not lamp.Broken and lamp.Level > 0
end

-- Returns true if the lamp was intact and is now broken. Unknown / unbreakable / already broken ids
-- are ignored (safe to call with exploiter garbage).
function Lamps.Break(id: string): boolean
	if type(id) ~= "string" then
		return false
	end
	local lamp = byId[id]
	if not lamp or not lamp.Breakable or lamp.Broken then
		return false
	end
	local wasLit = lamp.Powered and lamp.Level > 0
	lamp.Broken = true
	setAttrs(lamp)
	-- Pop: a short overbright flash, then dark. Sparks + glass shards fall from the fixture.
	if wasLit then
		for _, light in lamp.Lights do
			local base = (light:GetAttribute("BaseBrightness") :: number?) or light.Brightness
			light.Brightness = base * 3
		end
	end
	if lamp.Sparks then
		lamp.Sparks:Emit(if wasLit then 28 else 10)
	end
	if lamp.Glass then
		lamp.Glass:Emit(12)
	end
	-- { id, volume, pitch }; kept quiet (user found volume 0.8 too loud)
	for _, entry in { { Lamps.Sounds.Break, 0.3, 1.15 }, { Lamps.Sounds.Spark, 0.18, 1 } } do
		local soundId, volume, pitch = entry[1], entry[2], entry[3]
		if soundId ~= 0 then
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://" .. tostring(soundId)
			sound.RollOffMinDistance = 5
			sound.RollOffMaxDistance = 80
			sound.Volume = volume
			sound.PlaybackSpeed = pitch
			sound.Parent = lamp.Part
			sound:Play()
			task.delay(4, function()
				sound:Destroy()
			end)
		end
	end
	local token = lamp.Token + 1
	lamp.Token = token
	task.delay(if wasLit then 0.07 else 0, function()
		if lamp.Token == token and lamp.Broken then
			apply(lamp)
		end
	end)
	return true
end

function Lamps.SetPower(group: string, on: boolean)
	for _, lamp in order do
		if lamp.PowerGroup == group and lamp.Powered ~= on then
			lamp.Powered = on
			apply(lamp)
		end
	end
end

-- LightDirector: set every lamp in a zone to a level (broken lamps stay broken).
function Lamps.SetZoneLevel(zone: string, level: number)
	for _, lamp in order do
		if lamp.Zone == zone and lamp.Level ~= level then
			lamp.Level = level
			apply(lamp)
		end
	end
end

-- LightDirector drift: one lamp's own brightness multiplier (broken / off lamps keep it for later).
function Lamps.SetScale(id: string, scale: number)
	local lamp = byId[id]
	if lamp and math.abs(lamp.Scale - scale) > 1e-3 then
		lamp.Scale = scale
		apply(lamp)
	end
end

-- Current light output relative to the default (0 when broken / unpowered / zone off).
function Lamps.Output(id: string): number
	local lamp = byId[id]
	if not lamp or lamp.Broken or not lamp.Powered then
		return 0
	end
	return math.max(lamp.Level * lamp.Scale, 0)
end

-- Unique zone ids in registration order.
function Lamps.Zones(): { string }
	local seen, list = {}, {}
	for _, lamp in order do
		local zone = lamp.Zone
		if zone and not seen[zone] then
			seen[zone] = true
			table.insert(list, zone)
		end
	end
	return list
end

function Lamps.ResetAll()
	for _, lamp in order do
		lamp.Broken = false
		lamp.Powered = true
		lamp.Level = 1
		lamp.Scale = 1
		apply(lamp)
	end
end

function Lamps.BreakableList(): { Lamp }
	local list = {}
	for _, lamp in order do
		if lamp.Breakable then
			table.insert(list, lamp)
		end
	end
	return list
end

return Lamps

--!strict
-- COD-style grenade flight shared by frags and smokes (Tuning.Throw), on the server (the real
-- grenade) and the client (the thrower's instant local "ghost", WeaponController). Launched from
-- the right hand, LaunchAngle degrees above the aim line, under lighter-than-world gravity (Gravity)
-- so the arc is a readable lob, with a dead bounce (Physics) so it skips once or twice and settles
-- near where it lands instead of pinballing down the corridor.

local Tuning = require(script.Parent:WaitForChild("Config"):WaitForChild("Tuning"))

local Lob = {}

-- Right-hand release point relative to the eye (studs): forward, right, down.
local HAND_FORWARD, HAND_RIGHT, HAND_DOWN = 1.1, 0.7, 0.4

-- Low bounce, high grip; the large weights make the grenade's own values win over the floor's.
function Lob.Physics(density: number): PhysicalProperties
	return PhysicalProperties.new(density, 1, 0.15, 100, 100)
end

-- Where the grenade leaves the right hand for an eye at `origin` looking along `direction`; pulled
-- back in front of a wall the thrower is hugging. `params` = raycast filter (thrower, fx folders).
function Lob.HandStart(origin: Vector3, direction: Vector3, params: RaycastParams): Vector3
	local d = direction.Unit
	local right = d:Cross(Vector3.yAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	local hand = origin + d * HAND_FORWARD + right * HAND_RIGHT - Vector3.yAxis * HAND_DOWN
	local offset = hand - origin
	local block = workspace:Raycast(origin, offset * 1.3, params)
	if block then
		return block.Position - offset.Unit * 0.45
	end
	return hand
end

-- `direction` tilted up by LaunchAngle (in its vertical plane), scaled to `speed`.
function Lob.Velocity(direction: Vector3, speed: number): Vector3
	local d = direction.Unit
	local axis = d:Cross(Vector3.yAxis)
	if axis.Magnitude < 1e-3 then
		return d * speed -- straight up / down: nothing to tilt
	end
	axis = axis.Unit
	local a = math.rad(Tuning.Throw.LaunchAngle)
	-- Rodrigues rotation about the right-hand axis: a positive angle pitches the aim upwards
	local tilted = d * math.cos(a) + axis:Cross(d) * math.sin(a)
	return tilted.Unit * speed
end

-- Fly a released grenade `seconds` ahead along its arc (no bounces): the server uses this to start
-- the real grenade where the thrower's screen already shows it (their ping). Stops short of the
-- first thing in the way.
function Lob.Advance(
	position: Vector3,
	velocity: Vector3,
	seconds: number,
	params: RaycastParams
): (Vector3, Vector3)
	if seconds <= 0 then
		return position, velocity
	end
	local g = Vector3.new(0, -Tuning.Throw.Gravity, 0)
	local steps = math.max(1, math.ceil(seconds / 0.03))
	local dt = seconds / steps
	local p, v = position, velocity
	for _ = 1, steps do
		local nextV = v + g * dt
		local move = (v + nextV) * 0.5 * dt
		local hit = workspace:Raycast(p, move + move.Unit * 0.3, params)
		if hit then
			return p, v -- about to touch something: let the physics take it from here
		end
		p, v = p + move, nextV
	end
	return p, v
end

-- Launch `part` (already parented; server-owned on the server) with `velocity` under the grenade
-- gravity.
function Lob.Launch(part: BasePart, velocity: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = "LobGravity"
	attachment.Parent = part
	local force = Instance.new("VectorForce")
	force.Name = "LobGravity"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	-- cancel part of the world gravity so the net pull is Tuning.Throw.Gravity
	force.Force = Vector3.new(0, part.AssemblyMass * (workspace.Gravity - Tuning.Throw.Gravity), 0)
	force.Parent = part
	part.AssemblyLinearVelocity = velocity
end

-- Throw strength that lands a flat-aimed lob (LaunchAngle above horizontal) on `target` from
-- `origin` at full speed `speed`. For bots; clamped to the player range.
function Lob.StrengthFor(origin: Vector3, target: Vector3, speed: number): number
	local cfg = Tuning.Throw
	local offset = target - origin
	local d = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local h = offset.Y
	local a = math.rad(cfg.LaunchAngle)
	local denom = 2 * math.cos(a) ^ 2 * (d * math.tan(a) - h)
	if d < 0.5 or denom <= 0 then
		return 1
	end
	local v = math.sqrt(cfg.Gravity * d * d / denom)
	return math.clamp(v / speed, cfg.MinStrength, 1)
end

return Lob

--!strict
-- Damped Vector3 spring (semi-implicit Euler, fixed sub-steps so it is frame-rate independent).
local Spring = {}
Spring.__index = Spring

export type Spring = typeof(setmetatable(
	{} :: {
		Position: Vector3,
		Velocity: Vector3,
		Target: Vector3,
		Stiffness: number,
		Damping: number,
	},
	Spring
))

function Spring.new(stiffness: number, damping: number): Spring
	return setmetatable({
		Position = Vector3.zero,
		Velocity = Vector3.zero,
		Target = Vector3.zero,
		Stiffness = stiffness,
		Damping = damping,
	}, Spring)
end

function Spring.Impulse(self: Spring, velocity: Vector3)
	self.Velocity += velocity
end

function Spring.Reset(self: Spring)
	self.Position = Vector3.zero
	self.Velocity = Vector3.zero
end

function Spring.Update(self: Spring, dt: number): Vector3
	dt = math.min(dt, 0.1)
	local steps = math.max(1, math.ceil(dt * 240))
	local h = dt / steps
	for _ = 1, steps do
		local force = (self.Target - self.Position) * self.Stiffness - self.Velocity * self.Damping
		self.Velocity += force * h
		self.Position += self.Velocity * h
	end
	return self.Position
end

return Spring

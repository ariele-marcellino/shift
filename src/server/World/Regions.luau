--!strict
-- Spatial queries about light and water.
--   Dark boxes: rooms that are dark by design (lit only by doorway lamps) -> always dark.
--   Zone lights: the light sources of lit/dim areas. A point outside every dark box is "dark" when no
--   active zone light covers it (all nearby tubes shot out, or corridor power failed).

local Lamps = require(script.Parent.Lamps)

export type Box = { Min: Vector3, Max: Vector3 }
type ZoneLight = { Position: Vector3, Radius: number, R2: number, LampId: string? }

local Regions = {}

local darkBoxes: { Box } = {}
local waterBoxes: { Box } = {}
local zoneLights: { ZoneLight } = {}

local function box(a: Vector3, b: Vector3): Box
	return {
		Min = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)),
		Max = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)),
	}
end

local function inside(b: Box, p: Vector3, padY: number): boolean
	return p.X >= b.Min.X
		and p.X <= b.Max.X
		and p.Z >= b.Min.Z
		and p.Z <= b.Max.Z
		and p.Y >= b.Min.Y - padY
		and p.Y <= b.Max.Y + padY
end

function Regions.AddDark(a: Vector3, b: Vector3)
	table.insert(darkBoxes, box(a, b))
end

function Regions.AddWater(a: Vector3, b: Vector3)
	table.insert(waterBoxes, box(a, b))
end

-- LampId nil = always on (emergency lights).
function Regions.AddZoneLight(position: Vector3, radius: number, lampId: string?)
	table.insert(zoneLights, { Position = position, Radius = radius, R2 = radius * radius, LampId = lampId })
end

function Regions.IsDark(position: Vector3): boolean
	for _, b in darkBoxes do
		if inside(b, position, 2) then
			return true
		end
	end
	for _, zl in zoneLights do
		local dx, dz = position.X - zl.Position.X, position.Z - zl.Position.Z
		if dx * dx + dz * dz <= zl.R2 and (zl.LampId == nil or Lamps.IsLit(zl.LampId)) then
			return false
		end
	end
	return true
end

-- Dark, or only lit by lamps running below `threshold` of their default output (dimmed zones,
-- drifted-down lamps). Used by the horror director, not by gameplay (bots / nav use IsDark).
function Regions.IsGloomy(position: Vector3, threshold: number): boolean
	for _, b in darkBoxes do
		if inside(b, position, 2) then
			return true
		end
	end
	for _, zl in zoneLights do
		local dx, dz = position.X - zl.Position.X, position.Z - zl.Position.Z
		if dx * dx + dz * dz <= zl.R2 then
			if zl.LampId == nil or Lamps.Output(zl.LampId) >= threshold then
				return false
			end
		end
	end
	return true
end

function Regions.IsInWater(position: Vector3): boolean
	for _, b in waterBoxes do
		if inside(b, position, 3) then
			return true
		end
	end
	return false
end

return Regions

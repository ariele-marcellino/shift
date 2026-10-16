--!strict
-- Post-build pass that removes z-fighting (flickering surfaces) anywhere in the facility.
--
-- Z-fighting happens when two visible parts have a face on exactly the same plane, facing the same
-- way, over an overlapping area (e.g. a window sill flush with the wall it sits in, a crate pressed
-- flat against a wall, a trim strip on a wall face). For every such pair we pull the smaller part's
-- face inward by EPS, so it hides just inside the bigger part. Back-to-back faces (one part's max on
-- the other's min) never flicker and are left alone.
--
-- Only axis-aligned Block parts are handled (that's everything the layout builds). Parts that move
-- or get restored to stored CFrames (hinges, lamp fixtures) are never resized; the other part of the
-- pair is adjusted instead, or the pair is skipped if both are protected.

local ZFightFix = {}

local EPS = 0.01 -- how far a face is pulled in (invisible at play distances)
local PLANE_TOL = 1e-3 -- faces closer than this are "the same plane"
local MIN_OVERLAP = 1e-3 -- overlap area side length that counts as visible

type Box = {
	Part: BasePart,
	Min: Vector3,
	Max: Vector3,
	Protected: boolean,
	Volume: number,
}

local AXES = { "X", "Y", "Z" }

-- The two other axes of each axis, in AXES order (constants: no per-pair allocation).
local OTHERS = { X = { "Y", "Z" }, Y = { "X", "Z" }, Z = { "X", "Y" } }
local SIDES = { 1, -1 }
local NONE: { string } = {}

local function comp(v: Vector3, axis: string): number
	return if axis == "X" then v.X elseif axis == "Y" then v.Y else v.Z
end

-- World AABB for parts whose rotation is a multiple of 90° on every axis; nil otherwise.
local function aabb(part: BasePart): (Vector3?, Vector3?)
	local cf = part.CFrame
	local function aligned(v: Vector3): boolean
		return math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) >= 0.999
	end
	if not (aligned(cf.RightVector) and aligned(cf.UpVector) and aligned(cf.LookVector)) then
		return nil, nil
	end
	-- Half extents along world axes from the (90°-aligned) basis vectors.
	local s = part.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, -cf.LookVector
	local h = Vector3.new(
		math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	)
	local p = cf.Position
	return p - h, p + h
end

-- Pull one face of `part` (world axis `axis`, side +1 = max face, -1 = min face) inward by `amount`.
local function pullFace(part: BasePart, axis: string, side: number, amount: number)
	local cf = part.CFrame
	local worldAxis = if axis == "X"
		then Vector3.xAxis
		elseif axis == "Y" then Vector3.yAxis
		else Vector3.zAxis
	-- Which local axis points along this world axis?
	local localDir = cf:VectorToObjectSpace(worldAxis)
	local size = part.Size
	if math.abs(localDir.X) > 0.5 then
		size -= Vector3.new(amount, 0, 0)
	elseif math.abs(localDir.Y) > 0.5 then
		size -= Vector3.new(0, amount, 0)
	else
		size -= Vector3.new(0, 0, amount)
	end
	if math.min(size.X, size.Y, size.Z) <= 0.002 then
		return -- too thin to shrink safely
	end
	part.Size = size
	part.CFrame = cf - worldAxis * (side * amount / 2)
end

local function overlap1(aMin: number, aMax: number, bMin: number, bMax: number): number
	return math.min(aMax, bMax) - math.max(aMin, bMin)
end

-- Fix every coplanar same-facing overlap under `root`. `isProtected(part)` marks parts that must
-- not be resized. Returns the number of faces adjusted.
function ZFightFix.Run(root: Instance, isProtected: (BasePart) -> boolean): number
	local boxes: { Box } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Part") and d.Shape == Enum.PartType.Block and d.Transparency < 1 then
			local mn, mx = aabb(d)
			if mn and mx then
				local size = mx - mn
				table.insert(boxes, {
					Part = d,
					Min = mn,
					Max = mx,
					Protected = isProtected(d),
					Volume = size.X * size.Y * size.Z,
				})
			end
		end
	end

	-- Spatial hash on X/Z cells to avoid checking every pair.
	local CELL = 16
	local grid: { [string]: { number } } = {}
	for i, b in boxes do
		for cx = math.floor(b.Min.X / CELL), math.floor(b.Max.X / CELL) do
			for cz = math.floor(b.Min.Z / CELL), math.floor(b.Max.Z / CELL) do
				local key = cx .. "," .. cz
				local list = grid[key]
				if not list then
					list = {}
					grid[key] = list
				end
				table.insert(list, i)
			end
		end
	end

	local fixed = 0
	-- Pair key i * N + j: lists are filled in ascending box order, so i < j always.
	local N = #boxes + 1
	local seen: { [number]: boolean } = {}
	for _, list in grid do
		for ai = 1, #list do
			for bi = ai + 1, #list do
				local i, j = list[ai], list[bi]
				local pairKey = i * N + j
				if not seen[pairKey] then
					seen[pairKey] = true
					local a, b = boxes[i], boxes[j]
					-- Cheap reject: an axis can only fire when both other axes overlap, so with two or
					-- more non-overlapping axes nothing fires (fixes only ever shrink parts).
					local apart = 0
					if overlap1(a.Min.X, a.Max.X, b.Min.X, b.Max.X) <= MIN_OVERLAP then
						apart += 1
					end
					if overlap1(a.Min.Y, a.Max.Y, b.Min.Y, b.Max.Y) <= MIN_OVERLAP then
						apart += 1
					end
					if overlap1(a.Min.Z, a.Max.Z, b.Min.Z, b.Max.Z) <= MIN_OVERLAP then
						apart += 1
					end
					for _, axis in if apart >= 2 then NONE else AXES do
						-- the two other axes must overlap with positive area
						local others = OTHERS[axis]
						local o1 = overlap1(
							comp(a.Min, others[1]),
							comp(a.Max, others[1]),
							comp(b.Min, others[1]),
							comp(b.Max, others[1])
						)
						local o2 = overlap1(
							comp(a.Min, others[2]),
							comp(a.Max, others[2]),
							comp(b.Min, others[2]),
							comp(b.Max, others[2])
						)
						if o1 > MIN_OVERLAP and o2 > MIN_OVERLAP then
							for _, side in SIDES do
								local fa = if side == 1 then comp(a.Max, axis) else comp(a.Min, axis)
								local fb = if side == 1 then comp(b.Max, axis) else comp(b.Min, axis)
								if math.abs(fa - fb) < PLANE_TOL then
									-- Shrink the smaller unprotected part.
									local target: Box? = nil
									if a.Protected and b.Protected then
										target = nil
									elseif a.Protected then
										target = b
									elseif b.Protected then
										target = a
									else
										target = if a.Volume <= b.Volume then a else b
									end
									if target then
										pullFace(target.Part, axis, side, EPS)
										local mn, mx = aabb(target.Part)
										if mn and mx then
											target.Min, target.Max = mn, mx
										end
										fixed += 1
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return fixed
end

return ZFightFix

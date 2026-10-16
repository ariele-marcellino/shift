--!strict
-- The owner's store karambit (Gear.KNIFE_ASSET, loaded + cleaned on the server and published as
-- ReplicatedStorage.StoreModels.Karambit) posed for holding: a clone whose parts sit in "grip
-- space" (origin = where the fist closes, -Z = forward, +Y = up), scaled so its longest side is
-- `length`. Used for the first-person viewmodel (KnifeModel.FromStore) and the third-person knife
-- (Gear). If the model came as a Tool, its Grip (kept as the "Grip" attribute) defines the hold,
-- exactly as Roblox holds tools; otherwise the longest side is laid along Z, the flattest across X.

local StoreKnife = {}

local function visibleBounds(model: Model): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			local cf, half = d.CFrame, d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cf:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
						lo = lo:Min(p)
						hi = hi:Max(p)
					end
				end
			end
		end
	end
	return lo, hi
end

-- Frame the model is held by, in its own (template) space.
local function holdFrame(model: Model): CFrame
	local grip = model:GetAttribute("Grip")
	local handle = model:FindFirstChild("Handle", true)
	if typeof(grip) == "CFrame" and handle and handle:IsA("BasePart") then
		-- Roblox tool hold: Handle = Hand * GripAttachment * Grip:Inverse(), arm raised forward
		return handle.CFrame * grip
	end
	-- no grip: box axes sorted by length -> thinnest = X, middle = Y, longest = Z
	local cf, size = model:GetBoundingBox()
	local axes = {
		{ size.X, cf.RightVector },
		{ size.Y, cf.UpVector },
		{ size.Z, cf.LookVector },
	}
	table.sort(axes, function(a, b)
		return a[1] < b[1]
	end)
	return CFrame.fromMatrix(cf.Position, axes[1][2], axes[2][2])
end

function StoreKnife.Posed(template: Model, length: number): Model
	local model = template:Clone()
	-- joints from the original tool would fight our own welds / anchoring
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") then
			d:Destroy()
		end
	end
	local ref = holdFrame(model):Inverse()
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Transparency >= 0.98 then
				d:Destroy() -- invisible handles / hitboxes
			else
				d.CFrame = ref * d.CFrame
				table.insert(parts, d)
			end
		end
	end
	local lo, hi = visibleBounds(model)
	local extent = hi - lo
	local longest = math.max(extent.X, extent.Y, extent.Z)
	local s = if longest > 1e-3 then length / longest else 1
	for _, p in parts do
		p.Size *= s
		p.CFrame = CFrame.new(p.Position * s) * p.CFrame.Rotation
		for _, m in p:GetChildren() do
			if m:IsA("SpecialMesh") then
				m.Scale *= s
				m.Offset *= s
			end
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	return model
end

return StoreKnife

--!strict
-- Loads Creator Store models (InsertService) and cleans them for use as pure decoration:
-- every script / sound / click or proximity prompt / humanoid is removed, all parts anchored with
-- no touch events. Results are cached per asset id; callers clone what they get.
-- Roblox only lets a game load models that the game owner has in their inventory.

local InsertService = game:GetService("InsertService")

local StoreAssets = {}

local cache: { [number]: Model | false } = {}

local STRIP = {
	"Script",
	"LocalScript",
	"ModuleScript",
	"Sound",
	"ClickDetector",
	"ProximityPrompt",
	"Humanoid",
	"Tool",
}

local function strip(model: Instance)
	for _, d in model:GetDescendants() do
		if d.Parent then
			for _, className in STRIP do
				if d:IsA(className) then
					d:Destroy()
					break
				end
			end
		end
	end
end

-- Cleaned template for an asset (do not parent or edit it; Clone() it), or nil if it can't load.
function StoreAssets.Load(assetId: number): Model?
	local cached = cache[assetId]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not container then
		warn(`[StoreAssets] could not load {assetId} (is it in the game owner's inventory?): {container}`)
		cache[assetId] = false
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Store_" .. assetId
	for _, child in (container :: Instance):GetChildren() do
		child.Parent = model
	end
	(container :: Instance):Destroy()
	-- A Tool (e.g. a knife) would be stripped whole: keep its parts, drop the Tool itself, and keep
	-- its Grip (how it sits in the hand) as an attribute for StoreKnife.
	for _, tool in model:GetDescendants() do
		if tool:IsA("Tool") and tool.Parent then
			if model:GetAttribute("Grip") == nil then
				model:SetAttribute("Grip", tool.Grip)
			end
			for _, child in tool:GetChildren() do
				child.Parent = tool.Parent
			end
			tool:Destroy()
		end
	end
	strip(model)
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			d.Anchored = true
			d.CanTouch = false
		end
	end
	if parts == 0 then
		warn(`[StoreAssets] {assetId} has no visible parts`)
		cache[assetId] = false
		return nil
	end
	cache[assetId] = model
	return model
end

-- World-space box around the VISIBLE parts only (store models often carry big invisible root /
-- hitbox parts that would make them float or scale wrong). Returns min, max corners.
function StoreAssets.VisibleBounds(model: Model): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local any = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			any = true
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
	if not any then
		local cf, size = model:GetBoundingBox()
		return cf.Position - size / 2, cf.Position + size / 2
	end
	return lo, hi
end

-- Move a model so its visible parts stand on `floor` (bottom touching, centred on it in X/Z).
function StoreAssets.StandOn(model: Model, floor: Vector3)
	local lo, hi = StoreAssets.VisibleBounds(model)
	local bottomCentre = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	model:PivotTo(model:GetPivot() + (floor - bottomCentre))
end

-- Scale a model so its height (or, for flat things, its largest horizontal side) is `target`.
function StoreAssets.ScaleTo(model: Model, target: number, flatSpan: boolean?)
	local lo, hi = StoreAssets.VisibleBounds(model)
	local size = hi - lo
	local current = if flatSpan then math.max(size.X, size.Z) else size.Y
	if current > 0.01 then
		model:ScaleTo(model:GetScale() * target / current)
	end
end

return StoreAssets

--!strict
-- Line-of-sight raycasts against world geometry only (combatants, Cores and see-through parts
-- don't block). The exclude list is refreshed by BotService a few times per second.

local CollectionService = game:GetService("CollectionService")

local WorldRay = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local MAX_PASSES = 4

function WorldRay.Refresh()
	local exclude: { Instance } = {}
	for _, inst in CollectionService:GetTagged("Combatant") do
		table.insert(exclude, inst)
	end
	for _, name in { "Bots", "Cores" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	params.FilterDescendantsInstances = exclude
end

-- True when nothing solid blocks the segment a -> b. Skips mostly transparent parts (glass, smoke
-- volumes, light shafts); smoke is handled separately via CombatService:IsSmoked.
function WorldRay.Clear(a: Vector3, b: Vector3): boolean
	local origin = a
	for _ = 1, MAX_PASSES do
		local delta = b - origin
		if delta.Magnitude < 0.1 then
			return true
		end
		local result = workspace:Raycast(origin, delta, params)
		if not result then
			return true
		end
		local part = result.Instance
		if part.Transparency < 0.5 and part.CanCollide then
			return false
		end
		origin = result.Position + delta.Unit * 0.05
	end
	return false
end

return WorldRay

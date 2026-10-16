--!strict
-- Fair avatars: every player spawns with the same body (standard R15 parts and scale), so
-- hitboxes and silhouettes are identical, and with default animations (animation packs change
-- poses and where body parts are). What stays personal: face, skin tone, hats, hair, glasses and
-- other small head accessories. Large accessories (back, front, shoulder, waist, neck) and layered
-- clothing are removed; the team uniform (Uniform.luau) replaces shirts and pants anyway.

local Players = game:GetService("Players")

local Avatar = {}

local KEEP_ACCESSORIES: { [any]: boolean } = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

local BODY_PARTS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local ANIMATIONS = {
	"ClimbAnimation",
	"FallAnimation",
	"IdleAnimation",
	"JumpAnimation",
	"RunAnimation",
	"SwimAnimation",
	"WalkAnimation",
}

local cache: { [number]: HumanoidDescription } = {}

local function normalize(desc: HumanoidDescription)
	desc.HeightScale = 1
	desc.WidthScale = 1
	desc.DepthScale = 1
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	for _, name in BODY_PARTS do
		(desc :: any)[name] = 0
	end
	for _, name in ANIMATIONS do
		(desc :: any)[name] = 0
	end
	desc.Shirt = 0
	desc.Pants = 0
	desc.GraphicTShirt = 0
	local ok = pcall(function()
		local kept = {}
		for _, acc in desc:GetAccessories(true) do
			if not acc.IsLayered and KEEP_ACCESSORIES[acc.AccessoryType] then
				table.insert(kept, acc)
			end
		end
		desc:SetAccessories(kept, true)
	end)
	if not ok then
		-- Older API: clear the large slots directly.
		desc.BackAccessory = ""
		desc.FrontAccessory = ""
		desc.ShouldersAccessory = ""
		desc.WaistAccessory = ""
		desc.NeckAccessory = ""
	end
end

-- Normalised description for a player (fetched once per session), or nil if it can't be built.
function Avatar.DescriptionFor(player: Player): HumanoidDescription?
	local cached = cache[player.UserId]
	if cached then
		return cached:Clone()
	end
	local desc: HumanoidDescription? = nil
	if player.UserId > 0 then
		local ok, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if ok then
			desc = result
		end
	end
	if not desc then
		desc = Instance.new("HumanoidDescription") -- test players / web failure: plain default body
	end
	local d = desc :: HumanoidDescription
	normalize(d)
	cache[player.UserId] = d
	return d:Clone()
end

Players.PlayerRemoving:Connect(function(player)
	local d = cache[player.UserId]
	if d then
		d:Destroy()
		cache[player.UserId] = nil
	end
end)

return Avatar

--!strict
-- Weapon silhouettes drawn from plain Frames (no images, no emoji) for the kill feed, slot bar and
-- loadout menu. Each glyph is defined on a 30x12 pixel grid and built with Scale sizes, so it can be
-- any size: Glyphs.make("AK", UDim2.fromOffset(30, 12), color).

local UIKit = require(script.Parent.UIKit)

local Glyphs = {}

-- { x, y, w, h, rotation?, round? } on a 30 x 12 grid. round: 1 = filled disc, 2 = hollow ring.
type Part = { number }

local W, H = 30, 12

local SHAPES: { [string]: { Part } } = {
	AK = {
		{ 0, 4, 8, 3, 6 }, -- stock
		{ 7, 3.5, 12, 3 }, -- receiver
		{ 18.5, 4.2, 11.5, 1.4 }, -- barrel
		{ 19, 2.6, 5, 1.2 }, -- gas tube
		{ 15, 6.2, 2.4, 5.2, 20 }, -- curved magazine
		{ 9.5, 6, 2, 3.5, -18 }, -- pistol grip
		{ 27.5, 2.6, 0.8, 1.8 }, -- front sight
	},
	Sniper = {
		{ 0, 4.5, 8, 3.5, 4 }, -- stock
		{ 7, 4.5, 10, 2.6 }, -- action
		{ 16.5, 5, 13.5, 1.1 }, -- long barrel
		{ 8.5, 1.2, 8, 2.2, 0, 1 }, -- scope
		{ 11.5, 3.2, 1, 1.4 }, -- scope mount
		{ 12, 7, 1.8, 2.6 }, -- magazine
		{ 15.5, 6.6, 2.4, 0.8, 30 }, -- bolt handle
		{ 8, 7, 1.8, 3.2, -18 }, -- grip
	},
	Knife = { -- karambit, side view: finger ring, handle angled down, claw blade curving down
		{ 0.3, 0.6, 5.4, 5.4, 0, 2 }, -- finger ring (hollow)
		{ 5, 2.9, 8, 3, 12 }, -- handle
		{ 13.2, 4.6, 6, 3.6, 18 }, -- wide blade root
		{ 18, 6.2, 4.6, 3, 34 }, -- belly curving down
		{ 21.2, 8.2, 3.6, 2.2, 52 }, -- claw
		{ 23, 9.8, 2.6, 1.2, 68 }, -- point
	},
	Frag = {
		{ 9, 3, 8.5, 8.5, 0, 1 }, -- body
		{ 11.5, 1.2, 3.5, 2.2 }, -- fuse cap
		{ 15, 1.6, 4.5, 1, 25 }, -- lever
		{ 18.5, 3.2, 2.2, 2.2, 0, 1 }, -- pin ring
	},
	Smoke = {
		{ 10, 2.5, 7, 9, 0 }, -- canister
		{ 10.5, 1, 6, 1.6 }, -- cap
		{ 16.5, 1.4, 4, 1, 20 }, -- lever
		{ 10, 5.6, 7, 0.8 }, -- band
	},
}

function Glyphs.make(name: string, size: UDim2, color: Color3, transparency: number?): Frame
	local holder: Frame = UIKit.new("Frame", {
		Name = "Glyph_" .. name,
		Size = size,
		BackgroundTransparency = 1,
	})
	local parts = SHAPES[name] or SHAPES.AK
	for _, p in parts do
		local part: Frame = UIKit.new("Frame", {
			Position = UDim2.fromScale(p[1] / W, p[2] / H),
			Size = UDim2.fromScale(p[3] / W, p[4] / H),
			Rotation = p[5] or 0,
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			Parent = holder,
		})
		if p[6] == 1 then
			UIKit.corner(UDim.new(0.5, 0)).Parent = part
		elseif p[6] == 2 then
			-- hollow ring: transparent fill, the outline drawn by a stroke in the glyph colour
			UIKit.corner(UDim.new(0.5, 0)).Parent = part
			part.BackgroundTransparency = 1
			part:SetAttribute("Hollow", true)
			local stroke = Instance.new("UIStroke")
			stroke.Color = color
			stroke.Thickness = 1.5
			stroke.Transparency = transparency or 0
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = part
		end
	end
	return holder
end

-- Recolour an existing glyph.
function Glyphs.setColor(glyph: Instance, color: Color3, transparency: number?)
	for _, child in glyph:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
			end
			if transparency then
				if child:GetAttribute("Hollow") then
					if stroke then
						stroke.Transparency = transparency
					end
				else
					child.BackgroundTransparency = transparency
				end
			end
		end
	end
end

-- Wallbang marker: a wall slab with a round passing through it (14 x 12 grid).
function Glyphs.wallbang(size: UDim2, color: Color3): Frame
	local holder: Frame = UIKit.new("Frame", {
		Name = "Glyph_Wallbang",
		Size = size,
		BackgroundTransparency = 1,
	})
	local parts = {
		{ 5.5, 0, 2.5, 12, 0.35 }, -- wall (dimmer)
		{ 0, 5.4, 4.5, 1.2, 0 }, -- entry trace
		{ 9, 5.4, 5, 1.2, 0 }, -- exit trace
	}
	for _, p in parts do
		UIKit.new("Frame", {
			Position = UDim2.fromScale(p[1] / 14, p[2] / 12),
			Size = UDim2.fromScale(p[3] / 14, p[4] / 12),
			BackgroundColor3 = color,
			BackgroundTransparency = p[5],
			BorderSizePixel = 0,
			Parent = holder,
		})
	end
	return holder
end

return Glyphs

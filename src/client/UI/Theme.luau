--!strict
-- SHIFT visual language: a tactical overlay for a dark facility. Thin light text, small translucent
-- near-black panels, hairline strokes. White/grey for everything except team info (Tuning.Teams)
-- and a pale facility-amber reserved for PA announcements. Never bright, never cartoonish: the HUD
-- must not wash out the darkness of the map.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Theme = {}

local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"

Theme.Fonts = {
	Light = Font.new(GOTHAM, Enum.FontWeight.Light),
	Regular = Font.new(GOTHAM, Enum.FontWeight.Regular),
	Medium = Font.new(GOTHAM, Enum.FontWeight.Medium),
	Bold = Font.new(GOTHAM, Enum.FontWeight.Bold),
	Mono = Font.new(MONO, Enum.FontWeight.Regular),
	MonoBold = Font.new(MONO, Enum.FontWeight.Bold),
}

Theme.Colors = {
	Black = Color3.fromRGB(0, 0, 0),
	Panel = Color3.fromRGB(8, 10, 12),
	PanelRaised = Color3.fromRGB(22, 25, 29),
	Stroke = Color3.fromRGB(200, 205, 212),
	White = Color3.fromRGB(236, 238, 240),
	Text = Color3.fromRGB(210, 214, 219),
	TextDim = Color3.fromRGB(140, 146, 154),
	TextFaint = Color3.fromRGB(88, 94, 102),
	-- Facility amber: PA announcements and lit lamps on the report map only.
	Amber = Color3.fromRGB(224, 196, 120),
	-- Status (used sparingly and desaturated).
	Good = Color3.fromRGB(150, 205, 160),
	Bad = Color3.fromRGB(225, 110, 100),
	Head = Color3.fromRGB(255, 92, 72), -- headshot hit marker
	Damage = Color3.fromRGB(200, 40, 30),
}

-- Panel / stroke transparencies. Panels stay mostly see-through so the dark map stays dark.
Theme.PanelT = 0.45
Theme.PanelTLight = 0.65
Theme.StrokeT = 0.86

Theme.Corner = UDim.new(0, 3)

-- Text sizes at the 1000x500 reference resolution (UIKit.autoScale scales them).
Theme.TextSize = {
	Tiny = 10,
	Caption = 12,
	Body = 14,
	Label = 16,
	Title = 22,
	Hero = 36,
}

function Theme.teamColor(team: string?): Color3
	local t = team and (Tuning.Teams :: any)[team]
	if t then
		return t.Color
	end
	return Theme.Colors.TextDim
end

function Theme.enemyOf(team: string?): string?
	if team == "Blue" then
		return "Red"
	elseif team == "Red" then
		return "Blue"
	end
	return nil
end

return Theme

--!strict
-- Controls overlay ([H] on PC; CONTROLS in settings on touch). Modal while open so the mouse is free.

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)

local Help = {}

local PC = {
	{ "Fire / slash / throw (hold = harder)", "LMB" },
	{ "Aim  ·  sniper scope", "RMB" },
	{ "Reload", "R" },
	{ "Primary · Knife · Frag · Smoke", "1  2  3  4" },
	{ "Last weapon", "Q" },
	{ "Cycle weapons", "Mouse wheel" },
	{ "Quick frag  ·  quick smoke (hold)", "G  ·  T" },
	{ "Flashlight", "F" },
	{ "Drop the flag (a teammate can carry it)", "X" },
	{ "Sprint (not while aiming)", "Hold Shift" },
	{ "Slide (while sprinting)", "C" },
	{ "Crouch  ·  jump", "Ctrl  ·  Space" },
	{ "Map  ·  ping", "M  ·  Y / Z / middle mouse" },
	{ "Loadout", "B" },
	{ "Menu  ·  team · squad · find match", "P" },
	{ "Scoreboard", "Tab (hold)" },
	{ "Settings  ·  this help", "O  ·  H" },
}

local TOUCH = {
	{ "Move  ·  look", "Left stick  ·  drag right side" },
	{ "Fire / slash / throw", "FIRE (drag to look)" },
	{ "Aim  ·  sniper scope", "AIM (toggle)" },
	{ "Primary  ·  knife", "PRIMARY  ·  KNIFE  ·  slot bar" },
	{ "Throw frag  ·  smoke (hold = harder)", "FRAG  ·  SMOKE" },
	{ "Reload  ·  flashlight", "RELOAD  ·  LIGHT" },
	{ "Drop the flag (a teammate can carry it)", "DROP (while carrying)" },
	{ "Crouch  ·  jump", "CROUCH  ·  JUMP" },
	{ "Loadout", "LOADOUT (top right)" },
	{ "Menu  ·  team · squad · find match", "MENU (top left)" },
	{ "Scoreboard", "Tap the score bar" },
}

function Help.mount(gui: ScreenGui)
	local overlay: Frame = UIKit.new("Frame", {
		Name = "Help",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local api = {}
	UIKit.modalBackdrop(overlay, function()
		api.setVisible(false)
	end)

	local card = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(470, 380),
		BackgroundTransparency = 0.15,
		ZIndex = 2,
		Parent = overlay,
	})
	UIKit.autoScale(card)
	UIKit.text("CONTROLS", {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.fromOffset(200, 18),
		TextSize = Theme.TextSize.Caption,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.TextDim,
		ZIndex = 2,
		Parent = card,
	})
	UIKit.button("CLOSE", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(70, 26),
		TextSize = Theme.TextSize.Tiny,
		ZIndex = 3,
		Parent = card,
	}, function()
		api.setVisible(false)
	end)

	local list: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(20, 46),
		Size = UDim2.new(1, -40, 1, -60),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	}, {
		UIKit.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})

	local function render()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		for i, row in (if touch then TOUCH else PC) do
			local r = UIKit.new("Frame", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				LayoutOrder = i,
				ZIndex = 2,
				Parent = list,
			})
			UIKit.text(row[1], {
				Size = UDim2.fromScale(0.45, 1),
				TextSize = Theme.TextSize.Caption + 1,
				ZIndex = 2,
				Parent = r,
			})
			UIKit.mono(row[2], {
				Position = UDim2.fromScale(0.45, 0),
				Size = UDim2.fromScale(0.55, 1),
				TextSize = Theme.TextSize.Tiny + 1,
				TextColor3 = Theme.Colors.White,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 2,
				Parent = r,
			})
		end
		UIKit.text("Carrying the Flag: knife only, fast. Weapons unlock on capture or drop.", {
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.TextDim,
			LayoutOrder = 100,
			ZIndex = 2,
			Parent = list,
		})
	end

	function api.setVisible(visible: boolean)
		if visible then
			render()
		end
		overlay.Visible = visible
	end
	function api.toggle()
		api.setVisible(not overlay.Visible)
	end
	function api.isVisible(): boolean
		return overlay.Visible
	end
	return api
end

return Help

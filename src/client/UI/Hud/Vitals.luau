--!strict
-- Bottom-center vitals (v2):
--   carrier line   "CARRYING FLAG · KNIFE ONLY" (team color of the carried Flag)
--   slot bar       [1 AK|BOLT-7] [2 KNIFE] [3 FRAG n] [4 SMOKE n], held slot highlighted; while
--                  carrying, every slot except the knife is dimmed (locked). Cells are tappable
--                  (EquipSlot) so the bar doubles as slot buttons on touch.
--   strip          HP + bar | primary Mag / Reserve | flashlight
-- Bottom-center (not corners) so it never sits under the mobile thumbstick or fire cluster.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))
local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local Weapon = require(script.Parent.Parent.Weapon)
local Glyphs = require(script.Parent.Parent.Glyphs)

local Vitals = {}

local LOW_HEALTH = 35

type Slot = {
	Key: string, -- "Primary" | "Knife" | "Frag" | "Smoke"
	Button: TextButton,
	Stroke: UIStroke,
	Glyph: Frame,
	GlyphName: string,
	Label: TextLabel,
	Num: TextLabel,
}

local function primaryLabel(name: string): string
	if name == "Sniper" then
		return "BOLT-7"
	end
	return string.upper(name)
end

function Vitals.mount(gui: ScreenGui)
	local root: Frame = UIKit.new("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(380, 98),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(root)

	-- Carrier line ---------------------------------------------------------------------------------
	local carrier = UIKit.text("", {
		Name = "Carrier",
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Caption,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})

	-- Slot bar -------------------------------------------------------------------------------------
	local bar: Frame = UIKit.new("Frame", {
		Name = "Slots",
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center) })

	local slots: { Slot } = {}
	for i, key in { "Primary", "Knife", "Frag", "Smoke" } do
		local button: TextButton = UIKit.new("TextButton", {
			Name = "Slot_" .. key,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.fromOffset(91, 30),
			BackgroundColor3 = Theme.Colors.Panel,
			BackgroundTransparency = Theme.PanelTLight,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = bar,
		}, { UIKit.corner() })
		local stroke = UIKit.stroke()
		stroke.Parent = button
		UIKit.mono(tostring(i), {
			Position = UDim2.fromOffset(5, 2),
			Size = UDim2.fromOffset(10, 10),
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Colors.TextFaint,
			TextStrokeTransparency = 1,
			Parent = button,
		})
		local label = UIKit.text("", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(46, 14),
			TextSize = Theme.TextSize.Tiny,
			FontFace = Theme.Fonts.Medium,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 1,
			Parent = button,
		})
		local num = UIKit.mono("", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			TextSize = Theme.TextSize.Caption,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 1,
			Parent = button,
		})
		local glyphName = if key == "Primary" then "AK" else key
		local glyph = Glyphs.make(glyphName, UDim2.fromOffset(28, 11), Theme.Colors.White)
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, 14, 0.5, 1)
		glyph.Parent = button
		button.Activated:Connect(function()
			Weapon.call("EquipSlot", key)
		end)
		slots[i] = {
			Key = key,
			Button = button,
			Stroke = stroke,
			Glyph = glyph,
			GlyphName = glyphName,
			Label = label,
			Num = num,
		}
	end

	-- Strip: health | ammo | light -----------------------------------------------------------------
	local strip = UIKit.panel({
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = Theme.PanelTLight,
		Parent = root,
	})
	UIKit.text("HP", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.fromOffset(24, 14),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextFaint,
		FontFace = Theme.Fonts.Medium,
		Parent = strip,
	})
	local hpText = UIKit.mono("100", {
		Position = UDim2.fromOffset(34, 3),
		Size = UDim2.fromOffset(60, 20),
		TextSize = Theme.TextSize.Label + 2,
		TextColor3 = Theme.Colors.White,
		Parent = strip,
	})
	local hpTrack = UIKit.new("Frame", {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.fromOffset(140, 3),
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = strip,
	})
	local hpFill: Frame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = hpTrack,
	})
	UIKit.line({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1, 24),
		BackgroundTransparency = 0.85,
		Parent = strip,
	})
	local magText = UIKit.mono(tostring(Tuning.AK.Magazine), {
		Position = UDim2.new(0.5, 14, 0, 3),
		Size = UDim2.fromOffset(34, 22),
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = strip,
	})
	local reserveText = UIKit.mono("/ 120", {
		Position = UDim2.new(0.5, 52, 0, 8),
		Size = UDim2.fromOffset(70, 16),
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.TextDim,
		Parent = strip,
	})
	local weaponText = UIKit.text("", {
		Position = UDim2.new(0.5, 14, 0, 26),
		Size = UDim2.fromOffset(110, 12),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextFaint,
		FontFace = Theme.Fonts.Medium,
		Parent = strip,
	})
	local light: Frame = UIKit.new("Frame", {
		Name = "Flashlight",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(50, 30),
		BackgroundTransparency = 1,
		Parent = strip,
	})
	local lightBody: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(2, 9),
		Size = UDim2.fromOffset(10, 6),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Parent = light,
	}, { UIKit.corner(UDim.new(0, 1)) })
	local beam: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.fromOffset(26, 12),
		BackgroundColor3 = Theme.Colors.Amber,
		BorderSizePixel = 0,
		Parent = light,
	}, {
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local lightText = UIKit.text("LIGHT", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 12),
		TextSize = Theme.TextSize.Tiny,
		FontFace = Theme.Fonts.Medium,
		Parent = light,
	})

	-- Health ---------------------------------------------------------------------------------------
	local healthConn: RBXScriptConnection? = nil
	local function setHealth(health: number, max: number)
		local alpha = math.clamp(health / math.max(1, max), 0, 1)
		hpText.Text = tostring(math.ceil(math.max(0, health)))
		UIKit.tween(hpFill, 0.15, { Size = UDim2.fromScale(alpha, 1) })
		local low = health <= LOW_HEALTH
		hpFill.BackgroundColor3 = if low then Theme.Colors.Bad else Theme.Colors.White
		hpText.TextColor3 = if low then Theme.Colors.Bad else Theme.Colors.White
	end
	local function watchCharacter(character: Model)
		if healthConn then
			healthConn:Disconnect()
			healthConn = nil
		end
		local hum = character:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			setHealth(hum.Health, hum.MaxHealth)
			healthConn = hum.HealthChanged:Connect(function(h: number)
				setHealth(h, hum.MaxHealth)
			end)
		end
	end
	Players.LocalPlayer.CharacterAdded:Connect(watchCharacter)
	if Players.LocalPlayer.Character then
		task.spawn(watchCharacter, Players.LocalPlayer.Character)
	end
	Remotes.Get("Damaged").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.Health) == "number" then
			setHealth(data.Health, Tuning.Health.Max)
		end
	end)

	-- Weapon state ---------------------------------------------------------------------------------
	local function heldSlot(held: string): string
		if held == "Knife" or held == "Frag" or held == "Smoke" then
			return held
		end
		return "Primary"
	end

	local function refresh()
		local s = Weapon.state()
		local current = heldSlot(s.Held)
		for _, slot in slots do
			local selected = slot.Key == current
			local locked = s.Carrying ~= nil and slot.Key ~= "Knife"
			local count: number? = if slot.Key == "Frag"
				then s.Frags
				elseif slot.Key == "Smoke" then s.Smokes
				else nil
			local empty = count ~= nil and count <= 0
			local dim = locked or empty

			if slot.Key == "Primary" and slot.GlyphName ~= s.Primary then
				slot.Glyph:Destroy()
				local g = Glyphs.make(s.Primary, UDim2.fromOffset(28, 11), Theme.Colors.White)
				g.AnchorPoint = Vector2.new(0, 0.5)
				g.Position = UDim2.new(0, 14, 0.5, 1)
				g.Parent = slot.Button
				slot.Glyph = g
				slot.GlyphName = s.Primary
			end
			if count ~= nil then
				slot.Label.Text = ""
				slot.Num.Text = tostring(count)
			else
				slot.Num.Text = ""
				slot.Label.Text = if slot.Key == "Primary" then primaryLabel(s.Primary) else "KNIFE"
			end

			local fg = if selected
				then Theme.Colors.White
				elseif dim then Theme.Colors.TextFaint
				else Theme.Colors.TextDim
			slot.Label.TextColor3 = fg
			slot.Num.TextColor3 = fg
			Glyphs.setColor(slot.Glyph, fg, if dim and not selected then 0.4 else 0)
			slot.Stroke.Transparency = if selected then 0.35 else Theme.StrokeT
			slot.Button.BackgroundTransparency = if selected
				then 0.35
				else Theme.PanelTLight + (if dim then 0.15 else 0)
		end

		-- Ammo for the primary; dimmed when something else is in hand.
		local primaryHeld = current == "Primary"
		if s.Reloading then
			magText.Text = "--"
			reserveText.Text = "RELOAD"
		else
			magText.Text = tostring(s.Mag)
			reserveText.Text = "/ " .. tostring(s.Reserve)
		end
		local lowMag = if s.Primary == "Sniper" then 1 else 7
		magText.TextColor3 = if s.Mag <= lowMag and not s.Reloading
			then Theme.Colors.Bad
			else Theme.Colors.White
		magText.TextTransparency = if primaryHeld then 0 else 0.55
		reserveText.TextTransparency = if primaryHeld then 0 else 0.55
		weaponText.Text = if s.Primary == "Sniper" then Tuning.Sniper.DisplayName else "AK"

		lightBody.BackgroundTransparency = if s.Flashlight then 0.1 else 0.6
		beam.Visible = s.Flashlight
		lightText.TextColor3 = if s.Flashlight then Theme.Colors.White else Theme.Colors.TextFaint
		lightText.Text = if s.Flashlight then "LIGHT ON" else "LIGHT"

		if s.Carrying then
			carrier.Text = if UserInputService.KeyboardEnabled
				then "CARRYING FLAG  ·  KNIFE ONLY  ·  X TO DROP"
				else "CARRYING FLAG  ·  KNIFE ONLY"
			carrier.TextColor3 = Theme.teamColor(s.Carrying)
		else
			carrier.Text = ""
		end
	end
	Weapon.Changed:Connect(refresh)
	refresh()
	-- WeaponController may not fire Changed for every field; a slow poll keeps the HUD honest
	-- without per-frame work.
	task.spawn(function()
		while true do
			task.wait(0.25)
			refresh()
		end
	end)

	return root
end

return Vitals

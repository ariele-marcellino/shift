--!strict
-- Loadout menu (v2 §V1): pick the primary from Tuning.Primaries. Each option shows a drawn
-- silhouette, a one-line role and four stat bars computed from Tuning (damage per hit, fire rate,
-- mobility, range). Selecting fires SelectLoadout(primary); the server answers with LoadoutState
-- { Primary, Options, AppliesNow } and the footer shows "EQUIPPED NOW" or "APPLIES ON NEXT SPAWN".
-- Modal while open (frees the first-person mouse). HudController decides when it opens: once
-- automatically per session, then only on [B] / the LOADOUT button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local Glyphs = require(script.Parent.Parent.Glyphs)
local Weapon = require(script.Parent.Parent.Weapon)

local Loadout = {}

local ROLE: { [string]: string } = {
	AK = "Full auto. Controlled bursts win mid-range fights.",
	Sniper = "Bolt-action. One shot to the body. Scope with RMB / AIM.",
}

type Card = { Name: string, Button: TextButton, Stroke: UIStroke, Tag: TextLabel }

local function weaponData(name: string): any
	return (Tuning :: any)[name] or {}
end

local function displayName(name: string): string
	local d = weaponData(name).DisplayName
	return if type(d) == "string" then d else string.upper(name)
end

-- Stat rows: label, 0..1 fill, value text. Normalised against fixed caps so bars stay comparable.
local function stats(name: string): { { any } }
	local w = weaponData(name)
	local dmg = tonumber(w.Damage) or 0
	local rpm = tonumber(w.RPM) or 0
	local speed = tonumber((Tuning.Movement :: any)[name]) or Tuning.Movement.AK
	local range = tonumber(w.Range) or 0
	return {
		{ "DAMAGE", math.clamp(dmg / 120, 0.04, 1), tostring(dmg) },
		{ "FIRE RATE", math.clamp(rpm / 600, 0.04, 1), tostring(rpm) .. " RPM" },
		{ "MOBILITY", math.clamp(speed / Tuning.Movement.Knife, 0.04, 1), tostring(speed) },
		{ "RANGE", math.clamp(range / 900, 0.04, 1), tostring(range) },
	}
end

function Loadout.mount(gui: ScreenGui)
	local api = {}
	local overlay: Frame = UIKit.new("Frame", {
		Name = "Loadout",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local backdrop = UIKit.modalBackdrop(overlay, function()
		api.setVisible(false)
	end)
	backdrop.BackgroundTransparency = 0.35

	local card = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 320),
		BackgroundTransparency = 0.1,
		ZIndex = 2,
		Parent = overlay,
	})
	UIKit.autoScale(card)

	UIKit.text("LOADOUT", {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.fromOffset(200, 12),
		TextSize = Theme.TextSize.Tiny,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 1,
		Parent = card,
	})
	UIKit.text("Choose your primary", {
		Position = UDim2.fromOffset(20, 28),
		Size = UDim2.fromOffset(300, 24),
		TextSize = Theme.TextSize.Title,
		FontFace = Theme.Fonts.Light,
		TextColor3 = Theme.Colors.White,
		TextStrokeTransparency = 1,
		Parent = card,
	})
	UIKit.button("CLOSE", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(70, 26),
		TextSize = Theme.TextSize.Tiny,
		Parent = card,
	}, function()
		api.setVisible(false)
	end)

	local row: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(20, 62),
		Size = UDim2.new(1, -40, 0, 196),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		UIKit.list(
			Enum.FillDirection.Horizontal,
			12,
			Enum.HorizontalAlignment.Left,
			Enum.VerticalAlignment.Top
		),
	})

	local status = UIKit.text("", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -38),
		Size = UDim2.fromOffset(360, 16),
		TextSize = Theme.TextSize.Caption,
		FontFace = Theme.Fonts.Bold,
		TextStrokeTransparency = 1,
		Parent = card,
	})
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	UIKit.text(
		"Knife, 1 frag and 1 smoke are always carried."
			.. (if touch then "  Reopen with LOADOUT." else "  Reopen with [B]."),
		{
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 20, 1, -16),
			Size = UDim2.fromOffset(420, 16),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.TextFaint,
			TextStrokeTransparency = 1,
			Parent = card,
		}
	)
	UIKit.button("DEPLOY", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -16),
		Size = UDim2.fromOffset(120, 36),
		TextSize = Theme.TextSize.Caption,
		Parent = card,
	}, function()
		api.setVisible(false)
	end)

	local selected: string? = Weapon.loadoutPrimary()
	local options: { string } = table.clone(Tuning.Primaries)
	local pending: string? = nil
	local lastState: { Primary: string, AppliesNow: boolean }? = nil
	local cards: { Card } = {}

	local function renderStatus()
		if pending then
			status.Text = "SELECTING " .. displayName(pending) .. " ..."
			status.TextColor3 = Theme.Colors.TextDim
		elseif lastState and selected == lastState.Primary then
			if lastState.AppliesNow then
				status.Text = displayName(lastState.Primary) .. "  ·  EQUIPPED NOW"
				status.TextColor3 = Theme.Colors.Good
			else
				status.Text = displayName(lastState.Primary) .. "  ·  APPLIES ON NEXT SPAWN"
				status.TextColor3 = Theme.Colors.Amber
			end
		elseif selected then
			status.Text = displayName(selected) .. "  ·  CURRENT"
			status.TextColor3 = Theme.Colors.TextDim
		else
			status.Text = "Select a primary weapon"
			status.TextColor3 = Theme.Colors.TextDim
		end
		for _, c in cards do
			local isSel = c.Name == (pending or selected)
			local available = table.find(options, c.Name) ~= nil
			c.Stroke.Transparency = if isSel then 0.25 else 0.8
			c.Button.BackgroundTransparency = if isSel then 0.55 else 0.75
			c.Tag.Text = if not available then "UNAVAILABLE" elseif isSel then "SELECTED" else ""
		end
	end

	local function choose(name: string)
		if not table.find(options, name) then
			return
		end
		pending = name
		renderStatus()
		Remotes.Get("SelectLoadout"):FireServer(name)
		-- If the server never answers (e.g. Mode not updated yet), stop showing "selecting".
		task.delay(3, function()
			if pending == name then
				pending = nil
				selected = name
				renderStatus()
			end
		end)
	end

	local function buildCards()
		for _, c in cards do
			c.Button:Destroy()
		end
		table.clear(cards)
		local count = math.max(1, #Tuning.Primaries)
		for i, name in Tuning.Primaries do
			local button: TextButton = UIKit.new("TextButton", {
				Name = "Option_" .. name,
				AutoButtonColor = false,
				Text = "",
				Size = UDim2.new(1 / count, -12 * (count - 1) / count, 1, 0),
				BackgroundColor3 = Theme.Colors.PanelRaised,
				BackgroundTransparency = 0.75,
				BorderSizePixel = 0,
				LayoutOrder = i,
				Parent = row,
			}, { UIKit.corner() })
			local stroke = UIKit.stroke(nil, 0.8)
			stroke.Parent = button

			local glyph = Glyphs.make(name, UDim2.fromOffset(120, 48), Theme.Colors.White, 0.1)
			glyph.Position = UDim2.fromOffset(14, 12)
			glyph.Parent = button
			local tag = UIKit.text("", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 10),
				Size = UDim2.fromOffset(100, 12),
				TextSize = Theme.TextSize.Tiny,
				FontFace = Theme.Fonts.Bold,
				TextColor3 = Theme.Colors.White,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextStrokeTransparency = 1,
				Parent = button,
			})
			UIKit.text(displayName(name), {
				Position = UDim2.fromOffset(14, 66),
				Size = UDim2.new(1, -28, 0, 20),
				TextSize = Theme.TextSize.Label,
				FontFace = Theme.Fonts.Medium,
				TextColor3 = Theme.Colors.White,
				TextStrokeTransparency = 1,
				Parent = button,
			})
			UIKit.text(ROLE[name] or "", {
				Position = UDim2.fromOffset(14, 86),
				Size = UDim2.new(1, -28, 0, 14),
				TextSize = Theme.TextSize.Tiny,
				TextColor3 = Theme.Colors.TextDim,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextStrokeTransparency = 1,
				Parent = button,
			})
			for j, st in stats(name) do
				local y = 106 + (j - 1) * 21
				UIKit.text(st[1], {
					Position = UDim2.fromOffset(14, y),
					Size = UDim2.fromOffset(70, 12),
					TextSize = Theme.TextSize.Tiny,
					FontFace = Theme.Fonts.Medium,
					TextColor3 = Theme.Colors.TextFaint,
					TextStrokeTransparency = 1,
					Parent = button,
				})
				local track = UIKit.line({
					Position = UDim2.fromOffset(84, y + 5),
					Size = UDim2.new(1, -164, 0, 3),
					BackgroundTransparency = 0.85,
					Parent = button,
				})
				UIKit.line({
					Size = UDim2.fromScale(st[2], 1),
					BackgroundTransparency = 0.1,
					Parent = track,
				})
				UIKit.mono(st[3], {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, y),
					Size = UDim2.fromOffset(70, 12),
					TextSize = Theme.TextSize.Tiny,
					TextColor3 = Theme.Colors.Text,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextStrokeTransparency = 1,
					Parent = button,
				})
			end
			button.Activated:Connect(function()
				choose(name)
			end)
			table.insert(cards, { Name = name, Button = button, Stroke = stroke, Tag = tag })
		end
	end
	buildCards()

	Remotes.Get("LoadoutState").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" or type(data.Primary) ~= "string" then
			return
		end
		if type(data.Options) == "table" and #data.Options > 0 then
			options = {}
			for _, o in data.Options do
				if type(o) == "string" then
					table.insert(options, o)
				end
			end
		end
		selected = data.Primary
		pending = nil
		lastState = { Primary = data.Primary, AppliesNow = data.AppliesNow == true }
		renderStatus()
	end)

	function api.setVisible(visible: boolean)
		if visible then
			selected = selected or Weapon.loadoutPrimary() or Weapon.state().Primary
			renderStatus()
		end
		overlay.Visible = visible
	end
	function api.toggle()
		api.setVisible(not overlay.Visible)
	end
	function api.isVisible(): boolean
		return overlay.Visible
	end
	renderStatus()
	return api
end

return Loadout

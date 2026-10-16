--!strict
-- Transient HUD text:
--   * PA shift banner (ShiftAnnounce): "PA SYSTEM · FACILITY SHIFT IN 5", title, detail line,
--     amber countdown rule; flips to "SHIFT APPLIED" at zero and fades.
--   * Announce (text, kind): one short line under the match bar.
--   * Death + RespawnTimer: "ELIMINATED BY X" / "REDEPLOY IN 4" under the crosshair.
--   * Spawn protection: "SPAWN PROTECTION" with a draining rule while the character attribute
--     `SpawnProtected` (set/cleared by Mode's Spawner) is true.
--   * Warmup card while Phase == "Warmup".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local MatchStore = require(script.Parent.Parent.MatchStore)

local Banners = {}

local function fadeOut(root: Instance, time: number)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			UIKit.tween(d, time, { TextTransparency = 1, TextStrokeTransparency = 1 })
		elseif d:IsA("UIStroke") then
			UIKit.tween(d, time, { Transparency = 1 })
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			UIKit.tween(d, time, { BackgroundTransparency = 1 })
		end
	end
	if root:IsA("Frame") and root.BackgroundTransparency < 1 then
		UIKit.tween(root, time, { BackgroundTransparency = 1 })
	end
end

--------------------------------------------------------------------------------
-- PA shift banner
--------------------------------------------------------------------------------

local function mountShift(gui: ScreenGui)
	local holder: Frame = UIKit.new("Frame", {
		Name = "ShiftBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(440, 74),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(holder)

	local current: Frame? = nil
	local token = 0

	Remotes.Get("ShiftAnnounce").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		token += 1
		local my = token
		if current then
			current:Destroy()
		end
		local seconds = tonumber(data.Seconds) or Tuning.Core.ShiftWarningSeconds
		local title = string.upper(tostring(data.Title or "FACILITY SHIFT"))
		local detail = tostring(data.Detail or "")

		local panel = UIKit.panel({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.35,
			Parent = holder,
		})
		current = panel
		local rule = UIKit.line({
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Theme.Colors.Amber,
			BackgroundTransparency = 0.1,
			Parent = panel,
		})
		UIKit.text("PA SYSTEM", {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.fromOffset(200, 12),
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Colors.Amber,
			FontFace = Theme.Fonts.Bold,
			Parent = panel,
		})
		local count = UIKit.mono("", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 6),
			Size = UDim2.fromOffset(120, 16),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.Amber,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = panel,
		})
		local titleLabel = UIKit.text(title, {
			Position = UDim2.fromOffset(14, 22),
			Size = UDim2.new(1, -28, 0, 24),
			TextSize = Theme.TextSize.Title,
			TextColor3 = Theme.Colors.White,
			FontFace = Theme.Fonts.Light,
			Parent = panel,
		})
		UIKit.text(detail, {
			Position = UDim2.fromOffset(14, 48),
			Size = UDim2.new(1, -28, 0, 18),
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.Colors.TextDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = panel,
		})
		UIKit.tween(rule, seconds, { Size = UDim2.fromOffset(0, 2) }, Enum.EasingStyle.Linear)

		local endsAt = os.clock() + seconds
		task.spawn(function()
			while my == token and os.clock() < endsAt do
				count.Text = string.format("SHIFT IN %d", math.ceil(endsAt - os.clock()))
				task.wait(0.1)
			end
			if my ~= token then
				return
			end
			count.Text = "APPLIED"
			titleLabel.Text = "SHIFT APPLIED"
			task.wait(3)
			if my ~= token then
				return
			end
			fadeOut(panel, 0.6)
			task.wait(0.7)
			if my == token then
				panel:Destroy()
				current = nil
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Announce
--------------------------------------------------------------------------------

local function mountAnnounce(gui: ScreenGui): (string, string?) -> ()
	local label = UIKit.text("", {
		Name = "Announce",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(520, 24),
		TextSize = Theme.TextSize.Label,
		FontFace = Theme.Fonts.Medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		TextTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(label)
	local token = 0
	local function show(text: string, kind: string?)
		token += 1
		local my = token
		label.Text = string.upper(text)
		label.TextColor3 = if kind == "Good"
			then Theme.Colors.Good
			elseif kind == "Bad" then Theme.Colors.Bad
			else Theme.Colors.White
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.6
		task.delay(3, function()
			if my == token then
				UIKit.tween(label, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
			end
		end)
	end
	Remotes.Get("Announce").OnClientEvent:Connect(function(text: any, kind: any)
		if type(text) == "string" then
			show(text, if type(kind) == "string" then kind else nil)
		end
	end)
	return show
end

--------------------------------------------------------------------------------
-- Death / respawn / spawn protection
--------------------------------------------------------------------------------

local function mountLife(gui: ScreenGui)
	local root: Frame = UIKit.new("Frame", {
		Name = "LifeStatus",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 46),
		Size = UDim2.fromOffset(320, 70),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(root)

	local killedBy = UIKit.text("", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TextSize.Body,
		FontFace = Theme.Fonts.Medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		RichText = true,
		Visible = false,
		Parent = root,
	})
	local redeploy = UIKit.mono("", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = root,
	})
	local protect = UIKit.text("SPAWN PROTECTION", {
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = Theme.TextSize.Tiny,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = root,
	})
	local protectRule = UIKit.line({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(90, 1),
		BackgroundTransparency = 0.4,
		Visible = false,
		Parent = root,
	})

	local respawnToken = 0
	Remotes.Get("RespawnTimer").OnClientEvent:Connect(function(seconds: any)
		if type(seconds) ~= "number" then
			return
		end
		respawnToken += 1
		local my = respawnToken
		local endsAt = os.clock() + seconds
		redeploy.Visible = true
		task.spawn(function()
			while my == respawnToken and os.clock() < endsAt do
				redeploy.Text = string.format("REDEPLOY IN %d", math.ceil(endsAt - os.clock()))
				task.wait(0.1)
			end
			if my == respawnToken then
				redeploy.Text = "REDEPLOYING"
			end
		end)
	end)

	MatchStore.KillFeed:Connect(function(entry: any)
		if not MatchStore.isMe(entry.Victim) then
			return
		end
		local killer = tostring(entry.Killer or "")
		if killer == "" or killer == entry.Victim then
			killedBy.Text = "ELIMINATED"
		else
			local c = Theme.teamColor(entry.KillerTeam)
			local hex = string.format("#%02X%02X%02X", c.R * 255, c.G * 255, c.B * 255)
			killedBy.Text = string.format(
				'ELIMINATED BY <font color="%s">%s</font>%s',
				hex,
				killer,
				if entry.Headshot == true then "  ·  HEADSHOT" else ""
			)
		end
		killedBy.TextColor3 = Theme.Colors.TextDim
		killedBy.Visible = true
	end)

	local protectToken = 0
	local function setProtect(on: boolean, seconds: number?)
		protectToken += 1
		protect.Visible = on
		protectRule.Visible = on
		if on and seconds then
			protectRule.Size = UDim2.fromOffset(90, 1)
			UIKit.tween(protectRule, seconds, { Size = UDim2.fromOffset(0, 1) }, Enum.EasingStyle.Linear)
			local my = protectToken
			task.delay(seconds, function()
				if my == protectToken then
					protect.Visible = false
					protectRule.Visible = false
				end
			end)
		end
	end

	local function onCharacter(character: Model)
		respawnToken += 1
		killedBy.Visible = false
		redeploy.Visible = false
		local hum = character:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum.Died:Connect(function()
				setProtect(false)
				if not killedBy.Visible then
					killedBy.Text = "ELIMINATED"
					killedBy.TextColor3 = Theme.Colors.TextDim
					killedBy.Visible = true
				end
			end)
		end
		-- Mode sets SpawnProtected = true on spawn and clears it on expiry or when you fire.
		local function sync()
			if character:GetAttribute("SpawnProtected") == true then
				setProtect(true, Tuning.Match.SpawnProtection)
			else
				setProtect(false)
			end
		end
		character:GetAttributeChangedSignal("SpawnProtected"):Connect(sync)
		sync()
	end
	Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
	if Players.LocalPlayer.Character then
		task.spawn(onCharacter, Players.LocalPlayer.Character)
	end
end

--------------------------------------------------------------------------------
-- Warmup card
--------------------------------------------------------------------------------

local function mountWarmup(gui: ScreenGui)
	local card = UIKit.panel({
		Name = "Warmup",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.18),
		Size = UDim2.fromOffset(420, 150),
		BackgroundTransparency = 0.4,
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(card)
	UIKit.text("WARMUP", {
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.fromOffset(200, 14),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		FontFace = Theme.Fonts.Bold,
		Parent = card,
	})
	local countdown = UIKit.mono("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 10),
		Size = UDim2.fromOffset(200, 16),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	local headline = UIKit.text("", {
		Position = UDim2.fromOffset(18, 28),
		Size = UDim2.new(1, -36, 0, 28),
		TextSize = Theme.TextSize.Title,
		FontFace = Theme.Fonts.Light,
		TextColor3 = Theme.Colors.White,
		Parent = card,
	})
	UIKit.line({
		Position = UDim2.fromOffset(18, 62),
		Size = UDim2.new(1, -36, 0, 1),
		BackgroundTransparency = 0.85,
		Parent = card,
	})
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local lines = {
		"Steal the enemy Flag. Bring it to your base while yours is home.",
		"Carrying the Flag: knife only, but you move fast. Escort your carrier.",
		"Broken lights stay broken. Every capture shifts the facility.",
		if touch
			then "LOADOUT (top right) to change your primary"
			else "[B] loadout   ·   [H] controls   ·   [Tab] scoreboard   ·   [O] settings",
	}
	for i, text in lines do
		UIKit.text(text, {
			Position = UDim2.fromOffset(18, 68 + (i - 1) * 18),
			Size = UDim2.new(1, -36, 0, 16),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = if i == 4 then Theme.Colors.TextFaint else Theme.Colors.TextDim,
			Parent = card,
		})
	end

	task.spawn(function()
		while true do
			local warm = MatchStore.Phase == "Warmup" and MatchStore.HasState
			card.Visible = warm
			if warm then
				local size = Tuning.Match.TeamSize
				headline.Text = string.format(
					"%dv%d  ·  CAPTURE THE FLAG  ·  FIRST TO %d CAPTURES",
					size,
					size,
					MatchStore.CaptureLimit
				)
				countdown.Text = string.format("MATCH STARTS IN %d", math.ceil(MatchStore.timeLeft()))
			end
			task.wait(0.2)
		end
	end)
end

function Banners.mount(gui: ScreenGui)
	mountShift(gui)
	local announce = mountAnnounce(gui)
	mountLife(gui)
	mountWarmup(gui)
	MatchStore.PhaseChanged:Connect(function(phase: string, old: string)
		if phase == "Live" and old == "Warmup" then
			announce("Match live", "Info")
		end
	end)
end

return Banners

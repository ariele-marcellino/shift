--!strict
-- Settings overlay (TEST_CONTRACT §6). Writes LocalPlayer attributes that other controllers read:
--   Setting_Sensitivity (number, 0.2-3.0, read by WeaponController)
--   Setting_FOV         (number, 70-90, read by WeaponController)
--   Setting_ReduceFlicker (bool, read by World's AmbienceController)
-- Attributes are only written when the player changes something, so Combat/World defaults stand
-- until then. Open with [O] on PC or the SETTINGS button (top-right) on touch. No saving (test build).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIKit = require(UI:WaitForChild("UIKit"))

local SettingsController = {}

local SENS_MIN, SENS_MAX, SENS_DEFAULT = 0.2, 3.0, 1.0
local FOV_MIN, FOV_MAX = 70, 90

local gui: ScreenGui
local overlay: Frame
local openButton: TextButton

local function setAttr(name: string, value: any)
	Players.LocalPlayer:SetAttribute(name, value)
end

local function getNumber(name: string, default: number): number
	local v = Players.LocalPlayer:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function rowLabel(parent: Instance, text: string, y: number)
	UIKit.text(text, {
		Position = UDim2.fromOffset(20, y),
		Size = UDim2.fromOffset(160, 18),
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	})
end

-- Horizontal slider. `format` renders the value; `onChange` fires while dragging.
local function slider(
	parent: Instance,
	y: number,
	min: number,
	max: number,
	step: number,
	initial: number,
	format: (number) -> string,
	onChange: (number) -> ()
)
	local valueLabel = UIKit.mono(format(initial), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, y),
		Size = UDim2.fromOffset(60, 18),
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	})
	-- Tall invisible hit area around a thin track (easy to grab with a thumb).
	local hit: TextButton = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, y + 20),
		Size = UDim2.new(1, -40, 0, 28),
		ZIndex = 2,
		Parent = parent,
	})
	local track = UIKit.line({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundTransparency = 0.8,
		ZIndex = 2,
		Parent = hit,
	})
	local fill = UIKit.line({
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 0.1,
		ZIndex = 2,
		Parent = track,
	})
	local knob: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = hit,
	}, { UIKit.corner(UDim.new(0.5, 0)) })

	local function show(value: number)
		local alpha = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = format(value)
	end
	show(initial)

	local dragging: InputObject? = nil
	local function update(x: number)
		local alpha = math.clamp((x - hit.AbsolutePosition.X) / math.max(1, hit.AbsoluteSize.X), 0, 1)
		local value = min + alpha * (max - min)
		value = math.clamp(math.floor(value / step + 0.5) * step, min, max)
		show(value)
		onChange(value)
	end
	hit.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = input
			update(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or (input.UserInputType == Enum.UserInputType.Touch and input == dragging)
		then
			update(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
		end
	end)
end

local function toggle(parent: Instance, y: number, initial: boolean, onChange: (boolean) -> ())
	local on = initial
	local button = UIKit.button("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, y - 6),
		Size = UDim2.fromOffset(70, 30),
		TextSize = Theme.TextSize.Caption,
		ZIndex = 2,
		Parent = parent,
	})
	local function render()
		button.Text = if on then "ON" else "OFF"
		button.TextColor3 = if on then Theme.Colors.White else Theme.Colors.TextDim
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = if on then 0.2 else 0.7
		end
	end
	render()
	button.Activated:Connect(function()
		on = not on
		render()
		onChange(on)
	end)
end

function SettingsController:SetOpen(open: boolean)
	overlay.Visible = open
end

function SettingsController:Toggle()
	self:SetOpen(not overlay.Visible)
end

function SettingsController:Init()
	gui = UIKit.screenGui("ShiftSettings", 25)

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	openButton = UIKit.button(if touch then "SETTINGS" else "[O]  SETTINGS", {
		Name = "SettingsButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(if touch then 84 else 104, 26),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		BackgroundTransparency = 0.6,
		Parent = gui,
	}, function()
		SettingsController:Toggle()
	end)
	UIKit.autoScale(openButton)

	overlay = UIKit.new("Frame", {
		Name = "Settings",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UIKit.modalBackdrop(overlay, function()
		SettingsController:SetOpen(false)
	end)

	local card = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 290),
		BackgroundTransparency = 0.12,
		ZIndex = 2,
		Parent = overlay,
	})
	UIKit.autoScale(card)
	UIKit.text("SETTINGS", {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.fromOffset(200, 16),
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
		SettingsController:SetOpen(false)
	end)

	local camera = workspace.CurrentCamera
	local fovDefault = math.clamp(camera and camera.FieldOfView or FOV_MIN, FOV_MIN, FOV_MAX)

	rowLabel(card, if touch then "Look sensitivity" else "Mouse sensitivity", 50)
	slider(
		card,
		50,
		SENS_MIN,
		SENS_MAX,
		0.05,
		getNumber("Setting_Sensitivity", SENS_DEFAULT),
		function(v: number)
			return string.format("%.2fx", v)
		end,
		function(v: number)
			setAttr("Setting_Sensitivity", v)
		end
	)

	rowLabel(card, "Field of view", 110)
	slider(card, 110, FOV_MIN, FOV_MAX, 1, getNumber("Setting_FOV", fovDefault), function(v: number)
		return string.format("%d", v)
	end, function(v: number)
		setAttr("Setting_FOV", v)
	end)

	rowLabel(card, "Reduce flicker", 176)
	toggle(card, 176, Players.LocalPlayer:GetAttribute("Setting_ReduceFlicker") == true, function(on: boolean)
		setAttr("Setting_ReduceFlicker", on)
	end)

	UIKit.button("CONTROLS", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -18),
		Size = UDim2.fromOffset(120, 34),
		TextSize = Theme.TextSize.Caption,
		ZIndex = 2,
		Parent = card,
	}, function()
		SettingsController:SetOpen(false)
		local mod = script.Parent:FindFirstChild("HudController")
		if mod then
			local ok, hud = pcall(require, mod)
			if ok and type(hud) == "table" and type(hud.ToggleHelp) == "function" then
				hud:ToggleHelp()
			end
		end
	end)
	UIKit.text("Applies immediately. Not saved in the test build.", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -26),
		Size = UDim2.fromOffset(200, 16),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})
end

function SettingsController:Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.O then
			SettingsController:Toggle()
		end
	end)
end

return SettingsController

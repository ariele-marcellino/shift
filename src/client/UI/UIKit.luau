--!strict
-- Small helpers for building SHIFT's UI in code. Not a controller (lives outside Controllers/).
--
-- Sizing model: clusters are positioned with Scale + AnchorPoint and sized in offset pixels designed
-- for a ~1000x500 screen; UIKit.autoScale() adds a UIScale that tracks the viewport so the same
-- layout fits phones, tablets and PCs.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UIKit = {}

local REF_WIDTH = 1000
local REF_HEIGHT = 500
local MIN_SCALE = 0.7
local MAX_SCALE = 1.4

--------------------------------------------------------------------------------
-- Instance builder
--------------------------------------------------------------------------------

local function applyProps(inst: Instance, props: { [string]: any })
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
end

function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = (Instance.new :: any)(className)
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props then
		applyProps(inst, props)
	end
	return inst
end

function UIKit.corner(radius: UDim?): UICorner
	return UIKit.new("UICorner", { CornerRadius = radius or Theme.Corner })
end

-- Hairline border.
function UIKit.stroke(color: Color3?, transparency: number?, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Transparency = transparency or Theme.StrokeT,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.padding(px: number, vertical: number?): UIPadding
	local h = UDim.new(0, px)
	local v = UDim.new(0, vertical or px)
	return UIKit.new("UIPadding", { PaddingTop = v, PaddingBottom = v, PaddingLeft = h, PaddingRight = h })
end

function UIKit.list(
	direction: Enum.FillDirection,
	spacing: number,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, spacing),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
	})
end

-- Plain text over the dark world. A faint text stroke keeps it readable against lit walls.
function UIKit.text(text: string, props: { [string]: any }?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Regular,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Body,
		TextStrokeColor3 = Theme.Colors.Black,
		TextStrokeTransparency = 0.8,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 18),
	})
	if props then
		applyProps(label, props)
	end
	return label
end

-- Monospace data text (timers, ammo, numbers).
function UIKit.mono(text: string, props: { [string]: any }?): TextLabel
	local label = UIKit.text(text, { FontFace = Theme.Fonts.Mono })
	if props then
		applyProps(label, props)
	end
	return label
end

-- Translucent dark panel with a hairline border.
function UIKit.panel(props: { [string]: any }?): Frame
	local frame: Frame = UIKit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.PanelT,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(200, 100),
	}, { UIKit.corner(), UIKit.stroke() })
	if props then
		applyProps(frame, props)
	end
	return frame
end

-- Solid line / bar.
function UIKit.line(props: { [string]: any }?): Frame
	local frame: Frame = UIKit.new("Frame", {
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
	})
	if props then
		applyProps(frame, props)
	end
	return frame
end

-- Outlined tactical button: thin border, uppercase label, subtle fill on press.
function UIKit.button(text: string, props: { [string]: any }?, onActivated: (() -> ())?): TextButton
	local button: TextButton = UIKit.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.PanelRaised,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Medium,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Body,
		Size = UDim2.fromOffset(150, 40),
	}, { UIKit.corner(), UIKit.stroke(nil, 0.7) })
	button.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			button.BackgroundColor3 = Theme.Colors.Stroke
			button.BackgroundTransparency = 0.8
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			button.BackgroundColor3 = Theme.Colors.PanelRaised
			button.BackgroundTransparency = 0.35
		end
	end)
	if onActivated then
		button.Activated:Connect(onActivated)
	end
	if props then
		applyProps(button, props)
	end
	return button
end

-- Invisible full-screen Modal button: while visible it frees the mouse from first-person lock so
-- overlays (settings, help, report) can be clicked. Clicking the backdrop calls onClick (optional).
function UIKit.modalBackdrop(parent: Instance, onClick: (() -> ())?): TextButton
	local b: TextButton = UIKit.new("TextButton", {
		Name = "ModalBackdrop",
		Modal = true,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = parent,
	})
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

--------------------------------------------------------------------------------
-- Tweens
--------------------------------------------------------------------------------

function UIKit.tween(
	inst: Instance,
	time: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	t:Play()
	return t
end

--------------------------------------------------------------------------------
-- Screen-size scaling
--------------------------------------------------------------------------------

local scales: { [UIScale]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local currentScale = 1

local function computeScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local vp = camera.ViewportSize
	if vp.X < 2 or vp.Y < 2 then
		return 1
	end
	return math.clamp(math.min(vp.X / REF_WIDTH, vp.Y / REF_HEIGHT), MIN_SCALE, MAX_SCALE)
end

local function refreshScales()
	currentScale = computeScale()
	for s in scales do
		if s.Parent then
			s.Scale = currentScale
		end
	end
end

local viewportConn: RBXScriptConnection? = nil
local function watchCamera()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
	end
	refreshScales()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

-- Adds a UIScale to `gui` that follows the screen size (scales around the gui's AnchorPoint).
function UIKit.autoScale(gui: Instance): UIScale
	local s = UIKit.new("UIScale", { Name = "AutoScale" })
	s.Scale = currentScale
	scales[s] = true
	s.Parent = gui
	return s
end

function UIKit.getScale(): number
	return currentScale
end

--------------------------------------------------------------------------------
-- Containers
--------------------------------------------------------------------------------

function UIKit.getPlayerGui(): PlayerGui
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

-- A ScreenGui that survives respawn. `fullScreen` = ignore the top-bar inset and safe-area insets
-- (used for the crosshair and world markers, which must line up with the 3D viewport).
function UIKit.screenGui(name: string, displayOrder: number, fullScreen: boolean?): ScreenGui
	return UIKit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = fullScreen == true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		ScreenInsets = if fullScreen then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets,
		Parent = UIKit.getPlayerGui(),
	})
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

function UIKit.formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return UIKit

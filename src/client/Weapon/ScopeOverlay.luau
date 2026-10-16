--!strict
-- Sniper scope overlay: black surround with a circular sight picture, soft inner vignette, thin
-- black crosshair with thicker outer posts and a centre gap. Built from frames only (no image ids).
-- The black surround is a circle frame with a very thick UIStroke plus side bars as a fallback.

local Players = game:GetService("Players")

local ScopeOverlay = {}

local gui: ScreenGui
local root: Frame

local function frame(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	color: Color3,
	transparency: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

function ScopeOverlay.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "ScopeOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1 -- under the HUD
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	root = frame(gui, "Root", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(), 1)
	local black = Color3.new(0, 0, 0)

	-- circle sized to 92% of screen height
	local circle = frame(root, "Circle", UDim2.fromScale(0.92, 0.92), UDim2.fromScale(0.5, 0.5), black, 1)
	circle.SizeConstraint = Enum.SizeConstraint.RelativeYY
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local surround = Instance.new("UIStroke")
	surround.Thickness = 2000
	surround.Color = black
	surround.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	surround.Parent = circle

	-- side bars beyond the circle's bounding square (in case the stroke is clipped)
	local left = frame(root, "Left", UDim2.fromScale(0.5, 1), UDim2.fromScale(0, 0.5), black)
	left.AnchorPoint = Vector2.new(1, 0.5)
	left.Position = UDim2.fromScale(0.5, 0.5)
	local right = frame(root, "Right", UDim2.fromScale(0.5, 1), UDim2.fromScale(0.5, 0.5), black)
	right.AnchorPoint = Vector2.new(0, 0.5)
	local function placeBars()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		local half = vp.Y * 0.46
		left.Position = UDim2.new(0.5, -half, 0.5, 0)
		right.Position = UDim2.new(0.5, half, 0.5, 0)
	end
	placeBars()
	task.spawn(function()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(placeBars)
		end
	end)

	-- soft inner vignette: a slightly smaller ring with a translucent stroke
	local inner = frame(circle, "Vignette", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), black, 1)
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0.5, 0)
	innerCorner.Parent = inner
	local soft = Instance.new("UIStroke")
	soft.Thickness = 28
	soft.Transparency = 0.45
	soft.Color = black
	soft.Parent = inner

	-- crosshair: thin full lines with a centre gap, thick outer posts
	local thin = 2
	local gap = 0.03
	local len = 0.5 - gap
	frame(circle, "H1", UDim2.new(len, 0, 0, thin), UDim2.fromScale(len / 2, 0.5), black)
	frame(circle, "H2", UDim2.new(len, 0, 0, thin), UDim2.fromScale(1 - len / 2, 0.5), black)
	frame(circle, "V1", UDim2.new(0, thin, len, 0), UDim2.fromScale(0.5, len / 2), black)
	frame(circle, "V2", UDim2.new(0, thin, len, 0), UDim2.fromScale(0.5, 1 - len / 2), black)
	local post = 0.18
	frame(circle, "PostL", UDim2.new(post, 0, 0, 7), UDim2.fromScale(post / 2, 0.5), black)
	frame(circle, "PostR", UDim2.new(post, 0, 0, 7), UDim2.fromScale(1 - post / 2, 0.5), black)
	frame(circle, "PostB", UDim2.new(0, 7, post, 0), UDim2.fromScale(0.5, 1 - post / 2), black)
	local dot =
		frame(circle, "Dot", UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(200, 40, 30))
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
end

function ScopeOverlay.SetVisible(on: boolean)
	if gui and gui.Enabled ~= on then
		gui.Enabled = on
	end
end

return ScopeOverlay

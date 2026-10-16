--!strict
-- Top-center match bar: your team on the left, enemy on the right.
--   [ BLUE  2  ■■□ ]   4:31   [ □■■  1  RED ]
--   CORE SECURE                 TAKEN · Unit-07
-- The whole bar is a button so phones can tap it to toggle the scoreboard.

local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local MatchStore = require(script.Parent.Parent.MatchStore)

local MatchBar = {}

type Side = {
	Name: TextLabel,
	Score: TextLabel,
	Pips: Frame,
	Core: TextLabel,
	CoreDot: Frame,
}

local function coreText(team: string, mine: boolean): (string, boolean)
	local core = MatchStore.Cores[team]
	if not core then
		return "FLAG  ·  --", false
	end
	if core.State == "Home" then
		return "FLAG SECURE", false
	elseif core.State == "Carried" then
		local who = core.CarrierName or "?"
		return (if mine then "FLAG TAKEN  ·  " else "FLAG CARRIED  ·  ") .. who, true
	elseif core.State == "Dropped" then
		local t = MatchStore.returnIn(team)
		return "FLAG DROPPED" .. (if t then string.format("  ·  RETURN %d", math.ceil(t)) else ""), true
	end
	return "FLAG  ·  " .. tostring(core.State), false
end

function MatchBar.mount(gui: ScreenGui): TextButton
	local root: TextButton = UIKit.new("TextButton", {
		Name = "MatchBar",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(380, 52),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(root)

	local bar = UIKit.panel({
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = Theme.PanelT,
		Parent = root,
	})

	local timer = UIKit.mono("0:00", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(80, 22),
		TextSize = Theme.TextSize.Label + 2,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bar,
	})
	local phaseLabel = UIKit.text("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(100, 12),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		FontFace = Theme.Fonts.Medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bar,
	})

	local function makeSide(isLeft: boolean): Side
		local align = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		local x = if isLeft then 0 else 1
		local sign = if isLeft then 1 else -1
		local name = UIKit.text("", {
			AnchorPoint = Vector2.new(x, 0.5),
			Position = UDim2.new(x, sign * 10, 0.5, 0),
			Size = UDim2.fromOffset(46, 16),
			TextSize = Theme.TextSize.Caption,
			FontFace = Theme.Fonts.Bold,
			TextXAlignment = align,
			Parent = bar,
		})
		local score = UIKit.mono("0", {
			AnchorPoint = Vector2.new(x, 0.5),
			Position = UDim2.new(x, sign * 58, 0.5, 0),
			Size = UDim2.fromOffset(20, 22),
			TextSize = Theme.TextSize.Title - 2,
			TextColor3 = Theme.Colors.White,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = bar,
		})
		local pips: Frame = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(x, 0.5),
			Position = UDim2.new(x, sign * 84, 0.5, 0),
			Size = UDim2.fromOffset(46, 6),
			BackgroundTransparency = 1,
			Parent = bar,
		}, {
			UIKit.list(
				Enum.FillDirection.Horizontal,
				3,
				if isLeft then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right
			),
		})
		local coreDot: Frame = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(x, 0),
			Position = UDim2.new(x, sign * 4, 0, 38),
			Size = UDim2.fromOffset(5, 5),
			Rotation = 45,
			BorderSizePixel = 0,
			Parent = root,
		})
		local core = UIKit.text("", {
			AnchorPoint = Vector2.new(x, 0),
			Position = UDim2.new(x, sign * 14, 0, 34),
			Size = UDim2.fromOffset(160, 14),
			TextSize = Theme.TextSize.Tiny,
			FontFace = Theme.Fonts.Medium,
			TextXAlignment = align,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = root,
		})
		return { Name = name, Score = score, Pips = pips, Core = core, CoreDot = coreDot }
	end

	local left = makeSide(true)
	local right = makeSide(false)

	local function setPips(side: Side, team: string, score: number)
		local limit = math.clamp(MatchStore.CaptureLimit, 1, 10)
		local frames = {}
		for _, c in side.Pips:GetChildren() do
			if c:IsA("Frame") then
				table.insert(frames, c)
			end
		end
		for i = #frames + 1, limit do
			table.insert(
				frames,
				UIKit.new("Frame", {
					Size = UDim2.fromOffset(12, 4),
					BorderSizePixel = 0,
					LayoutOrder = i,
					Parent = side.Pips,
				})
			)
		end
		for i, f in frames do
			f.Visible = i <= limit
			-- Pips fill from the outer edge inwards, mirrored on the right side.
			local order = if side == right then limit - i + 1 else i
			f.LayoutOrder = order
			f.BackgroundColor3 = Theme.teamColor(team)
			f.BackgroundTransparency = if i <= score then 0.05 else 0.8
		end
	end

	local function refresh()
		local mine = MatchStore.localTeam() or "Blue"
		local enemy = Theme.enemyOf(mine) or "Red"
		for _, pair in { { left, mine, true }, { right, enemy, false } } do
			local side: Side, team: string, isMine: boolean = pair[1], pair[2], pair[3]
			local color = Theme.teamColor(team)
			side.Name.Text = string.upper(team)
			side.Name.TextColor3 = color
			local score = MatchStore.Score[team] or 0
			side.Score.Text = tostring(score)
			setPips(side, team, score)
			local text, alert = coreText(team, isMine)
			side.Core.Text = text
			side.Core.TextColor3 = if alert then Theme.Colors.White else Theme.Colors.TextDim
			side.CoreDot.BackgroundColor3 = color
			side.CoreDot.BackgroundTransparency = if alert then 0 else 0.5
		end
		local phase = MatchStore.Phase
		timer.Text = if phase == "Waiting" then "--:--" else UIKit.formatTime(MatchStore.timeLeft())
		phaseLabel.Text = if phase == "Waiting"
			then "WAITING FOR PLAYERS"
			elseif phase == "Warmup" then "WARMUP"
			elseif phase == "Ended" then "MATCH OVER"
			else ""
		timer.TextColor3 = if phase == "Live" and MatchStore.timeLeft() <= 60
			then Theme.Colors.Bad
			else Theme.Colors.White
	end

	MatchStore.Changed:Connect(refresh)
	refresh()
	task.spawn(function()
		while true do
			task.wait(0.2)
			refresh()
		end
	end)

	return root
end

return MatchBar

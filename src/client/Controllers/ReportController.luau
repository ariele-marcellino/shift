--!strict
-- End-of-match Facility Report (TEST_CONTRACT §6). Full-screen, dark, built to be screenshotted:
--   left:  winner + score, MVP, per-team scoreboard (K / D / CAP / RET)
--   right: top-down blueprint of the facility from MapSnapshot (grid, base markers, hinges open /
--          sealed, lamps lit / broken), "x of y lights destroyed", list of shifts
-- On open, every lamp starts lit and the broken ones flicker out one by one: a short replay of how
-- the facility went dark. Closes with the button or automatically when the next match warms up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIKit = require(UI:WaitForChild("UIKit"))
local MatchStore = require(UI:WaitForChild("MatchStore"))

local ReportController = {}

local gui: ScreenGui
local content: Frame? = nil
local token = 0

local function hud(): any
	local mod = script.Parent:FindFirstChild("HudController")
	if not mod then
		return nil
	end
	local ok, result = pcall(require, mod)
	return if ok then result else nil
end

local function setHudHidden(hidden: boolean)
	local h = hud()
	if h and type(h.SetHiddenByReport) == "function" then
		pcall(h.SetHiddenByReport, h, hidden)
	end
end

local function caption(text: string, props: { [string]: any }?): TextLabel
	local label = UIKit.text(text, {
		Size = UDim2.new(1, 0, 0, 12),
		TextSize = Theme.TextSize.Tiny,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.TextFaint,
		TextStrokeTransparency = 1,
	})
	if props then
		for k, v in props do
			(label :: any)[k] = v
		end
	end
	return label
end

local function hide()
	token += 1
	if content then
		content:Destroy()
		content = nil
	end
	gui.Enabled = false
	setHudHidden(false)
end

--------------------------------------------------------------------------------
-- Map
--------------------------------------------------------------------------------

local function drawMap(parent: Frame, snapshot: any, myToken: number)
	local bounds = snapshot and snapshot.Bounds
	local minV: Vector3 = (bounds and typeof(bounds.Min) == "Vector3") and bounds.Min
		or Vector3.new(-100, 0, -100)
	local maxV: Vector3 = (bounds and typeof(bounds.Max) == "Vector3") and bounds.Max
		or Vector3.new(100, 0, 100)
	local range = maxV - minV
	-- Long axis horizontal so the map fills a landscape panel.
	local swap = math.abs(range.Z) > math.abs(range.X)
	local spanH = math.max(1, math.abs(if swap then range.Z else range.X))
	local spanV = math.max(1, math.abs(if swap then range.X else range.Z))

	local function uv(p: Vector3): (number, number)
		local d = p - minV
		local u = (if swap then d.Z else d.X) / spanH
		local v = (if swap then d.X else d.Z) / spanV
		return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
	end

	local canvas: Frame = UIKit.new("Frame", {
		Name = "Canvas",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = math.clamp(spanH / spanV, 0.5, 4) }),
		UIKit.stroke(nil, 0.8),
	})

	-- Blueprint grid
	for i = 1, 9 do
		UIKit.line({
			Position = UDim2.fromScale(i / 10, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundTransparency = 0.95,
			Parent = canvas,
		})
		UIKit.line({
			Position = UDim2.fromScale(0, i / 10),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundTransparency = 0.95,
			Parent = canvas,
		})
	end
	-- Mirror line
	UIKit.line({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundTransparency = 0.85,
		Parent = canvas,
	})

	-- Bases (last known Core home positions)
	for team, pos in MatchStore.HomePositions do
		local u, v = uv(pos)
		local color = Theme.teamColor(team)
		UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(u, v),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = canvas,
		}, { UIKit.corner(UDim.new(0.5, 0)) })
		UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(u, v),
			Size = UDim2.fromOffset(9, 9),
			Rotation = 45,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		})
		caption(string.upper(team) .. " FLAG", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(u, 0, v, 10),
			Size = UDim2.fromOffset(80, 12),
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
			Parent = canvas,
		})
	end

	-- Hinges
	local hinges = (snapshot and type(snapshot.Hinges) == "table") and snapshot.Hinges or {}
	for _, h in hinges do
		if typeof(h.Position) ~= "Vector3" then
			continue
		end
		local size: Vector3 = typeof(h.Size) == "Vector3" and h.Size or Vector3.new(8, 8, 8)
		local u, v = uv(h.Position)
		local sw = math.abs(if swap then size.Z else size.X) / spanH
		local sh = math.abs(if swap then size.X else size.Z) / spanV
		local open = h.Open == true
		local color = if open then Theme.Colors.Good else Theme.Colors.Bad
		UIKit.new("Frame", {
			Name = "Hinge_" .. tostring(h.Id),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(u, v),
			Size = UDim2.fromScale(sw, sh),
			BackgroundColor3 = color,
			BackgroundTransparency = if open then 0.9 else 0.35,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = canvas,
		}, {
			UIKit.stroke(color, if open then 0.2 else 0.5),
			UIKit.new("UISizeConstraint", { MinSize = Vector2.new(5, 5) }),
		})
	end

	-- Lamps: all start lit, broken ones flicker out in sequence.
	local lamps = (snapshot and type(snapshot.Lamps) == "table") and snapshot.Lamps or {}
	local broken: { { Dot: Frame, Glow: Frame } } = {}
	for _, l in lamps do
		if typeof(l.Position) ~= "Vector3" then
			continue
		end
		local u, v = uv(l.Position)
		local glow: Frame = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(u, v),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = Theme.Colors.Amber,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = canvas,
		}, { UIKit.corner(UDim.new(0.5, 0)) })
		local dot: Frame = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(u, v),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Theme.Colors.Amber,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = canvas,
		}, { UIKit.corner(UDim.new(0.5, 0)), UIKit.stroke(Theme.Colors.Bad, 1) })
		if l.Broken == true then
			table.insert(broken, { Dot = dot, Glow = glow })
		end
	end

	task.spawn(function()
		task.wait(0.8)
		local step = math.clamp(1.6 / math.max(1, #broken), 0.05, 0.25)
		for _, b in broken do
			if myToken ~= token then
				return
			end
			-- Two quick flickers, then dark.
			for _ = 1, 2 do
				b.Glow.BackgroundTransparency = 1
				task.wait(0.04)
				b.Glow.BackgroundTransparency = 0.82
				task.wait(0.04)
			end
			b.Glow.BackgroundTransparency = 1
			b.Dot.BackgroundColor3 = Theme.Colors.PanelRaised
			local stroke = b.Dot:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0.15
			end
			task.wait(step)
		end
	end)
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function show(report: any)
	if type(report) ~= "table" then
		return
	end
	hide()
	local myToken = token
	setHudHidden(true)
	gui.Enabled = true

	local root: Frame = UIKit.new("Frame", {
		Name = "Report",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	content = root
	local backdrop = UIKit.modalBackdrop(root)
	backdrop.BackgroundTransparency = 1
	UIKit.tween(backdrop, 0.6, { BackgroundTransparency = 0.12 })

	local card: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(940, 460),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})
	UIKit.autoScale(card)

	-- Header ---------------------------------------------------------------------------------------
	caption(
		"FACILITY REPORT",
		{ Position = UDim2.fromOffset(0, 0), TextColor3 = Theme.Colors.Amber, Parent = card }
	)
	caption(
		"LEVEL 0  ·  OFFICE ANNEX  ·  " .. DateTime.now():FormatLocalTime("YYYY-MM-DD  HH:mm", "en-us"),
		{
			Position = UDim2.fromOffset(120, 0),
			Size = UDim2.fromOffset(400, 12),
			Parent = card,
		}
	)
	local nextLabel = caption("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -96, 0, 0),
		Size = UDim2.fromOffset(200, 12),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	UIKit.button("CLOSE", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -8),
		Size = UDim2.fromOffset(84, 28),
		TextSize = Theme.TextSize.Tiny,
		Parent = card,
	}, hide)
	UIKit.line({ Position = UDim2.fromOffset(0, 24), BackgroundTransparency = 0.85, Parent = card })

	local winner = if type(report.Winner) == "string" and report.Winner ~= "" then report.Winner else nil
	local score = type(report.Score) == "table" and report.Score or MatchStore.Score
	local mine = MatchStore.localTeam()
	local headline = if winner then string.upper(winner) .. " HOLDS THE FACILITY" else "STALEMATE"
	UIKit.text(headline, {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.fromOffset(560, 42),
		TextSize = Theme.TextSize.Hero,
		FontFace = Theme.Fonts.Light,
		TextColor3 = if winner then Theme.teamColor(winner) else Theme.Colors.White,
		TextScaled = false,
		Parent = card,
	})
	local outcome = if not winner or not mine then "" elseif winner == mine then "VICTORY" else "DEFEAT"
	caption(outcome, {
		Position = UDim2.fromOffset(2, 78),
		Size = UDim2.fromOffset(200, 12),
		TextColor3 = Theme.Colors.TextDim,
		Parent = card,
	})
	-- Score: BLUE 3 — 1 RED
	local scoreRow: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 38),
		Size = UDim2.fromOffset(300, 40),
		BackgroundTransparency = 1,
		Parent = card,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right) })
	local parts = {
		{ "BLUE", Theme.teamColor("Blue"), Theme.Fonts.Bold, Theme.TextSize.Caption },
		{ tostring(tonumber(score.Blue) or 0), Theme.Colors.White, Theme.Fonts.Mono, Theme.TextSize.Hero },
		{ "—", Theme.Colors.TextFaint, Theme.Fonts.Light, Theme.TextSize.Title },
		{ tostring(tonumber(score.Red) or 0), Theme.Colors.White, Theme.Fonts.Mono, Theme.TextSize.Hero },
		{ "RED", Theme.teamColor("Red"), Theme.Fonts.Bold, Theme.TextSize.Caption },
	}
	for i, p in parts do
		UIKit.text(p[1], {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			TextColor3 = p[2],
			FontFace = p[3],
			TextSize = p[4],
			TextWrapped = false,
			LayoutOrder = i,
			Parent = scoreRow,
		})
	end

	-- Left column: MVP + scoreboard ----------------------------------------------------------------
	local left: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.fromOffset(420, 360),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local mvp = type(report.Mvp) == "table" and report.Mvp or nil
	local mvpCard = UIKit.panel({
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 0.5,
		Parent = left,
	})
	caption("MVP", { Position = UDim2.fromOffset(14, 9), TextColor3 = Theme.Colors.Amber, Parent = mvpCard })
	UIKit.text(if mvp then tostring(mvp.Name) else "--", {
		Position = UDim2.fromOffset(14, 22),
		Size = UDim2.new(0.6, 0, 0, 26),
		TextSize = Theme.TextSize.Title,
		FontFace = Theme.Fonts.Regular,
		TextColor3 = Theme.Colors.White,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = mvpCard,
	})
	UIKit.mono(
		if mvp
			then string.format(
				"%d KILLS  ·  %d CAPTURES",
				tonumber(mvp.Kills) or 0,
				tonumber(mvp.Captures) or 0
			)
			else "",
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(180, 16),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = mvpCard,
		}
	)

	local board: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 1, -68),
		BackgroundTransparency = 1,
		Parent = left,
	}, {
		UIKit.list(Enum.FillDirection.Vertical, 1, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})

	local players = type(report.Players) == "table" and report.Players or {}
	local order = 0
	local COLS = { { "K", "Kills" }, { "D", "Deaths" }, { "CAP", "Captures" }, { "RET", "Returns" } }
	local function row(cells: { string }, color: Color3, font: Font, highlight: boolean, height: number)
		order += 1
		local r: Frame = UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = if highlight then 0.93 else 1,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = board,
		})
		UIKit.text(cells[1], {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(0.5, -8, 1, 0),
			TextSize = Theme.TextSize.Caption,
			FontFace = font,
			TextColor3 = color,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = r,
		})
		for i = 2, #cells do
			UIKit.text(cells[i], {
				Position = UDim2.fromScale(0.5 + (i - 2) * 0.125, 0),
				Size = UDim2.fromScale(0.125, 1),
				TextSize = Theme.TextSize.Caption,
				FontFace = if font == Theme.Fonts.Bold then font else Theme.Fonts.Mono,
				TextColor3 = if font == Theme.Fonts.Bold then Theme.Colors.TextFaint else Theme.Colors.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = r,
			})
		end
	end
	local me = Players.LocalPlayer
	for _, team in { "Blue", "Red" } do
		local list = {}
		for _, p in players do
			if type(p) == "table" and p.Team == team then
				table.insert(list, p)
			end
		end
		table.sort(list, function(a, b)
			local ca, cb = tonumber(a.Captures) or 0, tonumber(b.Captures) or 0
			if ca ~= cb then
				return ca > cb
			end
			return (tonumber(a.Kills) or 0) > (tonumber(b.Kills) or 0)
		end)
		local header = { string.upper(team) }
		for _, c in COLS do
			table.insert(header, c[1])
		end
		row(header, Theme.teamColor(team), Theme.Fonts.Bold, false, 20)
		for _, p in list do
			local cells = { tostring(p.Name) }
			for _, c in COLS do
				table.insert(cells, tostring(tonumber(p[c[2]]) or 0))
			end
			local isMe = p.Name == me.Name or p.Name == me.DisplayName
			row(cells, if isMe then Theme.Colors.White else Theme.Colors.Text, Theme.Fonts.Regular, isMe, 20)
		end
		order += 1
		UIKit.new(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 1, LayoutOrder = order, Parent = board }
		)
	end

	-- Right column: map + lights + shifts ----------------------------------------------------------
	local right: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 100),
		Size = UDim2.fromOffset(490, 360),
		BackgroundTransparency = 1,
		Parent = card,
	})
	caption("FACILITY STATE  ·  END OF MATCH", { Parent = right })
	local mapHolder: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundTransparency = 1,
		Parent = right,
	})
	drawMap(mapHolder, report.MapSnapshot, myToken)

	-- Legend
	local legend: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 222),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Parent = right,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Left) })
	local legendItems = {
		{ "LIGHT ON", Theme.Colors.Amber, true },
		{ "LIGHT DESTROYED", Theme.Colors.PanelRaised, true },
		{ "ROUTE OPEN", Theme.Colors.Good, false },
		{ "ROUTE SEALED", Theme.Colors.Bad, false },
	}
	for i, item in legendItems do
		local holder: Frame = UIKit.new("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 14),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = legend,
		}, { UIKit.list(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left) })
		UIKit.new("Frame", {
			Size = UDim2.fromOffset(if item[3] then 6 else 10, 6),
			BackgroundColor3 = item[2],
			BackgroundTransparency = if i == 3 then 0.9 else 0,
			BorderSizePixel = 0,
			LayoutOrder = 1,
			Parent = holder,
		}, {
			UIKit.corner(if item[3] then UDim.new(0.5, 0) else UDim.new(0, 0)),
			UIKit.stroke(if i == 2 then Theme.Colors.Bad else item[2], if i == 2 then 0.15 else 0.3),
		})
		caption(item[1], {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 14),
			LayoutOrder = 2,
			TextWrapped = false,
			Parent = holder,
		})
	end

	-- Lights destroyed
	local total = tonumber(report.TotalLamps) or 0
	local brokenCount = type(report.BrokenLamps) == "table" and #report.BrokenLamps or 0
	local lightsRow: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 244),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = right,
	})
	local count = UIKit.mono("0", {
		Size = UDim2.fromOffset(48, 30),
		TextSize = Theme.TextSize.Hero - 6,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = lightsRow,
	})
	UIKit.text(string.format("of %d lights destroyed", total), {
		Position = UDim2.fromOffset(56, 8),
		Size = UDim2.fromOffset(240, 18),
		TextSize = Theme.TextSize.Label,
		FontFace = Theme.Fonts.Light,
		TextColor3 = Theme.Colors.TextDim,
		Parent = lightsRow,
	})
	local pct = if total > 0 then brokenCount / total else 0
	local track = UIKit.line({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(150, 3),
		BackgroundColor3 = Theme.Colors.Amber,
		BackgroundTransparency = 0.2,
		Parent = lightsRow,
	})
	local darkFill = UIKit.line({
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.PanelRaised,
		BackgroundTransparency = 0,
		Parent = track,
	})
	task.delay(0.8, function()
		if myToken ~= token then
			return
		end
		UIKit.tween(darkFill, 1.6, { Size = UDim2.fromScale(pct, 1) })
		local value = Instance.new("NumberValue")
		value.Changed:Connect(function(v: number)
			count.Text = tostring(math.floor(v + 0.5))
		end)
		UIKit.tween(value, 1.6, { Value = brokenCount }).Completed:Once(function()
			count.Text = tostring(brokenCount)
			value:Destroy()
		end)
	end)

	-- Shifts
	caption("SHIFTS", { Position = UDim2.fromOffset(0, 286), Parent = right })
	local shifts = type(report.Shifts) == "table" and report.Shifts or {}
	local shiftList: Frame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 300),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		Parent = right,
	}, {
		UIKit.list(Enum.FillDirection.Vertical, 1, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	if #shifts == 0 then
		UIKit.text("No shifts. The facility held its shape.", {
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.TextFaint,
			Parent = shiftList,
		})
	end
	for i, s in shifts do
		if i > 4 then
			break
		end
		local title = type(s) == "table" and tostring(s.Title or "") or ""
		local detail = type(s) == "table" and tostring(s.Detail or "") or ""
		UIKit.text(string.format("%02d   %s   ·   %s", i, string.upper(title), detail), {
			Size = UDim2.new(1, 0, 0, 15),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.TextDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			LayoutOrder = i,
			Parent = shiftList,
		})
	end

	-- Next match countdown (MatchState TimeLeft during "Ended").
	task.spawn(function()
		while myToken == token do
			if MatchStore.Phase == "Ended" then
				nextLabel.Text = string.format("NEXT MATCH IN %d", math.ceil(MatchStore.timeLeft()))
			else
				nextLabel.Text = ""
			end
			task.wait(0.25)
		end
	end)
end

function ReportController:Init()
	gui = UIKit.screenGui("ShiftReport", 30, true)
	gui.Enabled = false
end

function ReportController:Start()
	Remotes.Get("FacilityReport").OnClientEvent:Connect(function(report: any)
		local ok, err = pcall(show, report)
		if not ok then
			warn("[UI] Facility Report failed to render: " .. tostring(err))
		end
	end)
	MatchStore.PhaseChanged:Connect(function(phase: string)
		if phase == "Waiting" or phase == "Warmup" or phase == "Live" then
			if gui.Enabled then
				hide()
			end
		end
	end)
end

return ReportController

--!strict
-- Team list (hold Tab on PC, tap the match bar on touch). Two columns, your team first.
-- Roster = Players on each team + bot models in workspace.Bots (attribute Team). K / D / CAP are
-- counted locally from KillFeed and captures since this client saw the match go live (the
-- authoritative totals come in the Facility Report).

local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local MatchStore = require(script.Parent.Parent.MatchStore)

local Scoreboard = {}

type Entry = { Name: string, Display: string, Bot: boolean, Me: boolean }

local function roster(team: string): { Entry }
	local list: { Entry } = {}
	local me = Players.LocalPlayer
	for _, p in Players:GetPlayers() do
		local t = (p.Team and p.Team.Name) or (p.Character and p.Character:GetAttribute("Team") :: any)
		if t == team then
			table.insert(list, { Name = p.Name, Display = p.DisplayName, Bot = false, Me = p == me })
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, m in bots:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Team") == team then
				table.insert(list, { Name = m.Name, Display = m.Name, Bot = true, Me = false })
			end
		end
	end
	return list
end

local function statsFor(e: Entry)
	return MatchStore.Stats[e.Display] or MatchStore.Stats[e.Name] or { Kills = 0, Deaths = 0, Captures = 0 }
end

function Scoreboard.mount(gui: ScreenGui)
	local root = UIKit.panel({
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(560, 230),
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(root)

	local columns: { Frame } = {}
	for i = 1, 2 do
		columns[i] = UIKit.new("Frame", {
			Position = UDim2.new((i - 1) * 0.5, if i == 1 then 14 else 7, 0, 12),
			Size = UDim2.new(0.5, -21, 1, -24),
			BackgroundTransparency = 1,
			Parent = root,
		}, {
			UIKit.list(
				Enum.FillDirection.Vertical,
				2,
				Enum.HorizontalAlignment.Left,
				Enum.VerticalAlignment.Top
			),
		})
	end

	local function cell(
		parent: Instance,
		text: string,
		x: number,
		w: number,
		props: { [string]: any }?
	): TextLabel
		local label = UIKit.text(text, {
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromScale(w, 1),
			TextSize = Theme.TextSize.Caption,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = parent,
		})
		if props then
			for k, v in props do
				(label :: any)[k] = v
			end
		end
		return label
	end

	local function render()
		local mine = MatchStore.localTeam() or "Blue"
		local enemy = Theme.enemyOf(mine) or "Red"
		for i, team in { mine, enemy } do
			local col = columns[i]
			for _, c in col:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			local color = Theme.teamColor(team)
			local header = UIKit.new(
				"Frame",
				{ Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 0, Parent = col }
			)
			cell(header, string.upper(team) .. (if team == mine then "  ·  YOUR TEAM" else ""), 0, 0.55, {
				TextColor3 = color,
				FontFace = Theme.Fonts.Bold,
			})
			cell(
				header,
				"K",
				0.55,
				0.15,
				{ TextColor3 = Theme.Colors.TextFaint, TextXAlignment = Enum.TextXAlignment.Center }
			)
			cell(
				header,
				"D",
				0.7,
				0.15,
				{ TextColor3 = Theme.Colors.TextFaint, TextXAlignment = Enum.TextXAlignment.Center }
			)
			cell(
				header,
				"CAP",
				0.85,
				0.15,
				{ TextColor3 = Theme.Colors.TextFaint, TextXAlignment = Enum.TextXAlignment.Center }
			)
			UIKit.line({
				BackgroundColor3 = color,
				BackgroundTransparency = 0.5,
				LayoutOrder = 1,
				Parent = col,
			})

			local entries = roster(team)
			table.sort(entries, function(a, b)
				local sa, sb = statsFor(a), statsFor(b)
				if sa.Kills ~= sb.Kills then
					return sa.Kills > sb.Kills
				end
				return a.Display < b.Display
			end)
			for n, e in entries do
				local s = statsFor(e)
				local row = UIKit.new("Frame", {
					Size = UDim2.new(1, 0, 0, 22),
					BackgroundColor3 = Theme.Colors.White,
					BackgroundTransparency = if e.Me then 0.93 else 1,
					BorderSizePixel = 0,
					LayoutOrder = 1 + n,
					Parent = col,
				})
				cell(row, "  " .. e.Display .. (if e.Bot then "  BOT" else ""), 0, 0.55, {
					TextColor3 = if e.Me then Theme.Colors.White else Theme.Colors.Text,
					FontFace = if e.Me then Theme.Fonts.Medium else Theme.Fonts.Regular,
				})
				for j, v in { s.Kills, s.Deaths, s.Captures } do
					cell(row, tostring(v), 0.4 + j * 0.15, 0.15, {
						FontFace = Theme.Fonts.Mono,
						TextColor3 = Theme.Colors.Text,
						TextXAlignment = Enum.TextXAlignment.Center,
					})
				end
			end
		end
	end

	local shown = false
	local generation = 0
	local api = {}
	function api.setVisible(visible: boolean)
		if visible == shown then
			return
		end
		shown = visible
		root.Visible = visible
		generation += 1
		if visible then
			render()
			local gen = generation
			task.spawn(function()
				while true do
					task.wait(0.5)
					if gen ~= generation then
						return
					end
					render()
				end
			end)
		end
	end
	function api.toggle()
		api.setVisible(not shown)
	end
	return api
end

return Scoreboard

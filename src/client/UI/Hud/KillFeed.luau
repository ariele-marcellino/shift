--!strict
-- Top-right kill feed: "Killer [weapon glyph] [wallbang] Victim" rows with HEADSHOT / CARRIER tags,
-- names in team color. Weapon glyphs are drawn from frames (UI/Glyphs).
-- Max 5 rows, each fades after a few seconds. Rows involving you get a brighter border.

local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local MatchStore = require(script.Parent.Parent.MatchStore)
local Glyphs = require(script.Parent.Parent.Glyphs)

local KillFeed = {}

local MAX_ROWS = 5
local ROW_SECONDS = 6

function KillFeed.mount(gui: ScreenGui)
	local root: Frame = UIKit.new("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 44),
		Size = UDim2.fromOffset(300, 140),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UIKit.list(
			Enum.FillDirection.Vertical,
			3,
			Enum.HorizontalAlignment.Right,
			Enum.VerticalAlignment.Top
		),
	})
	UIKit.autoScale(root)

	local order = 0

	local function word(text: string, color: Color3, props: { [string]: any }?): TextLabel
		local label = UIKit.text(text, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			TextSize = Theme.TextSize.Caption,
			TextColor3 = color,
			TextWrapped = false,
		})
		if props then
			for k, v in props do
				(label :: any)[k] = v
			end
		end
		return label
	end

	MatchStore.KillFeed:Connect(function(entry: any)
		order += 1
		local involvesMe = MatchStore.isMe(entry.Killer) or MatchStore.isMe(entry.Victim)
		local row = UIKit.panel({
			Name = "Row",
			LayoutOrder = -order, -- newest on top
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundTransparency = Theme.PanelTLight,
			Parent = root,
		})
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke and involvesMe then
			stroke.Transparency = 0.55
		end
		UIKit.list(Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Right).Parent = row
		UIKit.padding(8, 0).Parent = row

		local i = 0
		local function add(item: GuiObject)
			i += 1
			item.LayoutOrder = i
			item.Parent = row
		end
		local killer = tostring(entry.Killer or "")
		if killer ~= "" and killer ~= entry.Victim then
			add(word(killer, Theme.teamColor(entry.KillerTeam), { FontFace = Theme.Fonts.Medium }))
		end
		local weapon = if type(entry.Weapon) == "string" then entry.Weapon else "AK"
		local glyphW = if weapon == "Sniper" then 36 elseif weapon == "Frag" then 22 else 30
		add(Glyphs.make(weapon, UDim2.fromOffset(glyphW, 12), Theme.Colors.TextDim))
		if entry.Wallbang == true then
			add(Glyphs.wallbang(UDim2.fromOffset(14, 12), Theme.Colors.TextDim))
		end
		if entry.Headshot == true then
			add(
				word(
					"HEADSHOT",
					Theme.Colors.Head,
					{ FontFace = Theme.Fonts.Bold, TextSize = Theme.TextSize.Tiny }
				)
			)
		end
		add(
			word(
				tostring(entry.Victim or "?"),
				Theme.teamColor(entry.VictimTeam),
				{ FontFace = Theme.Fonts.Medium }
			)
		)
		if entry.CarrierKill == true then
			add(
				word(
					"CARRIER",
					Theme.Colors.White,
					{ FontFace = Theme.Fonts.Bold, TextSize = Theme.TextSize.Tiny }
				)
			)
		end

		-- Trim old rows.
		local rows = {}
		for _, c in root:GetChildren() do
			if c:IsA("Frame") then
				table.insert(rows, c)
			end
		end
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder -- newest first
		end)
		for idx = MAX_ROWS + 1, #rows do
			rows[idx]:Destroy()
		end

		task.delay(ROW_SECONDS, function()
			if not row.Parent then
				return
			end
			UIKit.tween(row, 0.4, { BackgroundTransparency = 1 })
			if stroke then
				UIKit.tween(stroke, 0.4, { Transparency = 1 })
			end
			for _, c in row:GetChildren() do
				if c:IsA("TextLabel") then
					UIKit.tween(c, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
				elseif c:IsA("Frame") then
					for _, part in c:GetChildren() do
						if part:IsA("Frame") then
							UIKit.tween(part, 0.4, { BackgroundTransparency = 1 })
						end
					end
				end
			end
			task.delay(0.45, function()
				row:Destroy()
			end)
		end)
	end)
end

return KillFeed

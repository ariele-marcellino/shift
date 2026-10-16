--!strict
-- Draws the global "most time played" board on the spawn-room panel(s) tagged "TimeLeaderboard"
-- from ReplicatedStorage.TimePlayedTop (TimePlayedService). Clean, dark panel; avatar headshots.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UI:WaitForChild("UIKit"))
local Theme = require(UI:WaitForChild("Theme"))

local LeaderboardController = {}

local TAG = "TimeLeaderboard"
local ROWS = 10

type Board = { Rows: { Frame }, Status: TextLabel }
local boards: { [BasePart]: Board } = {}

local function formatMinutes(minutes: number): string
	local h = math.floor(minutes / 60)
	local m = minutes % 60
	return if h > 0 then string.format("%dh %02dm", h, m) else string.format("%dm", m)
end

local function build(part: BasePart): Board
	local gui = UIKit.new("SurfaceGui", {
		Name = "TimeLeaderboard",
		Adornee = part,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 50,
		LightInfluence = 0.2,
		Brightness = 1.2,
		Parent = UIKit.getPlayerGui(),
	})
	local bg = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Parent = gui,
	}, { UIKit.padding(18, 14) })
	UIKit.text("MOST TIME PLAYED", {
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 20,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.White,
		TextStrokeTransparency = 1,
		Parent = bg,
	})
	UIKit.text("ALL SERVERS  ·  ALL TIME", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = 12,
		FontFace = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 1,
		Parent = bg,
	})
	local status = UIKit.text("", {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 13,
		TextColor3 = Theme.Colors.TextFaint,
		TextStrokeTransparency = 1,
		Parent = bg,
	})
	local list = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		Parent = bg,
	})
	local rows = {}
	for i = 1, ROWS do
		local row = UIKit.new("Frame", {
			Position = UDim2.fromScale(0, (i - 1) / ROWS),
			Size = UDim2.new(1, 0, 1 / ROWS, -2),
			BackgroundColor3 = Theme.Colors.PanelRaised,
			BackgroundTransparency = if i % 2 == 0 then 0.6 else 0.85,
			BorderSizePixel = 0,
			Visible = false,
			Parent = list,
		})
		UIKit.mono(tostring(i), {
			Name = "Rank",
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(0, 26, 1, 0),
			TextSize = 14,
			TextColor3 = if i <= 3 then Theme.Colors.Amber else Theme.Colors.TextDim,
			TextStrokeTransparency = 1,
			Parent = row,
		})
		UIKit.new("ImageLabel", {
			Name = "Head",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 34, 0.5, 0),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			Parent = row,
		}, { UIKit.corner(UDim.new(0.5, 0)) })
		UIKit.text("", {
			Name = "PlayerName",
			Position = UDim2.fromOffset(62, 0),
			Size = UDim2.new(1, -170, 1, 0),
			TextSize = 14,
			FontFace = Theme.Fonts.Medium,
			TextColor3 = Theme.Colors.White,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextStrokeTransparency = 1,
			Parent = row,
		})
		UIKit.mono("", {
			Name = "Time",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 100, 1, 0),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.Colors.Text,
			TextStrokeTransparency = 1,
			Parent = row,
		})
		table.insert(rows, row)
	end
	return { Rows = rows, Status = status }
end

local function render(board: Board, json: string)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(data) ~= "table" then
		return
	end
	local rows = if type(data.Rows) == "table" then data.Rows else {}
	if data.Unavailable then
		board.Status.Text = "Leaderboard unavailable here (DataStores off)."
	elseif #rows == 0 then
		board.Status.Text = "No entries yet."
	else
		board.Status.Text = ""
	end
	for i, frame in board.Rows do
		local r = rows[i]
		frame.Visible = r ~= nil
		if r then
			(frame:FindFirstChild("PlayerName") :: TextLabel).Text = tostring(r.Name);
			(frame:FindFirstChild("Time") :: TextLabel).Text = formatMinutes(tonumber(r.Minutes) or 0);
			(frame:FindFirstChild("Head") :: ImageLabel).Image =
				`rbxthumb://type=AvatarHeadShot&id={tonumber(r.UserId) or 0}&w=48&h=48`
		end
	end
end

function LeaderboardController:Init() end

function LeaderboardController:Start()
	local value = ReplicatedStorage:WaitForChild("TimePlayedTop", 30)
	if not value or not value:IsA("StringValue") then
		return
	end
	local function add(inst: Instance)
		if inst:IsA("BasePart") and not boards[inst] then
			local board = build(inst)
			boards[inst] = board
			render(board, value.Value)
		end
	end
	for _, inst in CollectionService:GetTagged(TAG) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	value.Changed:Connect(function()
		for _, board in boards do
			render(board, value.Value)
		end
	end)
end

return LeaderboardController

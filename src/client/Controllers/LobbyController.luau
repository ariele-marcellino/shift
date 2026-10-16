--!strict
-- Deploy menu (server side: LobbyService). Shown on joining - a bot keeps your slot and the match
-- goes on until you press PLAY - and re-opened any time with [P] (or MENU on touch) to switch team,
-- form a squad, invite friends or FIND MATCH (queue against real players; the squad stays on one
-- team). While you haven't deployed the camera shows the facility from the Long Hall.
--
-- Layout: TEAM + WEAPON on the left, SQUAD + INVITE + FIND MATCH on the right, PLAY / RESUME below.
-- On a match server (built by the matchmaker) the team is fixed and FIND MATCH becomes QUICK PLAY.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UI:WaitForChild("UIKit"))
local Theme = require(UI:WaitForChild("Theme"))
local MatchStore = require(UI:WaitForChild("MatchStore"))

local LobbyController = {}

local player = Players.LocalPlayer
local OVERVIEW = CFrame.lookAt(Vector3.new(-104, 7.5, 2), Vector3.new(-30, 4, 0)) -- Long Hall, Blue end

local gui: ScreenGui
local root: Frame
local subtitle: TextLabel
local noticeLabel: TextLabel
local teamBox: Frame
local weaponBox: Frame
local squadBox: Frame
local searchBox: Frame
local playButton: TextButton
local menuButton: TextButton
local statusLabel: TextLabel

local state: { [string]: any } = { Mode = "Quick", Deployed = false, Teams = {} }
local open = true
local pickedTeam = "Auto"
local pickedPrimary = Tuning.Primaries[1]
local overviewOn = false

local function send(action: string, extra: { [string]: any }?)
	local msg: { [string]: any } = { Action = action }
	if extra then
		for k, v in extra do
			msg[k] = v
		end
	end
	Remotes.Get("Lobby"):FireServer(msg)
end

local function clear(box: Instance)
	for _, child in box:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function heading(text: string, parent: Instance, order: number)
	UIKit.text(text, {
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = Theme.TextSize.Tiny,
		FontFace = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function smallButton(text: string, order: number, parent: Instance, onClick: () -> ()): TextButton
	return UIKit.button(text, {
		Size = UDim2.new(1, 0, 0, 28),
		TextSize = Theme.TextSize.Caption,
		LayoutOrder = order,
		Parent = parent,
	}, onClick)
end

local function selected(button: TextButton, on: boolean, color: Color3?)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if on then (color or Theme.Colors.White) else Theme.Colors.Stroke
		stroke.Transparency = if on then 0.1 else 0.7
	end
	button.TextColor3 = if on then Theme.Colors.White else Theme.Colors.TextDim
end

local function setOverview(on: boolean)
	local camera = workspace.CurrentCamera
	if not camera or on == overviewOn then
		return
	end
	overviewOn = on
	if on then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = OVERVIEW
	else
		camera.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
	end
end

local function setOpen(on: boolean)
	-- not deployed: the menu can't be closed (there's nothing to go back to)
	open = on or not state.Deployed
	root.Visible = open
	gui.Enabled = open
	setOverview(open and not state.Deployed)
	menuButton.Visible = not open and UserInputService.TouchEnabled
end

---------------------------------------------------------------------------------------------------
-- Sections

local function buildTeams()
	clear(teamBox)
	heading("TEAM", teamBox, 0)
	local teams = state.Teams or {}
	local fixed = state.FixedTeam
	if state.Deployed or fixed then
		local mine = state.MyTeam or fixed
		UIKit.text(`YOUR TEAM  ·  {string.upper(mine or "-")}{if fixed then "  (matched)" else ""}`, {
			Size = UDim2.new(1, 0, 0, 22),
			FontFace = Theme.Fonts.Bold,
			TextColor3 = Theme.teamColor(mine),
			LayoutOrder = 1,
			Parent = teamBox,
		})
		if state.Deployed and not fixed and state.Mode ~= "Match" then
			smallButton("SWITCH TEAM", 2, teamBox, function()
				send("SwitchTeam")
			end)
		end
		return
	end
	local order = 1
	for _, team in { "Blue", "Red" } do
		local t = teams[team] or { Real = 0, Bots = 0, Size = Tuning.Match.TeamSize }
		local full = t.Real >= t.Size
		local players = `{t.Real} player{if t.Real == 1 then "" else "s"}`
		local bots = `{t.Bots} bot{if t.Bots == 1 then "" else "s"}`
		local label = `{string.upper(team)}   {players} · {bots}{if full then "  ·  FULL" else ""}`
		local b = smallButton(label, order, teamBox, function()
			if not full then
				pickedTeam = if pickedTeam == team then "Auto" else team
				buildTeams()
			end
		end)
		b.TextXAlignment = Enum.TextXAlignment.Left
		UIKit.padding(10).Parent = b
		selected(b, pickedTeam == team, Theme.teamColor(team))
		if full then
			b.TextColor3 = Theme.Colors.TextFaint
		end
		order += 1
	end
	UIKit.text(if pickedTeam == "Auto" then "Auto: with your friends, else the smaller team" else "", {
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextFaint,
		LayoutOrder = order,
		Parent = teamBox,
	})
end

local function buildWeapons()
	clear(weaponBox)
	heading("WEAPON", weaponBox, 0)
	local row: Frame = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = weaponBox,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 6) })
	for i, primary in Tuning.Primaries do
		local stats = (Tuning :: any)[primary]
		local name = if stats and stats.DisplayName then stats.DisplayName else string.upper(primary)
		local b = UIKit.button(name, {
			Size = UDim2.new(0.5, -3, 1, 0),
			TextSize = Theme.TextSize.Caption,
			LayoutOrder = i,
			Parent = row,
		}, function()
			pickedPrimary = primary
			if state.Deployed then
				Remotes.Get("SelectLoadout"):FireServer(primary) -- applies in your spawn / next spawn
			end
			buildWeapons()
		end)
		selected(b, pickedPrimary == primary)
	end
end

local function buildSquad()
	clear(squadBox)
	heading("SQUAD", squadBox, 0)
	local order = 1
	if state.Mode == "Match" then
		UIKit.text("Matched game: real players, fixed teams", {
			Size = UDim2.new(1, 0, 0, 18),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = Theme.TextSize.Caption,
			LayoutOrder = order,
			Parent = squadBox,
		})
		return
	end
	local squad = state.Squad
	if squad then
		for _, m in squad.Members do
			local lead = m.UserId == squad.LeaderId
			UIKit.text(`{m.Name}{if lead then "   ·  leader" else ""}`, {
				Size = UDim2.new(1, 0, 0, 18),
				TextSize = Theme.TextSize.Caption,
				TextColor3 = if m.UserId == player.UserId then Theme.Colors.White else Theme.Colors.Text,
				LayoutOrder = order,
				Parent = squadBox,
			})
			order += 1
		end
		smallButton("LEAVE SQUAD", order, squadBox, function()
			send("LeaveSquad")
		end)
	else
		smallButton("CREATE SQUAD", order, squadBox, function()
			send("CreateSquad")
		end)
		order += 1
		for _, s in state.OpenSquads or {} do
			smallButton(
				`JOIN {string.upper(s.Leader)}'S SQUAD  ({s.Count}/{Tuning.Matchmaking.MaxSquad})`,
				order,
				squadBox,
				function()
					send("JoinSquad", { Id = s.Id })
				end
			)
			order += 1
		end
	end
	order += 1
	smallButton("INVITE FRIENDS", order, squadBox, function()
		task.spawn(function()
			local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
			if ok and can then
				pcall(SocialService.PromptGameInvite, SocialService, player)
			end
		end)
	end)
end

local function buildSearch()
	clear(searchBox)
	local search = state.Search
	if state.Mode == "Match" then
		smallButton("QUICK PLAY  ·  leave to a public game", 1, searchBox, function()
			send("QuickPlay")
		end)
		return
	end
	if search and (search.Status == "Searching" or search.Status == "Found") then
		local remaining = tonumber(search.Remaining) or 0
		UIKit.text(
			if search.Status == "Found"
				then "MATCH FOUND  ·  joining"
				else `SEARCHING FOR OPPONENTS  ·  {UIKit.formatTime(remaining)}`,
			{
				Size = UDim2.new(1, 0, 0, 20),
				FontFace = Theme.Fonts.Bold,
				TextColor3 = Theme.Colors.Amber,
				LayoutOrder = 1,
				Parent = searchBox,
			}
		)
		if search.Message then
			UIKit.text(search.Message, {
				Size = UDim2.new(1, 0, 0, 14),
				TextSize = Theme.TextSize.Tiny,
				TextColor3 = Theme.Colors.TextDim,
				LayoutOrder = 2,
				Parent = searchBox,
			})
		end
		if search.Status == "Searching" then
			local leader = state.Squad == nil or state.Squad.LeaderId == player.UserId
			if leader then
				smallButton("CANCEL SEARCH", 3, searchBox, function()
					send("CancelSearch")
				end)
				smallButton("PLAY NOW WITH BOTS", 4, searchBox, function()
					send("PlayWithBots")
				end)
			end
		end
		return
	end
	if state.CanSearch then
		local b = UIKit.button("FIND MATCH", {
			Size = UDim2.new(1, 0, 0, 34),
			FontFace = Theme.Fonts.Bold,
			LayoutOrder = 1,
			Parent = searchBox,
		}, function()
			send("FindMatch")
		end)
		selected(b, true, Theme.Colors.Amber)
		UIKit.text("vs real players · your squad stays together", {
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Colors.TextFaint,
			LayoutOrder = 2,
			Parent = searchBox,
		})
	elseif state.Squad then
		UIKit.text("The squad leader starts the search", {
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Colors.TextDim,
			LayoutOrder = 1,
			Parent = searchBox,
		})
	end
end

-- What PLAY does right now: start a fresh match (server waiting) or join the running one.
local function refreshStatus()
	local phase = MatchStore.Phase
	if not MatchStore.HasState then
		statusLabel.Text = ""
	elseif phase == "Waiting" then
		statusLabel.Text = "The match starts when you press PLAY"
	elseif phase == "Warmup" then
		statusLabel.Text = "Match starting  ·  warmup"
	elseif phase == "Live" then
		local s = MatchStore.Score or {}
		statusLabel.Text =
			`Match in progress  ·  {UIKit.formatTime(MatchStore.timeLeft())} left  ·  {s.Blue or 0}-{s.Red or 0}`
	else
		statusLabel.Text = "Next match starting soon"
	end
end

local function refresh()
	subtitle.Text = if state.Mode == "Match"
		then "MATCHED GAME  ·  3v3  ·  real players"
		elseif state.Mode == "Private" then "PRIVATE SERVER  ·  3v3  ·  bots fill empty slots"
		else "QUICK PLAY  ·  3v3  ·  bots fill empty slots"
	if state.Notice then
		noticeLabel.Text = state.Notice
		noticeLabel.Visible = true
		task.delay(6, function()
			if noticeLabel.Text == state.Notice then
				noticeLabel.Visible = false
			end
		end)
	end
	buildTeams()
	buildWeapons()
	buildSquad()
	buildSearch()
	local searching = state.Search ~= nil and state.Search.Status == "Searching"
	playButton.Text = if state.Deployed then "RESUME" elseif searching then "SEARCHING..." else "PLAY"
	playButton.Active = not searching or state.Deployed
	playButton.AutoButtonColor = false
	-- deployed by the server (squad fallback, team switch): leave the overview
	setOpen(open)
end

---------------------------------------------------------------------------------------------------

local function column(x: number, width: number): Frame
	return UIKit.new("Frame", {
		Position = UDim2.fromOffset(x, 74),
		Size = UDim2.fromOffset(width, 250),
		BackgroundTransparency = 1,
		Parent = root,
	})
end

local function section(parent: Instance, order: number): Frame
	return UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		UIKit.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
end

function LobbyController:Init()
	gui = UIKit.screenGui("ShiftLobby", 30)
	UIKit.modalBackdrop(gui) -- frees the mouse; no click-to-close (PLAY / RESUME close it)
	local holder: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 380),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(holder)
	root = UIKit.panel({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.12, Parent = holder })

	UIKit.text("SHIFT", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.fromOffset(300, 30),
		TextSize = Theme.TextSize.Title,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.White,
		Parent = root,
	})
	subtitle = UIKit.text("", {
		Position = UDim2.fromOffset(22, 44),
		Size = UDim2.fromOffset(400, 16),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.TextDim,
		Parent = root,
	})
	noticeLabel = UIKit.text("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 44),
		Size = UDim2.fromOffset(300, 16),
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.Amber,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = root,
	})
	UIKit.line({
		Position = UDim2.fromOffset(22, 66),
		Size = UDim2.new(1, -44, 0, 1),
		BackgroundTransparency = 0.85,
		Parent = root,
	})

	local left = column(22, 282)
	UIKit.list(Enum.FillDirection.Vertical, 14, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top).Parent =
		left
	teamBox = section(left, 1)
	weaponBox = section(left, 2)
	local right = column(336, 282)
	UIKit.list(Enum.FillDirection.Vertical, 14, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top).Parent =
		right
	squadBox = section(right, 1)
	searchBox = section(right, 2)

	playButton = UIKit.button("PLAY", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(220, 40),
		FontFace = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Label,
		Parent = root,
	}, function()
		if state.Deployed then
			setOpen(false)
		elseif not (state.Search and state.Search.Status == "Searching") then
			send("Deploy", { Team = pickedTeam, Primary = pickedPrimary })
		end
	end)
	selected(playButton, true)
	statusLabel = UIKit.text("", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -26),
		Size = UDim2.fromOffset(180, 30),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Parent = root,
	})

	-- touch: a small MENU button to re-open the menu once deployed
	local touchGui = UIKit.screenGui("ShiftLobbyButton", 9)
	menuButton = UIKit.button("MENU", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(70, 26),
		TextSize = Theme.TextSize.Tiny,
		Visible = false,
		Parent = touchGui,
	}, function()
		setOpen(true)
	end)
	UIKit.autoScale(menuButton)

	setOpen(true)
	refresh()
end

function LobbyController:Start()
	MatchStore.Changed:Connect(function()
		if open then
			refreshStatus()
		end
	end)
	Remotes.Get("LobbyState").OnClientEvent:Connect(function(s: any)
		if type(s) ~= "table" then
			return
		end
		local wasDeployed = state.Deployed
		state = s
		if s.Deployed and not wasDeployed then
			open = false -- just deployed: into the game
		end
		refresh()
	end)
	Remotes.Get("LoadoutState").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.Primary) == "string" then
			pickedPrimary = data.Primary
			if open then
				buildWeapons()
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.P and state.Deployed then
			setOpen(not open)
		end
	end)
	player.CharacterAdded:Connect(function()
		if state.Deployed and not open then
			overviewOn = true -- force the camera back onto the character
			setOverview(false)
		end
	end)
end

return LobbyController

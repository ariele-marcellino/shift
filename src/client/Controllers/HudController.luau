--!strict
-- In-match HUD for SHIFT (TEST_CONTRACT §6). Builds three ScreenGuis:
--   ShiftHudWorld   (full screen, no insets): crosshair, hit markers, damage arcs, Core markers
--   ShiftHud        (safe-area): match bar, vitals, kill feed, banners, warmup card
--   ShiftHudOverlay : Tab scoreboard, [H] controls help, [B] loadout menu (auto-opens once per session)
-- Pieces live in src/client/UI/Hud/*. The HUD hides itself while the Facility Report is up.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UI:WaitForChild("UIKit"))
local MatchStore = require(UI:WaitForChild("MatchStore"))
local Hud = UI:WaitForChild("Hud")

local HudController = {}

local worldGui: ScreenGui
local hudGui: ScreenGui
local overlayGui: ScreenGui
local scoreboard: any
local help: any
local loadout: any
-- The loadout menu opens by itself exactly once per session (first spawn / first warmup); after
-- that only [B] or the mobile LOADOUT button open it. Never on respawn.
-- (Off since the deploy menu, LobbyController, picks the weapon before spawning: never auto-open.)
local loadoutAutoShown = true
local hiddenByReport = false

local function disableCoreGui()
	-- PlayerList would steal Tab; Health/Backpack are replaced by our HUD. SetCoreGuiEnabled can
	-- fail very early in startup, so retry briefly.
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

local function applyVisibility()
	local show = not hiddenByReport and MatchStore.Phase ~= "Ended"
	worldGui.Enabled = show
	hudGui.Enabled = show
	if not show then
		scoreboard.setVisible(false)
		if loadout then
			loadout.setVisible(false)
		end
	end
end

-- Called by ReportController while the Facility Report is on screen.
function HudController:SetHiddenByReport(hidden: boolean)
	hiddenByReport = hidden
	applyVisibility()
end

function HudController:ToggleScoreboard()
	if scoreboard and hudGui.Enabled then
		scoreboard.toggle()
	end
end

function HudController:ToggleLoadout()
	if loadout and (hudGui.Enabled or loadout.isVisible()) then
		loadout.toggle()
	end
end

function HudController:SetLoadoutVisible(visible: boolean)
	if loadout then
		loadout.setVisible(visible)
	end
end

local function tryAutoLoadout()
	if loadoutAutoShown or hiddenByReport or MatchStore.Phase == "Ended" then
		return
	end
	local character = Players.LocalPlayer.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	loadoutAutoShown = true
	task.delay(0.6, function()
		if not hiddenByReport and MatchStore.Phase ~= "Ended" then
			loadout.setVisible(true)
		end
	end)
end

function HudController:ToggleHelp()
	if help then
		help.toggle()
	end
end

function HudController:Init()
	worldGui = UIKit.screenGui("ShiftHudWorld", 5, true)
	hudGui = UIKit.screenGui("ShiftHud", 6)
	overlayGui = UIKit.screenGui("ShiftHudOverlay", 20)

	require(Hud:WaitForChild("Crosshair")).mount(worldGui)
	require(Hud:WaitForChild("Markers")).mount(worldGui)
	local bar = require(Hud:WaitForChild("MatchBar")).mount(hudGui)
	require(Hud:WaitForChild("Vitals")).mount(hudGui)
	require(Hud:WaitForChild("KillFeed")).mount(hudGui)
	require(Hud:WaitForChild("Banners")).mount(hudGui)
	scoreboard = require(Hud:WaitForChild("Scoreboard")).mount(overlayGui)
	help = require(Hud:WaitForChild("Help")).mount(overlayGui)
	loadout = require(Hud:WaitForChild("Loadout")).mount(overlayGui)

	bar.Activated:Connect(function()
		HudController:ToggleScoreboard()
	end)
end

function HudController:Start()
	task.spawn(disableCoreGui)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.Tab then
			-- Tab is checked even when "processed" since PlayerList no longer consumes it.
			if hudGui.Enabled and not UserInputService:GetFocusedTextBox() then
				scoreboard.setVisible(true)
			end
		elseif not processed and input.KeyCode == Enum.KeyCode.H then
			help.toggle()
		elseif not processed and input.KeyCode == Enum.KeyCode.B then
			if hudGui.Enabled or loadout.isVisible() then
				loadout.toggle()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Tab then
			scoreboard.setVisible(false)
		end
	end)

	MatchStore.PhaseChanged:Connect(function()
		applyVisibility()
		tryAutoLoadout()
	end)
	applyVisibility()

	local function onCharacter(character: Model)
		character:WaitForChild("Humanoid", 10)
		tryAutoLoadout()
	end
	Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
	if Players.LocalPlayer.Character then
		task.spawn(onCharacter, Players.LocalPlayer.Character)
	end
end

return HudController

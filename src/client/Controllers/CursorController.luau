--!strict
-- Cursor visibility in first person. LockFirstPerson keeps the mouse locked to the centre, where
-- Roblox's cursor would sit on top of the crosshair, so it's hidden during play. When a menu is
-- open (any visible GuiButton with Modal = true, e.g. loadout, settings, report) the mouse is freed
-- and the cursor shown, so players can click.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CursorController = {}

local modals: { [GuiButton]: boolean } = {}

local function track(inst: Instance)
	if inst:IsA("GuiButton") then
		modals[inst] = true
	end
end

-- Visible on screen: the button and all its GuiObject ancestors are Visible and its ScreenGui is
-- Enabled.
local function shown(button: GuiButton): boolean
	if not button.Modal or not button.Visible then
		return false
	end
	local node: Instance? = button.Parent
	while node do
		if node:IsA("ScreenGui") then
			return node.Enabled
		elseif node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return false
end

local function menuOpen(): boolean
	for button in modals do
		if button.Parent == nil then
			modals[button] = nil
		elseif shown(button) then
			return true
		end
	end
	return false
end

function CursorController:Init() end

function CursorController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, d in playerGui:GetDescendants() do
		track(d)
	end
	playerGui.DescendantAdded:Connect(track)

	-- After the camera scripts (which re-lock the mouse every frame in first person).
	RunService:BindToRenderStep("ShiftCursor", Enum.RenderPriority.Camera.Value + 10, function()
		local open = menuOpen()
		if open then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		local show = open or UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
		if UserInputService.MouseIconEnabled ~= show then
			UserInputService.MouseIconEnabled = show
		end
	end)
end

return CursorController

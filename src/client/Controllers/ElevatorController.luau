--!strict
-- Spawn elevator ride (ElevatorService): fade to black with a short caption while travelling, a
-- ding on arrival, then fade back in inside the atrium elevator.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UI = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UI:WaitForChild("UIKit"))
local Theme = require(UI:WaitForChild("Theme"))

local ElevatorController = {}

local DING = 9126073318 -- PSE "Synth ... Ding"
local FADE = 0.18

local function ding()
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(DING)
	s.Volume = 0.5
	s.Parent = SoundService
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end

function ElevatorController:Init() end

function ElevatorController:Start()
	local gui = UIKit.screenGui("ShiftElevator", 50, true)
	local black: Frame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local caption = UIKit.text("ELEVATOR  ·  ATRIUM", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Label,
		FontFace = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		TextTransparency = 1,
		Parent = black,
	})

	Remotes.Get("ElevatorRide").OnClientEvent:Connect(function(seconds: number)
		if type(seconds) ~= "number" then
			return
		end
		UIKit.tween(black, FADE, { BackgroundTransparency = 0 })
		UIKit.tween(caption, FADE, { TextTransparency = 0.2 })
		task.delay(math.max(0, seconds - 0.05), function()
			ding()
			UIKit.tween(black, FADE + 0.15, { BackgroundTransparency = 1 })
			UIKit.tween(caption, FADE, { TextTransparency = 1 })
		end)
	end)
end

return ElevatorController

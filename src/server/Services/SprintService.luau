--!strict
-- Sprint + slide. The client reports "holding sprint while moving" and requests slides; the server
-- validates and only sets character attributes (`Sprinting`, `Sliding`, `SlideStart`). Mode's
-- Movement turns those into WalkSpeed, so a client can't pick its own speed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Movement =
	require(script.Parent.Parent:WaitForChild("Systems"):WaitForChild("Mode"):WaitForChild("Movement"))

local SprintService = {}

local MIN_INTERVAL = 0.05 -- seconds between accepted toggles per player

local lastToggle: { [Player]: number } = {}
local lastSlide: { [Player]: number } = {}
local sliding: { [Model]: boolean } = {}

local function endSlide(character: Model)
	sliding[character] = nil
	if character.Parent then
		character:SetAttribute("Sliding", false)
		Movement.Apply(character)
	end
end

function SprintService:Init() end

function SprintService:Start()
	Remotes.Get("SetSprint").OnServerEvent:Connect(function(player: Player, on: any)
		if type(on) ~= "boolean" then
			return
		end
		local now = os.clock()
		if now - (lastToggle[player] or 0) < MIN_INTERVAL then
			return
		end
		lastToggle[player] = now
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			return
		end
		if character:GetAttribute("Sprinting") ~= on then
			character:SetAttribute("Sprinting", on)
		end
	end)

	Remotes.Get("Slide").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastSlide[player] or -math.huge) < Tuning.Slide.Cooldown then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			return
		end
		if character:GetAttribute("Sprinting") ~= true or character:GetAttribute("CarryingCore") ~= nil then
			return
		end
		if humanoid.FloorMaterial == Enum.Material.Air then
			return
		end
		lastSlide[player] = now
		sliding[character] = true
		character:SetAttribute("SlideStart", workspace:GetServerTimeNow())
		character:SetAttribute("Sliding", true)
		Movement.Apply(character)
	end)

	-- Ease the slide speed every frame, then end it.
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for character in sliding do
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local started = character:GetAttribute("SlideStart")
			if
				not character.Parent
				or not humanoid
				or humanoid.Health <= 0
				or type(started) ~= "number"
				or now - started >= Tuning.Slide.Seconds
			then
				endSlide(character)
			else
				Movement.Apply(character)
			end
		end
	end)

	-- Fresh characters never start sprinting.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			character:SetAttribute("Sprinting", false)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			character:SetAttribute("Sprinting", false)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastToggle[player] = nil
		lastSlide[player] = nil
	end)
end

return SprintService

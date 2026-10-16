--!strict
-- Footsteps as information (Rainbow Six Siege style). Every character, players and bots, plays a
-- discrete step sound per stride, positioned at its feet. How loud and how far it carries depends on
-- how it moves:
--   Sprint  - loud, carries ~120 studs
--   Run     - normal pace (knife / rifle / sniper), clearly audible ~90 studs
--   Quiet   - crouched, aiming or scoped: soft, ~22 studs (sneaking is a real choice)
-- Landings thud. Steps heard through a wall are muffled (high frequencies cut) so you can tell
-- "same room" from "next room". Your own steps play quieter and unpositioned.
-- Replaces Roblox's default looping "Running" sound (muted here), which bots never had.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local FootstepController = {}

-- Short single steps (concrete). Several variants, picked at random so it doesn't sound looped.
FootstepController.StepIds = { 87528672132102, 77458802348961, 123703547146060 } -- "DSteps concrete footstep 1-3"
FootstepController.LandId = 9113481039 -- PSE "Body Fall Wood 1" (layered under a step on landing)

type Tier = { Volume: number, MinDistance: number, MaxDistance: number, Stride: number }

FootstepController.Tiers = {
	Sprint = { Volume = 2.2, MinDistance = 14, MaxDistance = 120, Stride = 6.5 },
	Run = { Volume = 1.6, MinDistance = 10, MaxDistance = 90, Stride = 5.5 },
	Quiet = { Volume = 0.35, MinDistance = 3, MaxDistance = 22, Stride = 4.5 },
} :: { [string]: Tier }

FootstepController.OwnVolumeScale = 0.35 -- your own steps (2D)
FootstepController.MinSpeed = 3 -- studs/s; slower than this makes no steps
FootstepController.OccludedHighGain = -18 -- dB cut on steps heard through walls
FootstepController.OccludedVolumeScale = 0.7

type Track = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Distance: number,
	WasAirborne: boolean,
	FallSpeed: number,
}

local player = Players.LocalPlayer
local tracked: { [Model]: Track } = {}

local function tierFor(model: Model): string
	if
		model:GetAttribute("Crouching") == true
		or model:GetAttribute("Aiming") == true
		or model:GetAttribute("Scoped") == true
	then
		return "Quiet"
	end
	if model:GetAttribute("Sprinting") == true then
		return "Sprint"
	end
	return "Run"
end

local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Exclude
occlusionParams.IgnoreWater = true

-- True when solid geometry sits between the listener (camera) and the step.
local function occluded(from: Vector3, model: Model): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local exclude: { Instance } = { model }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		table.insert(exclude, bots)
	end
	occlusionParams.FilterDescendantsInstances = exclude
	local origin = camera.CFrame.Position
	local hit = workspace:Raycast(origin, from - origin, occlusionParams)
	return hit ~= nil and hit.Instance.CanCollide and hit.Instance.Transparency < 0.9
end

local function playStep(track: Track, tierName: string, landing: boolean)
	local tier = FootstepController.Tiers[tierName]
	local ids = FootstepController.StepIds
	if not tier or #ids == 0 then
		return
	end
	local own = track.Model == player.Character
	local feet = track.Root.Position - Vector3.new(0, 2.5, 0)

	local function make(id: number, volume: number, pitch: number)
		if id == 0 then
			return
		end
		local s = Instance.new("Sound")
		s.Name = "Footstep"
		s.SoundId = "rbxassetid://" .. tostring(id)
		s.PlaybackSpeed = pitch
		if own then
			s.Volume = volume * FootstepController.OwnVolumeScale
			s.Parent = SoundService
		else
			s.Volume = volume
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = tier.MinDistance
			s.RollOffMaxDistance = tier.MaxDistance
			if occluded(feet, track.Model) then
				s.Volume = volume * FootstepController.OccludedVolumeScale
				local eq = Instance.new("EqualizerSoundEffect")
				eq.LowGain = 2
				eq.MidGain = -6
				eq.HighGain = FootstepController.OccludedHighGain
				eq.Parent = s
			end
			s.Parent = track.Root
		end
		s:Play()
		task.delay(2, function()
			s:Destroy()
		end)
	end

	local volume = tier.Volume * (0.9 + math.random() * 0.2)
	make(ids[math.random(1, #ids)], volume, 0.92 + math.random() * 0.16)
	if landing then
		make(FootstepController.LandId, tier.Volume * 0.8, 0.9)
	end
end

local function untrack(model: Model)
	tracked[model] = nil
end

local function muteDefaultRunning(root: BasePart)
	local function mute(child: Instance)
		if child:IsA("Sound") and child.Name == "Running" then
			child.Volume = 0
		end
	end
	for _, child in root:GetChildren() do
		mute(child)
	end
	root.ChildAdded:Connect(mute)
end

local function trackCharacter(model: Model)
	if tracked[model] then
		return
	end
	task.spawn(function()
		local humanoid = model:WaitForChild("Humanoid", 10)
		local root = model:WaitForChild("HumanoidRootPart", 10)
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			return
		end
		if not model.Parent then
			return
		end
		muteDefaultRunning(root)
		tracked[model] = {
			Model = model,
			Humanoid = humanoid,
			Root = root,
			Distance = 0,
			WasAirborne = false,
			FallSpeed = 0,
		}
		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				untrack(model)
			end
		end)
		humanoid.Died:Connect(function()
			untrack(model)
		end)
	end)
end

local function watchPlayer(p: Player)
	if p.Character then
		trackCharacter(p.Character)
	end
	p.CharacterAdded:Connect(trackCharacter)
end

local function watchBots(folder: Instance)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			trackCharacter(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			trackCharacter(child)
		end
	end)
end

function FootstepController:Init() end

function FootstepController:Start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	local bots = workspace:FindFirstChild("Bots")
	if bots then
		watchBots(bots)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Bots" then
			watchBots(child)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		for model, track in tracked do
			if not model.Parent or track.Humanoid.Health <= 0 then
				tracked[model] = nil
				continue
			end
			local velocity = track.Root.AssemblyLinearVelocity
			local airborne = track.Humanoid.FloorMaterial == Enum.Material.Air
			if airborne then
				track.WasAirborne = true
				track.FallSpeed = math.max(track.FallSpeed, -velocity.Y)
				continue
			end
			local tierName = tierFor(model)
			if track.WasAirborne then
				track.WasAirborne = false
				-- Hops off small ledges stay quiet; real jumps / drops thud.
				if track.FallSpeed > 18 then
					playStep(track, if tierName == "Quiet" then "Run" else tierName, true)
					track.Distance = 0
				end
				track.FallSpeed = 0
			end
			-- Sliding has its own sound.
			if model:GetAttribute("Sliding") == true then
				track.Distance = 0
				continue
			end
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if speed < FootstepController.MinSpeed then
				track.Distance = 0
				continue
			end
			track.Distance += speed * dt
			local tier = FootstepController.Tiers[tierName]
			if track.Distance >= tier.Stride then
				track.Distance = 0
				playStep(track, tierName, false)
			end
		end
	end)
end

return FootstepController

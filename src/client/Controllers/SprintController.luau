--!strict
-- Hold Left Shift (or click the left stick on a gamepad) to sprint. Only reported while actually
-- moving and not aiming; the server decides the resulting speed (see SprintService / Movement).
-- Slide: while sprinting, press C (gamepad B). Direction locks, the camera drops, and the server
-- eases the speed down (Tuning.Slide). Crouch is Ctrl only. On gamepad B is both slide and crouch,
-- so after a slide we restore the crouch state from before it (you stand back up).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local SLIDE_SOUND = 9119197753 -- PSE "Slide On Wood 3" (verified public); 0 = silent

local function playSlideSound(parent: Instance)
	if SLIDE_SOUND == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "SlideSound"
	s.SoundId = "rbxassetid://" .. tostring(SLIDE_SOUND)
	s.Volume = 0.3 -- halved (owner, 2026-10-16; was 0.6)
	s.PlaybackSpeed = 1.1
	s.Parent = parent
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end

local SprintController = {}

local player = Players.LocalPlayer
local held = false
local sent = false
local slideUntil = 0
local lastSlide = -math.huge
local slideDir = Vector3.zero
-- Crouch state as of the previous frame, i.e. before this frame's key press toggled it.
local crouchedLastFrame = false

local function weaponController(): any
	local module = script.Parent:FindFirstChild("WeaponController")
	if not module then
		return nil
	end
	local ok, controller = pcall(require, module)
	return if ok then controller else nil
end

local function isCrouched(): boolean
	local wc = weaponController()
	return wc ~= nil and type(wc.State) == "table" and wc.State.Crouched == true
end

local function isSlideInput(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.ButtonB
end

local function cameraDrop(humanoid: Humanoid, drop: number, seconds: number)
	TweenService:Create(
		humanoid,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CameraOffset = Vector3.new(0, -drop, 0) }
	):Play()
end

local function trySlide(remote: RemoteEvent)
	local now = os.clock()
	if not sent or now - lastSlide < Tuning.Slide.Cooldown then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	if character:GetAttribute("CarryingCore") ~= nil then
		return
	end
	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.1 then
		return
	end
	local crouchedBefore = crouchedLastFrame
	lastSlide = now
	slideDir = Vector3.new(dir.X, 0, dir.Z).Unit
	slideUntil = now + Tuning.Slide.Seconds
	remote:FireServer()
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		playSlideSound(root)
	end
	cameraDrop(humanoid, Tuning.Slide.CameraDrop, 0.12)
	task.delay(Tuning.Slide.Seconds, function()
		if not humanoid.Parent or humanoid.Health <= 0 then
			return
		end
		cameraDrop(humanoid, 0, 0.25)
		-- Undo the crouch toggle the slide key caused (unless the player was crouched before).
		local wc = weaponController()
		if wc and isCrouched() ~= crouchedBefore and type(wc.ToggleCrouch) == "function" then
			pcall(wc.ToggleCrouch, wc)
		end
	end)
end

local function isSprintInput(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3
end

local function wantsSprint(): boolean
	if not held then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if humanoid.MoveDirection.Magnitude < 0.1 then
		return false
	end
	-- Aiming / scoping cancel sprint (the server ignores the bonus then anyway).
	return character:GetAttribute("Aiming") ~= true and character:GetAttribute("Scoped") ~= true
end

function SprintController:Init() end

function SprintController:Start()
	local remote = Remotes.Get("SetSprint")
	local slideRemote = Remotes.Get("Slide")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if isSprintInput(input) then
			held = true
		elseif isSlideInput(input) then
			trySlide(slideRemote)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isSprintInput(input) then
			held = false
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		held = false
	end)
	player.CharacterAdded:Connect(function()
		sent = false
		slideUntil = 0
	end)

	-- While sliding, keep moving in the locked direction regardless of input; a jump ends it.
	RunService:BindToRenderStep("ShiftSlide", Enum.RenderPriority.Input.Value + 1, function()
		if os.clock() >= slideUntil then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or humanoid.Jump then
			slideUntil = 0
			return
		end
		humanoid:Move(slideDir, false)
	end)

	RunService.Heartbeat:Connect(function()
		crouchedLastFrame = isCrouched()
		local want = wantsSprint()
		if want ~= sent then
			sent = want
			remote:FireServer(want)
		end
	end)
end

return SprintController

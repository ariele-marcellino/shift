--!strict
-- Makes the one-way spawn barriers readable:
--   * text on each barrier, worded for the viewer: "ENEMY SPAWN / NO ENTRY - NO FIRE" on the other
--     team's barriers, a quiet "YOUR SPAWN" on your own;
--   * walking into an enemy barrier (or your own while carrying a flag, which blocks you too): a
--     warning line on screen, a short denied buzz and the barrier's text flashes.
-- (Bullets that hit an enemy barrier ricochet: Effects.BarrierHit.)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local UI = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UI:WaitForChild("UIKit"))
local Theme = require(UI:WaitForChild("Theme"))
local MatchStore = require(UI:WaitForChild("MatchStore"))

local BarrierController = {}

local TAG = "SpawnBarrier"
local DENIED_SOUND = 9125935526 -- PSE "Shortwave Bleep Beeps Radio Staticky" (short denied buzz)
local TOUCH_DISTANCE = 2.4 -- studs from the barrier box that count as "walking into it"

local player = Players.LocalPlayer

type Entry = { Part: BasePart, Guis: { SurfaceGui }, Flash: { Frame } }
local entries: { [BasePart]: Entry } = {}
local builtFor: string? = nil
local warnLabel: TextLabel
local warnUntil = 0
local lastBuzz = 0

local function facesFor(part: BasePart): { Enum.NormalId }
	local s = part.Size
	if s.X <= s.Z then
		return { Enum.NormalId.Left, Enum.NormalId.Right }
	end
	return { Enum.NormalId.Front, Enum.NormalId.Back }
end

local function clear(entry: Entry)
	for _, g in entry.Guis do
		g:Destroy()
	end
	table.clear(entry.Guis)
	table.clear(entry.Flash)
end

local function decorate(part: BasePart)
	local entry = entries[part] or { Part = part, Guis = {}, Flash = {} }
	entries[part] = entry
	clear(entry)
	local team = part:GetAttribute("Team")
	local mine = MatchStore.localTeam()
	local enemy = team ~= mine
	for _, faceId in facesFor(part) do
		local gui = UIKit.new("SurfaceGui", {
			Name = "BarrierText",
			Adornee = part,
			Face = faceId,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 40,
			LightInfluence = 0,
			Brightness = 1.5,
			Parent = UIKit.getPlayerGui(),
		})
		local flash = UIKit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Colors.Bad,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = gui,
		})
		table.insert(entry.Flash, flash)
		if enemy then
			UIKit.text("ENEMY SPAWN", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromScale(0.9, 0.12),
				TextScaled = true,
				FontFace = Theme.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = Theme.Colors.White,
				TextStrokeTransparency = 0.3,
				Parent = gui,
			})
			UIKit.text("NO ENTRY  ·  NO FIRE", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.53),
				Size = UDim2.fromScale(0.9, 0.07),
				TextScaled = true,
				FontFace = Theme.Fonts.Medium,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = Theme.Colors.Bad,
				TextStrokeTransparency = 0.3,
				Parent = gui,
			})
		else
			UIKit.text("YOUR SPAWN", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				Size = UDim2.fromScale(0.8, 0.07),
				TextScaled = true,
				FontFace = Theme.Fonts.Medium,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = Theme.Colors.White,
				TextTransparency = 0.45,
				TextStrokeTransparency = 0.8,
				Parent = gui,
			})
		end
		table.insert(entry.Guis, gui)
	end
end

local function rebuildAll()
	builtFor = MatchStore.localTeam() or "?"
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("BasePart") then
			decorate(inst)
		end
	end
end

-- Distance from a point to a part's axis-aligned box.
local function boxDistance(part: BasePart, point: Vector3): number
	local half = part.Size / 2
	local d = point - part.Position
	local dx = math.max(math.abs(d.X) - half.X, 0)
	local dy = math.max(math.abs(d.Y) - half.Y, 0)
	local dz = math.max(math.abs(d.Z) - half.Z, 0)
	return Vector3.new(dx, dy, dz).Magnitude
end

local function buzz()
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(DENIED_SOUND)
	s.Volume = 0.4
	s.PlaybackSpeed = 1.2
	s.Parent = SoundService
	s:Play()
	task.delay(0.6, function()
		s:Destroy()
	end)
end

local function flashEntry(entry: Entry)
	for _, f in entry.Flash do
		f.BackgroundTransparency = 0.55
		UIKit.tween(f, 0.5, { BackgroundTransparency = 1 })
	end
end

function BarrierController:Init() end

function BarrierController:Start()
	local gui = UIKit.screenGui("ShiftBarrierWarn", 8)
	UIKit.autoScale(gui)
	warnLabel = UIKit.text("ENEMY SPAWN  ·  RESTRICTED", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(400, 22),
		TextSize = Theme.TextSize.Label,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.Bad,
		TextStrokeTransparency = 0.5,
		Visible = false,
		Parent = gui,
	})

	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			decorate(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		local entry = inst:IsA("BasePart") and entries[inst]
		if entry then
			clear(entry)
			entries[inst :: BasePart] = nil
		end
	end)
	rebuildAll()

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local mine = MatchStore.localTeam()
		if (mine or "?") ~= builtFor then
			rebuildAll()
		end
		local now = os.clock()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			-- carrying a flag: your own barriers block you too (TeamCollision "Carrier" group)
			local c = character and character:GetAttribute("CarryingCore")
			local carrying = c ~= nil and c ~= false and c ~= ""
			for part, entry in entries do
				if
					part.Parent
					and (carrying or part:GetAttribute("Team") ~= mine)
					and boxDistance(part, root.Position) < TOUCH_DISTANCE
				then
					warnLabel.Text = if part:GetAttribute("Team") == mine
						then "NO FLAGS IN YOUR SPAWN"
						else "ENEMY SPAWN  ·  RESTRICTED"
					warnUntil = now + 1.5
					if now - lastBuzz > 1.2 then
						lastBuzz = now
						buzz()
						flashEntry(entry)
					end
				end
			end
		end
		warnLabel.Visible = now < warnUntil
	end)
end

return BarrierController

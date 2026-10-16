--!strict
-- Shift hinges: pre-built blast doors / shutters that slide into the ceiling (open) or drop (sealed).
-- Sealing first pushes every combatant (tag "Combatant") out of the hinge's volumes to the nearest
-- exit, keeps pushing while the panel drops, and once more after it lands, so nobody is ever trapped
-- inside geometry or inside a closed-off tunnel.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Style = require(script.Parent.Style)

export type Panel = { Part: BasePart, ClosedCFrame: CFrame, OpenCFrame: CFrame }
export type Volume = { CFrame: CFrame, Size: Vector3, Exits: { Vector3 } }
export type Status = { Part: BasePart, Light: Light? }

export type Hinge = {
	Id: string,
	Kind: string,
	Open: boolean,
	InitialOpen: boolean,
	Panels: { Panel },
	Volumes: { Volume },
	Status: { Status },
	Position: Vector3,
	Size: Vector3,
	Token: number,
}

local Hinges = {}

local MOVE_SECONDS = 1.1
local byId: { [string]: Hinge } = {}
local order: { Hinge } = {}

-- Sound ids: none verified yet; 0 = skipped.
Hinges.Sounds = { Move = 9120370628 } -- PSE "Vehicle Door Bump Slamming Metal Door 1"

local function insideVolume(vol: Volume, p: Vector3): boolean
	local lp = vol.CFrame:PointToObjectSpace(p)
	local h = vol.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end

local function rootOf(model: Instance): BasePart?
	if not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

-- Nearest exit of the first volume containing `p`, or nil if `p` is not inside any of the volumes.
local function exitFor(volumes: { Volume }, p: Vector3): Vector3?
	for _, vol in volumes do
		if insideVolume(vol, p) then
			local best, bestDist = nil, math.huge
			for _, exit in vol.Exits do
				local d = (exit - p).Magnitude
				if d < bestDist then
					best, bestDist = exit, d
				end
			end
			return best
		end
	end
	return nil
end

function Hinges.PushOut(hinge: Hinge)
	for _, model in CollectionService:GetTagged("Combatant") do
		local root = rootOf(model)
		if root then
			local exit = exitFor(hinge.Volumes, root.Position)
			if exit then
				local _, yaw, _ = root.CFrame:ToOrientation()
				local target = CFrame.new(exit + Vector3.new(0, 3, 0)) * CFrame.Angles(0, yaw, 0)
				pcall(function()
					(model :: Model):PivotTo(target)
					root.AssemblyLinearVelocity = Vector3.zero
				end)
			end
		end
	end
end

-- Where a loose object (e.g. a dropped Core) should go if a sealed hinge now overlaps it.
function Hinges.SafePosition(p: Vector3): Vector3
	for _, hinge in order do
		if not hinge.Open then
			local exit = exitFor(hinge.Volumes, p)
			if exit then
				return exit + Vector3.new(0, p.Y - exit.Y, 0)
			end
		end
	end
	return p
end

local function applyStatus(hinge: Hinge)
	local preset = if hinge.Open then Style.Light.StatusOpen else Style.Light.StatusSealed
	for _, s in hinge.Status do
		s.Part.Color = preset.Color
		if s.Light then
			s.Light.Color = preset.Color
			s.Light.Brightness = preset.Brightness * Style.LightScale
			s.Light.Range = preset.Range
		end
	end
end

local function setPanels(hinge: Hinge, animate: boolean)
	for _, panel in hinge.Panels do
		local target = if hinge.Open then panel.OpenCFrame else panel.ClosedCFrame
		if animate then
			TweenService:Create(
				panel.Part,
				TweenInfo.new(MOVE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ CFrame = target }
			):Play()
		else
			panel.Part.CFrame = target
		end
		-- An open panel sits inside the ceiling; never let it block shots or bots.
		panel.Part.CanCollide = true
		panel.Part.CanQuery = not hinge.Open
	end
	if animate and Hinges.Sounds.Move ~= 0 then
		for _, panel in hinge.Panels do
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://" .. tostring(Hinges.Sounds.Move)
			sound.RollOffMaxDistance = 140
			sound.Parent = panel.Part
			sound:Play()
			task.delay(5, function()
				sound:Destroy()
			end)
		end
	end
end

function Hinges.SetOpen(hinge: Hinge, open: boolean, animate: boolean)
	if hinge.Open == open then
		return
	end
	hinge.Open = open
	hinge.Token += 1
	local token = hinge.Token
	hinge.Panels[1].Part.Parent:SetAttribute("Open", open)
	applyStatus(hinge)
	if open then
		setPanels(hinge, animate)
		return
	end
	-- Sealing: clear the volume, drop the panels, keep clearing until they land.
	Hinges.PushOut(hinge)
	setPanels(hinge, animate)
	if animate then
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < MOVE_SECONDS + 0.2 and hinge.Token == token do
				Hinges.PushOut(hinge)
				task.wait(0.1)
			end
			if hinge.Token == token then
				Hinges.PushOut(hinge)
			end
		end)
	end
end

export type RegisterArgs = {
	Id: string,
	Kind: string,
	InitialOpen: boolean,
	Panels: { Panel },
	Volumes: { Volume },
	Status: { Status },
	Position: Vector3,
	Size: Vector3,
}

function Hinges.Register(args: RegisterArgs): Hinge
	assert(byId[args.Id] == nil, "Duplicate hinge id " .. args.Id)
	local hinge: Hinge = {
		Id = args.Id,
		Kind = args.Kind,
		Open = not args.InitialOpen, -- forces the first SetOpen to apply
		InitialOpen = args.InitialOpen,
		Panels = args.Panels,
		Volumes = args.Volumes,
		Status = args.Status,
		Position = args.Position,
		Size = args.Size,
		Token = 0,
	}
	byId[args.Id] = hinge
	table.insert(order, hinge)
	Hinges.SetOpen(hinge, args.InitialOpen, false)
	return hinge
end

function Hinges.Get(id: string): Hinge?
	return byId[id]
end

function Hinges.All(): { Hinge }
	return order
end

function Hinges.IsOpen(id: string): boolean
	local hinge = byId[id]
	return hinge ~= nil and hinge.Open
end

function Hinges.ResetAll()
	for _, hinge in order do
		Hinges.SetOpen(hinge, hinge.InitialOpen, false)
	end
end

return Hinges

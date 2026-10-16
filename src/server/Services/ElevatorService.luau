--!strict
-- Spawn elevator (spawn exit C). Stand in your spawn's elevator car for WAIT seconds and you ride to
-- your team's half of the atrium elevator shaft; its sliding doors open, and close again once your
-- team has walked out. Each half has a team barrier, so enemies can't get in or shoot in.
-- Flag carriers can't ride (no escaping with the flag). While the Long Hall security doors are
-- sealed (the "SECTOR B LOCKDOWN" shift after a capture) the elevator is offline for everyone, so it
-- can't be used to get round the lockdown into mid-map (owner, 2026-10-16).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local WorldService = require(script.Parent.WorldService)
local Hinges = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("Hinges"))
local TeamService = require(script.Parent.TeamService)

local ElevatorService = {}

local WAIT = 0.4 -- seconds standing in the car before it goes
local RIDE = 1 -- seconds of travel (screen faded)
local DOOR_SECONDS = 0.35
local MIN_OPEN = 2.5 -- doors stay open at least this long
local CLOSE_WHEN_EMPTY = 1.5 -- then close once nobody of the team is inside for this long
local OFFLINE_NOTICE_EVERY = 4 -- seconds between "elevator offline" notices to the same player
local OFFLINE_TEXT = "ELEVATOR OFFLINE  ·  Long Hall lockdown"

type DoorState = { Open: boolean, OpenedAt: number, EmptySince: number? }

local standing: { [Model]: number } = {}
local riding: { [Model]: boolean } = {}
local doors: { [string]: DoorState } = {}
local nextSlot: { [string]: number } = {}
local noticedAt: { [Model]: number } = {}

-- Any Long Hall security door (hinge Kind "HallDoor") shut?
local function hallSealed(): boolean
	for _, hinge in Hinges.All() do
		if hinge.Kind == "HallDoor" and not hinge.Open then
			return true
		end
	end
	return false
end

local function inBox(cf: CFrame, size: Vector3, point: Vector3): boolean
	local p = cf:PointToObjectSpace(point)
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 and math.abs(p.Z) <= size.Z / 2
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function setDoors(team: string, open: boolean)
	local e = WorldService:GetElevator(team)
	if not e or not e.Leaves then
		return
	end
	local d = doors[team] or { Open = false, OpenedAt = 0, EmptySince = nil }
	doors[team] = d
	if open then
		d.OpenedAt = os.clock()
		d.EmptySince = nil
	end
	if d.Open == open then
		return
	end
	d.Open = open
	for _, leaf in e.Leaves do
		TweenService:Create(
			leaf.Part,
			TweenInfo.new(DOOR_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = if open then leaf.Open else leaf.Closed }
		):Play()
	end
end

local function ride(c: any, team: string)
	local model = c.Model :: Model
	riding[model] = true
	standing[model] = nil
	local player = c.Player :: Player?
	if player then
		Remotes.Get("ElevatorRide"):FireClient(player, RIDE)
	end
	task.delay(RIDE, function()
		riding[model] = nil
		local e = WorldService:GetElevator(team)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not e or not model.Parent or not hum or hum.Health <= 0 or c.Model ~= model then
			return
		end
		if model:GetAttribute("CarryingCore") ~= nil then
			return
		end
		local slots = e.Arrivals
		local i = (nextSlot[team] or 0) % #slots + 1
		nextSlot[team] = i
		model:PivotTo(slots[i])
		setDoors(team, true)
	end)
end

local function step(dt: number)
	local now = os.clock()
	local inside: { [string]: boolean } = {}
	local offline = hallSealed()
	for _, c in TeamService:GetAll() do
		local model = c.Model
		local team = c.Team
		local root = rootOf(model)
		if not model or not root or not c.Alive or type(team) ~= "string" then
			if model then
				standing[model] = nil -- died on the pad: don't keep the old character referenced
				noticedAt[model] = nil
			end
			continue
		end
		local e = WorldService:GetElevator(team)
		if not e or not e.Pad then
			continue
		end
		if e.Shaft and inBox(e.Shaft, e.ShaftSize, root.Position) then
			inside[team] = true
		end
		if
			not riding[model]
			and model:GetAttribute("CarryingCore") == nil
			and inBox(e.Pad, e.PadSize, root.Position)
		then
			if offline then
				standing[model] = nil
				if now - (noticedAt[model] or 0) >= OFFLINE_NOTICE_EVERY then
					noticedAt[model] = now
					local player = Players:GetPlayerFromCharacter(model)
					if player then
						Remotes.Get("Announce"):FireClient(player, OFFLINE_TEXT, "Bad")
					end
				end
				continue
			end
			standing[model] = (standing[model] or 0) + dt
			if standing[model] >= WAIT then
				ride(c, team)
			end
		else
			standing[model] = nil
		end
	end
	for team, d in doors do
		if d.Open and now - d.OpenedAt >= MIN_OPEN then
			if inside[team] then
				d.EmptySince = nil
			else
				d.EmptySince = d.EmptySince or now
				if now - (d.EmptySince :: number) >= CLOSE_WHEN_EMPTY then
					setDoors(team, false)
				end
			end
		end
	end
end

function ElevatorService:Init() end

function ElevatorService:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			step(acc)
			acc = 0
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local model = player.Character
		if model then
			standing[model] = nil
			riding[model] = nil
			noticedAt[model] = nil
		end
	end)
end

return ElevatorService

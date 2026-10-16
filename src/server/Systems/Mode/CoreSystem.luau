--!strict
-- Core Run state machine, one Core per team: Home -> Carried -> (Dropped -> Home | Captured -> Home).
-- Pickup/return/capture use server-side distance checks at the MatchService tick (10 Hz), not
-- Touched, so they are reliable and can't be faked by a client. Players see the "Core" as a team
-- flag (FlagModel): a pole + flag at the station / where dropped, and a small flag on the carrier's
-- back; the world flag is hidden while carried. (Code keeps the "Core" names.)
-- The carrier can drop the flag on purpose (DropBy, "DropFlag" remote): it lands at their feet as a
-- normal dropped flag, so a teammate can pick it up and carry on; the dropper can't re-grab it for
-- Tuning.Core.RedropSeconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Types = require(script.Parent.Types)
local FlagModel = require(script.Parent.FlagModel)
local Deps = require(script.Parent.Deps)
local TeamService = require(script.Parent.Parent.Parent.Services.TeamService)

type Combatant = Types.Combatant
type CoreState = Types.CoreState

local CoreSystem = {}

-- (kind: "Taken" | "Dropped" | "Returned" | "Captured" | "NeedHome", coreTeam: string, by: Combatant?,
--  deliberate: boolean? -- "Dropped" only: true when the carrier dropped it on purpose)
CoreSystem.Event = Signal.new()

local CORE_OFFSET = Vector3.new(0, 1.4, 0) -- Core center above the pedestal CFrame
local CARRY_NAME = "CarriedCore"

local cores: { [string]: CoreState } = {}
local needHomeWarnedAt: { [Combatant]: number } = {}
local noPickupUntil: { [Combatant]: number } = {}

local function coresFolder(): Folder
	local folder = workspace:FindFirstChild("Cores")
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Cores"
		newFolder.Parent = workspace
		folder = newFolder
	end
	return folder :: Folder
end
CoreSystem.Folder = coresFolder

-- World flag (pole + team flag). Its pivot sits CORE_OFFSET above the floor / pedestal top.
local function buildWorldCore(team: string): Model
	return FlagModel.World(team, CORE_OFFSET.Y)
end

local function placeWorldCore(s: CoreState, position: Vector3)
	s.Model:PivotTo(CFrame.new(position))
	s.Model.Parent = coresFolder()
end

local function rootOf(c: Combatant?): BasePart?
	local model = c and c.Model
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function attachCarry(c: Combatant, coreTeam: string)
	local model = c.Model
	if not model then
		return
	end
	local old = model:FindFirstChild(CARRY_NAME)
	if old then
		old:Destroy()
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or rootOf(c)
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local part = FlagModel.AttachCarry(torso, coreTeam, CARRY_NAME)
	part.Parent = model
	model:SetAttribute("CarryingCore", coreTeam)
end

local function detachCarry(c: Combatant?, clearAttribute: boolean)
	local model = c and c.Model
	if not model then
		return
	end
	local part = model:FindFirstChild(CARRY_NAME)
	if part then
		part:Destroy()
	end
	if clearAttribute then
		model:SetAttribute("CarryingCore", nil)
	end
end

local function goHome(s: CoreState)
	s.State = "Home"
	s.Carrier = nil
	s.ReturnAt = nil
	s.Position = s.HomeCFrame.Position + CORE_OFFSET
	placeWorldCore(s, s.Position)
end

-- Find the floor under a death position; nil if there is none (fell out of the map).
local function floorBelow(position: Vector3): Vector3?
	if position.Y < workspace.FallenPartsDestroyHeight + 25 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { coresFolder() }
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		table.insert(exclude, bots)
	end
	for _, c in TeamService:GetAll() do
		if c.Model then
			table.insert(exclude, c.Model)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), params)
	return if result then result.Position else nil
end

local function drop(s: CoreState, position: Vector3, clearAttribute: boolean, deliberate: boolean?)
	local carrier = s.Carrier
	detachCarry(carrier, clearAttribute)
	local floor = floorBelow(position)
	if not floor then
		goHome(s)
		CoreSystem.Event:Fire("Returned", s.Team, nil)
		return
	end
	s.State = "Dropped"
	s.Carrier = nil
	s.Position = floor + CORE_OFFSET
	s.ReturnAt = os.clock() + Tuning.Core.ReturnSeconds
	placeWorldCore(s, s.Position)
	CoreSystem.Event:Fire("Dropped", s.Team, carrier, deliberate == true)
end

local function pickUp(s: CoreState, c: Combatant)
	s.State = "Carried"
	s.Carrier = c
	s.ReturnAt = nil
	s.Model.Parent = nil
	attachCarry(c, s.Team)
	-- v2: carrier is knife-only. Combat locks switching while CarryingCore is set and restores the
	-- previous slot when it clears; this call just forces the swap now if Combat exposes one.
	if c.Model then
		Deps.EquipSlot(c.Model, "Knife")
	end
	CoreSystem.Event:Fire("Taken", s.Team, c)
end

local function near(a: Vector3, b: Vector3, radius: number): boolean
	local dx, dz = a.X - b.X, a.Z - b.Z
	return dx * dx + dz * dz <= radius * radius and math.abs(a.Y - b.Y) <= math.max(radius, 7)
end

-- (Re)build both Cores at their pedestals. Call at match start / after WorldService:ResetMatch().
function CoreSystem.ResetAll()
	for _, team in TeamService.TEAMS do
		local s = cores[team]
		if s and s.Carrier then
			detachCarry(s.Carrier, true)
		end
		if not s then
			s = {
				Team = team,
				State = "Home",
				Carrier = nil,
				Position = Vector3.zero,
				ReturnAt = nil,
				HomeCFrame = CFrame.identity,
				Model = buildWorldCore(team),
			}
			cores[team] = s
		end
		assert(s, "Core state missing")
		s.HomeCFrame = Deps.GetPedestal(team)
		goHome(s)
	end
	needHomeWarnedAt = {}
	noPickupUntil = {}
end

-- After a facility shift: move any dropped Core that a sealing hinge now encloses to a safe spot
-- (keeps its return timer). `safe` maps a position to the nearest reachable one.
function CoreSystem.RelocateDropped(safe: (Vector3) -> Vector3)
	for _, s in cores do
		if s.State == "Dropped" then
			local target = safe(s.Position)
			if (target - s.Position).Magnitude > 1 then
				s.Position = target
				placeWorldCore(s, target)
			end
		end
	end
end

function CoreSystem.Get(team: string): CoreState
	return cores[team]
end

function CoreSystem.HomePosition(team: string): Vector3
	local s = cores[team]
	return if s then s.HomeCFrame.Position + CORE_OFFSET else Deps.GetPedestal(team).Position
end

function CoreSystem.AnyMoving(): boolean
	for _, s in cores do
		if s.State ~= "Home" then
			return true
		end
	end
	return false
end

function CoreSystem.CarriedBy(c: Combatant): CoreState?
	for _, s in cores do
		if s.State == "Carried" and s.Carrier == c then
			return s
		end
	end
	return nil
end

-- The carrier drops the flag on purpose where they stand. Returns true if they were carrying one.
function CoreSystem.DropBy(c: Combatant): boolean
	local s = CoreSystem.CarriedBy(c)
	local root = rootOf(c)
	if not s or not root or not c.Alive then
		return false
	end
	noPickupUntil[c] = os.clock() + Tuning.Core.RedropSeconds
	drop(s, root.Position, true, true)
	return true
end

-- The combatant died / left / was removed: drop whatever they carry where they were.
-- On death the CarryingCore attribute stays on the dead body so Combat can flag a carrier kill.
function CoreSystem.OnCombatantDown(c: Combatant, position: Vector3, died: boolean)
	local s = CoreSystem.CarriedBy(c)
	if s then
		drop(s, position, not died)
	end
end

function CoreSystem.InfoFor(team: string): { [string]: any }
	local s = cores[team]
	local carrier = s.Carrier
	local player = carrier and carrier.Player
	return {
		State = s.State,
		CarrierName = if carrier then carrier.Name else nil,
		CarrierUserId = if player then player.UserId else nil,
		Position = s.Position,
		ReturnIn = if s.ReturnAt then math.max(0, math.ceil(s.ReturnAt - os.clock())) else nil,
	}
end

-- 10 Hz. `live` enables pickups/returns/captures (off in Warmup/Ended).
function CoreSystem.Step(live: boolean)
	local now = os.clock()
	for _, s in cores do
		if s.State == "Carried" then
			local carrier = s.Carrier
			local root = rootOf(carrier)
			if carrier == nil or carrier.Removed or not carrier.Alive or root == nil then
				drop(s, s.Position, true)
			else
				s.Position = root.Position
			end
		elseif s.State == "Dropped" and s.ReturnAt and now >= s.ReturnAt then
			goHome(s)
			CoreSystem.Event:Fire("Returned", s.Team, nil)
		end
	end
	if not live then
		return
	end

	for _, c in TeamService:GetAll() do
		local root = if c.Alive then rootOf(c) else nil
		local humanoid = c.Model and c.Model:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local pos = root.Position
			local own = cores[c.Team]
			local enemy = cores[TeamService:Enemy(c.Team)]
			if own == nil or enemy == nil then
				return
			end

			if
				enemy.State ~= "Carried"
				and now >= (noPickupUntil[c] or 0)
				and near(pos, enemy.Position, Tuning.Core.PickupRadius)
			then
				pickUp(enemy, c)
			elseif own.State == "Dropped" and near(pos, own.Position, Tuning.Core.PickupRadius) then
				goHome(own)
				CoreSystem.Event:Fire("Returned", own.Team, c)
			end

			if enemy.State == "Carried" and enemy.Carrier == c then
				if near(pos, CoreSystem.HomePosition(c.Team), Tuning.Core.CaptureRadius) then
					if own.State == "Home" then
						detachCarry(c, true)
						goHome(enemy)
						CoreSystem.Event:Fire("Captured", enemy.Team, c)
					elseif now - (needHomeWarnedAt[c] or 0) > 5 then
						needHomeWarnedAt[c] = now
						CoreSystem.Event:Fire("NeedHome", enemy.Team, c)
					end
				end
			end
		end
	end
end

return CoreSystem

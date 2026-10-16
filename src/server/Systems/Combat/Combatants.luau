--!strict
-- Registry of everything that can shoot and be shot (player characters and bot models tagged
-- "Combatant"). Holds per-combatant weapon state plus a short position history used for lag
-- compensation. No networking here; CombatService owns the remotes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local HISTORY_SECONDS = 1
local HISTORY_RATE = 1 / 20

export type Sample = { T: number, P: Vector3 }

export type Slot = "Primary" | "Knife" | "Frag" | "Smoke"

-- Who dealt the last damage, captured at damage time (the attacker may respawn before we need it).
export type Source = {
	Model: Model,
	Name: string,
	Team: string?,
	Player: Player?,
	Weapon: string, -- "AK" | "Sniper" | "Knife" | "Frag"
	Wallbang: boolean,
}

export type State = {
	Model: Model,
	Humanoid: Humanoid,
	Player: Player?,
	Primary: string, -- "AK" | "Sniper"
	Slot: Slot,
	PrevSlot: Slot,
	SlotBeforeCarry: Slot?,
	EquippedAt: number,
	Mag: number,
	Reserve: number,
	Smokes: number,
	Frags: number,
	LastMeleeAt: number,
	LastFragAt: number,
	Tokens: number,
	TokenTime: number,
	LastShotId: number,
	ReloadEndsAt: number?,
	ReloadToken: number,
	DrawnAt: number,
	LastDamageAt: number,
	Killer: Source?,
	KillerHeadshot: boolean,
	KillerAt: number,
	CarrierAtDeath: boolean,
	LastSmokeAt: number,
	LastToggleAt: number,
	LastSyncAt: number,
	History: { Sample },
	LastSampleAt: number,
	Connections: { RBXScriptConnection },
}

local Combatants = {}

local states: { [Model]: State } = {}

function Combatants.Get(model: Instance?): State?
	if model and model:IsA("Model") then
		return states[model]
	end
	return nil
end

function Combatants.All(): { [Model]: State }
	return states
end

function Combatants.Register(model: Model): State?
	local existing = states[model]
	if existing then
		return existing
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local now = os.clock()
	local state: State = {
		Model = model,
		Humanoid = humanoid,
		Player = Players:GetPlayerFromCharacter(model),
		Primary = "AK",
		Slot = "Primary",
		PrevSlot = "Knife",
		SlotBeforeCarry = nil,
		EquippedAt = 0,
		Mag = Tuning.AK.Magazine,
		Reserve = Tuning.AK.Reserve,
		Smokes = Tuning.Smoke.PerLife,
		Frags = Tuning.Frag.PerLife,
		LastMeleeAt = 0,
		LastFragAt = 0,
		Tokens = 3,
		TokenTime = now,
		LastShotId = -1,
		ReloadEndsAt = nil,
		ReloadToken = 0,
		DrawnAt = 0,
		LastDamageAt = 0,
		Killer = nil,
		KillerHeadshot = false,
		KillerAt = 0,
		CarrierAtDeath = false,
		LastSmokeAt = 0,
		LastToggleAt = 0,
		LastSyncAt = 0,
		History = {},
		LastSampleAt = 0,
		Connections = {},
	}
	states[model] = state
	if not CollectionService:HasTag(model, "Combatant") then
		CollectionService:AddTag(model, "Combatant")
	end
	return state
end

function Combatants.Unregister(model: Model)
	local state = states[model]
	if not state then
		return
	end
	for _, c in state.Connections do
		c:Disconnect()
	end
	states[model] = nil
end

-- Finds the combatant model a hit part belongs to (walks up through accessories / gear).
function Combatants.FromPart(part: Instance?): Model?
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and states[node :: Model] then
			return node :: Model
		end
		node = node.Parent
	end
	return nil
end

function Combatants.IsAlive(model: Model?): boolean
	if not model then
		return false
	end
	local state = states[model]
	local humanoid = if state then state.Humanoid else model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and humanoid.Parent == model
end

function Combatants.Team(model: Model?): string?
	if not model then
		return nil
	end
	local attr = model:GetAttribute("Team")
	if type(attr) == "string" then
		return attr
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player and player.Team then
		return player.Team.Name
	end
	return nil
end

function Combatants.DisplayName(model: Model): string
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player.DisplayName
	end
	return model.Name
end

function Combatants.Source(model: Model, weapon: string, wallbang: boolean?): Source
	return {
		Model = model,
		Name = Combatants.DisplayName(model),
		Team = Combatants.Team(model),
		Player = Players:GetPlayerFromCharacter(model),
		Weapon = weapon,
		Wallbang = wallbang == true,
	}
end

-- Weapon id currently in hand for a slot.
function Combatants.WeaponFor(state: State, slot: Slot?): string
	slot = slot or state.Slot
	if slot == "Primary" then
		return state.Primary
	end
	return slot :: string
end

-- Stats table for a primary ("AK" / "Sniper").
function Combatants.Stats(primary: string): any
	return if primary == "Sniper" then Tuning.Sniper else Tuning.AK
end

function Combatants.Torso(model: Model): BasePart?
	local t = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if t and t:IsA("BasePart") then
		return t
	end
	return Combatants.Root(model)
end

function Combatants.Head(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

function Combatants.Root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

-- Hit zone from the part name. Anything else on the model (gear, Core on the back) counts as body.
function Combatants.Zone(part: BasePart): "Head" | "Body" | "Limb"
	local z = part:GetAttribute("Zone") -- hitbox parts carry their zone
	if z == "Head" or z == "Body" or z == "Limb" then
		return z
	end
	local name = part.Name
	if name == "Head" then
		return "Head"
	end
	if name == "UpperTorso" or name == "LowerTorso" or name == "Torso" or name == "HumanoidRootPart" then
		return "Body"
	end
	if
		string.find(name, "Arm", 1, true)
		or string.find(name, "Leg", 1, true)
		or string.find(name, "Hand", 1, true)
		or string.find(name, "Foot", 1, true)
	then
		return "Limb"
	end
	return "Body"
end

-- Called ~20x/s by CombatService.
function Combatants.SampleHistory(now: number)
	for model, state in states do
		if now - state.LastSampleAt >= HISTORY_RATE then
			state.LastSampleAt = now
			local root = Combatants.Root(model)
			if root then
				local history = state.History
				table.insert(history, { T = now, P = root.Position })
				while #history > 0 and now - history[1].T > HISTORY_SECONDS do
					table.remove(history, 1)
				end
			end
		end
	end
end

-- Where was this combatant's root `secondsAgo` ago (linear interpolation)? nil if unknown.
function Combatants.PositionAt(state: State, time: number): Vector3?
	local history = state.History
	local n = #history
	if n == 0 then
		return nil
	end
	if time <= history[1].T then
		return history[1].P
	end
	for i = n, 1, -1 do
		local a = history[i]
		if a.T <= time then
			local b = history[i + 1]
			if not b then
				return a.P
			end
			local alpha = (time - a.T) / math.max(b.T - a.T, 1e-3)
			return a.P:Lerp(b.P, alpha)
		end
	end
	return history[n].P
end

return Combatants

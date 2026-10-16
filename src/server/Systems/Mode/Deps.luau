--!strict
-- Guarded access to WorldService and CombatService (built in parallel by other workstreams).
-- Every call is pcall'd; a missing service/method falls back to a safe default and warns (throttled),
-- so the mode keeps running while the other systems come online. Signatures: docs/TEST_CONTRACT.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tuning"))

local Deps = {}

export type ShiftInfo = { Title: string, Detail: string }
export type NavPoint = { Id: any, Position: Vector3, Links: { any }, Dark: boolean }

local servicesFolder = script.Parent.Parent.Parent:WaitForChild("Services")

local loaded: { [string]: any } = {}
local lastWarn: { [string]: number } = {}

local function warnThrottled(key: string, message: string)
	local now = os.clock()
	local last = lastWarn[key]
	if last and now - last < 30 then
		return
	end
	lastWarn[key] = now
	warn("[Mode] " .. message)
end

local function getService(name: string): any
	local cached = loaded[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local module = servicesFolder:FindFirstChild(name)
	if module == nil or not module:IsA("ModuleScript") then
		loaded[name] = false
		return nil
	end
	local ok, result = pcall(require :: any, module)
	if ok and type(result) == "table" then
		loaded[name] = result
		return result
	end
	loaded[name] = false
	return nil
end

local function has(service: string, method: string): boolean
	local svc = getService(service)
	return svc ~= nil and type(svc[method]) == "function"
end

-- Returns (ok, result1, result2). ok = false when the service/method is missing or errored.
local function call(service: string, method: string, ...: any): (boolean, any, any)
	local svc = getService(service)
	if svc == nil then
		warnThrottled(service, `{service} not available; using fallback for {method}`)
		return false, nil, nil
	end
	local fn = svc[method]
	if type(fn) ~= "function" then
		warnThrottled(service .. "." .. method, `{service}:{method} missing; using fallback`)
		return false, nil, nil
	end
	local ok, a, b = pcall(fn, svc, ...)
	if not ok then
		warnThrottled(service .. "." .. method .. ":err", `{service}:{method} errored: {a}`)
		return false, nil, nil
	end
	return true, a, b
end

-- Accepts CFrame / Vector3 / BasePart / Model / Attachment / {CFrame=..} / {Position=..}.
local function toCFrame(value: any): CFrame?
	local kind = typeof(value)
	if kind == "CFrame" then
		return value
	elseif kind == "Vector3" then
		return CFrame.new(value)
	elseif kind == "Instance" then
		if value:IsA("BasePart") then
			return value.CFrame
		elseif value:IsA("Model") then
			return value:GetPivot()
		elseif value:IsA("Attachment") then
			return value.WorldCFrame
		end
	elseif kind == "table" then
		if value.CFrame ~= nil then
			return toCFrame(value.CFrame)
		elseif value.Position ~= nil then
			return toCFrame(value.Position)
		end
	end
	return nil
end
Deps.ToCFrame = toCFrame

function Deps.HasWorld(): boolean
	return getService("WorldService") ~= nil
end

function Deps.HasCombat(): boolean
	return getService("CombatService") ~= nil
end

---------------------------------------------------------------------------------------------------
-- World

local FALLBACK_X = { Blue = -60, Red = 60 }

local function fallbackSpawns(team: string): { CFrame }
	local x = FALLBACK_X[team] or 0
	local list = {}
	for _, z in { -8, 0, 8 } do
		local pos = Vector3.new(x, 1, z)
		table.insert(list, CFrame.lookAt(pos, Vector3.new(0, 1, z)))
	end
	return list
end

function Deps.GetSpawns(team: string): { CFrame }
	local ok, result = call("WorldService", "GetSpawns", team)
	if ok and type(result) == "table" then
		local list = {}
		for _, entry in result do
			local cf = toCFrame(entry)
			if cf then
				table.insert(list, cf)
			end
		end
		if #list > 0 then
			return list
		end
	end
	return fallbackSpawns(team)
end

function Deps.GetPedestal(team: string): CFrame
	local ok, result = call("WorldService", "GetPedestal", team)
	if ok then
		local cf = toCFrame(result)
		if cf then
			return cf
		end
	end
	return CFrame.new((FALLBACK_X[team] or 0) * 1.25, 1, 0)
end

function Deps.GetNavPoints(): { NavPoint }
	local ok, result = call("WorldService", "GetNavPoints")
	local list: { NavPoint } = {}
	if ok and type(result) == "table" then
		for _, p in result do
			if type(p) == "table" and p.Id ~= nil and typeof(p.Position) == "Vector3" then
				table.insert(list, {
					Id = p.Id,
					Position = p.Position,
					Links = if type(p.Links) == "table" then p.Links else {},
					Dark = p.Dark == true,
				})
			end
		end
	end
	return list
end

function Deps.IsDark(position: Vector3): boolean
	local ok, result = call("WorldService", "IsDark", position)
	return ok and result == true
end

-- Optional (not in the contract): lets the 5 s warning name the coming change.
function Deps.PeekNextShift(): ShiftInfo?
	if not has("WorldService", "PeekNextShift") then
		return nil
	end
	local ok, result = call("WorldService", "PeekNextShift")
	if ok and type(result) == "table" and type(result.Title) == "string" then
		return { Title = result.Title, Detail = tostring(result.Detail or "") }
	end
	return nil
end

function Deps.ApplyNextShift(): ShiftInfo
	local ok, result = call("WorldService", "ApplyNextShift")
	if ok and type(result) == "table" then
		return { Title = tostring(result.Title or "FACILITY SHIFT"), Detail = tostring(result.Detail or "") }
	end
	return { Title = "FACILITY SHIFT", Detail = "No change (world offline)" }
end

function Deps.GetSnapshot(): any
	local ok, result = call("WorldService", "GetSnapshot")
	if ok and type(result) == "table" then
		result.Lamps = result.Lamps or {}
		result.Hinges = result.Hinges or {}
		result.Bounds = result.Bounds or { Min = Vector3.zero, Max = Vector3.zero }
		return result
	end
	return {
		Lamps = {},
		Hinges = {},
		Bounds = { Min = Vector3.new(-90, 0, -40), Max = Vector3.new(90, 10, 40) },
	}
end

function Deps.SafePosition(position: Vector3): Vector3
	local ok, result = call("WorldService", "GetSafePosition", position)
	return if ok and typeof(result) == "Vector3" then result else position
end

-- Sniper perches (foot-level CFrames facing down a lane). Empty when World has no such API.
function Deps.GetSniperSpots(team: string): { CFrame }
	if not has("WorldService", "GetSniperSpots") then
		return {}
	end
	local ok, result = call("WorldService", "GetSniperSpots", team)
	local list = {}
	if ok and type(result) == "table" then
		for _, entry in result do
			local cf = toCFrame(entry)
			if cf then
				table.insert(list, cf)
			end
		end
	end
	return list
end

function Deps.IsInWater(position: Vector3): boolean
	if not has("WorldService", "IsInWater") then
		return false
	end
	local ok, result = call("WorldService", "IsInWater", position)
	return ok and result == true
end

function Deps.IsInWater(position: Vector3): boolean
	if not has("WorldService", "IsInWater") then
		return false
	end
	local ok, result = call("WorldService", "IsInWater", position)
	return ok and result == true
end

-- "Inside own spawn room". Uses WorldService:IsInSpawnRoom(team, position) when it exists,
-- otherwise: within SPAWN_ROOM_RADIUS of one of the team's spawn points (same floor).
local SPAWN_ROOM_RADIUS = 22
function Deps.IsInSpawnRoom(team: string, position: Vector3): boolean
	if has("WorldService", "IsInSpawnRoom") then
		local ok, result = call("WorldService", "IsInSpawnRoom", team, position)
		if ok then
			return result == true
		end
	end
	for _, cf in Deps.GetSpawns(team) do
		local d = position - cf.Position
		if Vector3.new(d.X, 0, d.Z).Magnitude <= SPAWN_ROOM_RADIUS and math.abs(d.Y) < 10 then
			return true
		end
	end
	return false
end

-- Connect to a World signal (e.g. "LightChanged") if it exists. Returns true when connected.
function Deps.ConnectWorldSignal(name: string, fn: (...any) -> ()): boolean
	local svc = getService("WorldService")
	local signal = svc and svc[name]
	if signal == nil then
		return false
	end
	local ok = pcall(function()
		if typeof(signal) == "Instance" and signal:IsA("BindableEvent") then
			signal.Event:Connect(fn)
		else
			signal:Connect(fn)
		end
	end)
	return ok
end

function Deps.ResetMatch()
	call("WorldService", "ResetMatch")
	call("CombatService", "ResetMatch") -- clears lingering smoke clouds
end

-- Only when WorldService doesn't exist at all: a bare floor so the mode can be tested alone.
function Deps.EnsureFallbackWorld()
	if Deps.HasWorld() or workspace:FindFirstChild("ModeFallbackArena") then
		return
	end
	warn("[Mode] WorldService missing; building a fallback test floor")
	local floor = Instance.new("Part")
	floor.Name = "ModeFallbackArena"
	floor.Anchored = true
	floor.Size = Vector3.new(220, 2, 100)
	floor.CFrame = CFrame.new(0, -1, 0)
	floor.Color = Color3.fromRGB(90, 88, 80)
	floor.Material = Enum.Material.Carpet
	floor.Parent = workspace
	for team, x in FALLBACK_X do
		local light = Instance.new("PointLight")
		light.Color = Tuning.Teams[team].Color
		light.Range = 40
		light.Brightness = 2
		local holder = Instance.new("Part")
		holder.Name = "FallbackBaseLight_" .. team
		holder.Anchored = true
		holder.CanCollide = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(x * 1.1, 12, 0)
		light.Parent = holder
		holder.Parent = floor
	end
end

---------------------------------------------------------------------------------------------------
-- Combat

-- Returns true when a shot actually left the barrel (Combat applies rate, ammo, reload, error).
function Deps.BotFire(model: Model, targetPosition: Vector3): boolean
	local ok, fired = call("CombatService", "BotFire", model, targetPosition)
	return ok and fired ~= false
end

-- Optional (Combat extra): bot smoke throw toward a position.
function Deps.BotThrowSmoke(model: Model, targetPosition: Vector3): boolean
	if not has("CombatService", "BotThrowSmoke") then
		return false
	end
	local ok, thrown = call("CombatService", "BotThrowSmoke", model, targetPosition)
	return ok and thrown == true
end

-- v2: GiveLoadout(model, primary). Older Combat ignores the extra argument.
function Deps.GiveLoadout(model: Model, primary: string?)
	local ok = call("CombatService", "GiveLoadout", model, primary)
	if not ok and model:GetAttribute("HeldWeapon") == nil then
		model:SetAttribute("HeldWeapon", primary or "AK")
	end
end

-- Server-side slot change for bots / the forced carrier knife. Tries the likely Combat method
-- names; returns false when Combat has none (Combat may also react to CarryingCore by itself).
local EQUIP_METHODS = { "ForceSlot", "BotEquip", "EquipSlot", "SetSlot" }
function Deps.EquipSlot(model: Model, slot: string): boolean
	for _, method in EQUIP_METHODS do
		if has("CombatService", method) then
			local ok = call("CombatService", method, model, slot)
			return ok
		end
	end
	return false
end

function Deps.SetAiming(model: Model, aiming: boolean)
	local ok = call("CombatService", "SetAiming", model, aiming)
	if not ok then
		model:SetAttribute("Aiming", aiming)
	end
end

-- v2 bot melee (knife). Passes the target position like BotFire.
function Deps.BotMelee(model: Model, targetPosition: Vector3): boolean
	if not has("CombatService", "BotMelee") then
		return false
	end
	local ok, hit = call("CombatService", "BotMelee", model, targetPosition)
	return ok and hit ~= false
end

-- v2 bot frag throw toward a position.
function Deps.BotThrowFrag(model: Model, targetPosition: Vector3): boolean
	if not has("CombatService", "BotThrowFrag") then
		return false
	end
	local ok, thrown = call("CombatService", "BotThrowFrag", model, targetPosition)
	return ok and thrown ~= false
end

function Deps.IsSmoked(a: Vector3, b: Vector3): boolean
	local ok, result = call("CombatService", "IsSmoked", a, b)
	return ok and result == true
end

-- Optional (not in the contract). Returns false when Combat has no bot flashlight API.
function Deps.SetFlashlight(model: Model, on: boolean): boolean
	if not has("CombatService", "SetFlashlight") then
		return false
	end
	local ok = call("CombatService", "SetFlashlight", model, on)
	return ok
end

-- CombatService.OnDeath: Signal(victimModel, killerModel?, headshot)
function Deps.ConnectOnDeath(fn: (Model, Model?, boolean?) -> ()): boolean
	local svc = getService("CombatService")
	local signal = svc and svc.OnDeath
	if signal == nil then
		warn("[Mode] CombatService.OnDeath unavailable; kills will not be credited")
		return false
	end
	local ok, err = pcall(function()
		if typeof(signal) == "Instance" and signal:IsA("BindableEvent") then
			signal.Event:Connect(fn)
		else
			signal:Connect(fn) -- Signal module or RBXScriptSignal
		end
	end)
	if not ok then
		warn("[Mode] Could not connect CombatService.OnDeath: " .. tostring(err))
	end
	return ok
end

return Deps

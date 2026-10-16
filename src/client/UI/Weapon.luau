--!strict
-- Lazy, guarded bridge to Combat's WeaponController (src/client/Controllers/WeaponController).
-- The UI must keep working if that module is missing, still loading, or errors, so:
--   * Weapon.call(method, ...) pcalls the method if it exists (no-op otherwise).
--   * Weapon.state() merges WeaponController.State (v2: Held / Slots / Frags / Scoped) with
--     fallbacks from AmmoSync, LoadoutState and the server-set character attributes
--     (HeldWeapon / Scoped / Aiming / Flashlight / CarryingCore).
--   * Weapon.Changed fires whenever any of those sources change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

export type State = {
	Held: string, -- "AK" | "Sniper" | "Knife" | "Frag" | "Smoke"
	Primary: string, -- "AK" | "Sniper" (the primary currently in slot 1)
	Mag: number,
	Reserve: number,
	Smokes: number,
	Frags: number,
	Aiming: boolean,
	Scoped: boolean,
	Spread: number, -- degrees
	Reloading: boolean,
	Flashlight: boolean,
	Crouched: boolean,
	Carrying: string?, -- enemy team name while carrying a Core (knife only)
	ThrowCharge: number, -- 0 = not charging a throw, else its strength (Tuning.Throw.MinStrength..1)
}

local Weapon = {}
Weapon.Changed = Signal.new()

local controller: any = nil
local searching = false

local fallback = {
	Mag = Tuning.AK.Magazine,
	Reserve = Tuning.AK.Reserve,
	Smokes = Tuning.Smoke.PerLife,
	Frags = Tuning.Frag.PerLife,
}
local lastPrimary = "AK" -- last primary seen in hand / reported by WeaponController
local loadoutPrimary: string? = nil -- from LoadoutState

local function tryResolve(): any
	if controller then
		return controller
	end
	local controllers = script.Parent.Parent:FindFirstChild("Controllers")
	local mod = controllers and controllers:FindFirstChild("WeaponController")
	if not (mod and mod:IsA("ModuleScript")) then
		return nil
	end
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" then
		controller = result
		local changed = (result :: any).Changed
		if type(changed) == "table" and type(changed.Connect) == "function" then
			pcall(function()
				changed:Connect(function()
					Weapon.Changed:Fire()
				end)
			end)
		end
		Weapon.Changed:Fire()
	end
	return controller
end

-- Keep retrying in the background until the controller exists (it is written in parallel).
local function startSearch()
	if searching then
		return
	end
	searching = true
	task.spawn(function()
		for _ = 1, 120 do
			if tryResolve() then
				return
			end
			task.wait(1)
		end
	end)
end

function Weapon.get(): any
	return tryResolve()
end

-- Calls WeaponController:method(...) if available. Returns true if it ran without error.
function Weapon.call(method: string, ...: any): boolean
	local c = tryResolve()
	if not c then
		return false
	end
	local fn = c[method]
	if type(fn) ~= "function" then
		return false
	end
	local ok, err = pcall(fn, c, ...)
	if not ok then
		warn(`[UI] WeaponController:{method} failed: {err}`)
	end
	return ok
end

local function attr(name: string): any
	local character = Players.LocalPlayer.Character
	return character and character:GetAttribute(name)
end

local function isPrimary(name: any): boolean
	return type(name) == "string" and table.find(Tuning.Primaries, name) ~= nil
end

-- Combat may report Held as a slot ("Primary") or a weapon ("AK"); normalise to a weapon name.
local function normaliseHeld(held: any, primary: string): string?
	if held == "Primary" then
		return primary
	end
	if type(held) == "string" and held ~= "" then
		return held
	end
	return nil
end

function Weapon.state(): State
	local c = controller
	local s = (c and type(c.State) == "table") and c.State or {}
	local function num(v: any, default: number): number
		return if type(v) == "number" then v else default
	end

	local slots = s.Slots
	local primary = lastPrimary
	if type(slots) == "table" and isPrimary(slots.Primary) then
		primary = slots.Primary
	elseif isPrimary(s.Primary) then
		primary = s.Primary
	end
	local heldAttr = attr("HeldWeapon")
	if isPrimary(heldAttr) then
		primary = heldAttr
	end
	lastPrimary = primary

	local held = normaliseHeld(s.Held, primary) or normaliseHeld(heldAttr, primary) or primary
	local scoped = if type(s.Scoped) == "boolean" then s.Scoped else attr("Scoped") == true
	local aiming = if type(s.Aiming) == "boolean" then s.Aiming else attr("Aiming") == true
	local carrying = attr("CarryingCore")
	local spreadDefault = if held == "Sniper" then Tuning.Sniper.SpreadHip else Tuning.AK.SpreadHip
	return {
		Held = held,
		Primary = primary,
		Mag = num(s.Mag, fallback.Mag),
		Reserve = num(s.Reserve, fallback.Reserve),
		Smokes = num(s.Smokes, fallback.Smokes),
		Frags = num(s.Frags, fallback.Frags),
		Aiming = aiming,
		Scoped = scoped,
		Spread = num(s.Spread, spreadDefault),
		Reloading = s.Reloading == true,
		Flashlight = if type(s.Flashlight) == "boolean" then s.Flashlight else attr("Flashlight") == true,
		Crouched = s.Crouched == true,
		Carrying = if type(carrying) == "string" and carrying ~= "" then carrying else nil,
		ThrowCharge = num(s.ThrowCharge, 0),
	}
end

-- Primary chosen in the loadout menu as last confirmed by the server (may apply next spawn).
function Weapon.loadoutPrimary(): string?
	return loadoutPrimary
end

--------------------------------------------------------------------------------
-- Fallback sources
--------------------------------------------------------------------------------

Remotes.Get("AmmoSync").OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.Mag) == "number" then
		fallback.Mag = data.Mag
	end
	if type(data.Reserve) == "number" then
		fallback.Reserve = data.Reserve
	end
	if type(data.Smokes) == "number" then
		fallback.Smokes = data.Smokes
	end
	if type(data.Frags) == "number" then
		fallback.Frags = data.Frags
	end
	Weapon.Changed:Fire()
end)

local WATCHED = { "HeldWeapon", "Scoped", "Aiming", "Flashlight", "CarryingCore", "Team" }
local function watchCharacter(character: Model)
	for _, name in WATCHED do
		character:GetAttributeChangedSignal(name):Connect(function()
			Weapon.Changed:Fire()
		end)
	end
	Weapon.Changed:Fire()
end
Players.LocalPlayer.CharacterAdded:Connect(watchCharacter)
if Players.LocalPlayer.Character then
	watchCharacter(Players.LocalPlayer.Character)
end

Remotes.Get("LoadoutState").OnClientEvent:Connect(function(data: any)
	if type(data) == "table" and isPrimary(data.Primary) then
		loadoutPrimary = data.Primary
		if data.AppliesNow == true then
			lastPrimary = data.Primary
		end
		Weapon.Changed:Fire()
	end
end)

startSearch()

return Weapon

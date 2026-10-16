--!strict
-- Shared types for the Mode + Bots workstream.

export type Combatant = {
	Id: string, -- "P<userId>" for players, "B<n>" for bots
	Name: string,
	Team: string, -- "Blue" | "Red"
	Player: Player?,
	IsBot: boolean,
	Model: Model?, -- current character / bot body (nil before first spawn)
	Alive: boolean,
	Streak: number, -- consecutive deaths without a kill (respawn timer)
	SpawnToken: number, -- bumped on every spawn; cancels stale respawn timers
	Removed: boolean,
	Role: string?, -- bots: "attacker" | "defender" | "roamer"
	SpawnedAt: number?, -- os.clock() of the latest spawn (loadout apply window)
}

export type CoreStateName = "Home" | "Carried" | "Dropped"

export type CoreState = {
	Team: string, -- the team that owns this Core
	State: CoreStateName,
	Carrier: Combatant?,
	Position: Vector3,
	ReturnAt: number?, -- os.clock() when a dropped Core auto-returns
	HomeCFrame: CFrame,
	Model: Model,
}

return {}

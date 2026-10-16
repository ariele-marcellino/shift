--!strict
-- Per-match stats (kills/deaths/captures/returns) for every combatant who took part, including
-- players who left and bots that were replaced.

local Types = require(script.Parent.Types)
type Combatant = Types.Combatant

export type Row = {
	Name: string,
	Team: string,
	Kills: number,
	Deaths: number,
	Captures: number,
	Returns: number,
	Bot: boolean,
}

local Stats = {}

local rows: { [string]: Row } = {}
local order: { string } = {}

function Stats.Reset(members: { Combatant })
	rows = {}
	order = {}
	for _, c in members do
		Stats.Ensure(c)
	end
end

function Stats.Ensure(c: Combatant): Row
	local row = rows[c.Id]
	if not row then
		row =
			{ Name = c.Name, Team = c.Team, Kills = 0, Deaths = 0, Captures = 0, Returns = 0, Bot = c.IsBot }
		rows[c.Id] = row
		table.insert(order, c.Id)
	end
	assert(row, "Stats row missing")
	row.Team = c.Team
	return row
end

function Stats.Add(c: Combatant, field: "Kills" | "Deaths" | "Captures" | "Returns", amount: number?)
	local row = Stats.Ensure(c)
	local delta = amount or 1
	if field == "Kills" then
		row.Kills += delta
	elseif field == "Deaths" then
		row.Deaths += delta
	elseif field == "Captures" then
		row.Captures += delta
	else
		row.Returns += delta
	end
end

-- `only`: restrict to these combatant ids (live scoreboard = current roster); nil = everyone.
function Stats.Rows(only: { [string]: boolean }?): { Row }
	local list = {}
	for _, id in order do
		local row = rows[id]
		if only and not only[id] then
			continue
		end
		table.insert(list, {
			Name = row.Name,
			Team = row.Team,
			Kills = row.Kills,
			Deaths = row.Deaths,
			Captures = row.Captures,
			Returns = row.Returns,
			Bot = row.Bot,
		})
	end
	table.sort(list, function(a, b)
		if a.Captures ~= b.Captures then
			return a.Captures > b.Captures
		end
		return a.Kills > b.Kills
	end)
	return list
end

-- MVP: captures weigh most, then kills, then returns. nil when nobody did anything.
function Stats.Mvp(): { Name: string, Kills: number, Captures: number }?
	local best: Row? = nil
	local bestScore = 0
	for _, id in order do
		local row = rows[id]
		local score = row.Captures * 5 + row.Kills * 1 + row.Returns * 2
		if score > bestScore or (best ~= nil and score == bestScore and row.Kills > best.Kills) then
			best = row
			bestScore = score
		end
	end
	if not best or bestScore <= 0 then
		return nil
	end
	return { Name = best.Name, Kills = best.Kills, Captures = best.Captures }
end

return Stats

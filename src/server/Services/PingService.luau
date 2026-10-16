--!strict
-- Team pings. A client sends a world position (from the map or the crosshair); the server checks it
-- is a sane point inside the facility, rate-limits it, and relays it to the pinger's team only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))
local TeamService = require(script.Parent.TeamService)

local PingService = {}

local lastPing: { [Player]: number } = {}

-- Facility bounds (Layout: x +-177, z +-81) with a little slack.
local BOUNDS_X, BOUNDS_Z, MIN_Y, MAX_Y = 190, 84, -5, 20

local function valid(position: any): boolean
	return typeof(position) == "Vector3"
		and position.X == position.X -- not NaN
		and math.abs(position.X) <= BOUNDS_X
		and math.abs(position.Z) <= BOUNDS_Z
		and position.Y >= MIN_Y
		and position.Y <= MAX_Y
end

function PingService:Init() end

function PingService:Start()
	local shown = Remotes.Get("PingShown")
	Remotes.Get("Ping").OnServerEvent:Connect(function(player: Player, position: any)
		if not valid(position) then
			return
		end
		local now = os.clock()
		if now - (lastPing[player] or -math.huge) < Tuning.Map.PingCooldown * 0.6 then
			return
		end
		lastPing[player] = now
		local c = TeamService:GetByPlayer(player)
		local team = c and c.Team
		if not team then
			return
		end
		for _, mate in TeamService:GetTeam(team) do
			if mate.Player then
				shown:FireClient(mate.Player, player.Name, team, position)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPing[player] = nil
	end)
end

return PingService

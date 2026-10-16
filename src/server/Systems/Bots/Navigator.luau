--!strict
-- Bot movement: A* over WorldService:GetNavPoints() (shared graph, refreshed on invalidation and
-- every 10 s), followed with Humanoid:MoveTo. Random per-path edge noise makes bots vary lanes.
-- Falls back to PathfindingService when there is no graph or no graph path. Stuck handling:
-- jump -> skip waypoint -> PathfindingService repath -> give up (brain picks a new goal).

local PathfindingService = game:GetService("PathfindingService")

local Deps = require(script.Parent.Parent.Mode.Deps)
local WorldRay = require(script.Parent.WorldRay)

type NavNode = { Id: any, Position: Vector3, Links: { any }, Dark: boolean, Owner: string? }

local Navigator = {}
Navigator.__index = Navigator

local GRAPH_MAX_AGE = 10
local REACH_RADIUS = 2.5
local DIRECT_RANGE = 28
local LANE_NOISE = 0.7
local EYE = Vector3.new(0, 2, 0)

local graphList: { NavNode } = {}
local graphById: { [any]: NavNode } = {}
local graphStamp = -math.huge
local graphDirty = true
local rng = Random.new()

function Navigator.Invalidate()
	graphDirty = true
end

function Navigator.RefreshGraph()
	local now = os.clock()
	if not graphDirty and now - graphStamp < GRAPH_MAX_AGE then
		return
	end
	graphDirty = false
	graphStamp = now
	local points = Deps.GetNavPoints()
	graphList = points :: any
	graphById = {}
	for _, node in graphList do
		graphById[node.Id] = node
	end
end

function Navigator.Nodes(): { NavNode }
	Navigator.RefreshGraph()
	return graphList
end

-- Nearest node, preferring one we can actually walk to in a straight line.
local function nearestNode(position: Vector3): NavNode?
	local candidates: { { Node: NavNode, D: number } } = {}
	for _, node in graphList do
		local delta = node.Position - position
		local d = Vector3.new(delta.X, delta.Y * 3, delta.Z).Magnitude
		table.insert(candidates, { Node = node, D = d })
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates, function(a, b)
		return a.D < b.D
	end)
	for i = 1, math.min(4, #candidates) do
		local node = candidates[i].Node
		if WorldRay.Clear(position + EYE, node.Position + EYE) then
			return node
		end
	end
	return candidates[1].Node
end

-- `team`: nodes owned by another team (inside its spawn barriers) are never entered.
local function astar(start: NavNode, goal: NavNode, team: string?): { NavNode }?
	if start == goal then
		return { start }
	end
	local open: { NavNode } = { start }
	local inOpen: { [NavNode]: boolean } = { [start] = true }
	local closed: { [NavNode]: boolean } = {}
	local g: { [NavNode]: number } = { [start] = 0 }
	local f: { [NavNode]: number } = { [start] = (goal.Position - start.Position).Magnitude }
	local cameFrom: { [NavNode]: NavNode } = {}
	local expansions = 0

	while #open > 0 and expansions < 3000 do
		expansions += 1
		local bestIndex = 1
		for i = 2, #open do
			if f[open[i]] < f[open[bestIndex]] then
				bestIndex = i
			end
		end
		local node = open[bestIndex]
		open[bestIndex] = open[#open]
		open[#open] = nil
		inOpen[node] = nil

		if node == goal then
			local path = { node }
			local cursor = node
			while cameFrom[cursor] do
				cursor = cameFrom[cursor]
				table.insert(path, 1, cursor)
			end
			return path
		end
		closed[node] = true

		for _, id in node.Links do
			local neighbor = graphById[id]
			if neighbor and not closed[neighbor] and (neighbor.Owner == nil or neighbor.Owner == team) then
				local cost = (neighbor.Position - node.Position).Magnitude
					* (1 + rng:NextNumber() * LANE_NOISE)
				local tentative = g[node] + cost
				local known = g[neighbor]
				if known == nil or tentative < known then
					g[neighbor] = tentative
					f[neighbor] = tentative + (goal.Position - neighbor.Position).Magnitude
					cameFrom[neighbor] = node
					if not inOpen[neighbor] then
						inOpen[neighbor] = true
						table.insert(open, neighbor)
					end
				end
			end
		end
	end
	return nil
end

export type Navigator = typeof(setmetatable(
	{} :: {
		Humanoid: Humanoid,
		Root: BasePart,
		Goal: Vector3?,
		Waypoints: { Vector3 },
		JumpAt: { [number]: boolean },
		Index: number,
		Token: number,
		Held: boolean,
		Arrived: boolean,
		GaveUp: boolean,
		LastTarget: Vector3?,
		LastMoveTo: number,
		LastCheck: number,
		LastCheckPos: Vector3,
		Stuck: number,
	},
	Navigator
))

function Navigator.new(humanoid: Humanoid, root: BasePart): Navigator
	return setmetatable({
		Humanoid = humanoid,
		Root = root,
		Goal = nil,
		Waypoints = {},
		JumpAt = {},
		Index = 1,
		Token = 0,
		Held = false,
		Arrived = false,
		GaveUp = false,
		LastTarget = nil,
		LastMoveTo = 0,
		LastCheck = os.clock(),
		LastCheckPos = root.Position,
		Stuck = 0,
	}, Navigator)
end

function Navigator.SetWaypoints(self: Navigator, list: { Vector3 }, jumps: { [number]: boolean }?)
	self.Waypoints = list
	self.JumpAt = jumps or {}
	self.Index = 1
	self.Arrived = #list == 0
	self.LastTarget = nil
	self.Stuck = 0
end

function Navigator.Pathfind(self: Navigator)
	self.Token += 1
	local token = self.Token
	local from = self.Root.Position
	local goal = self.Goal
	if not goal then
		return
	end
	self:SetWaypoints({})
	self.Arrived = false
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		if self.Token ~= token then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			local list, jumps = {}, {}
			for i, waypoint in path:GetWaypoints() do
				if i > 1 then
					table.insert(list, waypoint.Position)
					if waypoint.Action == Enum.PathWaypointAction.Jump then
						jumps[#list] = true
					end
				end
			end
			self:SetWaypoints(list, jumps)
		else
			self:SetWaypoints({ goal }) -- last resort: straight line
		end
	end)
end

function Navigator.Plan(self: Navigator)
	local goal = self.Goal
	if not goal then
		return
	end
	self.Token += 1
	self.GaveUp = false
	local pos = self.Root.Position
	if (goal - pos).Magnitude < DIRECT_RANGE and WorldRay.Clear(pos + EYE, goal + EYE) then
		self:SetWaypoints({ goal })
		return
	end
	Navigator.RefreshGraph()
	local a, b = nearestNode(pos), nearestNode(goal)
	local model = self.Root.Parent
	local team = model and model:GetAttribute("Team")
	local nodes = if a and b then astar(a, b, if type(team) == "string" then team else nil) else nil
	if nodes then
		local list = {}
		for i, node in nodes do
			-- Skip the first node if we're already past it toward the second.
			if
				not (
					i == 1
					and #nodes > 1
					and (nodes[2].Position - pos).Magnitude
						< (nodes[2].Position - node.Position).Magnitude
				)
			then
				table.insert(list, node.Position)
			end
		end
		table.insert(list, goal)
		self:SetWaypoints(list)
	else
		self:Pathfind()
	end
end

-- Re-plans only when the goal moved meaningfully (or force).
function Navigator.SetGoal(self: Navigator, goal: Vector3?, force: boolean?)
	if goal == nil then
		self:Stop()
		return
	end
	local current = self.Goal
	if not force and current and (current - goal).Magnitude < 5 and not self.GaveUp then
		return
	end
	self.Goal = goal
	self.Held = false
	self:Plan()
end

function Navigator.Stop(self: Navigator)
	self.Goal = nil
	self.Token += 1
	self:SetWaypoints({})
	self.Humanoid:MoveTo(self.Root.Position)
end

-- Stand still (or strafe to `toward`) while keeping the goal; Resume re-plans from here.
function Navigator.Hold(self: Navigator, toward: Vector3?)
	self.Held = true
	self.Humanoid:MoveTo(toward or self.Root.Position)
	self.LastTarget = nil
end

function Navigator.Resume(self: Navigator)
	if self.Held then
		self.Held = false
		self:Plan()
	end
end

function Navigator.Step(self: Navigator, now: number)
	if self.Held or self.Goal == nil then
		return
	end
	local waypoint = self.Waypoints[self.Index]
	if not waypoint then
		return -- arrived, or a path is still computing
	end
	local pos = self.Root.Position
	local flat = Vector3.new(waypoint.X - pos.X, 0, waypoint.Z - pos.Z)
	if flat.Magnitude < REACH_RADIUS and math.abs(waypoint.Y - pos.Y) < 7 then
		self.Index += 1
		waypoint = self.Waypoints[self.Index]
		if not waypoint then
			self.Arrived = true
			return
		end
	end

	if waypoint ~= self.LastTarget or now - self.LastMoveTo > 2 then
		self.Humanoid:MoveTo(waypoint)
		self.LastTarget = waypoint
		self.LastMoveTo = now
		if self.JumpAt[self.Index] then
			self.Humanoid.Jump = true
		end
	end

	if now - self.LastCheck >= 1 then
		local moved = (pos - self.LastCheckPos).Magnitude
		self.LastCheck = now
		self.LastCheckPos = pos
		if moved < 1 and self.Humanoid.WalkSpeed > 1 then
			self.Stuck += 1
			if self.Stuck == 1 then
				self.Humanoid.Jump = true
			elseif self.Stuck == 2 then
				self.Index = math.min(self.Index + 1, #self.Waypoints)
				self.LastTarget = nil
			elseif self.Stuck == 3 then
				self:Pathfind()
			elseif self.Stuck >= 6 then
				self.GaveUp = true
				self:Stop()
			end
		else
			self.Stuck = 0
		end
	end
end

function Navigator.IsIdle(self: Navigator): boolean
	return self.Goal == nil or self.Arrived or self.GaveUp
end

return Navigator

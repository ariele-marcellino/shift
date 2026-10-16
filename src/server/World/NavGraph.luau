--!strict
-- Hand-placed navigation graph for bots. Nodes sit at floor level (Y = 0) on corridor centres and in
-- doorways, so every link is a straight, unobstructed walk. Links through a shift hinge carry that
-- hinge's id and only exist while the hinge is open.

-- Owner: nodes inside a team's spawn area (behind its spawn barriers); other teams never path there.
export type NavPoint = { Id: string, Position: Vector3, Links: { string }, Dark: boolean, Owner: string? }

type Edge = { To: string, Hinge: string? }
type Node = { Id: string, Position: Vector3, Edges: { Edge }, Owner: string? }

local NavGraph = {}

local nodes: { [string]: Node } = {}
local order: { Node } = {}

function NavGraph.AddNode(id: string, position: Vector3, owner: string?)
	assert(nodes[id] == nil, "Duplicate nav node " .. id)
	local node = { Id = id, Position = position, Edges = {}, Owner = owner }
	nodes[id] = node
	table.insert(order, node)
end

function NavGraph.Link(a: string, b: string, hinge: string?)
	local na, nb = nodes[a], nodes[b]
	assert(na and nb, `Nav link to unknown node: {a} <-> {b}`)
	table.insert(na.Edges, { To = b, Hinge = hinge })
	table.insert(nb.Edges, { To = a, Hinge = hinge })
end

function NavGraph.Has(id: string): boolean
	return nodes[id] ~= nil
end

local function edgeOpen(edge: Edge, isOpen: (string) -> boolean): boolean
	return edge.Hinge == nil or isOpen(edge.Hinge)
end

-- Fresh read-only snapshot of the graph under the given hinge states.
function NavGraph.Build(isOpen: (string) -> boolean, isDark: (Vector3) -> boolean): { NavPoint }
	local out = table.create(#order)
	for _, node in order do
		local links = {}
		for _, edge in node.Edges do
			if edgeOpen(edge, isOpen) then
				table.insert(links, edge.To)
			end
		end
		table.insert(out, {
			Id = node.Id,
			Position = node.Position,
			Links = links,
			Dark = isDark(node.Position),
			Owner = node.Owner,
		})
	end
	return out
end

function NavGraph.Reachable(from: string, to: string, isOpen: (string) -> boolean): boolean
	if not nodes[from] or not nodes[to] then
		return false
	end
	local seen = { [from] = true }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		if id == to then
			return true
		end
		for _, edge in nodes[id].Edges do
			if not seen[edge.To] and edgeOpen(edge, isOpen) then
				seen[edge.To] = true
				table.insert(queue, edge.To)
			end
		end
	end
	return false
end

-- Nodes not reachable from `from` (used as a build-time sanity check).
-- One BFS from `from` (a node is reachable exactly when it is in that closure) instead of one
-- Reachable search per node.
function NavGraph.Unreachable(from: string, isOpen: (string) -> boolean): { string }
	local missing = {}
	if not nodes[from] then
		for _, node in order do
			table.insert(missing, node.Id)
		end
		return missing
	end
	local seen = { [from] = true }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, edge in nodes[id].Edges do
			if not seen[edge.To] and edgeOpen(edge, isOpen) then
				seen[edge.To] = true
				table.insert(queue, edge.To)
			end
		end
	end
	for _, node in order do
		if not seen[node.Id] then
			table.insert(missing, node.Id)
		end
	end
	return missing
end

return NavGraph

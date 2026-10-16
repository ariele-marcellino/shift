--!strict
-- Client bootstrap: require every ModuleScript in Controllers, call all :Init(), then all :Start(),
-- then fire ClientReady so every server service pushes its current state to this player.
-- Each module is error-isolated so one broken controller can't stop the others from running.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local START_TIMEOUT = 10 -- seconds to wait for yielding :Start() calls before firing ClientReady

type Module = { Init: ((self: any) -> ())?, Start: ((self: any) -> ())? }
type Entry = { Name: string, Module: Module }

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local folder = script:WaitForChild("Controllers")

local children = folder:GetChildren()
table.sort(children, function(a, b)
	return a.Name < b.Name
end)

local entries: { Entry } = {}
for _, child in children do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			warn(`[Client] Failed to require {child.Name}: {result}`)
		elseif type(result) ~= "table" then
			warn(`[Client] {child.Name} did not return a table`)
		else
			table.insert(entries, { Name = child.Name, Module = result :: any })
		end
	end
end

for _, entry in entries do
	local init = entry.Module.Init
	if type(init) == "function" then
		local ok, err = pcall(init, entry.Module)
		if not ok then
			warn(`[Client] {entry.Name}:Init() failed: {err}`)
		end
	end
end

local pending = 0
for _, entry in entries do
	local start = entry.Module.Start
	if type(start) == "function" then
		pending += 1
		task.spawn(function()
			local ok, err = xpcall(start, debug.traceback, entry.Module)
			if not ok then
				warn(`[Client] {entry.Name}:Start() failed: {err}`)
			end
			pending -= 1
		end)
	end
end

local deadline = os.clock() + START_TIMEOUT
while pending > 0 and os.clock() < deadline do
	task.wait()
end
if pending > 0 then
	warn(`[Client] {pending} controller(s) still starting after {START_TIMEOUT}s; firing ClientReady anyway`)
end

Remotes.Get("ClientReady"):FireServer()

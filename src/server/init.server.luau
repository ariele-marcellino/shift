--!strict
-- Server bootstrap: require every ModuleScript in Services, call all :Init(), then all :Start().
-- Each module is error-isolated so one broken service can't stop the others from running.

local START_TIMEOUT = 15 -- seconds before we warn about a :Start() that is still yielding

type Module = { Init: ((self: any) -> ())?, Start: ((self: any) -> ())? }
type Entry = { Name: string, Module: Module }

local folder = script:WaitForChild("Services")

local children = folder:GetChildren()
table.sort(children, function(a, b)
	return a.Name < b.Name
end)

local entries: { Entry } = {}
for _, child in children do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			warn(`[Server] Failed to require {child.Name}: {result}`)
		elseif type(result) ~= "table" then
			warn(`[Server] {child.Name} did not return a table`)
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
			warn(`[Server] {entry.Name}:Init() failed: {err}`)
		end
	end
end

local pending = 0
local stillStarting: { [string]: boolean } = {}
for _, entry in entries do
	local start = entry.Module.Start
	if type(start) == "function" then
		pending += 1
		stillStarting[entry.Name] = true
		task.spawn(function()
			local ok, err = xpcall(start, debug.traceback, entry.Module)
			if not ok then
				warn(`[Server] {entry.Name}:Start() failed: {err}`)
			end
			stillStarting[entry.Name] = nil
			pending -= 1
		end)
	end
end

local deadline = os.clock() + START_TIMEOUT
while pending > 0 and os.clock() < deadline do
	task.wait()
end
if pending > 0 then
	local names = {}
	for name in stillStarting do
		table.insert(names, name)
	end
	warn(`[Server] Still starting after {START_TIMEOUT}s: {table.concat(names, ", ")}`)
end

print(`[Server] Booted {#entries} services`)

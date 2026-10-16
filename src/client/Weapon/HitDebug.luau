--!strict
-- Studio-only hit registration debug (toggle F7): shows every hitbox (head red, body yellow,
-- limbs blue) and, per shot, the client's hit point (green) next to the point the server accepted
-- (magenta = accepted the client's claim, orange = server re-cast) for 2 seconds.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HitDebug = {}

local ZONE_COLORS: { [string]: Color3 } = {
	Head = Color3.fromRGB(255, 60, 60),
	Body = Color3.fromRGB(255, 210, 60),
	Limb = Color3.fromRGB(70, 150, 255),
}

local enabled = false
local folder: Folder? = nil
local pending: { [number]: Vector3 } = {}

local function marker(position: Vector3, color: Color3, size: number)
	if not folder then
		return
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.2
	p.Position = position
	p.Parent = folder
	task.delay(2, function()
		p:Destroy()
	end)
end

local function paintHitboxes(show: boolean)
	for _, model in CollectionService:GetTagged("Combatant") do
		local boxes = model:FindFirstChild("Hitboxes")
		if boxes then
			for _, box in boxes:GetChildren() do
				if box:IsA("BasePart") then
					box.Transparency = if show then 0.65 else 1 -- local-only change
					box.Color = ZONE_COLORS[tostring(box:GetAttribute("Zone"))] or Color3.new(1, 1, 1)
				end
			end
		end
	end
end

function HitDebug.Init()
	if not RunService:IsStudio() then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "HitDebug"
	f.Parent = workspace
	folder = f
	task.spawn(function()
		local net = ReplicatedStorage:WaitForChild("CombatNet", 30)
		local remote = net and net:WaitForChild("DebugShot", 10)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(function(shotId: any, serverPos: any, mode: any)
				if not enabled or typeof(serverPos) ~= "Vector3" then
					return
				end
				local color = if mode == "Claim"
					then Color3.fromRGB(255, 60, 255)
					elseif mode == "Recast" then Color3.fromRGB(255, 140, 30)
					else Color3.fromRGB(120, 120, 120)
				marker(serverPos, color, 0.16)
				local clientPos = if type(shotId) == "number" then pending[shotId] else nil
				if clientPos then
					pending[shotId] = nil
					print(
						string.format(
							"[HitDebug] shot %d %s  client->server %.2f studs",
							shotId,
							tostring(mode),
							(clientPos - serverPos).Magnitude
						)
					)
				end
			end)
		end
	end)
	-- new combatants get painted while the view is on
	task.spawn(function()
		while true do
			task.wait(0.5)
			if enabled then
				paintHitboxes(true)
			end
		end
	end)
end

function HitDebug.Enabled(): boolean
	return enabled
end

function HitDebug.Toggle()
	if not folder then
		return
	end
	enabled = not enabled
	paintHitboxes(enabled)
	print(
		"[HitDebug] "
			.. (if enabled then "ON" else "OFF")
			.. " (green = client, magenta = server accepted claim, orange = server re-cast)"
	)
end

-- Called for every own shot with the client's predicted hit point.
function HitDebug.ClientShot(shotId: number, position: Vector3)
	if not enabled then
		return
	end
	pending[shotId] = position
	marker(position, Color3.fromRGB(60, 255, 90), 0.22)
	task.delay(3, function()
		pending[shotId] = nil
	end)
end

return HitDebug

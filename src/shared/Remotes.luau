--!strict
-- Single source of truth for every network remote. Payload shapes: docs/TEST_CONTRACT.md.
-- Server: remotes are created on first require. Client: waits for them.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	-- Server -> Client
	"MatchState",
	"ShotFx",
	"HitConfirm",
	"Damaged",
	"KillFeed",
	"ShiftAnnounce",
	"FacilityReport",
	"RespawnTimer",
	"Announce",
	"AmmoSync",
	"LoadoutState",
	"LightState",
	"PingShown", -- (pinger name, team, position) to the pinger's team
	"ElevatorRide", -- (seconds) riding the spawn elevator: fade out / in
	"Scare", -- (kind) a quiet, one-player creepy moment (HorrorController)
	-- Client -> Server
	"ClientReady",
	"Fire",
	"Reload",
	"EquipSlot",
	"ThrowFrag",
	"Melee",
	"SelectLoadout",
	"ThrowSmoke",
	"SetFlashlight",
	"SetAiming",
	"SetSprint",
	"Slide",
	"Ping", -- (position) map / world ping for your team
	"DropFlag", -- drop the flag you carry where you stand (a teammate can pick it up)
	"ScareSeen", -- (scareId) I looked straight at a shared apparition (HorrorService)
	"HorrorTest", -- Studio only: run the next scare kind for me
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local known: { [string]: boolean } = {}
for _, name in EVENTS do
	known[name] = true
end

function Remotes.Get(name: string): RemoteEvent
	assert(known[name], "Unknown remote: " .. name)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes

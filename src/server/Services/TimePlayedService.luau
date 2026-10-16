--!strict
-- Global "most time played" leaderboard. Minutes played are added to an OrderedDataStore (shared by
-- every server) every couple of minutes and when a player leaves; the top 10 is re-read on a timer
-- and published as JSON in ReplicatedStorage.TimePlayedTop for the spawn-room board
-- (LeaderboardController). Skipped quietly where DataStores are unavailable (Studio without API
-- access): the board then says so.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimePlayedService = {}

local FLUSH_SECONDS = 120
local REFRESH_SECONDS = 120
local TOP = 10

local store: OrderedDataStore? = nil
local pending: { [Player]: number } = {} -- seconds not yet saved
local lastTick = os.clock()
local names: { [number]: string } = {}
local published: StringValue

local function key(userId: number): string
	return "u_" .. userId
end

local function tickTime()
	local now = os.clock()
	local dt = now - lastTick
	lastTick = now
	for _, p in Players:GetPlayers() do
		pending[p] = (pending[p] or 0) + dt
	end
end

local function flush(player: Player)
	local seconds = pending[player] or 0
	local minutes = math.floor(seconds / 60)
	if not store or minutes <= 0 or player.UserId <= 0 then
		return
	end
	local ok, err = pcall(function()
		(store :: OrderedDataStore):IncrementAsync(key(player.UserId), minutes)
	end)
	if ok then
		pending[player] = seconds - minutes * 60
	else
		warn("[TimePlayed] save failed:", err)
	end
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else "Player"
	names[userId] = result
	return result
end

local function refresh()
	if not store then
		published.Value = HttpService:JSONEncode({ Unavailable = true })
		return
	end
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, TOP)
	end)
	if not ok or not pages then
		published.Value = HttpService:JSONEncode({ Unavailable = true })
		return
	end
	local rows = {}
	for _, entry in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(string.match(entry.key, "^u_(%d+)$"))
		if userId then
			table.insert(rows, { UserId = userId, Name = nameOf(userId), Minutes = entry.value })
		end
	end
	published.Value = HttpService:JSONEncode({ Rows = rows })
end

function TimePlayedService:Init()
	published = Instance.new("StringValue")
	published.Name = "TimePlayedTop"
	published.Value = HttpService:JSONEncode({ Rows = {} })
	published.Parent = ReplicatedStorage
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore("TimePlayed_v1")
	end)
	store = if ok then result else nil
end

function TimePlayedService:Start()
	Players.PlayerRemoving:Connect(function(player)
		tickTime()
		flush(player)
		pending[player] = nil
	end)
	game:BindToClose(function()
		tickTime()
		for _, p in Players:GetPlayers() do
			flush(p)
		end
	end)
	task.spawn(function()
		refresh()
		local sinceRefresh = 0
		while true do
			task.wait(FLUSH_SECONDS)
			tickTime()
			for _, p in Players:GetPlayers() do
				flush(p)
			end
			sinceRefresh += FLUSH_SECONDS
			if sinceRefresh >= REFRESH_SECONDS then
				sinceRefresh = 0
				refresh()
			end
		end
	end)
end

return TimePlayedService

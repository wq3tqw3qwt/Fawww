--!strict
--[[
	DataService (L1): ProfileStore sessions, migrations, batched replication and shutdown handling.

	Store choice: ProfileStore already falls back to an in-memory store when DataStores are not
	reachable. We make the choice explicit: in Studio, once ProfileStore reports that DataStore
	access is not "Access", sessions use ProfileStore.Mock so local playtests never block or
	spam errors. Live servers always use the real store.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataTemplate = require(ReplicatedStorage.Shared.DataTemplate)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Migrations = require(ReplicatedStorage.Shared.Migrations)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local Server = script.Parent.Parent.Server
local Guard = require(Server.Guard)
local Remote = require(Server.Remote)
local Retry = require(Server.Retry)
local RuntimeState = require(Server.RuntimeState)

local ProfileStore = require(script.Parent.Parent.ServerPackages.ProfileStore)
local AntiExploitService = require(script.Parent.AntiExploitService)

type Session = {
	Profile: any,
	Data: Types.PlayerData,
	Loaded: boolean,
	Released: boolean,
	Ended: boolean,
	ReleasingFired: boolean,
	Maid: Maid.Maid,
	PlayClock: number,
}

local DataService = {
	Loaded = Signal.new() :: Signal.Signal<Player, Types.PlayerData>,
	Releasing = Signal.new() :: Signal.Signal<Player, Types.PlayerData>,
	MessageReceived = Signal.new() :: Signal.Signal<Player, any>,
}

local sessions: { [Player]: Session } = {}
local dirty: { [Player]: { [string]: boolean } } = {}

local baseStore: any = ProfileStore.New(Config.Data.ProfileStoreName, DataTemplate.Template() :: any)
local activeStore: any = nil

local function awaitStore(): any
	while activeStore == nil do
		task.wait(0.1)
	end
	return activeStore
end

local function resolveStore()
	local deadline = os.clock() + Config.Data.WaitForTimeoutSeconds
	while ProfileStore.DataStoreState == "NotReady" and os.clock() < deadline do
		task.wait(0.1)
	end
	if RunService:IsStudio() and ProfileStore.DataStoreState ~= "Access" then
		activeStore = baseStore.Mock
		print("[DataService] Studio without DataStore access: using ProfileStore.Mock (progress is not saved)")
	else
		activeStore = baseStore
	end
end

local function profileKey(userId: number): string
	return "Player_" .. tostring(userId)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function DataService.Get(player: Player): Types.PlayerData?
	local session = sessions[player]
	return if session then session.Data else nil
end

function DataService.IsLoaded(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Loaded
end

function DataService.WaitFor(player: Player, timeout: number?): Types.PlayerData?
	local deadline = os.clock() + (timeout or Config.Data.WaitForTimeoutSeconds)
	while player.Parent == Players and os.clock() < deadline do
		local session = sessions[player]
		if session and session.Loaded then
			return session.Data
		end
		task.wait(0.1)
	end
	return nil
end

function DataService.GetProfile(player: Player): any?
	local session = sessions[player]
	return if session then session.Profile else nil
end

function DataService.GetLoadedPlayers(): { Player }
	local list: { Player } = {}
	for player, session in sessions do
		if session.Loaded and not session.Ended then
			table.insert(list, player)
		end
	end
	return list
end

-- Queues a top-level key for the next DataPatch flush.
function DataService.MarkDirty(player: Player, key: string)
	if not sessions[player] then
		return
	end
	local set = dirty[player]
	if not set then
		set = {}
		dirty[player] = set
	end
	set[key] = true
end

function DataService.SendSnapshot(player: Player)
	local session = sessions[player]
	if session then
		dirty[player] = nil
		Remote.Fire("DataSync", player, session.Data)
	end
end

-- Delivers a message to a (possibly offline) player's profile. Returns true when queued.
function DataService.MessageUserAsync(userId: number, message: { [string]: any }): boolean
	local store = awaitStore()
	local ok, result = Retry.Call("ProfileMessage", function()
		return store:MessageAsync(profileKey(userId), message)
	end)
	return ok and result == true
end

--------------------------------------------------------------------------------
-- Session lifecycle
--------------------------------------------------------------------------------
local function fireReleasing(player: Player, session: Session)
	if session.ReleasingFired then
		return
	end
	session.ReleasingFired = true
	DataService.Releasing:Fire(player, session.Data)
end

local function releasePlayer(player: Player)
	dirty[player] = nil
	local session = sessions[player]
	if session then
		fireReleasing(player, session)
		session.Released = true
		session.Maid:Clean()
		sessions[player] = nil
		session.Profile:EndSession()
	end
	RuntimeState.Clear(player)
end

local function loadPlayer(player: Player)
	local banned, reason = AntiExploitService.IsBannedAsync(player.UserId)
	if banned then
		player:Kick("You are banned: " .. (reason or "Banned"))
		return
	end

	local store = awaitStore()
	local ok, profile = pcall(function()
		return store:StartSessionAsync(profileKey(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end)
	if not ok then
		warn(string.format("[DataService] StartSessionAsync failed for %s: %s", player.Name, tostring(profile)))
		if player.Parent == Players then
			player:Kick("We couldn't load your factory. Please rejoin in a minute.")
		end
		return
	end
	if profile == nil then
		if player.Parent == Players then
			player:Kick("Your factory is busy on another server. Please rejoin in a minute.")
		end
		return
	end
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	local migrated, migrateError = pcall(Migrations.Migrate, profile.Data)
	if not migrated then
		warn(string.format("[DataService] migration failed for %s: %s", player.Name, tostring(migrateError)))
		profile:EndSession()
		player:Kick("Your save needs attention. Please contact support.")
		return
	end

	local session: Session = {
		Profile = profile,
		Data = profile.Data,
		Loaded = false,
		Released = false,
		Ended = false,
		ReleasingFired = false,
		Maid = Maid.new(),
		PlayClock = 0,
	}
	sessions[player] = session

	profile.OnSessionEnd:Connect(function()
		session.Ended = true
		if sessions[player] == session then
			sessions[player] = nil
		end
		if not session.Released and player.Parent == Players and not ProfileStore.IsClosing then
			player:Kick("Your factory was opened on another server. Please rejoin.")
		end
	end)
	-- Fires right before the final save on every path (leave, shutdown, steal).
	profile.OnLastSave:Connect(function()
		fireReleasing(player, session)
	end)
	profile:MessageHandler(function(message: any, processed: () -> ())
		DataService.MessageReceived:Fire(player, message)
		processed()
	end)

	DataService.Loaded:Fire(player, session.Data)
	if sessions[player] ~= session then
		return
	end
	session.Loaded = true
	DataService.SendSnapshot(player)
end

local function flushDirty()
	for player, set in dirty do
		local session = sessions[player]
		if session and session.Loaded then
			for key in set do
				Remote.Fire("DataPatch", player, key, (session.Data :: any)[key])
			end
			dirty[player] = nil
		end
	end
end

local function trackPlaySeconds(elapsed: number)
	for _, session in sessions do
		if session.Loaded then
			session.PlayClock += elapsed
			if session.PlayClock >= 1 then
				local whole = math.floor(session.PlayClock)
				session.PlayClock -= whole
				session.Data.Stats.PlaySeconds += whole
			end
		end
	end
end

function DataService.Init()
	-- Late-connecting clients ask for the full mirror instead of relying on the one-shot DataSync.
	Remote.Handle("RequestSnapshot", function(player: Player): (boolean, string?, any?)
		if not DataService.IsLoaded(player) then
			return false, "Not loaded"
		end
		DataService.SendSnapshot(player)
		return true
	end, { AllowBeforeLoad = true })

	Remote.Handle("SetSetting", function(player: Player, key: any, value: any)
		local data = DataService.Get(player)
		if not data then
			return false, "Not loaded"
		end
		local settingKey = Guard.Key(key, data.Settings :: { [string]: boolean })
		local flag = Guard.Boolean(value)
		if settingKey == nil or flag == nil then
			return false, "Invalid setting"
		end
		data.Settings[settingKey :: "Music"] = flag
		DataService.MarkDirty(player, "Settings")
		return true
	end)
end

function DataService.Start()
	task.spawn(resolveStore)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(loadPlayer, player)
	end)
	Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Data.ReplicationFlushSeconds)
			local now = os.clock()
			local ok, err = pcall(function()
				trackPlaySeconds(now - last)
				flushDirty()
			end)
			last = now
			if not ok then
				warn("[DataService] flush failed: " .. tostring(err))
			end
		end
	end)

	game:BindToClose(function()
		local remaining: { Player } = {}
		for player in sessions do
			table.insert(remaining, player)
		end
		for _, player in remaining do
			releasePlayer(player)
		end
	end)
end

return DataService

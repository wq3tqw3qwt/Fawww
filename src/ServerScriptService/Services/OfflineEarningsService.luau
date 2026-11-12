--!strict
--[[
	OfflineEarningsService (L5): credits income for time away (capped, reduced efficiency),
	claimable once per return, with an optional "double" granted through an ad or product.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Types = require(ReplicatedStorage.Shared.Types)

local Server = script.Parent.Parent.Server
local Remote = require(Server.Remote)
local RuntimeState = require(Server.RuntimeState)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local MultiplierService = require(script.Parent.MultiplierService)

local OfflineEarningsService = {}

-- Amount claimed this session; Double() pays it a second time.
local lastClaimed: { [Player]: number } = {}

local function onLoaded(player: Player, data: Types.PlayerData)
	local offline = data.Offline
	local now = os.time()
	local lastSeen = offline.LastSeenUnix
	-- Moving LastSeen forward now prevents double credit if this server crashes before release.
	offline.LastSeenUnix = now
	if lastSeen <= 0 then
		return
	end
	local cash, seconds = Formulas.OfflineEarnings(
		now - lastSeen,
		offline.LastIncome,
		MultiplierService.GetOfflineCapHours(player),
		MultiplierService.GetOfflineEfficiency(player)
	)
	if cash <= 0 then
		return
	end
	offline.PendingCash = Formulas.Clamp(offline.PendingCash + cash)
	offline.PendingSeconds += seconds
	offline.DoubleAvailable = Config.Offline.DoubleWithAd
	RuntimeState.Get(player).PendingOfflineCash = offline.PendingCash
	DataService.MarkDirty(player, "Offline")
	Remote.Fire("Effect", player, "Offline", { Cash = offline.PendingCash, Seconds = offline.PendingSeconds })
end

local function checkpoint(player: Player, data: Types.PlayerData)
	data.Offline.LastSeenUnix = os.time()
	local income = RuntimeState.Get(player).IncomePerSecond
	if income > 0 then
		data.Offline.LastIncome = income
	end
end

local function handleClaim(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	local amount = data.Offline.PendingCash
	if amount <= 0 then
		return false, "Nothing to claim"
	end
	data.Offline.PendingCash = 0
	data.Offline.PendingSeconds = 0
	RuntimeState.Get(player).PendingOfflineCash = 0
	DataService.MarkDirty(player, "Offline")
	CurrencyService.AddCash(player, amount, "Offline", false)
	lastClaimed[player] = amount
	return true, nil, { Cash = amount, DoubleAvailable = data.Offline.DoubleAvailable }
end

-- Pays the last claimed amount again (or doubles an unclaimed pending amount). Once per return.
function OfflineEarningsService.Double(player: Player): boolean
	local data = DataService.Get(player)
	if not data or not data.Offline.DoubleAvailable then
		return false
	end
	local claimed = lastClaimed[player]
	if claimed and claimed > 0 then
		CurrencyService.AddCash(player, claimed, "OfflineDouble", false)
		lastClaimed[player] = nil
	elseif data.Offline.PendingCash > 0 then
		data.Offline.PendingCash = Formulas.Clamp(data.Offline.PendingCash * 2)
		RuntimeState.Get(player).PendingOfflineCash = data.Offline.PendingCash
	else
		return false
	end
	data.Offline.DoubleAvailable = false
	DataService.MarkDirty(player, "Offline")
	return true
end

function OfflineEarningsService.Init()
	Remote.Handle("ClaimOffline", handleClaim)
end

function OfflineEarningsService.Start()
	DataService.Loaded:Connect(onLoaded)
	for _, player in DataService.GetLoadedPlayers() do
		local data = DataService.Get(player)
		if data then
			onLoaded(player, data)
		end
	end
	DataService.Releasing:Connect(function(player: Player, data: Types.PlayerData)
		checkpoint(player, data)
		lastClaimed[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Offline.CheckpointSeconds)
			for _, player in DataService.GetLoadedPlayers() do
				local data = DataService.Get(player)
				if data and player.Parent == Players then
					checkpoint(player, data)
				end
			end
		end
	end)
end

return OfflineEarningsService

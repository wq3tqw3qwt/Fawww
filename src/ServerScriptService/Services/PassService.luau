--!strict
--[[
	PassService (L2): game pass ownership. Verified with UserOwnsGamePassAsync on join (cached in
	Data.Passes for the session) and updated live by PromptGamePassPurchaseFinished.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Grants = require(script.Parent.Parent.Server.Grants)
local Retry = require(script.Parent.Parent.Server.Retry)
local ServerSignals = require(script.Parent.Parent.Server.ServerSignals)
local DataService = require(script.Parent.DataService)

local PassService = {}

function PassService.Owns(player: Player, passKey: string): boolean
	local data = DataService.Get(player)
	return data ~= nil and data.Passes[passKey] == true
end

function PassService.IsPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

local function grantVipMachine(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for _, item in data.Machines.Inventory do
		if item.Id == Config.PassEffects.VIPMachineId then
			return
		end
	end
	Grants.GrantMachine(player, Config.PassEffects.VIPMachineId, "Pass:VIP")
end

local function markOwned(player: Player, passKey: string)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local isNew = data.Passes[passKey] ~= true
	data.Passes[passKey] = true
	if isNew then
		DataService.MarkDirty(player, "Passes")
	end
	if passKey == "VIP" then
		grantVipMachine(player)
	end
	if isNew then
		ServerSignals.PassOwned:Fire(player, passKey)
		ServerSignals.MultipliersDirty:Fire(player)
	end
end

function PassService.Refresh(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for passKey, def in Config.GamePasses do
		if def.Id ~= 0 then
			local ok, owns = Retry.Call("UserOwnsGamePass:" .. passKey, function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
			end)
			if player.Parent ~= Players or DataService.Get(player) ~= data then
				return
			end
			if ok and owns == true then
				markOwned(player, passKey)
			elseif ok and data.Passes[passKey] == true then
				-- Verified as not owned (e.g. refunded): drop the stale cache.
				data.Passes[passKey] = nil
				DataService.MarkDirty(player, "Passes")
				ServerSignals.MultipliersDirty:Fire(player)
			end
		end
	end
end

function PassService.Init() end

function PassService.Start()
	DataService.Loaded:Connect(function(player: Player)
		task.spawn(PassService.Refresh, player)
	end)
	for _, player in DataService.GetLoadedPlayers() do
		task.spawn(PassService.Refresh, player)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			for passKey, def in Config.GamePasses do
				if def.Id ~= 0 and def.Id == passId then
					markOwned(player, passKey)
				end
			end
		end
	)
end

return PassService

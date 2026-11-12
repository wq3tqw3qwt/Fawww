--!strict
--[[
	ExpansionService (L5): Expansion (run prestige) and Franchise (endgame prestige layer).
	Shares always derive from FranchiseEarnings, so Expansions never lose permanent power.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local Server = script.Parent.Parent.Server
local Grants = require(Server.Grants)
local Remote = require(Server.Remote)
local ServerSignals = require(Server.ServerSignals)
local DataService = require(script.Parent.DataService)
local FactoryService = require(script.Parent.FactoryService)
local StatsService = require(script.Parent.StatsService)

local ExpansionService = {}

local function handleExpand(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	if not Formulas.CanExpand(data.Expansions, data.RunEarnings) then
		return false, "Earn more this run before expanding"
	end
	data.Expansions += 1
	-- BonusShares (Investor product) is stored separately and added by MultiplierService.
	data.Shares = Formulas.SharesTotal(data.FranchiseEarnings)
	DataService.MarkDirty(player, "Expansions")
	DataService.MarkDirty(player, "Shares")
	StatsService.Increment(player, "Expanded", 1)
	FactoryService.ResetRun(player)
	ServerSignals.Expanded:Fire(player, data.Expansions)
	ServerSignals.MultipliersDirty:Fire(player)
	local mult = Formulas.SharesMultiplier(data.Shares + data.BonusShares)
	Remote.Fire("Effect", player, "Expansion", { Count = data.Expansions, Shares = data.Shares, Mult = mult })
	return true, nil, { Count = data.Expansions, Shares = data.Shares }
end

local function handleFranchise(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	if not Formulas.CanFranchise(data.Expansions) then
		return false, "Reach more Expansions before franchising"
	end
	data.Franchise += 1
	data.Expansions = 0
	data.Shares = 0
	data.FranchiseEarnings = 0
	for _, key in { "Franchise", "Expansions", "Shares", "FranchiseEarnings" } do
		DataService.MarkDirty(player, key)
	end
	Grants.GrantCredits(player, Config.Franchise.CreditsPerLevel * data.Franchise, "Franchise")
	local title = string.format("%s %d", Config.Franchise.TitlePrefix, data.Franchise)
	Grants.GrantTitle(player, title)
	data.Social.Title = title
	DataService.MarkDirty(player, "Social")
	FactoryService.ResetRun(player)
	ServerSignals.Franchised:Fire(player, data.Franchise)
	ServerSignals.MultipliersDirty:Fire(player)
	Remote.Fire("Effect", player, "Franchise", { Level = data.Franchise })
	return true, nil, { Level = data.Franchise }
end

function ExpansionService.Init()
	Remote.Handle("Expand", handleExpand)
	Remote.Handle("Franchise", handleFranchise)
end

function ExpansionService.Start() end

return ExpansionService

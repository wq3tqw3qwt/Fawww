--!strict
--[[
	MultiplierService (L3): builds every income/ability modifier for a player once and caches it.
	Recomputed lazily after MultipliersDirty/PassOwned and on a fixed cadence (boost and event expiry).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Types = require(ReplicatedStorage.Shared.Types)

local Grants = require(script.Parent.Parent.Server.Grants)
local ServerSignals = require(script.Parent.Parent.Server.ServerSignals)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PassService = require(script.Parent.PassService)
local SocialBonusService = require(script.Parent.SocialBonusService)

type Cache = {
	Parts: Formulas.MultiplierParts,
	Mult: number,
	Abilities: { [string]: number },
	Discount: number,
	ProductionMult: number,
	OfflineEfficiency: number,
	OfflineCapHours: number,
	VaultBonus: number,
	OverdriveSeconds: number,
	Research: { [string]: number },
}

local MultiplierService = {}

local caches: { [Player]: Cache } = {}
local stale: { [Player]: boolean } = {}

-- Sum of ValuePerLevel * level per research Effect.
local function researchTotals(data: Types.PlayerData): { [string]: number }
	local totals: { [string]: number } = {}
	for _, def in Config.Research do
		local level = data.Research.Levels[def.Id] or 0
		if level > 0 then
			totals[def.Effect] = (totals[def.Effect] or 0) + math.min(level, def.MaxLevel) * def.ValuePerLevel
		end
	end
	return totals
end

local function compute(player: Player, data: Types.PlayerData): Cache
	local equipped: { Formulas.EquippedMachine } = {}
	for _, uid in data.Machines.Bays do
		local item = if uid ~= "" then data.Machines.Inventory[uid] else nil
		if item then
			table.insert(equipped, { Id = item.Id, Grade = item.Grade })
		end
	end
	local power, abilities = Formulas.MachineTotals(equipped, EventService.IsRushActive())
	local research = researchTotals(data)

	local parts: Formulas.MultiplierParts = {
		Shares = data.Shares + data.BonusShares,
		MachinePowerPct = power,
		CatalogBonus = Formulas.CatalogBonus(data.Catalog.Stamps),
		ResearchIncome = research.IncomeMult or 0,
		OperatorCount = SocialBonusService.GetOperatorCount(player),
		TeamworkBonus = if SocialBonusService.GetTeamworkActive(player) then (abilities.Teamwork or 0) else 0,
		Premium = PassService.IsPremium(player),
		InGroup = SocialBonusService.IsInGroup(player),
		VIP = PassService.Owns(player, "VIP"),
		Cash2xPass = PassService.Owns(player, "Cash2x"),
		BoostMult = Grants.BoostMult(data),
		WeekendActive = EventService.IsWeekend(),
		FranchiseLevel = data.Franchise,
		CashBurst = abilities.CashBurst or 0,
	}

	return {
		Parts = parts,
		Mult = Formulas.IncomeMultiplier(parts),
		Abilities = abilities,
		Discount = (abilities.Bargain or 0) + (research.UpgradeDiscount or 0),
		ProductionMult = if PassService.Owns(player, "TurboConveyors")
			then Config.PassEffects.TurboConveyorsMult
			else 1,
		OfflineEfficiency = Config.Offline.Efficiency + (abilities.NightShift or 0),
		OfflineCapHours = Formulas.OfflineCapHours(research.OfflineHours or 0, PassService.Owns(player, "OfflineX2")),
		VaultBonus = abilities.BigVault or 0,
		OverdriveSeconds = Config.Overdrive.DurationSeconds + (abilities.OverdrivePlus or 0),
		Research = research,
	}
end

local function ensure(player: Player): Cache?
	local cache = caches[player]
	if cache and not stale[player] then
		return cache
	end
	local data = DataService.Get(player)
	if not data then
		return cache
	end
	local ok, result = pcall(compute, player, data)
	if not ok then
		warn("[MultiplierService] compute failed: " .. tostring(result))
		return cache
	end
	caches[player] = result
	stale[player] = nil
	return result
end

function MultiplierService.Invalidate(player: Player)
	stale[player] = true
end

function MultiplierService.Get(player: Player): number
	local cache = ensure(player)
	return if cache then cache.Mult else 1
end

function MultiplierService.GetParts(player: Player): Formulas.MultiplierParts
	local cache = ensure(player)
	if cache then
		return cache.Parts
	end
	return {
		Shares = 0,
		MachinePowerPct = 0,
		CatalogBonus = 0,
		ResearchIncome = 0,
		OperatorCount = 0,
		TeamworkBonus = 0,
		Premium = false,
		InGroup = false,
		VIP = false,
		Cash2xPass = false,
		BoostMult = 1,
		WeekendActive = false,
		FranchiseLevel = 0,
		CashBurst = 0,
	}
end

function MultiplierService.GetAbilities(player: Player): { [string]: number }
	local cache = ensure(player)
	return if cache then cache.Abilities else {}
end

function MultiplierService.GetUpgradeDiscount(player: Player): number
	local cache = ensure(player)
	return if cache then cache.Discount else 0
end

-- Turbo Conveyors pass.
function MultiplierService.GetProductionMult(player: Player): number
	local cache = ensure(player)
	return if cache then cache.ProductionMult else 1
end

function MultiplierService.GetOfflineEfficiency(player: Player): number
	local cache = ensure(player)
	return if cache then cache.OfflineEfficiency else Config.Offline.Efficiency
end

function MultiplierService.GetOfflineCapHours(player: Player): number
	local cache = ensure(player)
	return if cache then cache.OfflineCapHours else Config.Offline.BaseCapHours
end

function MultiplierService.GetVaultBonus(player: Player): number
	local cache = ensure(player)
	return if cache then cache.VaultBonus else 0
end

function MultiplierService.GetOverdriveSeconds(player: Player): number
	local cache = ensure(player)
	return if cache then cache.OverdriveSeconds else Config.Overdrive.DurationSeconds
end

-- Extra (not in the contract): summed research value for an Effect ("ExtraBay", "ContractReward"...).
function MultiplierService.GetResearchValue(player: Player, effect: string): number
	local cache = ensure(player)
	return if cache then (cache.Research[effect] or 0) else 0
end

function MultiplierService.Init() end

function MultiplierService.Start()
	ServerSignals.MultipliersDirty:Connect(MultiplierService.Invalidate)
	ServerSignals.PassOwned:Connect(function(player: Player)
		MultiplierService.Invalidate(player)
	end)
	DataService.Loaded:Connect(MultiplierService.Invalidate)
	Players.PlayerRemoving:Connect(function(player: Player)
		caches[player] = nil
		stale[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Data.MultiplierRefreshSeconds)
			for _, player in Players:GetPlayers() do
				stale[player] = true
			end
		end
	end)
end

return MultiplierService

--!strict
--[[
	CurrencyService (L2): the only writer of Cash, Credits and Vault. All amounts are
	validated here so no caller can create NaN/negative balances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local ServerSignals = require(script.Parent.Parent.Server.ServerSignals)
local DataService = require(script.Parent.DataService)

local CurrencyService = {}

local function validAmount(amount: number): boolean
	return type(amount) == "number" and amount == amount and amount >= 0 and amount < math.huge
end

function CurrencyService.GetCash(player: Player): number
	local data = DataService.Get(player)
	return if data then data.Cash else 0
end

function CurrencyService.GetCredits(player: Player): number
	local data = DataService.Get(player)
	return if data then data.Credits else 0
end

function CurrencyService.AddCash(player: Player, amount: number, source: string, countsAsEarnings: boolean?)
	local data = DataService.Get(player)
	if not data or not validAmount(amount) or amount == 0 then
		return
	end
	data.Cash = Formulas.Clamp(data.Cash + amount)
	DataService.MarkDirty(player, "Cash")
	if countsAsEarnings ~= false then
		local weekKey = Formulas.WeekKey(os.time())
		if data.WeeklyKey ~= weekKey then
			data.WeeklyKey = weekKey
			data.WeeklyEarnings = 0
		end
		data.RunEarnings = Formulas.Clamp(data.RunEarnings + amount)
		data.FranchiseEarnings = Formulas.Clamp(data.FranchiseEarnings + amount)
		data.TotalEarnings = Formulas.Clamp(data.TotalEarnings + amount)
		data.WeeklyEarnings = Formulas.Clamp(data.WeeklyEarnings + amount)
		DataService.MarkDirty(player, "RunEarnings")
		DataService.MarkDirty(player, "FranchiseEarnings")
		DataService.MarkDirty(player, "TotalEarnings")
		DataService.MarkDirty(player, "WeeklyEarnings")
		DataService.MarkDirty(player, "WeeklyKey")
		ServerSignals.CashEarned:Fire(player, amount, source)
	end
end

function CurrencyService.SpendCash(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or not validAmount(amount) or data.Cash < amount then
		return false
	end
	if amount > 0 then
		data.Cash -= amount
		DataService.MarkDirty(player, "Cash")
	end
	return true
end

function CurrencyService.AddCredits(player: Player, amount: number, _source: string)
	local data = DataService.Get(player)
	if not data or not validAmount(amount) or amount == 0 then
		return
	end
	data.Credits = Formulas.Clamp(data.Credits + amount)
	DataService.MarkDirty(player, "Credits")
end

function CurrencyService.SpendCredits(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or not validAmount(amount) or data.Credits < amount then
		return false
	end
	if amount > 0 then
		data.Credits -= amount
		DataService.MarkDirty(player, "Credits")
	end
	return true
end

-- Adds production to the vault up to `capacity`; returns the amount actually stored.
function CurrencyService.DepositVault(player: Player, amount: number, capacity: number): number
	local data = DataService.Get(player)
	if not data or not validAmount(amount) or not validAmount(capacity) then
		return 0
	end
	local stored = math.min(amount, math.max(0, capacity - data.Vault))
	if stored > 0 then
		data.Vault = Formulas.Clamp(data.Vault + stored)
		DataService.MarkDirty(player, "Vault")
	end
	return stored
end

-- Moves the vault into the wallet (counts as earnings); returns the amount collected.
function CurrencyService.CollectVault(player: Player): number
	local data = DataService.Get(player)
	if not data or data.Vault <= 0 then
		return 0
	end
	local amount = data.Vault
	data.Vault = 0
	DataService.MarkDirty(player, "Vault")
	CurrencyService.AddCash(player, amount, "Vault", true)
	return amount
end

function CurrencyService.Init() end

function CurrencyService.Start() end

return CurrencyService

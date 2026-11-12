--!strict
--[[
	Grants: the single path for handing out machines, boosts, income, credits and titles.
	Used by shop products, rewards, codes and the tutorial so inventory limits and
	announcements behave identically everywhere.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Types = require(ReplicatedStorage.Shared.Types)

local Remote = require(script.Parent.Remote)
local RuntimeState = require(script.Parent.RuntimeState)
local ServerSignals = require(script.Parent.ServerSignals)
local CurrencyService = require(script.Parent.Parent.Services.CurrencyService)
local DataService = require(script.Parent.Parent.Services.DataService)

local Grants = {}

local MIN_INCOME_PER_SECOND = 1

local function inventoryCount(data: Types.PlayerData): number
	local count = 0
	for _ in data.Machines.Inventory do
		count += 1
	end
	return count
end

-- Returns the new item uid, or nil when the machine id is unknown or the inventory is full.
function Grants.GrantMachine(player: Player, id: string, source: string, grade: number?): string?
	local data = DataService.Get(player)
	local def = Formulas.GetMachine(id)
	if not data or not def then
		return nil
	end
	if inventoryCount(data) >= Config.MachineGrades.InventoryLimit then
		Remote.Notify(player, "Error", "Machine inventory is full - merge or trade some machines.")
		return nil
	end
	local uid = HttpService:GenerateGUID(false)
	data.Machines.Inventory[uid] = {
		Id = id,
		Grade = math.clamp(grade or 0, 0, #Config.MachineGrades.Names - 1),
		Locked = false,
		At = os.time(),
	}
	DataService.MarkDirty(player, "Machines")
	ServerSignals.MachineGranted:Fire(player, id, source)
	Remote.Fire("Effect", player, "MachineGranted", { Id = id, Rarity = def.Rarity })
	Remote.Notify(player, "Reward", string.format("New machine: %s (%s)", def.Name, def.Rarity))
	if table.find(Config.Events.AnnounceRarities, def.Rarity) then
		local color = Config.Rarities.Colors[def.Rarity] or Config.Rarities.Colors.Special
		Remote.FireAll("Announce", string.format("%s found a %s %s!", player.DisplayName, def.Rarity, def.Name), color)
	end
	return uid
end

function Grants.IsBoostActive(data: Types.PlayerData, key: string): boolean
	local expiry = data.Boosts[key]
	return expiry ~= nil and expiry > os.time()
end

-- Product of IncomeMult over every active boost.
function Grants.BoostMult(data: Types.PlayerData): number
	local mult = 1
	for key, def in Config.Boosts do
		if Grants.IsBoostActive(data, key) then
			mult *= def.IncomeMult
		end
	end
	return mult
end

-- Adds time to a boost (stacks onto the remaining duration).
function Grants.GrantBoost(player: Player, key: string, minutes: number)
	local data = DataService.Get(player)
	if not data or Config.Boosts[key] == nil or minutes <= 0 then
		return
	end
	local start = math.max(os.time(), data.Boosts[key] or 0)
	data.Boosts[key] = start + math.floor(minutes * 60)
	DataService.MarkDirty(player, "Boosts")
	ServerSignals.MultipliersDirty:Fire(player)
	Remote.Notify(player, "Reward", string.format("%s boost active!", Config.Boosts[key].Name))
end

-- Grants `minutes` of the player's current income. Purchased/rewarded cash does not count
-- toward Expansion progress, so it cannot be used to skip a run.
function Grants.GrantIncomeMinutes(player: Player, minutes: number, source: string): number
	local income = math.max(RuntimeState.Get(player).IncomePerSecond, MIN_INCOME_PER_SECOND)
	local amount = income * minutes * 60
	CurrencyService.AddCash(player, amount, source, false)
	return amount
end

function Grants.GrantCredits(player: Player, amount: number, source: string)
	CurrencyService.AddCredits(player, amount, source)
end

function Grants.GrantTitle(player: Player, title: string)
	local data = DataService.Get(player)
	if not data or title == "" or data.Social.Titles[title] then
		return
	end
	data.Social.Titles[title] = true
	DataService.MarkDirty(player, "Social")
	Remote.Notify(player, "Reward", "New title unlocked: " .. title)
end

return Grants

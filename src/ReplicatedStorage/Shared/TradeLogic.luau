--!strict
--[[
	TradeLogic: pure validation and atomic execution of a two-sided machine trade.
	TradeService owns sessions, confirmation and persistence; this module guarantees that a
	swap either fully happens or does not happen, and that no uid can be duplicated.
]]

local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Types = require(script.Parent.Types)

local TradeLogic = {}

type Inventory = { [string]: Types.MachineItem }

-- Uids that cannot leave the inventory (equipped bays).
function TradeLogic.EquippedSet(bays: { string }): { [string]: boolean }
	local set = {}
	for _, uid in bays do
		if uid ~= "" then
			set[uid] = true
		end
	end
	return set
end

function TradeLogic.ValidateOffer(inventory: Inventory, equipped: { [string]: boolean }, offer: any): (boolean, string?)
	if type(offer) ~= "table" then
		return false, "Offer must be a list"
	end
	local count = 0
	local seen: { [string]: boolean } = {}
	for key, uid in offer do
		count += 1
		if type(key) ~= "number" or key ~= count then
			return false, "Offer must be a list"
		end
		if type(uid) ~= "string" or #uid > 64 then
			return false, "Invalid item"
		end
		if seen[uid] then
			return false, "Duplicate item"
		end
		seen[uid] = true
		local item = inventory[uid]
		if not item then
			return false, "You no longer own that machine"
		end
		local def = Formulas.GetMachine(item.Id)
		if not def or not def.Tradable then
			return false, "That machine cannot be traded"
		end
		if item.Locked then
			return false, "Unlock the machine first"
		end
		if equipped[uid] then
			return false, "Unequip the machine first"
		end
	end
	if count > Config.Trade.MaxItemsPerSide then
		return false, "Too many items"
	end
	return true, nil
end

function TradeLogic.OfferPower(inventory: Inventory, offer: { string }): number
	local total = 0
	for _, uid in offer do
		local item = inventory[uid]
		local def = if item then Formulas.GetMachine(item.Id) else nil
		if item and def then
			total += Formulas.MachinePower(def, item.Grade)
		end
	end
	return total
end

function TradeLogic.IsLopsided(powerA: number, powerB: number): boolean
	local hi, lo = math.max(powerA, powerB), math.min(powerA, powerB)
	if hi <= 0 then
		return false
	end
	return lo <= 0 or hi / lo >= Config.Trade.LopsidedWarnRatio
end

local function countItems(inventory: Inventory): number
	local n = 0
	for _ in inventory do
		n += 1
	end
	return n
end

-- Re-validates both sides and swaps the items. Mutates both inventories only on success.
function TradeLogic.Execute(
	invA: Inventory,
	equippedA: { [string]: boolean },
	offerA: { string },
	invB: Inventory,
	equippedB: { [string]: boolean },
	offerB: { string }
): (boolean, string?)
	local okA, errA = TradeLogic.ValidateOffer(invA, equippedA, offerA)
	if not okA then
		return false, errA
	end
	local okB, errB = TradeLogic.ValidateOffer(invB, equippedB, offerB)
	if not okB then
		return false, errB
	end
	if #offerA == 0 and #offerB == 0 then
		return false, "Nothing to trade"
	end
	-- A uid present in both inventories would indicate a duplication bug; refuse.
	for _, uid in offerA do
		if invB[uid] then
			return false, "Item conflict"
		end
	end
	for _, uid in offerB do
		if invA[uid] then
			return false, "Item conflict"
		end
	end
	local limit = Config.MachineGrades.InventoryLimit
	if countItems(invA) - #offerA + #offerB > limit or countItems(invB) - #offerB + #offerA > limit then
		return false, "Inventory full"
	end

	local movingA: { [string]: Types.MachineItem } = {}
	local movingB: { [string]: Types.MachineItem } = {}
	for _, uid in offerA do
		movingA[uid] = invA[uid]
	end
	for _, uid in offerB do
		movingB[uid] = invB[uid]
	end
	for uid in movingA do
		invA[uid] = nil
	end
	for uid in movingB do
		invB[uid] = nil
	end
	for uid, item in movingA do
		invB[uid] = item
	end
	for uid, item in movingB do
		invA[uid] = item
	end
	return true, nil
end

return TradeLogic

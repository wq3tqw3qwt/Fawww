--!strict
--[[
	MachineService (L5): shop purchases, bays, merging (Chrome / Gold-Plated) and locking.
	Machines are items in Data.Machines.Inventory keyed by uid; Bays hold equipped uids.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent.Server

local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Maid = require(Shared.Maid)
local Types = require(Shared.Types)
local Grants = require(Server.Grants)
local Guard = require(Server.Guard)
local Remote = require(Server.Remote)
local ServerSignals = require(Server.ServerSignals)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)

local MachineService = {}

local grades = Config.MachineGrades
local maid = Maid.new()

local function inventoryCount(data: Types.PlayerData): number
	local n = 0
	for _ in data.Machines.Inventory do
		n += 1
	end
	return n
end

local function equippedSet(data: Types.PlayerData): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, uid in data.Machines.Bays do
		if uid ~= "" then
			set[uid] = true
		end
	end
	return set
end

local function researchBays(data: Types.PlayerData): number
	local total = 0
	for _, def in Config.Research do
		if def.Effect == "ExtraBay" then
			total += (data.Research.Levels[def.Id] or 0) * def.ValuePerLevel
		end
	end
	return total
end

local function targetBayCount(player: Player, data: Types.PlayerData): number
	return Formulas.BaysFor(data.Expansions, PassService.Owns(player, "ExtraBays"), researchBays(data))
end

-- Keeps Bays at BaysFor() entries and drops references to machines that no longer exist.
local function syncBays(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local bays = data.Machines.Bays
	local want = targetBayCount(player, data)
	local changed = false
	while #bays < want do
		table.insert(bays, "")
		changed = true
	end
	while #bays > want do
		table.remove(bays)
		changed = true
	end
	for i, uid in bays do
		if uid ~= "" and data.Machines.Inventory[uid] == nil then
			bays[i] = ""
			changed = true
		end
	end
	if changed then
		DataService.MarkDirty(player, "Machines")
		ServerSignals.MultipliersDirty:Fire(player)
	end
end

local function sortedUids(data: Types.PlayerData, predicate: (string, Types.MachineItem) -> boolean): { string }
	local uids = {}
	for uid, item in data.Machines.Inventory do
		if predicate(uid, item) then
			table.insert(uids, uid)
		end
	end
	local inventory = data.Machines.Inventory
	table.sort(uids, function(a, b)
		local ia, ib = inventory[a], inventory[b]
		if ia.At ~= ib.At then
			return ia.At < ib.At
		end
		return a < b
	end)
	return uids
end

-- Picks `count` identical, unlocked, unequipped copies of `first`'s machine at `grade`, `first` included.
local function pickCopies(data: Types.PlayerData, first: string, grade: number, count: number): { string }?
	local item = data.Machines.Inventory[first]
	if not item or item.Grade ~= grade or item.Locked then
		return nil
	end
	local equipped = equippedSet(data)
	if equipped[first] then
		return nil
	end
	local others = sortedUids(data, function(uid, other)
		return uid ~= first and other.Id == item.Id and other.Grade == grade and not other.Locked and not equipped[uid]
	end)
	if #others < count - 1 then
		return nil
	end
	local picked = { first }
	for i = 1, count - 1 do
		table.insert(picked, others[i])
	end
	return picked
end

local function buyMachine(player: Player, machineId: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local id = Guard.String(machineId, 64)
	if not data or not id then
		return false, "Invalid machine"
	end
	local def = Formulas.GetMachine(id)
	local price = if def then Formulas.MachinePrice(def) else nil
	if not def or not price then
		return false, "That machine isn't for sale"
	end
	if not Formulas.HallUnlocked(def.Hall, data.Expansions) then
		return false, "Unlock this industry first"
	end
	if inventoryCount(data) >= grades.InventoryLimit then
		return false, "Machine inventory is full"
	end
	local paid = if price.Currency == "Cash"
		then CurrencyService.SpendCash(player, price.Amount)
		else CurrencyService.SpendCredits(player, price.Amount)
	if not paid then
		return false, if price.Currency == "Cash" then "Not enough cash" else "Not enough Credits"
	end
	local uid = Grants.GrantMachine(player, id, "Shop")
	if not uid then
		if price.Currency == "Cash" then
			CurrencyService.AddCash(player, price.Amount, "Refund", false)
		else
			CurrencyService.AddCredits(player, price.Amount, "Refund")
		end
		return false, "Could not add the machine"
	end
	return true, nil, { Uid = uid }
end

local function equipMachine(player: Player, uidArg: any, bayArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local uid = Guard.String(uidArg, 64)
	if not data or not uid then
		return false, "Invalid machine"
	end
	local bays = data.Machines.Bays
	local bay = Guard.Integer(bayArg, 1, #bays)
	if not bay then
		return false, "Invalid bay"
	end
	if data.Machines.Inventory[uid] == nil then
		return false, "You don't own that machine"
	end
	for i, other in bays do
		if other == uid then
			if i == bay then
				return true, nil
			end
			return false, "That machine is already equipped in another bay"
		end
	end
	bays[bay] = uid
	DataService.MarkDirty(player, "Machines")
	ServerSignals.MultipliersDirty:Fire(player)
	ServerSignals.TutorialAction:Fire(player, "MachineEquipped")
	return true
end

local function unequipMachine(player: Player, bayArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local bay = Guard.Integer(bayArg, 1, #data.Machines.Bays)
	if not bay then
		return false, "Invalid bay"
	end
	if data.Machines.Bays[bay] ~= "" then
		data.Machines.Bays[bay] = ""
		DataService.MarkDirty(player, "Machines")
		ServerSignals.MultipliersDirty:Fire(player)
	end
	return true
end

-- Removes the picked items and returns them so a failed grant can restore them.
local function consume(data: Types.PlayerData, uids: { string }): { [string]: Types.MachineItem }
	local removed: { [string]: Types.MachineItem } = {}
	for _, uid in uids do
		removed[uid] = data.Machines.Inventory[uid]
		data.Machines.Inventory[uid] = nil
	end
	return removed
end

local function restore(data: Types.PlayerData, removed: { [string]: Types.MachineItem })
	for uid, item in removed do
		data.Machines.Inventory[uid] = item
	end
end

local function mergeChrome(player: Player, uidArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local uid = Guard.String(uidArg, 64)
	if not data or not uid then
		return false, "Invalid machine"
	end
	local picked = pickCopies(data, uid, 0, grades.ChromeMergeCount)
	if not picked then
		return false,
			string.format("You need %d identical, unlocked, unequipped Standard copies", grades.ChromeMergeCount)
	end
	local id = data.Machines.Inventory[uid].Id
	local removed = consume(data, picked)
	local newUid = Grants.GrantMachine(player, id, "Merge", 1)
	if not newUid then
		restore(data, removed)
		return false, "Could not create the Chrome machine"
	end
	DataService.MarkDirty(player, "Machines")
	return true, nil, { Uid = newUid }
end

local function startPlating(player: Player, uidArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local uid = Guard.String(uidArg, 64)
	if not data or not uid then
		return false, "Invalid machine"
	end
	if data.Machines.Plating.Id ~= "" then
		return false, "The plating bath is busy"
	end
	local picked = pickCopies(data, uid, 1, grades.GoldMergeCount)
	if not picked then
		return false, string.format("You need %d identical, unlocked, unequipped Chrome copies", grades.GoldMergeCount)
	end
	local id = data.Machines.Inventory[uid].Id
	consume(data, picked)
	data.Machines.Plating = { Id = id, EndsAt = os.time() + grades.PlatingSeconds }
	DataService.MarkDirty(player, "Machines")
	return true, nil, { EndsAt = data.Machines.Plating.EndsAt }
end

local function claimPlating(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local plating = data.Machines.Plating
	if plating.Id == "" then
		return false, "Nothing is being plated"
	end
	if os.time() < plating.EndsAt then
		return false, "Plating isn't finished yet"
	end
	local uid = Grants.GrantMachine(player, plating.Id, "Plating", 2)
	if not uid then
		return false, "Make room in your machine inventory first"
	end
	data.Machines.Plating = { Id = "", EndsAt = 0 }
	DataService.MarkDirty(player, "Machines")
	return true, nil, { Uid = uid }
end

local function lockMachine(player: Player, uidArg: any, lockedArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local uid = Guard.String(uidArg, 64)
	local locked = Guard.Boolean(lockedArg)
	if not data or not uid or locked == nil then
		return false, "Invalid request"
	end
	local item = data.Machines.Inventory[uid]
	if not item then
		return false, "You don't own that machine"
	end
	item.Locked = locked
	DataService.MarkDirty(player, "Machines")
	return true
end

-- Finishes the running plating timer (used by the instant-plating product).
function MachineService.SkipPlating(player: Player): boolean
	local data = DataService.Get(player)
	if not data or data.Machines.Plating.Id == "" then
		return false
	end
	data.Machines.Plating.EndsAt = os.time()
	DataService.MarkDirty(player, "Machines")
	return true
end

function MachineService.Init()
	Remote.Handle("BuyMachine", buyMachine)
	Remote.Handle("EquipMachine", equipMachine)
	Remote.Handle("UnequipMachine", unequipMachine)
	Remote.Handle("MergeChrome", mergeChrome)
	Remote.Handle("StartPlating", startPlating)
	Remote.Handle("ClaimPlating", claimPlating)
	Remote.Handle("LockMachine", lockMachine)
end

function MachineService.Start()
	maid:Add(DataService.Loaded:Connect(function(player: Player)
		syncBays(player)
	end))
	maid:Add(ServerSignals.Expanded:Connect(syncBays))
	maid:Add(ServerSignals.PassOwned:Connect(syncBays))
	-- Research completion fires MultipliersDirty; syncBays only re-fires when the bay count changed.
	maid:Add(ServerSignals.MultipliersDirty:Connect(syncBays))
	for _, player in Players:GetPlayers() do
		syncBays(player)
	end
end

return MachineService

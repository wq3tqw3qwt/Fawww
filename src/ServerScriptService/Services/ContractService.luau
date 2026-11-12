--!strict
--[[
	ContractService (L5): the free active layer. Slots refill on a timer, progress comes from
	ServerSignals.Produced, rewards are cash + Credits + a free blueprint roll (ContractOdds).
	Robux can never buy, complete or re-roll a contract. Also owns server-local Mega Contracts.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent.Server

local Config = require(Shared.Config)
local ContractOdds = require(Shared.ContractOdds)
local Formulas = require(Shared.Formulas)
local Maid = require(Shared.Maid)
local Types = require(Shared.Types)
local Grants = require(Server.Grants)
local Guard = require(Server.Guard)
local Remote = require(Server.Remote)
local ServerSignals = require(Server.ServerSignals)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local FactoryService = require(script.Parent.FactoryService)
local MultiplierService = require(script.Parent.MultiplierService)
local PassService = require(script.Parent.PassService)
local StatsService = require(script.Parent.StatsService)

local ContractService = {}

local cfg = Config.Contracts
local rng = Random.new()
local maid = Maid.new()

local function rand(): number
	return rng:NextNumber()
end

local function emptySlot(): Types.ContractSlot
	return { Tier = "", Line = 0, Target = 0, Progress = 0, EndsAt = 0, Done = false }
end

local function slotCount(player: Player): number
	return cfg.Slots + (if PassService.Owns(player, "ContractMaster") then cfg.ContractMasterExtraSlots else 0)
end

local function refillSeconds(player: Player): number
	return cfg.RefillSeconds * (if PassService.Owns(player, "ContractMaster") then cfg.ContractMasterRefillMult else 1)
end

local function researchBonus(data: Types.PlayerData): number
	local total = 0
	for _, def in Config.Research do
		if def.Effect == "ContractReward" then
			total += (data.Research.Levels[def.Id] or 0) * def.ValuePerLevel
		end
	end
	return total
end

local function tutorialPending(data: Types.PlayerData): boolean
	return not data.Contracts.TutorialDone
		and not data.Tutorial.Done
		and Config.Tutorial.Steps[data.Tutorial.Step] == "Contract"
end

-- The tutorial contract is a normal Bronze-looking slot 1 with the fixed tutorial line/target.
local function isTutorialSlot(data: Types.PlayerData, index: number, slot: Types.ContractSlot): boolean
	local tut = cfg.Tutorial
	return index == 1
		and not data.Contracts.TutorialDone
		and not data.Tutorial.Done
		and slot.Tier == cfg.TierOrder[1]
		and slot.Line == tut.Line
		and slot.Target == tut.Target
end

local function offerTutorial(data: Types.PlayerData)
	local tut = cfg.Tutorial
	data.Contracts.Slots[1] = {
		Tier = cfg.TierOrder[1],
		Line = tut.Line,
		Target = tut.Target,
		Progress = 0,
		EndsAt = os.time() + tut.DurationSeconds,
		Done = false,
	}
end

local function makeSlot(player: Player, data: Types.PlayerData, now: number): Types.ContractSlot
	local tierName = ContractOdds.PickTier(rand)
	local tier = cfg.Tiers[tierName]
	local owned = #data.Lines
	local lowest = math.max(1, owned - cfg.TopLinesPool + 1)
	local line = rng:NextInteger(lowest, owned)
	return {
		Tier = tierName,
		Line = line,
		Target = Formulas.ContractTarget(FactoryService.GetLineOutput(player, line), tier),
		Progress = 0,
		EndsAt = now + tier.DurationSeconds,
		Done = false,
	}
end

local function firstEmpty(slots: { Types.ContractSlot }): number?
	for i, slot in slots do
		if slot.Tier == "" then
			return i
		end
	end
	return nil
end

local function filledCount(slots: { Types.ContractSlot }): number
	local n = 0
	for _, slot in slots do
		if slot.Tier ~= "" then
			n += 1
		end
	end
	return n
end

-- Expires, offers the tutorial contract and refills one slot when the timer allows.
local function refreshSlots(player: Player, data: Types.PlayerData, now: number)
	local contracts = data.Contracts
	local slots = contracts.Slots
	local changed = false
	for _ = #slots + 1, slotCount(player) do
		table.insert(slots, emptySlot())
		changed = true
	end
	for i, slot in slots do
		if slot.Tier ~= "" and not slot.Done and slot.EndsAt <= now then
			slots[i] = emptySlot()
			changed = true
		end
	end
	if tutorialPending(data) and not isTutorialSlot(data, 1, slots[1]) then
		offerTutorial(data)
		changed = true
	end

	-- NextRefillAt == 0 means the timer is idle (every slot is full).
	local canRefill = data.Tutorial.Done or contracts.TutorialDone
	local empty = firstEmpty(slots)
	if empty == nil then
		if contracts.NextRefillAt ~= 0 then
			contracts.NextRefillAt = 0
			changed = true
		end
	elseif canRefill then
		local fillNow = false
		if contracts.NextRefillAt == 0 then
			if filledCount(slots) == 0 then
				fillNow = true
			else
				contracts.NextRefillAt = now + refillSeconds(player)
				changed = true
			end
		elseif now >= contracts.NextRefillAt then
			fillNow = true
		end
		if fillNow then
			slots[empty] = makeSlot(player, data, now)
			contracts.NextRefillAt = if firstEmpty(slots) then now + refillSeconds(player) else 0
			changed = true
		end
	end
	if changed then
		DataService.MarkDirty(player, "Contracts")
	end
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------
type Member = { Player: Player, Line: number, Target: number, Progress: number, Done: boolean }
type Mega = {
	Id: string,
	Host: Player,
	Members: { [number]: Member }, -- by UserId
	Count: number,
	State: string, -- "Joining" | "Active"
	StartsAt: number,
	EndsAt: number,
}

local megas: { [string]: Mega } = {}
local megaOf: { [number]: Mega } = {}
local lastMegaEnd: { [number]: number } = {}

local function onProduced(player: Player, line: number, products: number, _cash: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local changed = false
	for _, slot in data.Contracts.Slots do
		if slot.Tier ~= "" and not slot.Done and slot.Line == line then
			slot.Progress = math.min(slot.Target, slot.Progress + products)
			if slot.Progress >= slot.Target then
				slot.Done = true
			end
			changed = true
		end
	end
	if changed then
		DataService.MarkDirty(player, "Contracts")
	end
	local session = megaOf[player.UserId]
	if session and session.State == "Active" then
		local member = session.Members[player.UserId]
		if member and member.Line == line and not member.Done then
			member.Progress = math.min(member.Target, member.Progress + products)
			member.Done = member.Progress >= member.Target
		end
	end
end

--------------------------------------------------------------------------------
-- Claim
--------------------------------------------------------------------------------
local function claimContract(player: Player, slotArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local slots = data.Contracts.Slots
	local index = Guard.Integer(slotArg, 1, #slots)
	if not index then
		return false, "Invalid contract"
	end
	local slot = slots[index]
	if slot.Tier == "" then
		return false, "That slot is empty"
	end
	if not slot.Done and slot.Progress < slot.Target then
		return false, "Contract not finished yet"
	end
	if not slot.Done and slot.EndsAt <= os.time() then
		return false, "Contract expired"
	end
	local tier = cfg.Tiers[slot.Tier]
	if not tier then
		return false, "Unknown contract"
	end

	local tutorial = isTutorialSlot(data, index, slot)
	local cash: number
	local credits: number
	local blueprint: string? = nil
	if tutorial then
		cash, credits = cfg.Tutorial.RewardCash, cfg.Tutorial.RewardCredits
	else
		local abilities = MultiplierService.GetAbilities(player)
		cash = Formulas.ContractCashReward(
			FactoryService.GetIncome(player),
			tier,
			abilities.ContractPro or 0,
			researchBonus(data),
			EventService.IsRushActive()
		)
		credits = tier.Credits
	end

	-- Free blueprint roll; the pity counter is persisted whether or not a blueprint drops.
	local rarity: string? = nil
	if not tutorial then
		local result = ContractOdds.Roll(slot.Tier, data.Contracts.GoldSinceLegendary, rand)
		data.Contracts.GoldSinceLegendary = result.GoldSinceLegendary
		rarity = result.Rarity
	end

	slots[index] = emptySlot()
	if tutorial then
		data.Contracts.TutorialDone = true
	end
	DataService.MarkDirty(player, "Contracts")

	CurrencyService.AddCash(player, cash, "Contract")
	CurrencyService.AddCredits(player, credits, "Contract")
	if rarity then
		local machineId = ContractOdds.PickMachine(rarity, Formulas.HighestHall(data.Expansions), rand)
		if machineId and Grants.GrantMachine(player, machineId, "Contract") then
			blueprint = machineId
		end
	end

	StatsService.Increment(player, "ContractsCompleted", 1)
	if slot.Tier == "Gold" then
		StatsService.Increment(player, "GoldContracts", 1)
	end
	ServerSignals.ContractCompleted:Fire(player, slot.Tier)
	if tutorial then
		ServerSignals.TutorialAction:Fire(player, "ContractClaimed")
	end
	local payload = { Tier = slot.Tier, Cash = cash, Credits = credits, Blueprint = blueprint }
	Remote.Fire("Effect", player, "ContractStamp", payload)
	return true, nil, payload
end

-- "Contract Extend" product: pushes every unfinished contract deadline back.
function ContractService.ExtendAll(player: Player, seconds: number): boolean
	local data = DataService.Get(player)
	if not data or seconds <= 0 then
		return false
	end
	local extended = false
	for _, slot in data.Contracts.Slots do
		if slot.Tier ~= "" and not slot.Done then
			slot.EndsAt += seconds
			extended = true
		end
	end
	if extended then
		DataService.MarkDirty(player, "Contracts")
	end
	return extended
end

--------------------------------------------------------------------------------
-- Mega Contracts (server-local co-op)
--------------------------------------------------------------------------------
local mega = cfg.Mega

local function megaPayload(m: Mega, viewer: Player): { [string]: any }
	local members = {}
	for _, member in m.Members do
		table.insert(members, {
			UserId = member.Player.UserId,
			Name = member.Player.DisplayName,
			Progress = member.Progress,
			Target = member.Target,
			Done = member.Done,
		})
	end
	local mine = m.Members[viewer.UserId]
	return {
		MegaId = m.Id,
		State = m.State,
		Host = m.Host.DisplayName,
		StartsAt = m.StartsAt,
		EndsAt = m.EndsAt,
		MaxPlayers = mega.MaxPlayers,
		Members = members,
		Progress = if mine then mine.Progress else 0,
		Target = if mine then mine.Target else 0,
	}
end

local function pushMega(m: Mega)
	for _, member in m.Members do
		Remote.Fire("Effect", member.Player, "MegaState", megaPayload(m, member.Player))
	end
end

local function removeMega(m: Mega, withCooldown: boolean)
	local now = os.clock()
	for userId in m.Members do
		megaOf[userId] = nil
		if withCooldown then
			lastMegaEnd[userId] = now
		end
	end
	megas[m.Id] = nil
	for _, member in m.Members do
		Remote.Fire("Effect", member.Player, "MegaState", { MegaId = m.Id, State = "Closed" })
	end
end

local function onCooldown(userId: number): boolean
	local last = lastMegaEnd[userId]
	return last ~= nil and os.clock() - last < mega.CooldownSeconds
end

local function addMember(m: Mega, player: Player)
	m.Members[player.UserId] = { Player = player, Line = 0, Target = 0, Progress = 0, Done = false }
	m.Count += 1
	megaOf[player.UserId] = m
end

local function startMega(m: Mega)
	local now = os.time()
	m.State = "Active"
	m.StartsAt = now
	m.EndsAt = now + mega.DurationSeconds
	for _, member in m.Members do
		local data = DataService.Get(member.Player)
		local line = if data then math.max(1, #data.Lines) else 1
		member.Line = line
		member.Target =
			math.max(cfg.MinTarget, math.floor(FactoryService.GetLineOutput(member.Player, line) * mega.TargetSeconds))
	end
	pushMega(m)
end

local function finishMega(m: Mega)
	for _, member in m.Members do
		local data = DataService.Get(member.Player)
		if data then
			data.Contracts.MegaPoints += mega.PointsPerWin
			if data.Contracts.MegaPoints >= mega.PointsForMythic then
				local id = EventService.GetMythicOfWeek()
				if Grants.GrantMachine(member.Player, id, "Mega") then
					data.Contracts.MegaPoints -= mega.PointsForMythic
					local def = Formulas.GetMachine(id)
					EventService.Announce(
						string.format(
							"%s earned the Mythic %s from Mega Contracts!",
							member.Player.DisplayName,
							if def then def.Name else id
						),
						Config.Rarities.Colors.Mythic,
						true
					)
				end
			end
			DataService.MarkDirty(member.Player, "Contracts")
			Remote.Notify(member.Player, "Reward", "Mega Contract complete!")
		end
	end
	removeMega(m, true)
end

local function megaCreate(player: Player): (boolean, string?, any?)
	if megaOf[player.UserId] then
		return false, "You're already in a Mega Contract"
	end
	if onCooldown(player.UserId) then
		return false, "Mega Contracts are cooling down"
	end
	local now = os.time()
	local m: Mega = {
		Id = HttpService:GenerateGUID(false),
		Host = player,
		Members = {},
		Count = 0,
		State = "Joining",
		StartsAt = now + mega.JoinWindowSeconds,
		EndsAt = 0,
	}
	megas[m.Id] = m
	addMember(m, player)
	pushMega(m)
	for _, other in DataService.GetLoadedPlayers() do
		if other ~= player then
			Remote.Fire(
				"Effect",
				other,
				"MegaOpen",
				{ MegaId = m.Id, Host = player.DisplayName, StartsAt = m.StartsAt }
			)
		end
	end
	return true, nil, megaPayload(m, player)
end

local function megaJoin(player: Player, megaIdArg: any): (boolean, string?, any?)
	local id = Guard.String(megaIdArg, 64)
	local m = if id then megas[id] else nil
	if not m or m.State ~= "Joining" then
		return false, "That Mega Contract isn't open"
	end
	if megaOf[player.UserId] then
		return false, "You're already in a Mega Contract"
	end
	if onCooldown(player.UserId) then
		return false, "Mega Contracts are cooling down"
	end
	if m.Count >= mega.MaxPlayers then
		return false, "That Mega Contract is full"
	end
	addMember(m, player)
	if m.Count >= mega.MaxPlayers then
		startMega(m)
	else
		pushMega(m)
	end
	return true, nil, megaPayload(m, player)
end

local function onPlayerRemoving(player: Player)
	local m = megaOf[player.UserId]
	if not m then
		return
	end
	m.Members[player.UserId] = nil
	m.Count -= 1
	megaOf[player.UserId] = nil
	if m.Count <= 0 then
		megas[m.Id] = nil
	elseif m.Host == player then
		for _, member in m.Members do
			m.Host = member.Player
			break
		end
	end
end

local function tickMegas()
	local now = os.time()
	for _, m in table.clone(megas) do
		if m.State == "Joining" then
			if now >= m.StartsAt then
				if m.Count >= mega.MinPlayers then
					startMega(m)
				else
					for _, member in m.Members do
						Remote.Notify(member.Player, "Info", "Not enough players joined the Mega Contract.")
					end
					removeMega(m, false)
				end
			end
		else
			local allDone = m.Count > 0
			for _, member in m.Members do
				allDone = allDone and member.Done
			end
			if m.Count < mega.MinPlayers and not allDone then
				for _, member in m.Members do
					Remote.Notify(member.Player, "Error", "Mega Contract cancelled: not enough players left.")
				end
				removeMega(m, true)
			elseif allDone then
				finishMega(m)
			elseif now >= m.EndsAt then
				for _, member in m.Members do
					Remote.Notify(member.Player, "Error", "Mega Contract failed: time ran out.")
				end
				removeMega(m, true)
			else
				pushMega(m)
			end
		end
	end
end

local function runLoop()
	while true do
		task.wait(1)
		local now = os.time()
		for _, player in DataService.GetLoadedPlayers() do
			local data = DataService.Get(player)
			if data then
				refreshSlots(player, data, now)
			end
		end
		tickMegas()
	end
end

function ContractService.Init()
	Remote.Handle("ClaimContract", claimContract)
	Remote.Handle("MegaCreate", megaCreate)
	Remote.Handle("MegaJoin", megaJoin)
end

function ContractService.Start()
	maid:Add(ServerSignals.Produced:Connect(onProduced))
	maid:Add(Players.PlayerRemoving:Connect(onPlayerRemoving))
	runLoop()
end

return ContractService

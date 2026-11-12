--!strict
--[[
	QuestService (L5): daily (UTC day) and weekly (ISO week) quests, deterministically shuffled
	per player so a rejoin never rerolls them. Progress is driven by ServerSignals.
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
local RuntimeState = require(Server.RuntimeState)
local ServerSignals = require(Server.ServerSignals)
local DataService = require(script.Parent.DataService)

local QuestService = {}

local cfg = Config.Quests
local maid = Maid.new()

-- Runtime figures are zero right after join; wait this long (or for income) before sizing targets.
local TARGET_READY_SECONDS = 15
local LOOP_SECONDS = 5

local questById: { [string]: Config.QuestDef } = {}
for _, def in cfg.Daily do
	questById[def.Id] = def
end
for _, def in cfg.Weekly do
	questById[def.Id] = def
end

local function targetFor(player: Player, def: Config.QuestDef): number
	local state = RuntimeState.Get(player)
	if def.TargetMode == "OutputSeconds" then
		local total = 0
		for _, output in state.LineOutputs do
			total += output
		end
		return math.max(def.Base, math.floor(def.Base * total))
	elseif def.TargetMode == "IncomeSeconds" then
		return math.max(def.Base, math.floor(def.Base * state.IncomePerSecond))
	end
	return def.Base
end

local function pickQuests(player: Player, pool: { Config.QuestDef }, count: number, seed: number): { Types.QuestState }
	local r = Random.new(seed)
	local order = {}
	for i = 1, #pool do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = r:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local quests: { Types.QuestState } = {}
	for i = 1, math.min(count, #pool) do
		local def = pool[order[i]]
		table.insert(quests, { Id = def.Id, Target = targetFor(player, def), Progress = 0, Claimed = false })
	end
	return quests
end

local function weekSeed(weekKey: string): number
	local year, week = string.match(weekKey, "^(%d+)W(%d+)$")
	return (tonumber(year) or 0) * 100 + (tonumber(week) or 0)
end

local function targetsReady(player: Player): boolean
	local state = RuntimeState.Get(player)
	return state.IncomePerSecond > 0 or os.clock() - state.JoinedAt >= TARGET_READY_SECONDS
end

local function refreshQuests(player: Player, data: Types.PlayerData)
	local quests = data.Quests
	local now = os.time()
	local day = Formulas.DayNumber(now)
	local weekKey = Formulas.WeekKey(now)
	if quests.DailyDay == day and quests.WeekKey == weekKey then
		return
	end
	if not targetsReady(player) then
		return
	end
	if quests.DailyDay ~= day then
		quests.DailyDay = day
		quests.Daily = pickQuests(player, cfg.Daily, cfg.DailyCount, player.UserId + day * 1000003)
		quests.DailyBonusClaimed = false
	end
	if quests.WeekKey ~= weekKey then
		quests.WeekKey = weekKey
		quests.Weekly = pickQuests(player, cfg.Weekly, cfg.WeeklyCount, player.UserId + weekSeed(weekKey) * 1000003)
	end
	DataService.MarkDirty(player, "Quests")
end

local function addProgress(player: Player, kind: string, amount: number)
	local data = DataService.Get(player)
	if not data or amount <= 0 then
		return
	end
	local changed = false
	for _, list in { data.Quests.Daily, data.Quests.Weekly } do
		for _, quest in list do
			local def = questById[quest.Id]
			if def and def.Kind == kind and not quest.Claimed and quest.Progress < quest.Target then
				quest.Progress = math.min(quest.Target, quest.Progress + amount)
				changed = true
			end
		end
	end
	if changed then
		DataService.MarkDirty(player, "Quests")
	end
end

local function claimQuest(player: Player, kindArg: any, indexArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data or (kindArg ~= "Daily" and kindArg ~= "Weekly") then
		return false, "Invalid quest"
	end
	local list = if kindArg == "Daily" then data.Quests.Daily else data.Quests.Weekly
	local index = Guard.Integer(indexArg, 1, #list)
	if not index then
		return false, "Invalid quest"
	end
	local quest = list[index]
	local def = questById[quest.Id]
	if not def then
		return false, "Unknown quest"
	end
	if quest.Claimed then
		return false, "Already claimed"
	end
	if quest.Progress < quest.Target then
		return false, "Quest not finished yet"
	end
	quest.Claimed = true
	DataService.MarkDirty(player, "Quests")
	Grants.GrantCredits(player, def.Credits, "Quest")
	if kindArg == "Weekly" then
		Grants.GrantBoost(player, cfg.WeeklyBoostKey, cfg.WeeklyBoostMinutes)
	end
	return true, nil, { Credits = def.Credits }
end

local function claimDailyBonus(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local quests = data.Quests
	if quests.DailyBonusClaimed or #quests.Daily == 0 then
		return false, "Bonus not available"
	end
	for _, quest in quests.Daily do
		if not quest.Claimed then
			return false, "Claim all daily quests first"
		end
	end
	quests.DailyBonusClaimed = true
	DataService.MarkDirty(player, "Quests")
	Grants.GrantCredits(player, cfg.AllDailyBonusCredits, "QuestBonus")
	return true, nil, { Credits = cfg.AllDailyBonusCredits }
end

local function runLoop()
	while true do
		task.wait(LOOP_SECONDS)
		for _, player in DataService.GetLoadedPlayers() do
			local data = DataService.Get(player)
			if data then
				refreshQuests(player, data)
			end
		end
	end
end

function QuestService.Init()
	Remote.Handle("ClaimQuest", claimQuest)
	Remote.Handle("ClaimDailyQuestBonus", claimDailyBonus)
end

function QuestService.Start()
	-- Stats cover ContractsCompleted / GoldContracts / Expanded as well as the plain counters.
	maid:Add(ServerSignals.StatChanged:Connect(function(player: Player, key: string, amount: number)
		addProgress(player, key, amount)
	end))
	maid:Add(ServerSignals.CashEarned:Connect(function(player: Player, amount: number, _source: string)
		addProgress(player, "CashEarned", amount)
	end))
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data then
			refreshQuests(player, data)
		end
	end
	runLoop()
end

return QuestService

--!strict
--[[
	DailyRewardService (L5): 7-day reward cycle with streak shields, streak milestones,
	Premium daily Credits and the accruing Supply Drop.
]]

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
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local StatsService = require(script.Parent.StatsService)

local DailyRewardService = {}

type DailyState = typeof(({} :: Types.PlayerData).Daily)

local cfg = Config.DailyRewards
local maid = Maid.new()
local SUPPLY_LOOP_SECONDS = 10

local function formatWait(seconds: number): string
	local minutes = math.ceil(seconds / 60)
	if minutes >= 60 then
		return string.format("%dh %dm", minutes // 60, minutes % 60)
	end
	return string.format("%dm", minutes)
end

-- One free shield per ISO week, capped at MaxShields.
local function grantWeeklyShield(data: Types.PlayerData, now: number): boolean
	local daily = data.Daily
	local weekKey = Formulas.WeekKey(now)
	if daily.ShieldWeek == weekKey then
		return false
	end
	daily.ShieldWeek = weekKey
	daily.Shields = math.min(cfg.MaxShields, daily.Shields + cfg.FreeShieldsPerWeek)
	return true
end

-- Returns the streak after applying grace/shields, and how many shields the claim burns.
local function resolveStreak(daily: DailyState, now: number): (number, number)
	if daily.LastClaimUnix == 0 then
		return 0, 0
	end
	local gap = now - daily.LastClaimUnix
	local grace = cfg.StreakGraceHours * 3600
	if gap <= grace then
		return daily.Streak, 0
	end
	-- Each cooldown-length window beyond the grace period costs one shield.
	local missed = math.ceil((gap - grace) / (cfg.ClaimCooldownHours * 3600))
	if daily.Shields >= missed then
		return daily.Streak, missed
	end
	return 0, 0
end

-- Rare (or configured rarity) machines from halls the player has unlocked, bought normally.
local function validChoice(data: Types.PlayerData, machineId: string, rarity: string): boolean
	local def = Formulas.GetMachine(machineId)
	if not def or def.Rarity ~= rarity or def.Hall < 1 then
		return false
	end
	if not Formulas.HallUnlocked(def.Hall, data.Expansions) then
		return false
	end
	return table.find(ContractOdds.BlueprintPool(rarity, def.Hall), machineId) ~= nil
end

local function claimDaily(player: Player, choiceArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local daily = data.Daily
	local now = os.time()
	if daily.LastClaimUnix > 0 then
		local remaining = daily.LastClaimUnix + cfg.ClaimCooldownHours * 3600 - now
		if remaining > 0 then
			return false, "Come back in " .. formatWait(remaining)
		end
	end
	grantWeeklyShield(data, now)
	local streak, shieldsUsed = resolveStreak(daily, now)
	local dayIndex = (streak % #cfg.Cycle) + 1
	local reward = cfg.Cycle[dayIndex]

	-- Validate and take the fallible machine grant before changing any streak state.
	if reward.Kind == "MachineChoice" then
		local choice = Guard.String(choiceArg, 64)
		if not choice or not validChoice(data, choice, reward.Rarity or "Rare") then
			return false, "Pick a machine from an unlocked industry"
		end
		if not Grants.GrantMachine(player, choice, "Daily") then
			return false, "Make room in your machine inventory first"
		end
		Grants.GrantCredits(player, reward.Amount, "Daily")
	elseif reward.Kind == "IncomeMinutes" then
		Grants.GrantIncomeMinutes(player, reward.Amount, "Daily")
	elseif reward.Kind == "Credits" then
		Grants.GrantCredits(player, reward.Amount, "Daily")
	elseif reward.Kind == "Boost" and reward.BoostKey then
		Grants.GrantBoost(player, reward.BoostKey, reward.Amount)
	end

	daily.Shields -= shieldsUsed
	daily.Streak = streak + 1
	daily.LastClaimUnix = now

	for _, milestone in cfg.Milestones do
		local key = tostring(milestone.Day)
		if daily.Streak >= milestone.Day and not daily.Milestones[key] then
			if Grants.GrantMachine(player, milestone.MachineId, "Milestone") then
				daily.Milestones[key] = true
				if milestone.Title then
					Grants.GrantTitle(player, milestone.Title)
				end
			end
		end
	end
	DataService.MarkDirty(player, "Daily")
	return true, nil, { Day = dayIndex, Streak = daily.Streak, ShieldsUsed = shieldsUsed }
end

--------------------------------------------------------------------------------
-- Supply Drop
--------------------------------------------------------------------------------
local drop = Config.SupplyDrop

-- Banks whole intervals up to MaxStored; the timer only runs while below the cap.
local function accrueSupply(data: Types.PlayerData, now: number): boolean
	local supply = data.Supply
	local before = supply.Stored
	if supply.LastGrantUnix == 0 or supply.Stored >= drop.MaxStored then
		-- At the cap (or first ever call) the timer just follows the clock; nothing to replicate.
		supply.LastGrantUnix = now
		return false
	end
	local intervals = math.floor((now - supply.LastGrantUnix) / drop.IntervalSeconds)
	if intervals > 0 then
		supply.Stored = math.min(drop.MaxStored, supply.Stored + intervals)
		supply.LastGrantUnix = if supply.Stored >= drop.MaxStored
			then now
			else supply.LastGrantUnix + intervals * drop.IntervalSeconds
	end
	return supply.Stored ~= before
end

local function claimSupplyDrop(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local now = os.time()
	accrueSupply(data, now)
	local supply = data.Supply
	if supply.Stored < 1 then
		return false, "No supply drop ready yet"
	end
	if supply.Stored >= drop.MaxStored then
		supply.LastGrantUnix = now -- the timer restarts once below the cap
	end
	supply.Stored -= 1
	DataService.MarkDirty(player, "Supply")
	local cash = Grants.GrantIncomeMinutes(player, drop.IncomeMinutes, "Supply")
	Grants.GrantCredits(player, drop.Credits, "Supply")
	StatsService.Increment(player, "SupplyOpened", 1)
	return true, nil, { Cash = cash, Credits = drop.Credits }
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function onLoaded(player: Player, data: Types.PlayerData)
	local now = os.time()
	if grantWeeklyShield(data, now) then
		DataService.MarkDirty(player, "Daily")
	end
	accrueSupply(data, now)
	DataService.MarkDirty(player, "Supply")
	local today = Formulas.DayNumber(now)
	if PassService.IsPremium(player) and data.Daily.PremiumDay ~= today then
		data.Daily.PremiumDay = today
		DataService.MarkDirty(player, "Daily")
		Grants.GrantCredits(player, Config.Premium.DailyCredits, "Premium")
		Remote.Notify(player, "Reward", "Premium daily Credits delivered!")
	end
end

local function runLoop()
	while true do
		task.wait(SUPPLY_LOOP_SECONDS)
		local now = os.time()
		for _, player in DataService.GetLoadedPlayers() do
			local data = DataService.Get(player)
			if data and accrueSupply(data, now) then
				DataService.MarkDirty(player, "Supply")
			end
		end
	end
end

function DailyRewardService.Init()
	Remote.Handle("ClaimDaily", claimDaily)
	Remote.Handle("ClaimSupplyDrop", claimSupplyDrop)
end

function DailyRewardService.Start()
	maid:Add(DataService.Loaded:Connect(onLoaded))
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data then
			onLoaded(player, data)
		end
	end
	runLoop()
end

return DailyRewardService

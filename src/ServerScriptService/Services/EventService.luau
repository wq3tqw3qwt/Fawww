--!strict
--[[
	EventService (L2): Rush Orders, Weekend, admin-forced events, global weekly goal
	(MemoryStore SortedMap) and the periodic EventState broadcast.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent.Server

local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Maid = require(Shared.Maid)
local Types = require(Shared.Types)
local Grants = require(Server.Grants)
local Remote = require(Server.Remote)
local Retry = require(Server.Retry)
local ServerSignals = require(Server.ServerSignals)
local DataService = require(script.Parent.DataService)

export type GoalState = { WeekKey: string, Total: number, Tiers: { number } }
export type EventState = {
	RushActive: boolean,
	RushSecondsLeft: number,
	WeekendActive: boolean,
	ForcedRushUntil: number,
	ForcedWeekendUntil: number,
	GlobalGoal: GoalState,
	NextUpdateUnix: number,
	ServerTime: number,
}

type DateParts = { wday: number, hour: number, min: number, sec: number }

local EventService = {}

local cfg = Config.Events
local goalCfg = cfg.GlobalGoal

local forcedRushUntil = 0
local forcedWeekendUntil = 0
local polledTotal = 0
local polledWeekKey = ""
local bufferedByWeek: { [string]: number } = {}
local lastSignature = ""
local goalMap: MemoryStoreSortedMap? = nil
local flushing = false
local polling = false
local maid = Maid.new()

local function utcParts(now: number): DateParts
	return (os.date("!*t", now) :: any) :: DateParts
end

local function weekNumber(now: number): number
	-- Monday-aligned week counter (1970-01-01 was a Thursday).
	return math.floor((Formulas.DayNumber(now) + 3) / 7)
end

function EventService.GetMythicOfWeek(): string
	local rotation = goalCfg.MythicRotation
	return rotation[(weekNumber(os.time()) % #rotation) + 1]
end

function EventService.IsRushActive(): boolean
	local now = os.time()
	if forcedRushUntil > now then
		return true
	end
	local t = utcParts(now)
	local active = Formulas.RushState(t, t.sec)
	return active
end

function EventService.IsWeekend(): boolean
	local now = os.time()
	return forcedWeekendUntil > now or Formulas.IsWeekend(utcParts(now))
end

local function bufferedFor(weekKey: string): number
	return bufferedByWeek[weekKey] or 0
end

function EventService.GetGlobalTotal(): number
	local weekKey = Formulas.WeekKey(os.time())
	return polledTotal + bufferedFor(weekKey)
end

local function nextUpdateUnix(now: number): number
	local period = cfg.UpdateCadenceDays * 86400
	if now < cfg.UpdateEpochUnix then
		return cfg.UpdateEpochUnix
	end
	return cfg.UpdateEpochUnix + (math.floor((now - cfg.UpdateEpochUnix) / period) + 1) * period
end

function EventService.GetState(): EventState
	local now = os.time()
	local t = utcParts(now)
	local naturalRush, naturalLeft = Formulas.RushState(t, t.sec)
	local forcedLeft = math.max(0, forcedRushUntil - now)
	return {
		RushActive = naturalRush or forcedLeft > 0,
		RushSecondsLeft = math.max(if naturalRush then naturalLeft else 0, forcedLeft),
		WeekendActive = forcedWeekendUntil > now or Formulas.IsWeekend(t),
		ForcedRushUntil = forcedRushUntil,
		ForcedWeekendUntil = forcedWeekendUntil,
		GlobalGoal = {
			WeekKey = Formulas.WeekKey(now),
			Total = EventService.GetGlobalTotal(),
			Tiers = goalCfg.Tiers,
		},
		NextUpdateUnix = nextUpdateUnix(now),
		ServerTime = now,
	}
end

local function signatureOf(state: EventState): string
	return string.format(
		"%s|%s|%d|%d|%s|%d",
		tostring(state.RushActive),
		tostring(state.WeekendActive),
		state.ForcedRushUntil,
		state.ForcedWeekendUntil,
		state.GlobalGoal.WeekKey,
		state.GlobalGoal.Total
	)
end

local function broadcast(force: boolean)
	local state = EventService.GetState()
	local signature = signatureOf(state)
	-- Rush seconds count down client-side from ServerTime, so only real changes are pushed early.
	if force or signature ~= lastSignature then
		lastSignature = signature
		Remote.FireAll("EventState", state)
	end
end

--------------------------------------------------------------------------------
-- Cross-server messaging
--------------------------------------------------------------------------------
local function publish(payload: { [string]: any })
	task.spawn(function()
		payload.Origin = game.JobId
		Retry.Call("Messaging.PublishAsync", function()
			MessagingService:PublishAsync(cfg.MessagingTopic, payload)
		end)
	end)
end

local function applyForce(kind: string, untilUnix: number)
	if kind == "Rush" then
		forcedRushUntil = math.max(forcedRushUntil, untilUnix)
	elseif kind == "Weekend" then
		forcedWeekendUntil = math.max(forcedWeekendUntil, untilUnix)
	end
end

function EventService.ForceEvent(kind: string, minutes: number, global: boolean)
	local clamped = math.clamp(minutes, 0, cfg.MaxForcedMinutes)
	local untilUnix = os.time() + math.floor(clamped * 60)
	applyForce(kind, untilUnix)
	if global then
		publish({ Type = "Force", Kind = kind, Until = untilUnix })
	end
	broadcast(true)
end

function EventService.Announce(text: string, color: Color3?, global: boolean?)
	local c = color or Config.Rarities.Colors.Special
	Remote.FireAll("Announce", text, c)
	if global then
		publish({ Type = "Announce", Text = text, R = c.R, G = c.G, B = c.B })
	end
end

local function onMessage(message: any)
	local data = message.Data
	if type(data) ~= "table" or data.Origin == game.JobId then
		return
	end
	if data.Type == "Force" then
		local kind = data.Kind
		local untilUnix = data.Until
		if type(kind) == "string" and type(untilUnix) == "number" then
			local now = os.time()
			-- Never trust the wire: cap how far ahead a forced event may run.
			applyForce(kind, math.clamp(untilUnix, now, now + cfg.MaxForcedMinutes * 60))
			broadcast(true)
		end
	elseif data.Type == "Announce" then
		local text = data.Text
		if type(text) == "string" and #text <= 200 and type(data.R) == "number" then
			Remote.FireAll("Announce", text, Color3.new(data.R, data.G, data.B))
		end
	end
end

--------------------------------------------------------------------------------
-- Global weekly goal
--------------------------------------------------------------------------------
local function getMap(): MemoryStoreSortedMap?
	if goalMap == nil then
		local ok, map = Retry.Call("MemoryStore.GetSortedMap", function()
			return MemoryStoreService:GetSortedMap(goalCfg.MapName)
		end)
		if ok then
			goalMap = map :: MemoryStoreSortedMap
		end
	end
	return goalMap
end

local function flushBuffer()
	if flushing then
		return
	end
	flushing = true
	for weekKey, delta in table.clone(bufferedByWeek) do
		local map = getMap()
		if map == nil or delta <= 0 then
			break
		end
		local ok = Retry.Call("MemoryStore.UpdateAsync", function()
			return map:UpdateAsync(weekKey, function(old: any)
				return (if type(old) == "number" then old else 0) + delta
			end, goalCfg.ExpirationSeconds)
		end)
		if ok then
			-- Move the delta from "buffered" to "polled" in one step so the shown total never dips.
			bufferedByWeek[weekKey] = bufferedFor(weekKey) - delta
			if weekKey == Formulas.WeekKey(os.time()) then
				polledTotal += delta
			end
			if bufferedByWeek[weekKey] <= 0 then
				bufferedByWeek[weekKey] = nil
			end
		end
	end
	flushing = false
end

local function pollTotal()
	if polling then
		return
	end
	polling = true
	local map = getMap()
	if map then
		local weekKey = Formulas.WeekKey(os.time())
		local ok, value = Retry.Call("MemoryStore.GetAsync", function()
			return map:GetAsync(weekKey)
		end)
		-- Ignore the result when the week turned over while the call was in flight.
		if ok and weekKey == Formulas.WeekKey(os.time()) then
			polledTotal = math.max(
				if polledWeekKey == weekKey then polledTotal else 0,
				if type(value) == "number" then value else 0
			)
			polledWeekKey = weekKey
		end
	end
	polling = false
end

local function ensureGoalWeek(data: Types.PlayerData, weekKey: string): boolean
	local goal = data.GlobalGoal
	if goal.WeekKey == weekKey then
		return false
	end
	goal.WeekKey = weekKey
	goal.Contracts = 0
	goal.ClaimedTier = 0
	return true
end

local function applyReward(player: Player, reward: Config.RewardDef): (boolean, string?)
	if reward.MythicOfWeek then
		local uid = Grants.GrantMachine(player, EventService.GetMythicOfWeek(), "GlobalGoal")
		if uid == nil then
			return false, "Your machine inventory is full"
		end
	end
	if reward.Credits then
		Grants.GrantCredits(player, reward.Credits, "GlobalGoal")
	end
	if reward.BoostKey and reward.Minutes then
		Grants.GrantBoost(player, reward.BoostKey, reward.Minutes)
	end
	return true, nil
end

local function claimGlobalGoal(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local weekKey = Formulas.WeekKey(os.time())
	ensureGoalWeek(data, weekKey)
	local goal = data.GlobalGoal
	if goal.Contracts < goalCfg.MinPersonalContracts then
		DataService.MarkDirty(player, "GlobalGoal")
		return false, string.format("Complete %d contracts this week to claim rewards", goalCfg.MinPersonalContracts)
	end
	local total = EventService.GetGlobalTotal()
	local claimed = 0
	local lastError: string? = nil
	while goal.ClaimedTier < #goalCfg.Tiers do
		local nextTier = goal.ClaimedTier + 1
		if total < goalCfg.Tiers[nextTier] then
			break
		end
		local reward = goalCfg.Rewards[nextTier]
		if reward then
			local ok, err = applyReward(player, reward)
			if not ok then
				lastError = err
				break
			end
		end
		goal.ClaimedTier = nextTier
		claimed += 1
	end
	DataService.MarkDirty(player, "GlobalGoal")
	if claimed == 0 then
		return false, lastError or "No new goal reward is ready yet"
	end
	Remote.Notify(player, "Reward", "Community goal reward claimed!")
	return true, nil, { Claimed = claimed, ClaimedTier = goal.ClaimedTier }
end

local function onContractCompleted(player: Player, _tier: string)
	local weekKey = Formulas.WeekKey(os.time())
	bufferedByWeek[weekKey] = bufferedFor(weekKey) + 1
	local data = DataService.Get(player)
	if data then
		ensureGoalWeek(data, weekKey)
		data.GlobalGoal.Contracts += 1
		DataService.MarkDirty(player, "GlobalGoal")
	end
end

local function onPlayerLoaded(player: Player, data: Types.PlayerData)
	if ensureGoalWeek(data, Formulas.WeekKey(os.time())) then
		DataService.MarkDirty(player, "GlobalGoal")
	end
	Remote.Fire("EventState", player, EventService.GetState())
end

local function runLoop()
	local tick = 0
	while true do
		task.wait(1)
		tick += 1
		if tick % goalCfg.FlushSeconds == 0 then
			task.spawn(flushBuffer)
		end
		local weekKey = Formulas.WeekKey(os.time())
		if polledWeekKey ~= weekKey then
			-- New ISO week: the total restarts from zero before the next poll lands.
			polledWeekKey = weekKey
			polledTotal = 0
			task.spawn(pollTotal)
		elseif tick % goalCfg.PollSeconds == 0 then
			task.spawn(pollTotal)
		end
		broadcast(tick % cfg.StateBroadcastSeconds == 0)
	end
end

function EventService.Init()
	Remote.Handle("ClaimGlobalGoal", claimGlobalGoal)
end

function EventService.Start()
	maid:Add(ServerSignals.ContractCompleted:Connect(onContractCompleted))
	maid:Add(DataService.Loaded:Connect(onPlayerLoaded))
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data then
			onPlayerLoaded(player, data)
		end
	end
	task.spawn(function()
		Retry.Call("Messaging.SubscribeAsync", function()
			return MessagingService:SubscribeAsync(cfg.MessagingTopic, onMessage)
		end)
	end)
	task.spawn(pollTotal)
	runLoop()
end

return EventService

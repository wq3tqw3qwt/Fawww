--!strict
--[[
	FactoryService (L4): owns the single shared 1 s production tick and every factory remote
	(lines, stage upgrades, Overdrive, vault, packaging, robots). Costs are always recomputed
	from Formulas on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Types = require(ReplicatedStorage.Shared.Types)

local Server = script.Parent.Parent.Server
local Grants = require(Server.Grants)
local Guard = require(Server.Guard)
local Remote = require(Server.Remote)
local RuntimeState = require(Server.RuntimeState)
local ServerSignals = require(Server.ServerSignals)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local MultiplierService = require(script.Parent.MultiplierService)
local PassService = require(script.Parent.PassService)
local PlotService = require(script.Parent.PlotService)
local SocialBonusService = require(script.Parent.SocialBonusService)
local StatsService = require(script.Parent.StatsService)

type PlayerState = {
	Carry: { number },
	ValueCarry: { number },
	NeedAssign: boolean,
}

local protect: (...any) -> (boolean, any) = pcall :: any

local FactoryService = {}

local MAX_USER_ID = 2 ^ 53
local STAGE_COUNT = #Config.Economy.StageNames
local OVERDRIVE_STEP = table.find(Config.Tutorial.Steps, "Overdrive") or 0

local states: { [Player]: PlayerState } = {}

local function stateFor(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = { Carry = {}, ValueCarry = {}, NeedAssign = true }
		states[player] = state
	end
	return state
end

local function robotCount(player: Player, data: Types.PlayerData): number
	return Formulas.RobotsFor(data.Expansions, PassService.Owns(player, "ExtraRobots"))
end

local function robotOnLine(data: Types.PlayerData, line: number): boolean
	for _, assigned in data.RobotAssignments do
		if assigned == line then
			return true
		end
	end
	return false
end

-- Keeps RobotAssignments sized to the robots the player owns; idle robots go to the highest lines.
local function syncRobots(player: Player, data: Types.PlayerData, state: PlayerState)
	local assignments = data.RobotAssignments
	local count = robotCount(player, data)
	local changed = false
	while #assignments < count do
		table.insert(assignments, 0)
		state.NeedAssign = true
		changed = true
	end
	while #assignments > count do
		table.remove(assignments)
		changed = true
	end
	for i, line in assignments do
		if line ~= 0 and (line < 1 or line > #data.Lines) then
			assignments[i] = 0
			state.NeedAssign = true
			changed = true
		end
	end
	if state.NeedAssign then
		state.NeedAssign = false
		for i, line in assignments do
			if line == 0 then
				for k = #data.Lines, 1, -1 do
					local taken = 0
					for _, other in assignments do
						if other == k then
							taken += 1
						end
					end
					if taken < Config.Robots.MaxPerLine then
						assignments[i] = k
						changed = true
						break
					end
				end
			end
		end
	end
	if changed then
		DataService.MarkDirty(player, "RobotAssignments")
	end
end

-- Awards catalog stamps for lines whose lowest stage reached a new threshold.
local function refreshStamps(player: Player, data: Types.PlayerData)
	local stamps = data.Catalog.Stamps
	for k = 1, #Config.Lines do
		if stamps[k] == nil then
			stamps[k] = 0
		end
	end
	local changed = false
	for k, levels in data.Lines do
		local old = stamps[k]
		local new = Formulas.StampLevel(Formulas.LineMinLevel(levels), true)
		if new > old then
			stamps[k] = new
			changed = true
			for s = old + 1, new do
				local credits = Config.Catalog.Credits[s] or 0
				Grants.GrantCredits(player, credits, "Catalog")
				Remote.Notify(
					player,
					"Reward",
					string.format(
						"%s stamp: %s! +%d Credits",
						Config.Catalog.StampNames[s],
						Config.Lines[k].Name,
						credits
					)
				)
			end
		end
	end
	if changed then
		DataService.MarkDirty(player, "Catalog")
		ServerSignals.MultipliersDirty:Fire(player)
	end
end

local function startOverdrive(player: Player, line: number, now: number)
	local rs = RuntimeState.Get(player)
	local duration = MultiplierService.GetOverdriveSeconds(player)
	local untilClock = now + duration
	rs.OverdriveUntil[line] = untilClock
	rs.OverdriveReadyAt[line] = math.max(now + Config.Overdrive.CooldownSeconds, untilClock)
end

local function autoOverdriveAllowed(data: Types.PlayerData): boolean
	return Config.Robots.AutoOverdrive and (data.Tutorial.Done or data.Tutorial.Step > OVERDRIVE_STEP)
end

--------------------------------------------------------------------------------
-- Production tick
--------------------------------------------------------------------------------
local function tickPlayer(player: Player, data: Types.PlayerData, dt: number, now: number)
	local rs = RuntimeState.Get(player)
	local state = stateFor(player)
	syncRobots(player, data, state)

	local multiplier = MultiplierService.Get(player)
	local productionMult = MultiplierService.GetProductionMult(player)
	local lineCount = #data.Lines
	local lastLine = #Config.Lines
	local autoOverdrive = autoOverdriveAllowed(data)

	local income = 0
	local shipped = 0
	local rocketsShipped = 0
	local runtimeLines = {}

	for k = 1, lineCount do
		local levels = data.Lines[k]
		local robot = robotOnLine(data, k)
		if robot and autoOverdrive and (rs.OverdriveUntil[k] or 0) <= now and (rs.OverdriveReadyAt[k] or 0) <= now then
			startOverdrive(player, k, now)
		end
		local overdriveLeft = math.max(0, (rs.OverdriveUntil[k] or 0) - now)
		local output = Formulas.LineOutput(levels, {
			RobotBonus = if robot then Config.Robots.SpeedBonus else 0,
			Overdrive = if overdriveLeft > 0 then Config.Overdrive.Multiplier else 1,
			ProductionMult = productionMult,
		})
		rs.LineOutputs[k] = output
		local perSecond = Formulas.Clamp(
			output
				* Formulas.LineValue(k)
				* (1 + Formulas.PackagingBonus(data.Packaging[Formulas.LineHall(k)] or 1))
				* multiplier
		)
		income += perSecond

		local carry = (state.Carry[k] or 0) + output * dt
		local whole = math.floor(carry)
		state.Carry[k] = carry - whole
		state.ValueCarry[k] = (state.ValueCarry[k] or 0) + perSecond * dt
		if whole > 0 then
			ServerSignals.Produced:Fire(player, k, whole, state.ValueCarry[k])
			state.ValueCarry[k] = 0
			shipped += whole
			if k == lastLine then
				rocketsShipped += whole
			end
		end

		table.insert(runtimeLines, {
			Output = output,
			Bottleneck = Formulas.BottleneckStage(levels),
			OverdriveLeft = overdriveLeft,
			CooldownLeft = math.max(0, (rs.OverdriveReadyAt[k] or 0) - now),
			Robot = robot,
		})
	end
	for k = #rs.LineOutputs, lineCount + 1, -1 do
		rs.LineOutputs[k] = nil
	end
	income = Formulas.Clamp(income)
	rs.IncomePerSecond = income

	-- Vault capacity is a number of seconds of income.
	local capacitySeconds = if data.Tutorial.Done
		then Formulas.VaultCapacitySeconds(data.VaultTier, MultiplierService.GetVaultBonus(player))
		else Config.Vault.TutorialCapacitySeconds
	local capacity = capacitySeconds * income
	rs.VaultCapacity = capacity

	local produced = income * dt
	if PassService.Owns(player, "AutoCollect") then
		CurrencyService.AddCash(player, produced, "Production")
		CurrencyService.CollectVault(player)
	else
		CurrencyService.DepositVault(player, produced, capacity)
	end

	if shipped > 0 then
		StatsService.Increment(player, "ProductsShipped", shipped)
	end
	if rocketsShipped > 0 then
		local before = data.Stats.RocketsShipped
		StatsService.Increment(player, "RocketsShipped", rocketsShipped)
		if
			math.floor((before + rocketsShipped) / Config.World.RocketLaunchEvery)
			> math.floor(before / Config.World.RocketLaunchEvery)
		then
			Remote.FireAll("Effect", "Rocket", { UserId = player.UserId })
		end
	end

	for operatorId, pulledAt in rs.Operators do
		if now - pulledAt > Config.Social.OperatorTimeoutSeconds then
			rs.Operators[operatorId] = nil
		end
	end

	Remote.Fire("RuntimeState", player, {
		Income = income,
		Multiplier = multiplier,
		VaultCapacity = capacity,
		Discount = MultiplierService.GetUpgradeDiscount(player),
		Lines = runtimeLines,
		Operators = SocialBonusService.GetOperatorCount(player),
		Robots = #data.RobotAssignments,
		OfflineCapHours = MultiplierService.GetOfflineCapHours(player),
		Abilities = MultiplierService.GetAbilities(player),
	})
end

local function tickAll(dt: number)
	local now = os.clock()
	for _, player in DataService.GetLoadedPlayers() do
		local data = DataService.Get(player)
		if data then
			local ok, err = protect(tickPlayer, player, data, dt, now)
			if not ok then
				warn(string.format("[FactoryService] tick failed for %s: %s", player.Name, tostring(err)))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function FactoryService.GetIncome(player: Player): number
	return RuntimeState.Get(player).IncomePerSecond
end

function FactoryService.GetLineOutput(player: Player, line: number): number
	return RuntimeState.Get(player).LineOutputs[line] or 0
end

function FactoryService.ResetRun(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Cash = Config.Expansion.StartingCash
	data.Vault = 0
	data.RunEarnings = 0
	data.Lines = { table.create(STAGE_COUNT, 1) }
	data.Packaging = table.create(#Config.Halls, 1)
	data.VaultTier = 1
	data.RobotAssignments = table.create(#data.RobotAssignments, 0)

	local rs = RuntimeState.Get(player)
	table.clear(rs.OverdriveUntil)
	table.clear(rs.OverdriveReadyAt)
	table.clear(rs.LineOutputs)
	local state = stateFor(player)
	table.clear(state.Carry)
	table.clear(state.ValueCarry)
	state.NeedAssign = true

	for _, key in { "Cash", "Vault", "RunEarnings", "Lines", "Packaging", "VaultTier", "RobotAssignments" } do
		DataService.MarkDirty(player, key)
	end
	refreshStamps(player, data)
	ServerSignals.LinesChanged:Fire(player, 1)
end

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------
local function levelMilestone(player: Player, line: number, oldLevel: number, newLevel: number)
	local every = Config.Economy.MilestoneEvery
	local crossed = math.floor(newLevel / every)
	if crossed > math.floor(oldLevel / every) then
		Remote.Fire("Effect", player, "LevelMilestone", { Line = line, Level = crossed * every })
	end
end

local function handleBuyLine(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	local line = #data.Lines + 1
	if line > Formulas.LineCount() then
		return false, "All production lines built"
	end
	if line > Formulas.MaxLineForExpansions(data.Expansions) then
		return false, "Expand to unlock the next industry"
	end
	if not CurrencyService.SpendCash(player, Formulas.LineUnlockCost(line)) then
		return false, "Not enough cash"
	end
	table.insert(data.Lines, table.create(STAGE_COUNT, 1))
	stateFor(player).NeedAssign = true
	DataService.MarkDirty(player, "Lines")
	refreshStamps(player, data)
	ServerSignals.LinesChanged:Fire(player, line)
	ServerSignals.TutorialAction:Fire(player, "LineBought")
	Remote.Fire("Effect", player, "LineBuilt", { Line = line })
	return true, nil, { Line = line }
end

local function handleUpgradeStage(player: Player, lineArg: any, stageArg: any, countArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	local line = Guard.Integer(lineArg, 1, #data.Lines)
	local stage = Guard.Integer(stageArg, 1, STAGE_COUNT)
	local count = Guard.Integer(countArg, 0, Config.Economy.MaxBulkLevels)
	if line == nil or stage == nil or count == nil or not table.find(Config.UI.BulkBuyOptions, count) then
		return false, "Invalid upgrade"
	end
	local levels = data.Lines[line]
	local level = levels[stage]
	if level >= Config.Economy.MaxStageLevel then
		return false, "Already at max level"
	end
	local discount = MultiplierService.GetUpgradeDiscount(player)
	local n: number
	if count == 0 then
		n = Formulas.MaxAffordableLevels(line, stage, level, CurrencyService.GetCash(player), discount)
	else
		n = math.min(count, Config.Economy.MaxStageLevel - level)
	end
	if n <= 0 then
		return false, "Not enough cash"
	end
	local cost = Formulas.BulkUpgradeCost(line, stage, level, n, discount)
	if not CurrencyService.SpendCash(player, cost) then
		return false, "Not enough cash"
	end
	levels[stage] = level + n
	DataService.MarkDirty(player, "Lines")
	StatsService.Increment(player, "UpgradesBought", n)
	if not data.Tutorial.Done then
		data.Tutorial.Upgrades += n
		DataService.MarkDirty(player, "Tutorial")
	end
	levelMilestone(player, line, level, level + n)
	refreshStamps(player, data)
	ServerSignals.LinesChanged:Fire(player, line)
	ServerSignals.TutorialAction:Fire(player, "Upgrade")
	return true, nil, { Line = line, Stage = stage, Level = level + n, Count = n }
end

local function handleOverdrive(player: Player, lineArg: any, hostArg: any): (boolean, string?, any?)
	local line = Guard.Integer(lineArg, 1, Formulas.LineCount())
	if line == nil then
		return false, "Invalid line"
	end
	local hostId: number? = nil
	if hostArg ~= nil then
		hostId = Guard.Integer(hostArg, 1, MAX_USER_ID)
		if hostId == nil then
			return false, "Invalid host"
		end
	end
	local now = os.clock()

	if hostId == nil or hostId == player.UserId then
		local data = DataService.Get(player)
		if not data or line > #data.Lines then
			return false, "Build this line first"
		end
		local rs = RuntimeState.Get(player)
		if (rs.OverdriveReadyAt[line] or 0) > now then
			return false, "Lever is cooling down"
		end
		startOverdrive(player, line, now)
		StatsService.Increment(player, "OverdriveUsed", 1)
		ServerSignals.TutorialAction:Fire(player, "Overdrive")
		return true
	end

	local host = Players:GetPlayerByUserId(hostId)
	local hostData = if host then DataService.Get(host) else nil
	if not host or not hostData or not DataService.IsLoaded(host) then
		return false, "That factory is not in this server"
	end
	if line > #hostData.Lines then
		return false, "That line is not built yet"
	end
	if (RuntimeState.Get(host).OverdriveReadyAt[line] or 0) > now then
		return false, "Lever is cooling down"
	end
	local ok, err = SocialBonusService.RegisterOperatorPull(player, host, line)
	if not ok then
		return false, err or "You can't operate this lever"
	end
	startOverdrive(host, line, now)
	return true
end

local function handleCollectVault(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data or data.Vault <= 0 then
		return false, "Vault is empty"
	end
	if not PassService.Owns(player, "AutoCollect") then
		local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
		local vaultPosition = PlotService.GetVaultPosition(player)
		if not root or not root:IsA("BasePart") or not vaultPosition then
			return false, "Vault not available"
		end
		if (root.Position - vaultPosition).Magnitude > Config.Vault.CollectDistance then
			return false, "Move closer to your vault"
		end
	end
	local amount = CurrencyService.CollectVault(player)
	if amount <= 0 then
		return false, "Vault is empty"
	end
	StatsService.Increment(player, "VaultCollected", 1)
	Remote.Fire("Effect", player, "VaultCollected", { Amount = amount })
	ServerSignals.TutorialAction:Fire(player, "VaultCollected")
	return true, nil, { Amount = amount }
end

local function handleBuyPackaging(player: Player, hallArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	local hall = Guard.Integer(hallArg, 1, #Config.Halls)
	if hall == nil or not Formulas.HallUnlocked(hall, data.Expansions) then
		return false, "Industry not unlocked"
	end
	local tier = data.Packaging[hall] or 1
	if tier >= #Config.Packaging.Bonus then
		return false, "Packaging is maxed"
	end
	if not CurrencyService.SpendCash(player, Formulas.PackagingCost(hall, tier + 1)) then
		return false, "Not enough cash"
	end
	data.Packaging[hall] = tier + 1
	DataService.MarkDirty(player, "Packaging")
	return true, nil, { Hall = hall, Tier = tier + 1 }
end

local function handleBuyVault(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	if data.VaultTier >= #Config.Vault.CapacityMinutes then
		return false, "Vault is maxed"
	end
	local nextTier = data.VaultTier + 1
	if not CurrencyService.SpendCash(player, Formulas.VaultCost(nextTier, Formulas.HighestHall(data.Expansions))) then
		return false, "Not enough cash"
	end
	data.VaultTier = nextTier
	DataService.MarkDirty(player, "VaultTier")
	return true, nil, { Tier = nextTier }
end

local function handleAssignRobot(player: Player, robotArg: any, lineArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	local robot = Guard.Integer(robotArg, 1, robotCount(player, data))
	local line = Guard.Integer(lineArg, 0, #data.Lines)
	if robot == nil or line == nil then
		return false, "Invalid robot assignment"
	end
	if line ~= 0 then
		local taken = 0
		for i, assigned in data.RobotAssignments do
			if assigned == line and i ~= robot then
				taken += 1
			end
		end
		if taken >= Config.Robots.MaxPerLine then
			return false, "That line already has a robot"
		end
	end
	data.RobotAssignments[robot] = line
	DataService.MarkDirty(player, "RobotAssignments")
	return true
end

function FactoryService.Init()
	Remote.Handle("BuyLine", handleBuyLine)
	Remote.Handle("UpgradeStage", handleUpgradeStage)
	Remote.Handle("Overdrive", handleOverdrive)
	Remote.Handle("CollectVault", handleCollectVault)
	Remote.Handle("BuyPackaging", handleBuyPackaging)
	Remote.Handle("BuyVault", handleBuyVault)
	Remote.Handle("AssignRobot", handleAssignRobot)
end

local function onLoaded(player: Player, data: Types.PlayerData)
	local state = stateFor(player)
	state.NeedAssign = true
	syncRobots(player, data, state)
	refreshStamps(player, data)
end

function FactoryService.Start()
	DataService.Loaded:Connect(onLoaded)
	DataService.Releasing:Connect(function(player: Player)
		states[player] = nil
	end)
	for _, player in DataService.GetLoadedPlayers() do
		local data = DataService.Get(player)
		if data then
			onLoaded(player, data)
		end
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Economy.TickSeconds)
			local now = os.clock()
			local dt = math.min(now - last, Config.Economy.MaxTickSeconds)
			last = now
			tickAll(dt)
		end
	end)
end

return FactoryService

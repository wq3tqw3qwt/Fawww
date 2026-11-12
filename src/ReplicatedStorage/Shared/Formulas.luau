--!strict
--[[
	Formulas: pure economy math shared by server, client UI and the pacing simulation.
	No Roblox services are used here so the module runs under Lune for tests and the sim.
]]

local Config = require(script.Parent.Config)

local Formulas = {}

local Economy = Config.Economy
local LOG_G = math.log(Economy.UpgradeGrowth)

local function clampNumber(x: number): number
	if x ~= x then
		return 0
	end
	if x > Economy.NumberCeiling then
		return Economy.NumberCeiling
	end
	return x
end
Formulas.Clamp = clampNumber

--------------------------------------------------------------------------------
-- Lines & halls
--------------------------------------------------------------------------------
function Formulas.LineCount(): number
	return #Config.Lines
end

function Formulas.LineHall(k: number): number
	local def = Config.Lines[k]
	return if def then def.Hall else math.ceil(k / Config.LinesPerHall)
end

function Formulas.HallFirstLine(hall: number): number
	return (hall - 1) * Config.LinesPerHall + 1
end

function Formulas.HallUnlocked(hall: number, expansions: number): boolean
	local def = Config.Halls[hall]
	return def ~= nil and expansions >= def.UnlockExpansions
end

function Formulas.HighestHall(expansions: number): number
	local best = 1
	for i, def in Config.Halls do
		if expansions >= def.UnlockExpansions then
			best = i
		end
	end
	return best
end

function Formulas.MaxLineForExpansions(expansions: number): number
	return Formulas.HighestHall(expansions) * Config.LinesPerHall
end

function Formulas.LineValue(k: number): number
	return clampNumber(Economy.ValueBase * Economy.ValueRatio ^ (k - 1))
end

function Formulas.LineUnlockCost(k: number): number
	if k <= 1 then
		return 0
	end
	local hall = Formulas.LineHall(k)
	local mult = Economy.HallCostMult[hall] or 1
	return clampNumber(Economy.CostBase * Economy.CostRatio ^ (k - 2) * mult)
end

--------------------------------------------------------------------------------
-- Stages
--------------------------------------------------------------------------------
function Formulas.StageSpeed(level: number): number
	if level <= 0 then
		return 0
	end
	return level * Economy.MilestoneMult ^ math.floor(level / Economy.MilestoneEvery)
end

-- Cost of the upgrade from `level` to `level + 1`.
function Formulas.StageUpgradeCost(k: number, stage: number, level: number, discount: number?): number
	local base = Formulas.LineValue(k) * Economy.UpgradeBaseSeconds * Economy.StageWeights[stage]
	local d = math.clamp(discount or 0, 0, 0.9)
	return clampNumber(base * Economy.UpgradeGrowth ^ (level - 1) * (1 - d))
end

-- Total cost of buying `n` levels starting at `level` (geometric series).
function Formulas.BulkUpgradeCost(k: number, stage: number, level: number, n: number, discount: number?): number
	if n <= 0 then
		return 0
	end
	local first = Formulas.StageUpgradeCost(k, stage, level, discount)
	local g = Economy.UpgradeGrowth
	return clampNumber(first * (g ^ n - 1) / (g - 1))
end

-- Largest n such that BulkUpgradeCost(n) <= cash, capped by `cap`.
function Formulas.MaxAffordableLevels(
	k: number,
	stage: number,
	level: number,
	cash: number,
	discount: number?,
	cap: number?
): number
	local first = Formulas.StageUpgradeCost(k, stage, level, discount)
	if first <= 0 or cash < first then
		return 0
	end
	local g = Economy.UpgradeGrowth
	local n = math.floor(math.log(cash * (g - 1) / first + 1) / LOG_G)
	-- Guard against floating point edge cases.
	while n > 0 and Formulas.BulkUpgradeCost(k, stage, level, n, discount) > cash do
		n -= 1
	end
	local limit = math.min(cap or Economy.MaxBulkLevels, Economy.MaxStageLevel - level)
	return math.clamp(n, 0, math.max(limit, 0))
end

-- Index (1..4) of the slowest stage; ties resolve to the cheapest stage to upgrade.
function Formulas.BottleneckStage(levels: { number }): number
	local best = 1
	for i = 2, #levels do
		local li, lb = levels[i], levels[best]
		if li < lb or (li == lb and Economy.StageWeights[i] < Economy.StageWeights[best]) then
			best = i
		end
	end
	return best
end

function Formulas.LineMinLevel(levels: { number }): number
	local m = math.huge
	for _, l in levels do
		m = math.min(m, l)
	end
	return if m == math.huge then 0 else m
end

export type LineModifiers = {
	RobotBonus: number?, -- e.g. 0.25 when a robot is assigned
	Overdrive: number?, -- multiplier while Overdrive is active (1 otherwise)
	ProductionMult: number?, -- e.g. Turbo Conveyors 1.3
}

-- Products per second for a line.
function Formulas.LineOutput(levels: { number }, mods: LineModifiers?): number
	local m: LineModifiers = mods or {}
	local slowest = math.huge
	for _, l in levels do
		slowest = math.min(slowest, Formulas.StageSpeed(l))
	end
	if slowest == math.huge then
		return 0
	end
	return clampNumber(slowest * (1 + (m.RobotBonus or 0)) * (m.Overdrive or 1) * (m.ProductionMult or 1))
end

--------------------------------------------------------------------------------
-- Packaging & vault
--------------------------------------------------------------------------------
function Formulas.PackagingBonus(tier: number): number
	return Config.Packaging.Bonus[tier] or 0
end

function Formulas.PackagingCost(hall: number, tier: number): number
	if tier <= 1 then
		return 0
	end
	return clampNumber(Formulas.LineUnlockCost(Formulas.HallFirstLine(hall) + tier) * Config.Packaging.CostMult)
end

function Formulas.VaultCapacitySeconds(tier: number, bigVaultBonus: number?): number
	local minutes = Config.Vault.CapacityMinutes[tier] or Config.Vault.CapacityMinutes[1]
	return minutes * 60 * (1 + (bigVaultBonus or 0))
end

function Formulas.VaultCost(tier: number, highestHall: number): number
	if tier <= 1 then
		return 0
	end
	return Formulas.LineUnlockCost(Formulas.HallFirstLine(highestHall) + tier - 1 + Config.Vault.CostLineOffset)
end

--------------------------------------------------------------------------------
-- Expansion, Shares, Franchise
--------------------------------------------------------------------------------
function Formulas.SharesTotal(franchiseLifetime: number): number
	local e = Config.Expansion
	if franchiseLifetime <= 0 then
		return 0
	end
	return math.floor(e.SharesK * (franchiseLifetime / e.SharesDivisor) ^ e.SharesExponent)
end

function Formulas.SharesMultiplier(shares: number): number
	return 1 + Config.Expansion.BonusPerShare * shares
end

-- Run earnings needed to perform Expansion number n (1-based).
function Formulas.ExpansionRequirement(n: number): number
	local tbl = Config.Expansion.RequirementTable
	if n <= #tbl then
		return tbl[math.max(n, 1)]
	end
	local last = tbl[#tbl]
	return clampNumber(last * Config.Expansion.BeyondGrowth ^ (n - #tbl))
end

function Formulas.CanExpand(expansions: number, runEarnings: number): boolean
	if expansions >= Config.Expansion.MaxExpansions then
		return false
	end
	return runEarnings >= Formulas.ExpansionRequirement(expansions + 1)
end

function Formulas.CanFranchise(expansions: number): boolean
	return expansions >= Config.Franchise.UnlockExpansions
end

function Formulas.FranchiseMultiplier(level: number): number
	return 1 + Config.Franchise.MultPerLevel * level
end

local function countAtOrBelow(list: { number }, value: number): number
	local n = 0
	for _, v in list do
		if value >= v then
			n += 1
		end
	end
	return n
end

function Formulas.BaysFor(expansions: number, hasPass: boolean, researchBays: number): number
	local e = Config.Expansion
	return e.BaysBase
		+ countAtOrBelow(e.BaysAtExpansions, expansions)
		+ (if hasPass then e.BaysPassBonus else 0)
		+ researchBays
end

function Formulas.RobotsFor(expansions: number, hasPass: boolean): number
	local r = Config.Robots
	return r.BaseCount + countAtOrBelow(r.BonusAtExpansions, expansions) + (if hasPass then r.PassBonus else 0)
end

--------------------------------------------------------------------------------
-- Machines
--------------------------------------------------------------------------------
local machineById: { [string]: Config.MachineDef } = {}
for _, def in Config.Machines do
	machineById[def.Id] = def
end

function Formulas.GetMachine(id: string): Config.MachineDef?
	return machineById[id]
end

function Formulas.MachinePower(def: Config.MachineDef, grade: number): number
	return def.Power * (Config.MachineGrades.PowerMult[grade + 1] or 1)
end

export type Price = { Currency: "Cash" | "Credits", Amount: number }

-- Shop price for a machine, or nil when it cannot be bought directly.
function Formulas.MachinePrice(def: Config.MachineDef): Price?
	local shop = Config.MachineShop
	if def.Hall < 1 then
		return nil
	end
	if def.Source == "Shop" then
		local lineNo = if def.Rarity == "Common" then shop.CommonCostLine else shop.RareCostLine
		return { Currency = "Cash", Amount = Formulas.LineUnlockCost(Formulas.HallFirstLine(def.Hall) + lineNo - 1) }
	elseif def.Source == "Credits" then
		local base = if def.Rarity == "Legendary" then shop.LegendaryCredits else shop.EpicCredits
		return { Currency = "Credits", Amount = base * 2 ^ (def.Hall - 1) }
	end
	return nil
end

export type EquippedMachine = { Id: string, Grade: number }

-- Sum of machine Power (percent) and capped ability totals for the equipped set.
function Formulas.MachineTotals(equipped: { EquippedMachine }, rushActive: boolean): (number, { [string]: number })
	local power = 0
	local abilities: { [string]: number } = {}
	local hasRushHour = false
	for _, m in equipped do
		local def = machineById[m.Id]
		if def then
			power += Formulas.MachinePower(def, m.Grade)
			local ability = def.Ability
			if ability then
				if ability.Kind == "RushHour" then
					hasRushHour = true
				else
					abilities[ability.Kind] = (abilities[ability.Kind] or 0) + ability.Value
				end
			end
		end
	end
	for kind, value in abilities do
		local cap = Config.AbilityCaps[kind]
		if cap then
			abilities[kind] = math.min(value, cap)
		end
	end
	if hasRushHour then
		abilities.RushHour = 1
		if rushActive then
			power *= 2
		end
	end
	return power, abilities
end

--------------------------------------------------------------------------------
-- Income multiplier composition
--------------------------------------------------------------------------------
export type MultiplierParts = {
	Shares: number,
	MachinePowerPct: number,
	CatalogBonus: number,
	ResearchIncome: number,
	OperatorCount: number,
	TeamworkBonus: number,
	Premium: boolean,
	InGroup: boolean,
	VIP: boolean,
	Cash2xPass: boolean,
	BoostMult: number, -- product of active timed boosts
	WeekendActive: boolean,
	FranchiseLevel: number,
	CashBurst: number,
}

-- Small social/meta boosts add together; big boosts multiply. Documented in docs/03-architecture.md.
function Formulas.IncomeMultiplier(p: MultiplierParts): number
	local s = Config.Social
	local operators = math.min(p.OperatorCount, s.MaxOperators)
	local additive = 1
		+ (if p.Premium then Config.Premium.IncomeBonus else 0)
		+ (if p.InGroup then s.GroupBonus else 0)
		+ (if p.VIP then Config.PassEffects.VIPIncomeBonus else 0)
		+ operators * s.OperatorBonusPerOperator
		+ (if operators > 0 then p.TeamworkBonus else 0)
		+ p.CatalogBonus
		+ p.ResearchIncome
		+ p.CashBurst
	local mult = additive
		* Formulas.SharesMultiplier(p.Shares)
		* (1 + p.MachinePowerPct / 100)
		* (if p.Cash2xPass then Config.PassEffects.Cash2xMult else 1)
		* p.BoostMult
		* (if p.WeekendActive then Config.Events.Weekend.CashMult else 1)
		* Formulas.FranchiseMultiplier(p.FranchiseLevel)
	return clampNumber(mult)
end

--------------------------------------------------------------------------------
-- Catalog
--------------------------------------------------------------------------------
function Formulas.StampLevel(minStageLevel: number, owned: boolean): number
	if not owned then
		return 0
	end
	local s = 0
	for i, threshold in Config.Catalog.Thresholds do
		if minStageLevel >= threshold then
			s = i
		end
	end
	return s
end

function Formulas.CatalogBonus(stamps: { number }): number
	local bonus = 0
	local cat = Config.Catalog
	for _, s in stamps do
		for i = 1, math.min(s, #cat.Bonus) do
			bonus += cat.Bonus[i]
		end
	end
	for hall = 1, #Config.Halls do
		local first = Formulas.HallFirstLine(hall)
		local allGold = true
		for k = first, first + Config.LinesPerHall - 1 do
			if (stamps[k] or 0) < 3 then
				allGold = false
				break
			end
		end
		if allGold then
			bonus += cat.HallGoldBonus
		end
	end
	return bonus
end

--------------------------------------------------------------------------------
-- Research
--------------------------------------------------------------------------------
function Formulas.ResearchCost(def: Config.ResearchDef, currentLevel: number): number
	return math.floor(def.BaseCredits * def.CostGrowth ^ currentLevel + 0.5)
end

function Formulas.ResearchDuration(def: Config.ResearchDef, labRat: number): number
	return math.floor(def.DurationSeconds * (1 - math.clamp(labRat, 0, Config.AbilityCaps.LabRat)))
end

--------------------------------------------------------------------------------
-- Offline earnings
--------------------------------------------------------------------------------
-- Returns (cash, creditedSeconds).
function Formulas.OfflineEarnings(
	secondsAway: number,
	incomePerSecond: number,
	capHours: number,
	efficiency: number
): (number, number)
	if secondsAway < Config.Offline.MinSeconds or incomePerSecond <= 0 then
		return 0, 0
	end
	local credited = math.min(secondsAway, capHours * 3600)
	return clampNumber(credited * incomePerSecond * efficiency), credited
end

function Formulas.OfflineCapHours(researchHours: number, hasPass: boolean): number
	local base = Config.Offline.BaseCapHours + researchHours
	return if hasPass then base * Config.Offline.PassCapMult else base
end

--------------------------------------------------------------------------------
-- Contracts
--------------------------------------------------------------------------------
function Formulas.ContractTarget(outputPerSecond: number, tier: Config.ContractTierDef): number
	return math.max(Config.Contracts.MinTarget, math.floor(outputPerSecond * tier.TargetSeconds))
end

function Formulas.ContractCashReward(
	incomePerSecond: number,
	tier: Config.ContractTierDef,
	contractPro: number,
	researchBonus: number,
	rushActive: boolean
): number
	local mult = (1 + contractPro + researchBonus)
		* (if rushActive then Config.Events.RushOrders.ContractRewardMult else 1)
	return clampNumber(incomePerSecond * tier.RewardIncomeMinutes * 60 * mult)
end

--------------------------------------------------------------------------------
-- Time helpers (UTC)
--------------------------------------------------------------------------------
export type UtcParts = { wday: number, hour: number, min: number }

function Formulas.IsWeekend(t: UtcParts): boolean
	local w = Config.Events.Weekend
	if t.wday == w.StartWday then
		return t.hour >= w.StartHour
	end
	-- Saturday through the configured end day (Sunday).
	return t.wday == 7 or t.wday == w.EndWday
end

-- Returns (active, secondsLeft).
function Formulas.RushState(t: UtcParts, sec: number?): (boolean, number)
	local r = Config.Events.RushOrders
	local nowMin = t.hour * 60 + t.min
	for _, h in r.UtcHours do
		local startMin = h * 60
		if nowMin >= startMin and nowMin < startMin + r.DurationMinutes then
			return true, (startMin + r.DurationMinutes - nowMin) * 60 - (sec or 0)
		end
	end
	return false, 0
end

function Formulas.DayNumber(unix: number): number
	return math.floor(unix / 86400)
end

-- ISO-8601 week key such as "2026W46".
function Formulas.WeekKey(unix: number): string
	local days = math.floor(unix / 86400)
	-- 1970-01-01 was a Thursday. ISO weekday: Monday = 1 ... Sunday = 7.
	local weekday = ((days + 3) % 7) + 1
	local thursday = days - weekday + 4
	-- Civil-from-days (Howard Hinnant) to get the year of that Thursday.
	local z = thursday + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local m = mp + (if mp < 10 then 3 else -9)
	if m <= 2 then
		y += 1
	end
	-- Days from Jan 1 of year y to the Thursday.
	local function daysFromCivil(year: number, month: number, day: number): number
		local yy = if month <= 2 then year - 1 else year
		local e = math.floor(yy / 400)
		local yoe2 = yy - e * 400
		local mm = if month > 2 then month - 3 else month + 9
		local doy2 = math.floor((153 * mm + 2) / 5) + day - 1
		local doe2 = yoe2 * 365 + math.floor(yoe2 / 4) - math.floor(yoe2 / 100) + doy2
		return e * 146097 + doe2 - 719468
	end
	local week = math.floor((thursday - daysFromCivil(y, 1, 1)) / 7) + 1
	return string.format("%dW%02d", y, week)
end

--------------------------------------------------------------------------------
-- Leaderboard encoding (OrderedDataStore only stores integers)
--------------------------------------------------------------------------------
-- stored = floor(log10(x + 1) * LogScale): 0 stays 0 and order is preserved.
function Formulas.EncodeLog(x: number): number
	if x <= 0 then
		return 0
	end
	return math.floor(math.log10(x + 1) * Config.Leaderboards.LogScale)
end

function Formulas.DecodeLog(v: number): number
	if v <= 0 then
		return 0
	end
	return 10 ^ (v / Config.Leaderboards.LogScale) - 1
end

return Formulas

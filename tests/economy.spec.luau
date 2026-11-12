local Loader = require("./lib/loader")
local T = require("./lib/testkit")
local describe, it, expect = T.describe, T.it, T.expect

local Config = Loader.require("src/ReplicatedStorage/Shared/Config")
local F = Loader.require("src/ReplicatedStorage/Shared/Formulas")
local NumberFormat = Loader.require("src/ReplicatedStorage/Shared/NumberFormat")

describe("Economy formulas", function()
	it("product value grows by ValueRatio per line", function()
		expect(F.LineValue(1)).toBe(2)
		expect(F.LineValue(2)).toBe(14)
		expect(F.LineValue(6)).toBe(2 * 7 ^ 5)
	end)

	it("line unlock costs follow CostBase * CostRatio^(k-2) * hall premium", function()
		expect(F.LineUnlockCost(1)).toBe(0)
		expect(F.LineUnlockCost(2)).toBe(250 * Config.Economy.HallCostMult[1])
		expect(F.LineUnlockCost(3)).toBe(3750 * Config.Economy.HallCostMult[1])
		local k = 7
		expect(F.LineUnlockCost(k)).toBeCloseTo(250 * 15 ^ (k - 2) * Config.Economy.HallCostMult[2])
	end)

	it("line costs strictly increase across all 30 lines", function()
		for k = 2, #Config.Lines do
			expect(F.LineUnlockCost(k)).toBeGreaterThan(F.LineUnlockCost(k - 1))
		end
	end)

	it("stage speed doubles at each 25-level milestone", function()
		expect(F.StageSpeed(0)).toBe(0)
		expect(F.StageSpeed(1)).toBe(1)
		expect(F.StageSpeed(24)).toBe(24)
		expect(F.StageSpeed(25)).toBe(50)
		expect(F.StageSpeed(50)).toBe(200)
		expect(F.StageSpeed(100)).toBe(1600)
	end)

	it("first Nails upgrade costs about $6 (tutorial beat)", function()
		local cheapest = math.huge
		for stage = 1, 4 do
			cheapest = math.min(cheapest, F.StageUpgradeCost(1, stage, 1))
		end
		expect(cheapest).toBeCloseTo(6.4)
	end)

	it("bulk cost equals the sum of single upgrades", function()
		local sum = 0
		for i = 0, 9 do
			sum += F.StageUpgradeCost(3, 2, 17 + i)
		end
		expect(F.BulkUpgradeCost(3, 2, 17, 10)).toBeCloseTo(sum, 1e-9)
	end)

	it("discount reduces upgrade cost proportionally", function()
		expect(F.StageUpgradeCost(2, 1, 10, 0.2)).toBeCloseTo(F.StageUpgradeCost(2, 1, 10) * 0.8)
	end)

	it("max affordable levels never exceed the cash available", function()
		for _, cash in { 5, 100, 12345, 9.9e9, 1e30 } do
			local n = F.MaxAffordableLevels(4, 3, 12, cash)
			expect(F.BulkUpgradeCost(4, 3, 12, n)).toBeAtMost(cash)
			if n < Config.Economy.MaxBulkLevels then
				expect(F.BulkUpgradeCost(4, 3, 12, n + 1)).toBeGreaterThan(cash)
			end
		end
	end)

	it("line output is limited by the slowest stage (bottleneck)", function()
		expect(F.LineOutput({ 30, 10, 40, 50 })).toBe(10)
		expect(F.BottleneckStage({ 30, 10, 40, 50 })).toBe(2)
		-- Ties pick the cheapest stage (Conveyor weight 0.8).
		expect(F.BottleneckStage({ 5, 5, 5, 5 })).toBe(1)
	end)

	it("robots, overdrive and production multipliers stack on output", function()
		local out = F.LineOutput({ 10, 10, 10, 10 }, { RobotBonus = 0.25, Overdrive = 3, ProductionMult = 1.3 })
		expect(out).toBeCloseTo(10 * 1.25 * 3 * 1.3)
	end)

	it("income multiplier: additive social bucket, multiplicative big boosts", function()
		local m = F.IncomeMultiplier({
			Shares = 25,
			MachinePowerPct = 100,
			CatalogBonus = 0,
			ResearchIncome = 0,
			OperatorCount = 3, -- capped to 2
			TeamworkBonus = 0,
			Premium = true,
			InGroup = true,
			VIP = false,
			Cash2xPass = true,
			BoostMult = 1,
			WeekendActive = false,
			FranchiseLevel = 1,
			CashBurst = 0,
		})
		local additive = 1 + 0.10 + 0.05 + 2 * 0.25
		expect(m).toBeCloseTo(additive * (1 + 0.04 * 25) * 2 * 2 * 2)
	end)

	it("packaging and vault costs are positive and increasing", function()
		for tier = 3, #Config.Packaging.Bonus do
			expect(F.PackagingCost(1, tier)).toBeGreaterThan(F.PackagingCost(1, tier - 1))
		end
		expect(F.VaultCapacitySeconds(1)).toBe(600)
		expect(F.VaultCapacitySeconds(5, 0.5)).toBe(5400)
		expect(F.VaultCost(2, 1)).toBeGreaterThan(0)
	end)

	it("catalog bonus sums stamp bonuses and adds the hall Gold bonus", function()
		local stamps = table.create(#Config.Lines, 0)
		stamps[1] = 1
		expect(F.CatalogBonus(stamps)).toBeCloseTo(0.01)
		for k = 1, 6 do
			stamps[k] = 3
		end
		expect(F.CatalogBonus(stamps)).toBeCloseTo(6 * 0.08 + 0.10)
		expect(F.StampLevel(120, true)).toBe(3)
		expect(F.StampLevel(500, false)).toBe(0)
	end)
end)

describe("Number formatting and leaderboard encoding", function()
	it("formats compact numbers", function()
		expect(NumberFormat.Short(999)).toBe("999")
		expect(NumberFormat.Short(1234)).toBe("1.23K")
		expect(NumberFormat.Short(12.7e6)).toBe("12.7M")
		expect(NumberFormat.Short(3.79e6)).toBe("3.79M")
		expect(NumberFormat.Cash(1e9)).toBe("$1.00B")
		expect(NumberFormat.Duration(3725)).toBe("1h 02m")
		expect(NumberFormat.Commas(1200)).toBe("1,200")
	end)

	it("log encoding round-trips huge numbers within 0.001%", function()
		for _, x in { 1, 2, 1234.5, 1e15, 4.33e31, 1e300 } do
			local encoded = F.EncodeLog(x)
			expect(encoded == math.floor(encoded)).toBeTruthy()
			expect(F.DecodeLog(encoded)).toBeCloseTo(x, 1e-5)
		end
		expect(F.EncodeLog(0)).toBe(0)
		expect(F.EncodeLog(1e300)).toBeLessThan(2 ^ 53)
	end)
end)

describe("Calendar helpers (UTC)", function()
	it("computes ISO week keys", function()
		expect(F.WeekKey(1794441600)).toBe("2026W46") -- 2026-11-12
		expect(F.WeekKey(1609632000)).toBe("2020W53") -- 2021-01-03
		expect(F.WeekKey(1735516800)).toBe("2025W01") -- 2024-12-30
	end)

	it("detects the weekend window Fri 18:00 - Sun 23:59", function()
		expect(F.IsWeekend({ wday = 6, hour = 17, min = 59 })).toBeFalsy()
		expect(F.IsWeekend({ wday = 6, hour = 18, min = 0 })).toBeTruthy()
		expect(F.IsWeekend({ wday = 7, hour = 3, min = 0 })).toBeTruthy()
		expect(F.IsWeekend({ wday = 1, hour = 23, min = 59 })).toBeTruthy()
		expect(F.IsWeekend({ wday = 2, hour = 0, min = 0 })).toBeFalsy()
	end)

	it("detects Rush Orders windows", function()
		local active, left = F.RushState({ wday = 3, hour = 12, min = 5 }, 0)
		expect(active).toBeTruthy()
		expect(left).toBe(600)
		expect((F.RushState({ wday = 3, hour = 12, min = 15 }))).toBeFalsy()
	end)
end)

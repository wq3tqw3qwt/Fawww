local Loader = require("./lib/loader")
local T = require("./lib/testkit")
local describe, it, expect = T.describe, T.it, T.expect

local Config = Loader.require("src/ReplicatedStorage/Shared/Config")
local F = Loader.require("src/ReplicatedStorage/Shared/Formulas")

describe("Expansion and Shares math", function()
	it("Shares = floor(25 * (lifetime / 1e9)^0.2)", function()
		expect(F.SharesTotal(0)).toBe(0)
		expect(F.SharesTotal(1e9)).toBe(25)
		expect(F.SharesTotal(32e9)).toBe(50)
		expect(F.SharesTotal(1e19)).toBe(math.floor(25 * 1e10 ^ 0.2))
	end)

	it("each Share adds 4% income", function()
		expect(F.SharesMultiplier(25)).toBeCloseTo(2)
		expect(F.SharesMultiplier(0)).toBe(1)
	end)

	it("requirement table is strictly increasing and continues beyond the table", function()
		local tbl = Config.Expansion.RequirementTable
		for n = 2, #tbl do
			expect(F.ExpansionRequirement(n)).toBeGreaterThan(F.ExpansionRequirement(n - 1))
		end
		local last = #tbl
		expect(F.ExpansionRequirement(last + 1)).toBeCloseTo(tbl[last] * Config.Expansion.BeyondGrowth)
		expect(F.ExpansionRequirement(Config.Expansion.MaxExpansions)).toBeLessThan(1e300)
	end)

	it("CanExpand respects the requirement and the cap", function()
		local req = F.ExpansionRequirement(1)
		expect(F.CanExpand(0, req - 1)).toBeFalsy()
		expect(F.CanExpand(0, req)).toBeTruthy()
		expect(F.CanExpand(Config.Expansion.MaxExpansions, 1e300)).toBeFalsy()
	end)

	it("halls unlock at Expansions 0, 1, 3, 6, 10", function()
		expect(F.HighestHall(0)).toBe(1)
		expect(F.HighestHall(1)).toBe(2)
		expect(F.HighestHall(2)).toBe(2)
		expect(F.HighestHall(3)).toBe(3)
		expect(F.HighestHall(6)).toBe(4)
		expect(F.HighestHall(10)).toBe(5)
		expect(F.MaxLineForExpansions(0)).toBe(6)
		expect(F.MaxLineForExpansions(10)).toBe(30)
	end)

	it("bays and robots grow with Expansions and passes", function()
		expect(F.BaysFor(0, false, 0)).toBe(3)
		expect(F.BaysFor(10, false, 0)).toBe(7)
		expect(F.BaysFor(10, true, 1)).toBe(10)
		expect(F.RobotsFor(0, false)).toBe(1)
		expect(F.RobotsFor(8, true)).toBe(6)
	end)

	it("Franchise (endgame) unlocks at 12 Expansions and multiplies income", function()
		expect(F.CanFranchise(11)).toBeFalsy()
		expect(F.CanFranchise(12)).toBeTruthy()
		expect(F.FranchiseMultiplier(0)).toBe(1)
		expect(F.FranchiseMultiplier(3)).toBe(4)
	end)
end)

describe("Machine catalog balance", function()
	it("has 40+ machines with unique ids across 6 rarities plus specials", function()
		local seen = {}
		local rarities = {}
		for _, def in Config.Machines do
			expect(seen[def.Id]).toBe(nil)
			seen[def.Id] = true
			rarities[def.Rarity] = true
		end
		expect(#Config.Machines).toBeGreaterThan(40)
		for _, r in { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" } do
			expect(rarities[r]).toBeTruthy()
		end
	end)

	it("no Secret machine outperforms the Legendary of the same hall", function()
		for _, secret in Config.Machines do
			if secret.Rarity == "Secret" then
				local legendaryPower = nil
				for _, def in Config.Machines do
					if def.Rarity == "Legendary" and def.Hall == secret.Hall then
						legendaryPower = def.Power
					end
				end
				expect(legendaryPower ~= nil).toBeTruthy()
				expect(secret.Power).toBeLessThan(legendaryPower)
			end
		end
	end)

	it("grades multiply power x1 / x2 / x4", function()
		local def = F.GetMachine("titan_forge")
		expect(F.MachinePower(def, 0)).toBe(150)
		expect(F.MachinePower(def, 1)).toBe(300)
		expect(F.MachinePower(def, 2)).toBe(600)
	end)

	it("prices: Common/Rare cost cash, Epic/Legendary cost Credits, others not sold", function()
		local common = F.MachinePrice(F.GetMachine("rivet_bot"))
		expect(common.Currency).toBe("Cash")
		expect(common.Amount).toBe(F.LineUnlockCost(3))
		local legendary = F.MachinePrice(F.GetMachine("mainframe_prime"))
		expect(legendary.Currency).toBe("Credits")
		expect(legendary.Amount).toBe(1600)
		expect(F.MachinePrice(F.GetMachine("cloud_maker"))).toBe(nil)
		expect(F.MachinePrice(F.GetMachine("infinity_belt"))).toBe(nil)
	end)

	it("ability totals are capped and RushHour doubles power only during Rush Orders", function()
		local equipped = {
			{ Id = "titan_forge", Grade = 2 }, -- Bargain 0.05
			{ Id = "assembly_arm_x", Grade = 0 }, -- Bargain 0.05
			{ Id = "atomic_assembler", Grade = 2 }, -- Bargain 0.10 -> total 0.20 (cap 0.20)
			{ Id = "turbo_press", Grade = 0 }, -- RushHour
		}
		local power, abilities = F.MachineTotals(equipped, false)
		expect(abilities.Bargain).toBeCloseTo(0.20)
		expect(abilities.RushHour).toBe(1)
		local rushPower = F.MachineTotals(equipped, true)
		expect(rushPower).toBeCloseTo(power * 2)
	end)
end)

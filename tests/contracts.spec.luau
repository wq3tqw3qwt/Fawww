local Loader = require("./lib/loader")
local T = require("./lib/testkit")
local describe, it, expect = T.describe, T.it, T.expect

local Config = Loader.require("src/ReplicatedStorage/Shared/Config")
local Odds = Loader.require("src/ReplicatedStorage/Shared/ContractOdds")

-- Deterministic linear congruential generator in [0, 1).
local function lcg(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function constant(x: number): () -> number
	return function()
		return x
	end
end

describe("Contract odds", function()
	it("disclosed odds sum to exactly 100%", function()
		for _, tier in Config.Contracts.TierOrder do
			local total = 0
			for _, line in Odds.DisplayOdds(tier) do
				total += line.Chance
			end
			expect(total).toBeCloseTo(1)
		end
	end)

	it("lowest roll gives the rarest blueprint, highest roll gives none", function()
		expect(Odds.Roll("Gold", 0, constant(0)).Rarity).toBe("Legendary")
		expect(Odds.Roll("Gold", 0, constant(0.03)).Rarity).toBe("Epic")
		expect(Odds.Roll("Gold", 0, constant(0.2)).Rarity).toBe("Rare")
		expect(Odds.Roll("Gold", 0, constant(0.9999)).Rarity).toBe(nil)
		expect(Odds.Roll("Bronze", 0, constant(0.02)).Rarity).toBe("Rare")
		expect(Odds.Roll("Bronze", 0, constant(0.5)).Rarity).toBe(nil)
	end)

	it("Gold pity guarantees a Legendary on the 40th completion and resets", function()
		local pity = 0
		local never = constant(0.9999)
		for _ = 1, 39 do
			local r = Odds.Roll("Gold", pity, never)
			expect(r.Rarity).toBe(nil)
			pity = r.GoldSinceLegendary
		end
		expect(pity).toBe(39)
		local r = Odds.Roll("Gold", pity, never)
		expect(r.Rarity).toBe("Legendary")
		expect(r.PityTriggered).toBeTruthy()
		expect(r.GoldSinceLegendary).toBe(0)
	end)

	it("a natural Legendary resets pity; Bronze never touches pity", function()
		expect(Odds.Roll("Gold", 17, constant(0)).GoldSinceLegendary).toBe(0)
		expect(Odds.Roll("Bronze", 17, constant(0.5)).GoldSinceLegendary).toBe(17)
	end)

	it("observed frequencies match disclosed odds (200k seeded rolls)", function()
		local rng = lcg(42)
		local counts = { Legendary = 0, Epic = 0, Rare = 0, None = 0 }
		local n = 200000
		for _ = 1, n do
			-- Pity is disabled here (counter stays 0) to measure raw odds.
			local r = Odds.Roll("Gold", -1e9, rng)
			local key = r.Rarity or "None"
			counts[key] += 1
		end
		expect(counts.Legendary / n).toBeCloseTo(0.02, 0.15)
		expect(counts.Epic / n).toBeCloseTo(0.08, 0.05)
		expect(counts.Rare / n).toBeCloseTo(0.25, 0.03)
	end)

	it("blueprints become a machine of that rarity from the player's highest hall", function()
		local rng = lcg(7)
		for hall = 1, 5 do
			for _, rarity in { "Rare", "Epic", "Legendary" } do
				local id = Odds.PickMachine(rarity, hall, rng)
				expect(id ~= nil).toBeTruthy()
				local found = nil
				for _, def in Config.Machines do
					if def.Id == id then
						found = def
					end
				end
				expect(found.Rarity).toBe(rarity)
				expect(found.Hall).toBe(hall)
			end
		end
	end)

	it("tier refill weights are 60/30/10", function()
		local rng = lcg(99)
		local counts = { Bronze = 0, Silver = 0, Gold = 0 }
		for _ = 1, 100000 do
			counts[Odds.PickTier(rng)] += 1
		end
		expect(counts.Bronze / 100000).toBeCloseTo(0.6, 0.03)
		expect(counts.Silver / 100000).toBeCloseTo(0.3, 0.05)
		expect(counts.Gold / 100000).toBeCloseTo(0.1, 0.08)
	end)
end)

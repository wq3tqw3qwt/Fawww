--!strict
--[[
	ContractOdds: blueprint drops for FREE contract rewards (never purchasable).
	Odds are disclosed in the Contracts UI via DisplayOdds(). The rng is injected
	so tests are deterministic; the server passes a Random-based function.
]]

local Config = require(script.Parent.Config)

local ContractOdds = {}

export type RollResult = {
	Rarity: string?, -- nil = no blueprint this time
	GoldSinceLegendary: number, -- updated pity counter
	PityTriggered: boolean,
}

export type OddsLine = { Label: string, Chance: number }

-- Rolls a blueprint for one completed contract of `tierName`.
-- `goldSinceLegendary` counts Gold completions since the last Legendary blueprint.
function ContractOdds.Roll(tierName: string, goldSinceLegendary: number, rng: () -> number): RollResult
	local tier = Config.Contracts.Tiers[tierName]
	assert(tier, "unknown contract tier " .. tostring(tierName))

	local pity = goldSinceLegendary
	if tier.PityLegendary then
		pity += 1
		if pity >= tier.PityLegendary then
			return { Rarity = "Legendary", GoldSinceLegendary = 0, PityTriggered = true }
		end
	end

	local roll = rng()
	local cumulative = 0
	for _, entry in tier.Odds do
		cumulative += entry.Chance
		if roll < cumulative then
			if entry.Rarity == "Legendary" then
				pity = 0
			end
			return { Rarity = entry.Rarity, GoldSinceLegendary = pity, PityTriggered = false }
		end
	end
	return { Rarity = nil, GoldSinceLegendary = pity, PityTriggered = false }
end

-- Human-readable odds for the UI, including the "no blueprint" remainder.
function ContractOdds.DisplayOdds(tierName: string): { OddsLine }
	local tier = Config.Contracts.Tiers[tierName]
	local lines: { OddsLine } = {}
	local total = 0
	for _, entry in tier.Odds do
		table.insert(lines, { Label = entry.Rarity .. " blueprint", Chance = entry.Chance })
		total += entry.Chance
	end
	table.insert(lines, { Label = "Credits and cash only", Chance = math.max(0, 1 - total) })
	return lines
end

-- Machines a blueprint of `rarity` can become for a player whose highest hall is `hall`.
function ContractOdds.BlueprintPool(rarity: string, hall: number): { string }
	local pool = {}
	for _, def in Config.Machines do
		if def.Rarity == rarity and def.Hall == hall and (def.Source == "Shop" or def.Source == "Credits") then
			table.insert(pool, def.Id)
		end
	end
	return pool
end

-- Uniform pick from the pool (disclosed as "equal chance for each machine of that rarity").
function ContractOdds.PickMachine(rarity: string, hall: number, rng: () -> number): string?
	local pool = ContractOdds.BlueprintPool(rarity, hall)
	if #pool == 0 then
		return nil
	end
	local index = math.clamp(math.floor(rng() * #pool) + 1, 1, #pool)
	return pool[index]
end

-- Weighted tier choice when refilling a contract slot.
function ContractOdds.PickTier(rng: () -> number): string
	local total = 0
	for _, name in Config.Contracts.TierOrder do
		total += Config.Contracts.Tiers[name].Weight
	end
	local roll = rng() * total
	local acc = 0
	for _, name in Config.Contracts.TierOrder do
		acc += Config.Contracts.Tiers[name].Weight
		if roll < acc then
			return name
		end
	end
	return Config.Contracts.TierOrder[1]
end

return ContractOdds

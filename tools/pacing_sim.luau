--[[
	Factory Empire pacing simulation.

	Runs the real economy code (src/ReplicatedStorage/Shared/Formulas + Config) with a
	greedy "optimal" player and reports how long each Expansion takes.

	Usage (from the repository root):
		lune run tools/pacing_sim                 -- simulate with the current Config
		lune run tools/pacing_sim -- --fit        -- fit Expansion requirements to target run lengths
		lune run tools/pacing_sim -- --franchise  -- also simulate the first Franchise cycle
		lune run tools/pacing_sim -- --timeline   -- print the first-run line unlock timeline

	See tools/README.md for the model, assumptions and the parameters to tune.
]]

local process = require("@lune/process")
local Loader = require("../tests/lib/loader")

local Config = Loader.require("src/ReplicatedStorage/Shared/Config")
local F = Loader.require("src/ReplicatedStorage/Shared/Formulas")
local NumberFormat = Loader.require("src/ReplicatedStorage/Shared/NumberFormat")

local args = {}
for _, a in process.args do
	args[a] = true
end

local Sim = Config.Sim

type RunResult = {
	seconds: number,
	earned: number,
	incomeAtEnd: number,
	events: { { t: number, text: string } },
	finished: boolean,
}

local function emptyParts(shares: number, franchise: number)
	return {
		Shares = shares,
		MachinePowerPct = 0,
		CatalogBonus = 0,
		ResearchIncome = 0,
		OperatorCount = 0,
		TeamworkBonus = 0,
		Premium = false,
		InGroup = false,
		VIP = false,
		Cash2xPass = false,
		BoostMult = 1,
		WeekendActive = false,
		FranchiseLevel = franchise,
		CashBurst = 0,
	}
end

-- Cost to raise every stage of line k from level L to L+1 (the player upgrades the bottleneck
-- repeatedly, which in steady state keeps all four stages level).
local function lineLevelCost(k: number, level: number): number
	local total = 0
	for stage = 1, 4 do
		total += F.StageUpgradeCost(k, stage, level)
	end
	return total
end

-- Simulates one run (from a fresh factory) until `target` run earnings.
local function simulateRun(
	expansions: number,
	shares: number,
	franchise: number,
	target: number,
	maxSeconds: number
): RunResult
	local mult = F.IncomeMultiplier(emptyParts(shares, franchise)) * Sim.CollectionEfficiency
	local maxLine = F.MaxLineForExpansions(expansions)
	local levels = { 1 }
	local cash = Config.Expansion.StartingCash
	local earned = 0
	local t = 0
	local events = {}

	local function income(): number
		local total = 0
		for k, level in levels do
			total += F.LineValue(k) * F.StageSpeed(level)
		end
		return total * mult
	end

	local inc = income()
	while t < maxSeconds do
		-- Spend greedily.
		while true do
			local nextLine = #levels + 1
			local bought = false
			if nextLine <= maxLine then
				local cost = F.LineUnlockCost(nextLine)
				if cash >= cost then
					cash -= cost
					levels[nextLine] = 1
					table.insert(events, {
						t = t,
						text = string.format(
							"Line %d (%s) cost %s, income %s/s",
							nextLine,
							Config.Lines[nextLine].Name,
							NumberFormat.Cash(cost),
							NumberFormat.Cash(inc)
						),
					})
					inc = income()
					bought = true
				elseif cost <= inc * Sim.SaveForLineSeconds then
					break -- save up for the next line
				end
			end
			if not bought then
				local bestK, bestRatio, bestCost = 0, 0, 0
				for k, level in levels do
					local cost = lineLevelCost(k, level)
					if cost <= cash then
						local gain = F.LineValue(k) * (F.StageSpeed(level + 1) - F.StageSpeed(level))
						local ratio = gain / cost
						if ratio > bestRatio then
							bestK, bestRatio, bestCost = k, ratio, cost
						end
					end
				end
				if bestK == 0 then
					break
				end
				cash -= bestCost
				levels[bestK] += 1
				inc = income()
			end
		end
		cash += inc * Sim.TickSeconds
		earned += inc * Sim.TickSeconds
		t += Sim.TickSeconds
		if earned >= target then
			return { seconds = t, earned = earned, incomeAtEnd = inc, events = events, finished = true }
		end
	end
	return { seconds = t, earned = earned, incomeAtEnd = inc, events = events, finished = false }
end

type CycleRow = {
	n: number,
	target: number,
	sharesBefore: number,
	mult: number,
	sharesAfter: number,
	minutes: number,
	cumulative: number,
	hall: number,
}

local function runCycle(franchise: number, count: number, requirement: (number) -> number): { CycleRow }
	local rows = {}
	local lifetime = 0
	local cumulative = 0
	for n = 1, count do
		local shares = F.SharesTotal(lifetime)
		local target = requirement(n)
		local result = simulateRun(n - 1, shares, franchise, target, Sim.MaxRunMinutes * 60)
		lifetime += result.earned
		cumulative += result.seconds
		table.insert(rows, {
			n = n,
			target = target,
			sharesBefore = shares,
			mult = F.SharesMultiplier(shares) * F.FranchiseMultiplier(franchise),
			sharesAfter = F.SharesTotal(lifetime),
			minutes = result.seconds / 60,
			cumulative = cumulative / 3600,
			hall = F.HighestHall(n - 1),
		})
		if not result.finished then
			print(string.format("  ! E%d did not finish within %d minutes", n, Sim.MaxRunMinutes))
			break
		end
	end
	return rows
end

local function printRows(title: string, rows: { CycleRow })
	print("\n" .. title)
	print(
		"| Expansion | Run earnings needed | Shares before | Income mult before | Shares after | Run length (min) | Cumulative (h) | Floors open |"
	)
	print("|---|---|---|---|---|---|---|---|")
	for _, r in rows do
		print(
			string.format(
				"| E%d | %s | %d | x%s | %d | %.1f | %.2f | %d |",
				r.n,
				NumberFormat.Cash(r.target),
				r.sharesBefore,
				NumberFormat.Short(r.mult),
				r.sharesAfter,
				r.minutes,
				r.cumulative,
				r.hall
			)
		)
	end
end

-- Fits RequirementTable so that run n lasts TargetFirstRunMinutes * TargetRunGrowth^(n-1).
local function fit(): { number }
	local fitted = {}
	local lifetime = 0
	local count = #Config.Expansion.RequirementTable
	for n = 1, count do
		local targetSeconds = Sim.TargetFirstRunMinutes * 60 * Sim.TargetRunGrowth ^ (n - 1)
		local shares = F.SharesTotal(lifetime)
		local lo = math.log10(math.max(fitted[n - 1] or 1e6, 1e6))
		local hi = lo + Sim.FitSearchOrders
		local best: RunResult? = nil
		for _ = 1, Sim.FitIterations do
			local mid = (lo + hi) / 2
			local result = simulateRun(n - 1, shares, 0, 10 ^ mid, targetSeconds + 60)
			if result.finished and result.seconds <= targetSeconds then
				lo = mid
				best = result
			else
				hi = mid
			end
		end
		-- Round to 3 significant digits for a readable Config.
		local value = tonumber(string.format("%.3g", 10 ^ lo)) :: number
		fitted[n] = value
		local result = simulateRun(n - 1, shares, 0, value, Sim.MaxRunMinutes * 60)
		lifetime += result.earned
		print(
			string.format(
				"  E%-2d target %5.1f min -> requirement %s (sim %.1f min)",
				n,
				targetSeconds / 60,
				string.format("%.3g", value),
				result.seconds / 60
			)
		)
		local _ = best
	end
	return fitted
end

local requirement = F.ExpansionRequirement

if args["--fit"] then
	print(
		"Fitting Expansion requirements (first run "
			.. Sim.TargetFirstRunMinutes
			.. " min, growth x"
			.. Sim.TargetRunGrowth
			.. " per Expansion)..."
	)
	local fitted = fit()
	local parts = {}
	for _, v in fitted do
		table.insert(parts, string.format("%.3g", v))
	end
	print("\nPaste into Config.Expansion.RequirementTable:\n\t{ " .. table.concat(parts, ", ") .. " }")
	local last, prev = fitted[#fitted], fitted[#fitted - 1]
	print(string.format("Suggested BeyondGrowth (last ratio): %.3g", last / prev))
	requirement = function(n: number): number
		return fitted[n] or F.ExpansionRequirement(n)
	end
end

if args["--timeline"] or not args["--fit"] then
	local first = simulateRun(0, 0, 0, requirement(1), Sim.MaxRunMinutes * 60)
	print("\nFirst run timeline (greedy player, collection efficiency " .. Sim.CollectionEfficiency .. ")")
	print("| Time | Event |")
	print("|---|---|")
	for _, e in first.events do
		print(string.format("| %d:%02d | %s |", e.t // 60, e.t % 60, e.text))
	end
	print(
		string.format(
			"| %d:%02d | **Expansion 1 ready** (run earnings %s, income %s/s) |",
			first.seconds // 60,
			first.seconds % 60,
			NumberFormat.Cash(first.earned),
			NumberFormat.Cash(first.incomeAtEnd)
		)
	)
end

local total = math.min(Config.Expansion.MaxExpansions, Config.Franchise.UnlockExpansions)
local rows = runCycle(0, total, requirement)
printRows("Expansion cycle (Franchise 0)", rows)

if args["--franchise"] then
	local cycles = { { level = 0, hours = rows[#rows].cumulative } }
	for level = 1, Config.Sim.FranchiseCycles do
		local franchiseRows = runCycle(level, Config.Franchise.UnlockExpansions, requirement)
		printRows(
			string.format(
				"Franchise %d (x%s permanent income)",
				level,
				NumberFormat.Short(F.FranchiseMultiplier(level))
			),
			franchiseRows
		)
		table.insert(cycles, { level = level, hours = franchiseRows[#franchiseRows].cumulative })
	end
	print("\nEndgame loop: hours per Franchise cycle (E1 -> E" .. Config.Franchise.UnlockExpansions .. ")")
	print("| Franchise level | Cycle length (h) |")
	print("|---|---|")
	for _, c in cycles do
		print(string.format("| %d | %.2f |", c.level, c.hours))
	end
end

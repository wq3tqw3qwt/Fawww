# Tools: pacing simulation

`tools/pacing_sim.luau` runs the **real game economy code**
(`src/ReplicatedStorage/Shared/Formulas.luau` and `Config.luau`, loaded via the Lune shim in
`tests/lib/loader.luau`) with a simulated player. Change a number in `Config.luau`, re-run the
simulation, and see the pacing impact immediately. Nothing is duplicated between the game and the sim.

## Run it

Install the toolchain once (see the root README), then from the repository root:

```bash
lune run tools/pacing_sim                         # first-run timeline + Expansion table with current Config
lune run tools/pacing_sim -- --franchise          # also simulate the first Franchise cycle (endgame)
lune run tools/pacing_sim -- --fit                # re-fit Config.Expansion.RequirementTable to target run lengths
lune run tools/pacing_sim -- --fit --franchise    # both (slow: ~20-40 min)
```

`--fit` prints a new `RequirementTable` and a suggested `BeyondGrowth`; paste them into
`Config.Expansion` and run the plain simulation again to confirm.

## Model

| Aspect | What the sim does | Game equivalent |
|---|---|---|
| Player | Greedy and always online: buys the next line as soon as affordable, saves for it when it costs ≤ `Config.Sim.SaveForLineSeconds` of income, otherwise buys the upgrade with the best income gain per cash | A focused player who keeps upgrading the bottleneck |
| Line levels | All four stages of a line rise together (one "line level" costs the sum of the four stage upgrades) | The UI always points at the bottleneck stage, so stages stay level |
| Income | `Σ LineValue(k) × StageSpeed(level)` × `Formulas.IncomeMultiplier` (Shares + Franchise only) × `Config.Sim.CollectionEfficiency` | Production tick in `FactoryService` |
| Expansion | Run ends when run earnings reach `Formulas.ExpansionRequirement(n)`; Shares = `Formulas.SharesTotal(lifetime earnings)` | `ExpansionService` |
| Halls | Lines available = `Formulas.MaxLineForExpansions(expansions)` | Floors unlock at E1/E3/E6/E10 |

**Not modelled** (all make a real player faster): Overdrive levers, robots, contracts, specialist
machines, catalog stamps, research, packaging, passes and boosts. **Also not modelled** (makes a real
player slower): idle time, sub-optimal choices, Vault collection delays. The simulated times are
therefore a *focused-player baseline*, not a promise; confirm with playtests and analytics (Stage 6).

## Parameters to tune

| Config key | Effect on pacing |
|---|---|
| `Economy.ValueRatio`, `Economy.CostRatio` | Gap between lines. Cost/Value ratio > 1 makes each new line slower than the last |
| `Economy.CostBase`, `Economy.HallCostMult[h]` | When lines (and each new floor) become affordable |
| `Economy.UpgradeBaseSeconds`, `Economy.UpgradeGrowth` | Cost of levels; growth controls how quickly levels stop paying off |
| `Economy.MilestoneEvery`, `Economy.MilestoneMult` | Speed doubling every 25 levels (big dopamine beats) |
| `Expansion.RequirementTable`, `Expansion.BeyondGrowth` | Run length per Expansion (fit with `--fit`) |
| `Expansion.SharesK`, `SharesExponent`, `BonusPerShare` | Power of each Expansion; a higher exponent makes later runs *shorter* |
| `Franchise.UnlockExpansions`, `Franchise.MultPerLevel` | Endgame loop length and reward |
| `Sim.TargetFirstRunMinutes`, `Sim.TargetRunGrowth` | Targets used by `--fit` (29 min first run, +6% per Expansion) |
| `Sim.CollectionEfficiency`, `Sim.SaveForLineSeconds` | Player-behaviour assumptions |
| `Sim.FitSearchOrders`, `Sim.FitIterations` | Fit search range/precision (speed vs accuracy) |

## Output

`docs/01-design.md` contains the output of the current Config, produced by
`lune run tools/pacing_sim -- --franchise`. Re-run and update it whenever you change the economy.

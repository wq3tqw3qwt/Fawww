# Stage 1: Design Document — Factory Empire: Idle Tycoon

Grow a tiny workshop into a global industrial empire: raw ore → parts → components → finished
products → rockets. Idle tycoon with production chains, contracts and prestige. All numbers below
come from `src/ReplicatedStorage/Shared/Config.luau`; pacing tables are **real output** of
`tools/pacing_sim.luau` (see section 3).

**Changes since the chat version of Stage 1:** pacing numbers replaced by simulation output; run
lengths smoothed (every Expansion now takes longer than the previous one in the first cycle);
endgame loop added (Franchise, repeatable forever); Secret machines rebalanced below the Legendary
of their floor; update cadence changed from weekly to **every 2 weeks**; platform assumptions marked
**VERIFY**.

## Theme and genre

- **Theme: "Toybox Industrial" + a vertical signature.** Chunky bevelled low-poly machines, one clean
  colour per industry and per level tier. The plot grows **upward**, one floor per industry
  (Metalworks → Electronics → Automobiles → Aviation → Aerospace roof). Rockets launch from the roof
  and are visible to the whole server.
- **Genre: idle tycoon** (fixed). Twists: vertical factory with public rocket launches, deterministic
  secret recipes, friends operating each other's lines, and **no paid randomness anywhere**.

## 1. Name, tagline, store page, genre

| Option | Verdict |
|---|---|
| **Factory Empire: Idle Tycoon** ✅ | Contains "factory", "idle", "tycoon" (highest-volume terms) plus the "empire" fantasy |
| Build a Factory! | Trendy pattern, weaker keywords |
| Idle Factory Tycoon 🚀 | Searchable but generic |
| Rocket Factory Tycoon | Gives away the endgame |
| Conveyor Kingdom | Low search volume |

- Launch title: `[🚀] Factory Empire: Idle Tycoon` (update tag changes every update; emoji rules **VERIFY**).
- Tagline: "From one tiny smelter to rockets in space. 🏭→🚀"
- Genre: Simulation → Tycoon (**VERIFY** current subgenre list). Maturity target: Minimal.

```
Build a tiny workshop into a GLOBAL FACTORY EMPIRE! 🏭
⚙️ Upgrade machines, speed up conveyors and fix bottlenecks
📦 Turn raw ore into gears, chips, cars, jets… and ROCKETS 🚀
📋 Complete contracts for huge payouts and rare machines
🔁 Expand for Shares, unlock 5 industries, then Franchise forever
🤝 Friends can operate your factory – you BOTH earn more!
🔍 Discover SECRET recipes in the R&D Lab
💤 Earn cash even while offline!
🎁 Like + Favorite for codes! Try: FACTORY
New update every 2 weeks!
```

## 2. Core loop and reward moments

| Timescale | Player action | Reward moment |
|---|---|---|
| 10 s | Tap the red-ringed **bottleneck** stage; pull an **Overdrive** lever (×3 for 20 s, 60 s cooldown) | Belt speeds up, truck honks, "+$" pops; "×2 SPEED!" at levels 25/50/75/100 |
| 5 min | Build the next line, finish a Bronze contract, collect the Vault | Machines drop in and bounce; contract stamp; cash rain |
| 30 min | **Expansion** to the next floor, Gold contract, R&D discovery | Building rises; "SHARES +25 → ×2 income" |
| Session (target 25 min) | Daily reward, 3 quests, contract refills, Rush Order, Supply Drop | Quest chest, blueprint drop, rocket launch |
| Week | Weekly quests, community goal, Weekend Rush | Mythic of the week, leaderboard titles |

```
Line = 4 stages: Conveyor → Processor → Assembler → Packer
Stage speed(L)      = L × 2^floor(L/25)
Line output/s       = min(stage speeds)  × (1 + robot) × Overdrive × Turbo Conveyors
Income/s            = Σ output × ProductValue × (1 + packaging) × Multiplier
Multiplier          = (1 + Premium + Group + VIP + operators + catalog + research + CashBurst)
                      × (1 + 0.04·Shares) × (1 + machine Power%) × 2x pass × boosts × weekend × (1 + Franchise)
Stage upgrade cost  = ProductValue × 4 × weight × 1.10^(L−1)   (weights 0.8 / 1.0 / 1.2 / 0.9)
```

Cash flows into the **Vault** (10–60 min of income); collect it with the pad or HUD button, or own
Auto-Collect. Vault cash counts toward Expansion only when collected; purchased cash never counts.

## 3. Progression (real simulation output)

**Floors and lines** — value `2·7^(k−1)`, unlock cost `250·15^(k−2)`:

| Floor | Unlock | Lines | Value range | Line cost range |
|---|---|---|---|---|
| 1 Metalworks | start | Nails, Pipes, Gears, Wrenches, Steel Beams, Engine Blocks | $2 → $33.6K | free → $12.7M |
| 2 Electronics | E1 | Copper Wire, Circuit Board, Microchip, Battery Pack, Smartphone, Robot Arm | $235K → $3.95B | $190M → $144T |
| 3 Automobiles | E3 | Tire, Car Seat, Car Engine, Chassis, Electric Motor, Sports Car | $27.7B → $465T | $2.16Qa → $1.64Sx |
| 4 Aviation | E6 | Propeller, Jet Turbine, Landing Gear, Wing, Cockpit, Jumbo Jet | $3.26Qa → $54.7Qi | $24.6Sx → $18.7Oc |
| 5 Aerospace | E10 | Heat Shield, Rocket Nozzle, Fuel Tank, Satellite, Space Capsule, Rocket | $383Qi → $6.44Sp | $281Oc → $213Dc |

**Expansion:** resets cash, lines, levels, Vault and Packaging; keeps Shares, machines, catalog,
Credits, research, robots, passes. Requirement table fitted by `--fit` so each run lasts
29 min × 1.06^(n−1); Shares `= floor(25 × (lifetime/1e9)^0.2)`, +4% income each. Bays 3 → 7
(+1 at E1/E3/E6/E10), robots 1 → 4 (+1 at E2/E5/E8).

**Endgame — Franchise:** at 12 Expansions the player can Franchise: Expansions, Shares and the run
reset, the player keeps everything else and gains a **permanent ×(1 + level) income multiplier**, 500 ×
level Credits and a title. Franchise repeats forever (Franchise level leaderboard), so the game no
longer ends at ~6 hours. Numbers stay below ~1e40, far from the double limit.

The simulated player is greedy and always online and ignores Overdrive, robots, contracts, machines,
catalog, research and passes (faster in reality) as well as idle time (slower). Expected real time to
Expansion 1: **30–40 minutes**. Within Franchise 0 every run is longer than the previous one; later
Franchise cycles are shorter overall (that is the Franchise reward) with small dips around E9–E10.

**Time to next upgrade (targets):** every 3–10 s in the first 2 minutes, then 15–45 s, then 1–2 min
once all six Metalworks lines are owned; a new line every 2–5 min in run 1.

**Simulation output** (`lune run tools/pacing_sim -- --franchise`, current Config). Check of the
chat-version claim: the original Stage 1 numbers reproduced Expansion 1 at **28:50 (28.8 min)**
exactly; after the smoothing fit and the $10 starting cash for the tutorial it lands at **28:56**.

<!-- BEGIN SIM OUTPUT -->

First run timeline (greedy player, collection efficiency 0.9)
| Time | Event |
|---|---|
| 2:14 | Line 2 (Pipes) cost $250, income $1.8/s |
| 5:17 | Line 3 (Gears) cost $3.75K, income $21.6/s |
| 8:51 | Line 4 (Wrenches) cost $56.2K, income $315/s |
| 13:26 | Line 5 (Steel Beams) cost $843K, income $5.29K/s |
| 18:42 | Line 6 (Engine Blocks) cost $12.6M, income $73.4K/s |
| 28:56 | **Expansion 1 ready** (run earnings $1.04B, income $3.78M/s) |

Expansion cycle (Franchise 0)
| Expansion | Run earnings needed | Shares before | Income mult before | Shares after | Run length (min) | Cumulative (h) | Floors open |
|---|---|---|---|---|---|---|---|
| E1 | $1.04B | 0 | x1 | 25 | 28.9 | 0.48 | 1 |
| E2 | $172B | 25 | x2 | 70 | 31.0 | 1.00 | 2 |
| E3 | $61.4T | 70 | x3.8 | 227 | 32.6 | 1.54 | 2 |
| E4 | $23.9Qa | 227 | x10.1 | 748 | 34.5 | 2.12 | 3 |
| E5 | $10.4Qi | 748 | x30.9 | 2521 | 36.6 | 2.73 | 3 |
| E6 | $13.5Sx | 2521 | x101.8 | 10572 | 38.8 | 3.37 | 3 |
| E7 | $46.5Sp | 10572 | x423.9 | 53886 | 41.1 | 4.06 | 4 |
| E8 | $351Oc | 53886 | x2.15K | 321640 | 43.6 | 4.79 | 4 |
| E9 | $20.7No | 321640 | x12.8K | 729608 | 46.2 | 5.56 | 4 |
| E10 | $106No | 729608 | x29.1K | 1044332 | 49.0 | 6.37 | 4 |
| E11 | $8.77Ud | 1044332 | x41.7K | 9697221 | 51.9 | 7.24 | 5 |
| E12 | $522Ud | 9697221 | x387K | 22028620 | 55.1 | 8.16 | 5 |

Franchise 1 (x2 permanent income)
| Expansion | Run earnings needed | Shares before | Income mult before | Shares after | Run length (min) | Cumulative (h) | Floors open |
|---|---|---|---|---|---|---|---|
| E1 | $1.04B | 0 | x2 | 25 | 18.0 | 0.30 | 1 |
| E2 | $172B | 25 | x4 | 70 | 20.8 | 0.65 | 2 |
| E3 | $61.4T | 70 | x7.6 | 226 | 23.9 | 1.04 | 2 |
| E4 | $23.9Qa | 226 | x20.1 | 748 | 24.1 | 1.45 | 3 |
| E5 | $10.4Qi | 748 | x61.8 | 2529 | 26.7 | 1.89 | 3 |
| E6 | $13.5Sx | 2529 | x204.3 | 10595 | 28.4 | 2.37 | 3 |
| E7 | $46.5Sp | 10595 | x849.6 | 53883 | 32.6 | 2.91 | 4 |
| E8 | $351Oc | 53883 | x4.31K | 321860 | 34.1 | 3.48 | 4 |
| E9 | $20.7No | 321860 | x25.7K | 729781 | 35.4 | 4.07 | 4 |
| E10 | $106No | 729781 | x58.3K | 1044344 | 34.6 | 4.64 | 4 |
| E11 | $8.77Ud | 1044344 | x83.5K | 9702703 | 41.9 | 5.34 | 5 |
| E12 | $522Ud | 9702703 | x776K | 22029855 | 42.6 | 6.05 | 5 |

Franchise 2 (x3 permanent income)
| Expansion | Run earnings needed | Shares before | Income mult before | Shares after | Run length (min) | Cumulative (h) | Floors open |
|---|---|---|---|---|---|---|---|
| E1 | $1.04B | 0 | x3 | 25 | 14.4 | 0.24 | 1 |
| E2 | $172B | 25 | x6 | 70 | 18.4 | 0.55 | 2 |
| E3 | $61.4T | 70 | x11.4 | 227 | 22.3 | 0.92 | 2 |
| E4 | $23.9Qa | 227 | x30.2 | 748 | 25.0 | 1.33 | 3 |
| E5 | $10.4Qi | 748 | x92.8 | 2539 | 25.5 | 1.76 | 3 |
| E6 | $13.5Sx | 2539 | x307.7 | 10608 | 28.2 | 2.23 | 3 |
| E7 | $46.5Sp | 10608 | x1.27K | 53964 | 30.0 | 2.73 | 4 |
| E8 | $351Oc | 53964 | x6.47K | 321875 | 34.8 | 3.31 | 4 |
| E9 | $20.7No | 321875 | x38.6K | 729675 | 30.4 | 3.82 | 4 |
| E10 | $106No | 729675 | x87.5K | 1044691 | 27.6 | 4.28 | 4 |
| E11 | $8.77Ud | 1044691 | x125K | 9702933 | 39.9 | 4.94 | 5 |
| E12 | $522Ud | 9702933 | x1.16M | 22030961 | 36.9 | 5.55 | 5 |

Franchise 3 (x4 permanent income)
| Expansion | Run earnings needed | Shares before | Income mult before | Shares after | Run length (min) | Cumulative (h) | Floors open |
|---|---|---|---|---|---|---|---|
| E1 | $1.04B | 0 | x4 | 25 | 11.9 | 0.20 | 1 |
| E2 | $172B | 25 | x8 | 70 | 17.1 | 0.48 | 2 |
| E3 | $61.4T | 70 | x15.2 | 227 | 19.8 | 0.81 | 2 |
| E4 | $23.9Qa | 227 | x40.3 | 748 | 21.7 | 1.17 | 3 |
| E5 | $10.4Qi | 748 | x123.7 | 2550 | 26.6 | 1.62 | 3 |
| E6 | $13.5Sx | 2550 | x412 | 10629 | 25.7 | 2.05 | 3 |
| E7 | $46.5Sp | 10629 | x1.70K | 53890 | 29.9 | 2.54 | 4 |
| E8 | $351Oc | 53890 | x8.62K | 322098 | 31.9 | 3.08 | 4 |
| E9 | $20.7No | 322098 | x51.5K | 730037 | 28.9 | 3.56 | 4 |
| E10 | $106No | 730037 | x116K | 1044703 | 26.3 | 4.00 | 4 |
| E11 | $8.77Ud | 1044703 | x167K | 9710927 | 37.8 | 4.63 | 5 |
| E12 | $522Ud | 9710927 | x1.55M | 22034664 | 33.8 | 5.19 | 5 |

Endgame loop: hours per Franchise cycle (E1 -> E12)
| Franchise level | Cycle length (h) |
|---|---|
| 0 | 8.16 |
| 1 | 6.05 |
| 2 | 5.55 |
| 3 | 5.19 |
<!-- END SIM OUTPUT -->

## 4. Specialist machines and product catalog (47 machines, 6 rarities + specials)

Machines sit in **Machine Bays** (3 → up to 10) and add Power (% income) to the whole factory;
Epic+ also have a capped ability. **Merging:** 3 identical → Chrome (×2, instant); 3 Chrome →
Gold-Plated (×2, 1 h plating timer). Prices: Common/Rare for cash (the floor's line 3 / line 5
unlock cost), Epic/Legendary for Credits (150 / 800 × 2^(floor−1)).

**Free contract blueprint odds** (disclosed in the Contracts UI; Robux can never roll them):

| Contract | Rare | Epic | Legendary | Pity |
|---|---|---|---|---|
| Bronze (5 min) | 3% | – | – | – |
| Silver (20 min) | 10% | 2% | – | – |
| Gold (60 min) | 25% | 8% | 2% | Legendary guaranteed by the 40th Gold contract |

A blueprint becomes one machine of that rarity from the player's highest floor, equal chance each.

| Floor | Common (Power) | Rare | Epic (ability) | Legendary (ability) |
|---|---|---|---|---|
| Metalworks | Rivet Bot, Bolt Buddy (+10%) | Spark Welder, Steam Hammer (+25%) | Furnace Golem (Night Shift +10), Crane Claw (Big Vault +20%) (+60%) | Titan Forge +150% (Bargain −5%) |
| Electronics | Solder Drone, Chip Sorter (+30%) | Circuit Spider, Laser Etcher (+75%) | Server Tower (Contract Pro +10%), Quantum Tester (Lab Rat −10%) (+180%) | Mainframe Prime +450% (Cash Burst +15%) |
| Automobiles | Wrench Arm, Tire Roller (+90%) | Paint Booth, Torque Bot (+225%) | Crash Tester (Overdrive +5 s), Assembly Arm X (Bargain −5%) (+540%) | Turbo Press +1,350% (Rush Hour) |
| Aviation | Rivet Drone, Wing Sander (+270%) | Wind Tunnel, Jet Balancer (+675%) | Hangar Hauler (Big Vault +30%), Autopilot AI (Teamwork +20%) (+1,620%) | Sky Foundry +4,050% (Night Shift +15) |
| Aerospace | Orbit Bolter, Thermal Tiler (+810%) | Fuel Mixer, Orbital Welder (+2,025%) | Launch Tower (Rush Hour), Zero-G Printer (Lab Rat −10%) (+4,860%) | Star Forge +12,150% (Cash Burst +25%) |

**Mythic** (weekly community goal tier 3 or 10 Mega Contract points): Infinity Belt +3,000%
(Overdrive +10 s), Atomic Assembler +10,000% (Bargain −10%), Gold Rush Refinery +25,000% (Cash Burst
+30%), Quantum Warehouse +60,000% (Big Vault +100%).

**Secret** (deterministic R&D recipes — **rebalanced: each is weaker than its floor's Legendary**,
its value is the unique ability, the collection and the bragging right; enforced by a unit test):

| Secret | Floor | Power | vs Legendary | Ability | Recipe (3 lines, min level) |
|---|---|---|---|---|---|
| Rubber Duck Factory | 1 | +120% | Titan Forge +150% | Teamwork +25% | Nails + Gears + Steel Beams, 75 |
| Pizza Printer | 2 | +400% | Mainframe Prime +450% | Contract Pro +25% | Wrenches + Microchip + Battery Pack, 50 |
| Toaster Rocket | 4 | +3,600% | Sky Foundry +4,050% | Rush Hour | Smartphone + Electric Motor + Jet Turbine, 50 |
| Cloud Maker | 5 | +11,000% | Star Forge +12,150% | Night Shift +30 | Steel Beams + Propeller + Heat Shield, 50 |

**Specials** (not tradable): Founder Bot, Group Gizmo, Buddy Bot (1 invite), Party Crane (5 invites),
Streak Steamer (14-day streak), Loyalty Locomotive (30-day streak), Golden Robot (VIP pass).
All 47 machines are built procedurally from Parts (`ServerStorage/Builders/MachineModelBuilder`).

**Product catalog:** each of the 30 products earns stamps Bronze (owned) / Silver (level 50) /
Gold (100) / Diamond (200) worth +1/+2/+5/+10% income and 5/10/25/50 Credits; all six lines of a
floor at Gold add +10%. Secrets and seasonal products show as "???" until found / "Vaulted" after.

## 5. Social systems

- **Plots:** 8 per server; your rocket launches are visible to everyone.
- **Operators:** a visiting friend pulls your Overdrive levers; you get +25% per operator (max 2);
  after 5 minutes the operator earns a 15-minute +25% Apprentice boost on their own economy.
- **Trading:** earned machines only (no specials, no pass items, no currency), up to 6 per side,
  two-sided Ready → 3 s countdown → Confirm, server re-validates and swaps atomically, unique ids,
  trade log, 30 s cooldown, lopsided-trade warning, account ≥ 3 days and ≥ 20 min playtime,
  disabled where `PolicyService` disallows paid item trading (**VERIFY**).
- **Boost gifting:** 2x Cash boosts can be bought for a friend in the server.
- **Leaderboards:** Richest Factory, Most Products Shipped, Highest Industry (Franchise × 1000 +
  Expansions), weekly board (ISO week); log-encoded for OrderedDataStore.
- **Group:** +5% income, Group Gizmo, chat tag (set `Config.GroupId`). **Corporations (clans)**
  ship in the day-30 update.
- **Invites:** referral via join data (**VERIFY**) after 5 minutes of play: Buddy Bot (1), 1 h 2x
  Cash (3), Party Crane (5), "Tycoon Recruiter" title (10).
- **Co-op Mega Contracts:** 2–4 players, personal targets sized to each player, 30 minutes,
  1 point each; 10 points = Mythic of the week.
- **Weekly global goal:** all-server contract counter in MemoryStore (**VERIFY** quotas); tiers
  5,000 / 25,000 / 100,000 → 100 Credits / 24 h +25% / Mythic of the week (min 3 personal contracts).

## 6. First 3 minutes (implemented by TutorialService + TutorialController)

| Time | Beat | Reward |
|---|---|---|
| 0–10 s | Spawn inside your plot, Nails line already running; Beam arrow + red ring on the bottleneck, one word "TAP" | First upgrade ≈ $6, belt speeds up |
| 10–40 s | Welcome Crate $100; 5 upgrades, the ring jumps to the new bottleneck | Learn the puzzle without reading |
| 40–70 s | Vault fills (20 s tutorial capacity) → arrow to Vault/COLLECT | Coin fountain |
| 70–120 s | Tutorial contract "Make 50 Nails" | $250 + 10 Credits = exactly Line 2 (Pipes) |
| 120–150 s | Overdrive lever "HOLD" | ×3 for 20 s |
| 150–180 s | Free Rivet Bot into Bay 1; quest tracker; one-time "Friends = +25% 👥 [Invite]" | Clear next goal |

No offers or daily popups until the tutorial is done; a small Skip button is always available.

## 7. Retention hooks

- **Daily rewards (7-day cycle):** 15 min income, 25 Credits, 15 min 2x Cash, 30 min income,
  50 Credits, 30 min Overdrive-all, Rare machine of choice + 100 Credits. **14-day:** Streak
  Steamer. **30-day:** Loyalty Locomotive + "Industrialist" title.
- **Streaks:** claim within 48 h; one free Streak Shield per week (auto-used), more for 50 Credits.
- **Quests:** 3 daily (20–50 Credits, all-done bonus 30) and 3 weekly (200 Credits + 1 h 2x Cash),
  targets scaled to your factory.
- **Offline earnings:** 20% of income at logout, 2 h cap (+1 h per Night Shift Office research
  level, ×2 with the Offline pass), "×2" via rewarded ad or product.
- **Come back in 4 hours:** Supply Drop every 4 h (30 min income + 10 Credits, stores 2), 4-hour R&D
  projects, contract refills every 20 min, 1 h Gold plating.
- **Events:** Rush Orders at 00:00, 12:00, 18:00 UTC (contracts ×2 for 15 min); Weekend Rush
  Fri 18:00 – Sun 23:59 UTC (×2 cash); weekly community goal.
- **Updates every 2 weeks** (biweekly Thursdays; the HUD shows a "next update" countdown).
- **Seasonal products:** a 14-day Seasonal Line (Snow Globes, Pumpkin Lanterns) with catalog stamps;
  vaulted forever afterwards.
- **Promo codes:** `FACTORY` (50 Credits + 15 min 2x), `1KLIKES` (75 Credits), `ROCKETMAN`
  (100 Credits + 30 min 2x); one use each, expiring, Credits/boosts only.
- **Reminders:** Experience Notifications opt-in in Settings (sending needs Open Cloud, **VERIFY**).

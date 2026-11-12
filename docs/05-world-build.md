# Stage 5: World Build and Asset Guide — Factory Empire: Idle Tycoon

The whole world is generated at runtime from plain Parts, Neon, particles and tweens: eight player plots on a ring around a central plaza, each plot a tower that grows one floor per industry (Metalworks → Electronics → Automobiles → Aviation → Aerospace) with a roof rocket pad. No Toolbox/Creator Store asset is required for the game to be fully playable. Every dimension, colour, particle and sound is read from `Config.World` and `Config.Visuals` in `src/ReplicatedStorage/Shared/Config.luau`; builders live in `src/ServerStorage/Builders` (`WorldBuilder`, `BuildKit`, `MachineModelBuilder`) and `src/ServerScriptService/Services/PlotService.luau`. This guide documents the layout and naming contract, the lighting recipe and palette, effects, audio defaults and licensed replacements, an optional path to swap in real models, and a performance checklist. Platform assumptions are flagged **VERIFY**.

## 1. Layout (all values from `Config.World` and `Config.Visuals.Plaza/Plot`)

| Parameter | Value | Config key |
|---|---|---|
| Plots per server | 8 | `World.PlotCount` |
| Plot ring radius (plot centre → world origin) | 230 studs | `World.PlotRingRadius` |
| Plot slab size | 110 × 1 × 130 (X × Y × Z) | `World.PlotSize` |
| Floor height (slab to slab) | 26 studs | `World.FloorHeight` |
| Line spacing (along Z) | 16 studs | `World.LineSpacing` |
| Belt length | 70 studs (4 stages, 17.5 studs each) | `World.LineLength` |
| Plaza radius | 70 studs | `World.PlazaRadius` |
| Spawn height above the plot slab | 4 studs | `World.SpawnHeight` |
| Visible rocket launch every | 200 Rockets shipped | `World.RocketLaunchEvery` |
| Road width / ring road margin / ground margin | 14 / 12 / 400 studs | `Plaza.RoadWidth/RingRoadMargin/GroundMargin` |

Derived: plot `i` sits at angle `(i − 0.5) × 45°` (22.5°, 67.5°, … 337.5°), `-Z` of each plot faces the plaza; plot fronts are at radius 165; the ring road is at radius 153; adjacent plot centres are ≈ 176 studs apart (plots are 110 wide, so there is a 66-stud gap). The four plaza axes (0°, 90°, 180°, 270°) fall between plots and carry the landmarks. Floor `h` has its slab top at `Y = (h − 1) × 26 + 1`: 1, 27, 53, 79, 105; the roof slab top is one floor above the highest unlocked floor (131 with all five). Rockets fly 520 studs (`Rocket.FlightHeight`) over 6 s (`Rocket.FlightSeconds`).

### Top-down map (not to scale; +X right, +Z up)

```
                       90° (+Z)
                 Leaderboards x4 (Board_Richest, Shipped, Industry, Weekly)
            [P3]        ▐▐▐▐        [P2]
                 \       |        /
      [P4]        \   spoke      /          [P1]
          \        ┌────┴────┐   /            /
 VIP Lounge ◄── 180°│ PLAZA   │ 0° ──► Trade Plaza (TradePlaza)
 (VIPLounge)    ... │ radius  │ ...
          /        │  70     │   \            \
      [P5]         │ Statue  │    \          [P8]
                  └────┬────┘
                 /     |      \
            [P6]     MegaBoard      [P7]
                       270° (-Z)
 Ring road at r=153 joins the 8 spoke roads (14 wide); trees (80, seeded) between plots and outside the ring.
```

### One plot, top-down (plot-local studs; front `-Z` at the bottom, faces the plaza)

```
 Z=+65  ┌──────────────────────────────────────────────┐ back edge
        │   stair well / ramps (Ramp_h, Landing_h)  Z≈58.5     │ upper slabs stop at Z=52
 Z=+40  │       ═[Lever]══Stage1══Stage2══Stage3══Stage4══►     │ Line_6   (belt X −20 → +50)
 Z=+24  │       Line_5
 Z=+8   │       Line_4                       (RocketPad on roof, offset X +15, Z 0, 14×14)
 Z=−8   │       Line_3
 Z=−24  │  Bay_1 Bay_2      Line_2
 Z=−40  │  (X −47,−35)      Line_1 + BuildPad on the next buyable line
 Z=−47  │   VaultPad (−30,−47)   SpawnPoint (0,−45)   ContractBoard (−45,−52)
 Z=−58  │ ◄══════════════ Dock road (TruckStart/TruckEnd, 100×0.4×8) ══════════════►
 Z=−63  │                 Sign (0, Y=16, −63) 34×7×1  (owner name + industry)
 Z=−65  └──────────────────────────────────────────────┘ front edge (faces plaza)
        X=−55                                          X=+55
```

Line `k` of a floor (`j = 1…6`) has its belt centreline at `Z = (j − 3.5) × 16` → −40, −24, −8, +8, +24, +40, and `X` from `LineStartX = −20` to +50. The Overdrive lever is at `X = −24` (`LeverOffsetX = −4` from the belt start). Stage `s` is centred at `X = −20 + (s − 0.5) × 17.5`. The belt is 3.2 wide at height 1.2 over the floor slab with yellow Neon edge stripes.

### Per-floor layout

| Floor (`Floor_h`) | Industry | Unlocks at | Slab top Y | Lines | Extras on this level |
|---|---|---|---|---|---|
| 1 (`Base`) | Metalworks (`#FF8C28`) | Expansion 0 | 1 | 1–6 | VaultPad, Dock, Bays, ContractBoard, Sign, SpawnPoint |
| 2 | Electronics (`#28D2FF`) | Expansion 1 | 27 | 7–12 | Stairs/ramp from floor 1; rails and pillars |
| 3 | Automobiles (`#EB373C`) | Expansion 3 | 53 | 13–18 | Same |
| 4 | Aviation (`#6EB4FF`) | Expansion 6 | 79 | 19–24 | Same |
| 5 | Aerospace (`#965AFF`) | Expansion 10 | 105 | 25–30 | Same; roof above with RocketPad |
| Roof | — | when floor 5 is open | 131 | — | RocketPad (14 × 0.6 × 14, ring marking); rocket launches |

Floors above the highest unlocked one are not built (the roof sits on top of the highest unlocked floor), so the tower literally rises at each Expansion. Upper slabs stop at `SlabBackZ = 52` so the stair well stays open. Machines in Bays sit on `Bay_<i>` pads (`BayPadSize` 7 × 0.6 × 7) in two columns at `X = −47, −35`, rows every 10 studs from `Z = −34`.

### Naming contract (matches `docs/03-architecture.md` §9)

`Workspace.Plots.Plot_<i>` (attrs `PlotIndex`, `OwnerUserId`) → `Base`, `Floor_<h>`, `Line_<k>` (`Stage_<s>` ×4, `Belt` with `BeltStart/BeltEnd`, `Lever` with the `OverdrivePrompt`, `BuildPad`), `VaultPad`, `Dock` (`TruckStart/TruckEnd`), `Bays/Bay_<i>`, `RocketPad`, `ContractBoard`, `Sign`, `SpawnPoint`. `Workspace.Plaza` → `SpawnLocation`, `Leaderboards/Board_<Key>` (SurfaceGui `Board`), `TradePlaza`, `VIPLounge` (`VIPDoor`), `MegaBoard`. Conveyor items, trucks, floating numbers, bottleneck rings and rocket flights are client-side and read these names; do not rename parts in real models.

### Plaza landmarks (`Config.Visuals.Plaza`)

| Landmark | Placement | Size / notes |
|---|---|---|
| Spawn | plaza centre, offset (0, 0, 18) | 16 × 1 × 16; players spawn into their own plot's `SpawnPoint` |
| Statue / monument | plaza centre | height 14 (gear, column, sparkling globe) |
| Leaderboard boards (4) | radius 56, centred on 90°, 15° apart | 12 × 16 × 1, canvas 600 × 800, 10 rows (`Leaderboards.PhysicalRows`) |
| Mega Contract board | 270°, plaza edge | 30 × 14 × 1 |
| Trade plaza | 0°, radius 44, pad radius 11 | glowing ring with sparkles |
| VIP lounge | 180°, radius 52 | 26 × 12 × 22, gold `#FFC83C`, door 9 × 9 × 1 (`VIPDoor`, 0.75 transparency when open), chandelier, plants |
| Fence | around the plaza, 48 segments | 2.4 high |
| Props | 80 trees (seed 20240611, min radius 85), 5 lamps per road side | deterministic, so every server looks identical |

## 2. Lighting recipe (`Config.Visuals.Lighting`, applied by `WorldBuilder.buildLighting`)

| Object | Property | Value |
|---|---|---|
| `Lighting` | ClockTime | 14.5 |
| | Brightness | 2.2 |
| | Ambient | `#787882` (120, 120, 130) |
| | OutdoorAmbient | `#9696A0` (150, 150, 160) |
| | GlobalShadows | true |
| `FactoryAtmosphere` (Atmosphere) | Density / Haze / Color | 0.28 / 1.2 / `#C8DCFF` |
| `FactoryBloom` (BloomEffect) | Intensity / Size / Threshold | 0.6 / 24 / 1.4 |
| `FactoryColor` (ColorCorrectionEffect) | Saturation / Contrast / TintColor | 0.15 / 0.08 / `#FFFAF5` |
| `FactorySunRays` (SunRaysEffect) | Intensity / Spread | engine defaults (0.25 / 1) — not in Config; **VERIFY** defaults in your Studio version |
| `FactorySky` (Sky) | — | engine default skybox, no asset; add a custom Sky later by setting its textures in `WorldBuilder` |

The high bloom threshold (1.4) means only Neon and bright particles glow, which is what makes the conveyor stripes, rocket flame and rarity glows pop while the daylight scene stays clean.

## 3. Colour palette (`Config.Visuals`)

| Role | Key | Hex |
|---|---|---|
| Ground | `Palette.Ground` | `#6EC878` |
| Plaza | `Palette.Plaza` | `#EBEBF0` |
| Road | `Palette.Road` | `#3C3E46` |
| Plot base | `Palette.PlotBase` | `#CDD2DC` |
| Conveyor | `Palette.Conveyor` | `#2D3038` |
| Conveyor stripe (Neon) | `Palette.ConveyorStripe` | `#FFC828` |
| Truck box | `Palette.Truck` | `#FFFFFF` |
| Bottleneck ring | `Palette.Bottleneck` | `#FF3C3C` |
| Cash | `Palette.Cash` | `#5AE66E` |
| Credits | `Palette.Credits` | `#50BEFF` |
| UI background / panel | `Palette.UIBackground` / `UIPanel` | `#1C1E28` / `#2A2D3C` |
| UI accent / text | `Palette.UIAccent` / `UIText` | `#FFB020` / `#FFFFFF` |
| UI good / bad | `Palette.UIGood` / `UIBad` | `#4CD964` / `#EB4646` |
| Plot roof | `Plot.RoofColor` | `#505664` |
| Truck cab / wheels | `Truck.CabColor` / `WheelColor` | `#EB4646` / `#1E1E22` |
| Rocket body / nose+fins / window / flame | `Rocket.*Color` | `#F5F8FF` / `#EB373C` / `#6EC8FF` / `#FFAA3C` |
| Expansion burst / Franchise burst | `Effects.ExpansionColor` / `FranchiseColor` | `#FFDC5A` / `#FF50C8` |

Halls (`Config.Halls`):

| Hall | Colour | Accent |
|---|---|---|
| Metalworks | `#FF8C28` | `#96A0AF` |
| Electronics | `#28D2FF` | `#EBF5FF` |
| Automobiles | `#EB373C` | `#282830` |
| Aviation | `#6EB4FF` | `#F5FAFF` |
| Aerospace | `#965AFF` | `#191E46` |

Level tiers (machine/stage colour by the line's lowest stage level, `Visuals.LevelTiers`): 0 `#AAACB4` · 25 `#4CD964` · 50 `#2F80ED` · 75 `#A050F0` · 100 `#FFB020` · 200 `#FF3C78`. Rarity colours (`Config.Rarities.Colors`): Common `#AAACB4`, Rare `#4CD964`, Epic `#2F80ED`, Legendary `#FFB020`, Mythic `#E63CC8`, Secret `#141418`, Special `#FFDC5A`. Machine materials: dark `#2D3038`, glass `#AADCFF` (0.45 transparency), Chrome `#D7DCE6` (reflectance 0.35), Gold `#FFC83C` with Neon `#FFEB8C`.

## 4. Particles and effects (`Config.Visuals.Particles`, `Effects`)

| Effect | Look (rate, colour) | Where it appears |
|---|---|---|
| Sparks | 14/s, warm yellow `#FFD25A`, gravity-pulled | Spark Welder, Orbital Welder (and the stage tool tips) |
| Steam | 6/s, white-blue, rising and growing | Steam Hammer, Streak Steamer, Loyalty Locomotive |
| Embers | 8/s, orange `#FF7828`, slow rise | Furnace Golem, Titan Forge, Turbo Press, Toaster Rocket |
| Bubbles | 5/s, light blue | Fuel Mixer, Rubber Duck Factory |
| Sparkles | 10/s, soft yellow, all directions | Atomic Assembler, Infinity Belt, Quantum Warehouse, Quantum Tester, Star Forge, Paint Booth, Party Crane, Golden Robot; every Gold-Plated machine; trade pad ring, VIP chandelier, monument globe |
| Clouds | 4/s, white, large | Cloud Maker, Sky Foundry, Wind Tunnel |
| Coins | 20/s, gold, fountain with gravity | Gold Rush Refinery; Vault collection fountain (client effect) |
| Fire | 60/s, orange | Rocket engine flame |
| Milestone burst | 40 particles + "x2 SPEED!" text (`#FFDC5A`, 1.6 s, rises 7 studs) | A stage reaches level 25/50/75/100 |
| Line drop-in | machines fall 16 studs in 0.55 s with a bounce | A line or floor is built |
| Expansion shockwave | gold ring, radius 110, 1.1 s | Expansion |
| Franchise shockwave | magenta ring, same size | Franchise |
| Rocket launch | rocket (9 tall, 2.6 wide) rises 520 studs in 6 s with Fire + Clouds; visible to the whole server | every 200 Rockets shipped (`RocketLaunchEvery`), from the owner's `RocketPad` |
| Truck + "+$" text | white box truck with red cab drives the Dock in 5 s every 8 s; label floats 6 studs | per delivery |
| Bottleneck ring | red ring (9 diameter), pulses 0.25 ↔ 0.8 transparency every 0.7 s | stages within 70 studs of the player |

Conveyor items, floating text, coins and rings are client-side and pooled (see §8).

## 5. Music and SFX

Defaults (`Config.Visuals.Sounds`) use built-in client sounds so the game is audible with zero uploads (**VERIFY** every `rbxasset://` path exists in your client; the engine's built-in sound set changes between versions):

| Key | Default | Used for |
|---|---|---|
| `Click` | `rbxasset://sounds/button.wav` | UI taps |
| `Upgrade` | `rbxasset://sounds/electronicpingshort.wav` | Upgrades, milestones |
| `Coins` | `rbxasset://sounds/electronicpingshort.wav` | Vault collect, contract stamp |
| `Whoosh` | `rbxasset://sounds/swoosh.wav` | Line built, panels |
| `Error` | `rbxasset://sounds/clickfast.wav` | Rejected action |
| `Fanfare` | `rbxasset://sounds/electronicpingshort.wav` | Expansion, Franchise, machine/secret discovered |
| `Music` | `""` (silent) | Looping background track (Settings.Music toggle) |

Replacement workflow: upload or pick licensed audio, copy the asset id, paste `"rbxassetid://<id>"` into the matching key. No code change is needed. Creator Store search queries (use the Audio tab; **VERIFY** the current name and filters of the store):

| Slot | Search queries |
|---|---|
| Music (loop, 90–120 s) | `upbeat factory loop`, `industrial chill loop`, `cheerful tycoon background`, `lofi industrial` |
| Conveyor (optional ambient) | `conveyor belt loop`, `factory machinery hum` |
| Click | `ui click soft`, `button pop` |
| Coins / Vault | `cash register`, `coin collect`, `coins cascade` |
| Upgrade / milestone | `level up chime`, `upgrade ding`, `power up short` |
| Whoosh / line built | `whoosh short`, `building thud` |
| Error | `ui error soft`, `denied blip` |
| Fanfare | `achievement fanfare`, `victory sting short` |
| Rocket | `rocket launch`, `rocket engine roar` |

Only use audio you are licensed to use: Roblox-uploaded audio you own, Roblox-provided audio in the Creator Store, or tracks whose license you have in writing. Audio uploaded by other creators can be removed or made private at any time, so prefer your own uploads. Keep SFX < 2 s, music normalised to about −14 LUFS, and never use copyrighted commercial music.

## 6. Optional upgrade path: replace procedural models with real ones

Currently the builders look for overrides for **machines** and **production stages**; the truck, rocket, plaza props, trees and lamps are procedural (replacing them needs a small `BuildKit.Override` hook in `WorldBuilder`/`VisualsController`, same pattern).

1. In Studio create `ServerStorage/ModelOverrides` (Folder; Rojo keeps it if you add it under `src/ServerStorage/ModelOverrides`).
2. Put your finished Model there, e.g. `RivetBotModel`.
3. Map it in `Config.Visuals.ModelOverrides`, key → model name. Keys the builders read, in priority order:
   - Machines: the machine **Id** (e.g. `rivet_bot`), then its **Shape** (e.g. `CubeBot`, which covers every machine with that shape).
   - Stages: `Stage_<hall>_<stage>` (e.g. `Stage_2_3` = Electronics Assembler), then `Stage_<stage>` (1 Conveyor/Feeder, 2 Processor, 3 Assembler, 4 Packer).
   ```lua
   ModelOverrides = { rivet_bot = "RivetBotModel", Stage_3 = "AssemblerGeneric" } :: { [string]: string },
   ```
4. Requirements for each model: `PrimaryPart` set; all parts `Anchored = true`, `CanCollide = false`, `CanTouch = false`; no Scripts; pivot at bottom centre (see brief); keep part names inside `Stage_<s>` models free of "Belt", "Lever", "BuildPad".
5. Playtest: the override is cloned and renamed to the machine Id / `Stage_<s>`; the builder still sets level attributes and positions it, but **does not recolour or add grade particles** to an override (Chrome / Gold-Plated grades then look the same; keep the grade badge in the UI, or ship `_chrome`/`_gold` variants and extend `OverrideFor` keys).
6. Check the Developer Console memory and the part-count budget in §8, then publish.

### Asset list (Toolbox / Creator Store search queries)

Search on the Creator Store (Toolbox; **VERIFY** current name) for the style `low poly cartoon`, filter to Models and "Verified creators" where available, and **remove every Script** from anything you take.

| Group | Assets | Search queries |
|---|---|---|
| Stages (20 = 4 × 5 halls; or 4 generic) | Conveyor/Feeder, Processor, Assembler, Packer for each hall | `low poly conveyor machine`, `cartoon processing machine`, `low poly assembly line robot arm`, `cartoon packing machine` |
| Metalworks machines (7) | Rivet Bot, Bolt Buddy (`CubeBot`, `HexBot`), Spark Welder (`Arm`), Steam Hammer (`Press`), Furnace Golem (`Golem`), Crane Claw (`Crane`), Titan Forge (`Forge`) | `low poly robot cube`, `welding robot arm cartoon`, `steam hammer press low poly`, `furnace golem`, `crane claw`, `forge anvil low poly` |
| Electronics machines (7) | Solder Drone (`Drone`), Chip Sorter (`Box`), Circuit Spider (`Spider`), Laser Etcher (`Gantry`), Server Tower (`Tower`), Quantum Tester (`Orb`), Mainframe Prime (`ScreenWall`) | `low poly drone`, `circuit board robot spider`, `laser gantry machine`, `server rack low poly`, `glowing orb machine`, `mainframe computer wall` |
| Automobiles machines (7) | Wrench Arm, Tire Roller (`Roller`), Paint Booth (`Booth`), Torque Bot, Crash Tester (`Dummy`), Assembly Arm X (`TwinArm`), Turbo Press | `car factory robot arm low poly`, `tire roller machine`, `paint spray booth low poly`, `crash test dummy cartoon`, `dual robot arm` |
| Aviation machines (7) | Rivet Drone, Wing Sander, Wind Tunnel (`Ring`), Jet Balancer (`Turbine`), Hangar Hauler (`Tug`), Autopilot AI, Sky Foundry (`Platform`) | `jet turbine low poly`, `wind tunnel ring`, `airport tug tractor low poly`, `floating platform foundry` |
| Aerospace machines (7) | Orbit Bolter (`Satellite`), Thermal Tiler, Fuel Mixer (`Tanks`), Orbital Welder, Launch Tower, Zero-G Printer (`GlassCube`), Star Forge (`Ring`) | `low poly satellite`, `rocket fuel tanks`, `launch tower low poly`, `glass cube printer` |
| Mythic (4) | Infinity Belt, Atomic Assembler, Gold Rush Refinery, Quantum Warehouse | `infinity loop conveyor low poly`, `atom machine glowing`, `gold refinery low poly`, `futuristic warehouse cube` |
| Secret (4) | Rubber Duck Factory (`DuckFactory`), Pizza Printer (`Printer`), Toaster Rocket (`Toaster`), Cloud Maker (`Chimney`) | `rubber duck factory`, `pizza oven machine cartoon`, `toaster rocket`, `cloud machine chimney` |
| Special (7) | Founder Bot, Group Gizmo, Buddy Bot, Party Crane, Streak Steamer, Loyalty Locomotive (`Locomotive`), Golden Robot | `golden robot low poly`, `toy steam locomotive low poly`, `party crane confetti` |
| Truck (client) | cargo box truck, red cab | `low poly box truck`, `cartoon delivery truck` |
| Rocket | white body, red nose and fins, window | `low poly rocket`, `cartoon rocket`, `rocket launch pad low poly` |
| Plaza props | monument/statue (gear + globe), boards frame, fence segments, lamp post, planter, VIP chandelier | `low poly fountain statue`, `street lamp low poly`, `picket fence low poly`, `crystal chandelier low poly` |
| Nature | trees ×3 variants, bushes | `low poly tree pack`, `cartoon bush` |

Machine ids and shapes are listed in `Config.Machines` (51 entries: 35 hall machines, 4 Mythic, 4 Secret, 7 Special, 1 tutorial copy of the Rivet Bot); each `Visual` has `Primary`, `Secondary` colours and a `Shape`.

### Modeler brief

- **Style:** Toybox Industrial — chunky, bevelled, low-poly, readable at 60 studs; clean flat colours, no photo textures; one Neon accent per machine.
- **Budget:** ≤ 2,000 tris per specialist machine, ≤ 3,000 per stage; ≤ 40 Parts per machine if built from Parts; MeshParts preferred, `RenderFidelity = Automatic`, `CollisionFidelity = Box` (and `CanCollide = false`).
- **Footprint:** machines 4 × 4 studs (`Visuals.Machine.Footprint = 4`), up to 5 high; stages 9 studs along the belt (X) × 11 studs (Z), belt passes through at height 1.2.
- **Pivot:** bottom centre of the footprint at Y = 0, `PrimaryPart` = a flat root part or the main body; front faces `-Z` (towards the plaza).
- **Colour slots:** name recolourable parts `Primary`, `Secondary`, `Neon`, `Glass`; use the rarity colour (`Config.Rarities.Colors`) for the Neon accent so rarity reads at a glance; hall colour (table in §3) for the main body of stages.
- **Naming:** no spaces in names; do not name any part `Belt`, `Lever`, `BuildPad`.
- **Delivery:** each model as `.rbxm` with a 512 px preview, plus a 1-line license note (own work / licensed).

## 7. Budget numbers (assumptions, tune in Studio)

- Per fully built plot: ≤ 5,000 Parts (all 30 lines, 9 bays, roof, rails); procedural stage ≤ 40 Parts, machine ≤ 60 Parts. These are budgets, not measurements — measure with `#plot:GetDescendants()` in the command bar and the MicroProfiler.
- Eight plots + plaza ≤ 45,000 Parts in total in the worst case; with streaming the client loads only a fraction.

## 8. Performance checklist

- [ ] `Workspace.StreamingEnabled = true`; own plot `ModelStreamingMode = PersistentPerPlayer`; other plots stream normally (set by `PlotService`). Streaming radius ≥ 300 studs is not needed: the nearest ring neighbours are > 170 studs away.
- [ ] Part budget per plot as in §7; upper floors are built only when unlocked.
- [ ] `CastShadow = false` on small decorative parts (belt stripes, frames, rails, particles hosts, bolts); keep shadows only for slabs, big machines and the rocket.
- [ ] All parts anchored, `CanCollide = false` except walkable surfaces (slabs, stairs, landings), `CanTouch = false`, `CanQuery = false` on decor.
- [ ] Conveyor items are client-side and **pooled** (`Conveyor.MaxItemsPerLine = 10`, `ItemSpacing = 6`); only lines within `VisibleRadius = 180` animate; other players' plots run at a fixed 10 studs/s; Low Graphics halves the pool (`LowGraphicsScale = 0.5`). The server never creates per-item parts.
- [ ] Floating text, coins, bottleneck rings (radius 70) and trucks are pooled and distance-gated (`Labels.MaxDistance = 140`).
- [ ] Particle emitters: fixed rates from Config; no emitter above 60/s; emitters `Enabled` only within view distance or when the line produces.
- [ ] Billboards use `Labels.MaxDistance`; boards update only every `Leaderboards.RefreshSeconds = 120`.
- [ ] Test on a low-end phone: aim for stable ≥ 30 FPS with all 8 plots occupied; check the Developer Console (memory < ~1 GB on mobile is a common target; **VERIFY** the current recommended budget).
- [ ] Prefer a single MeshPart for repeated real models and use `Model:Clone()` from ServerStorage instead of rebuilding.

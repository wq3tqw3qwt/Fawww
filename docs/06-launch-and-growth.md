# Stage 6: Launch and Growth Plan — Factory Empire: Idle Tycoon

This is the plan from "game is built" to "10,000+ concurrent players": a pre-release checklist, five icon/thumbnail concepts with an A/B test plan, the store page in seven languages, a 30-day live-ops calendar on a **biweekly (every 2 weeks, Thursday)** update cadence, a marketing plan with budget tiers from 0 to 20,000 Robux per month, an analytics scorecard with a decision tree wired to `Config.luau` knobs, and a 90-day roadmap with risks and fallbacks. Numbers that come from the game live in `src/ReplicatedStorage/Shared/Config.luau` or the pacing simulation (`tools/pacing_sim.luau`: first Expansion at 29:01 for a greedy always-online player); anything else is a labelled *assumption* to replace with your own analytics. Platform-dependent claims are marked **VERIFY**.

> **Config note before launch:** `Config.Events.UpdateEpochUnix` is the reference Thursday for the "next update" countdown. Set it to **00:00 UTC of your launch Thursday** (any later update Thursday works too, 14-day steps). The value currently in Config (`1803859200`) is Monday 2027-03-01 00:00 UTC, which is not a Thursday.

## 1. Pre-release checklist

**Devices and network**
- [ ] Phone, small phone (~5" / 360×640 class), tablet, desktop, and a gamepad: every panel fits, tap targets ≥ `Config.UI.MinTapSize`, HUD does not cover the Overdrive lever prompt, safe-area insets respected.
- [ ] Studio device emulator (small phone, portrait and landscape) plus one real low-end Android: ≥ 30 FPS with 8 plots occupied; Low Graphics toggle works.
- [ ] Slow connection: Studio Network → Incoming Replication Lag 250–500 ms and a throttled test client; UI never freezes, purchase prompts and trade confirmations still resolve, `DataSync` arrives (loading state shown).
- [ ] 2+ players (Studio "Local Server", 3 clients, then a live private server with friends): plots assign and free on leave, operators (+25%, max 2) work, leaderboards and the Mega Contract board update.

**Purchases**
- [ ] Creator Hub: 8 Game Passes and 17 Developer Products created, IDs pasted into `Config.GamePasses` / `Config.DevProducts`; prices equal the Config prices; icons and descriptions set.
- [ ] Studio test purchase for every product and pass: granted exactly once; rejoin: pass ownership is restored; kill the server right after the purchase prompt: the receipt is granted on the next join (idempotent `ReceiptLedger`).
- [ ] Live test with a small group (5+ people, real Robux, refund path known): Starter Pack once only; gift of a boost to another player; ad reward (opt-in) grants through the AdReward channel; a skip product refused when nothing is running.

**Trading dupe tests** (`TradeService`: revision-based offers, two-sided confirm, atomic swap)
- [ ] Rapid offer changes (change items 20× in 2 s, then confirm): the confirmation applies only to the last revision.
- [ ] Leave mid-trade (either side, before and during the 3-second countdown): no items lost, none duplicated, trade cancelled for the stayer.
- [ ] Server shutdown mid-trade (stop the server during the countdown and during the swap): after rejoin both inventories sum to the original total; the trade log (`Config.Trade.LogStoreName`) shows no completed entry for an aborted trade.
- [ ] Two simultaneous trades with the same item, a trade offering an item then equipping/merging it, offering a locked item: all refused server-side.
- [ ] Account gates: age < 3 days or play time < 20 min cannot trade; accounts where paid-item trading is disallowed by policy cannot trade (**VERIFY** `PolicyService` `IsPaidItemTradingAllowed`).

**Data**
- [ ] Studio → Game Settings → Security → **Enable Studio Access to API Services** is ON, otherwise DataStore/MemoryStore calls fail in Studio.
- [ ] ProfileStore: Studio runs use the **mock** store (no persistence between Studio sessions); at least one full test on a **live** published place: join, play 5 min, rejoin, state identical; join from two servers: session lock steals cleanly.
- [ ] Shutdown: close the server during play; `BindToClose` saves every profile (check by rejoin); crash simulation: rejoin loses < `Config.Offline.CheckpointSeconds` (60 s) of progress.
- [ ] Migrations: load a v1 profile (fixture) into the live build: upgrades to `Config.DataVersion`.
- [ ] Expansion/Franchise reset keeps the right data (Shares, machines, research, passes) and drops the rest.
- [ ] Exploit smoke test: fire every remote with garbage arguments (nil, NaN, huge numbers, wrong types): the server rejects and logs, nothing errors.
- [ ] Admin panel visible only to your UserId (`Config.Admin.UserIds`), codes expire correctly, `MemoryStore` global goal flushes (limits **VERIFY**).

## 2. Icon and thumbnails

Five concepts (icon 512×512 and thumbnails 1920×1080 share a subject; keep the title text out of the icon):

| # | Concept | Composition | Colours | Typography | Emotion | Focal object |
|---|---|---|---|---|---|---|
| A | **"Rocket from the roof"** | Low-angle tower of five coloured floors, rocket mid-launch top centre, trail on a diagonal | Hall colours bottom-up (`#FF8C28`, `#28D2FF`, `#EB373C`, `#6EB4FF`, `#965AFF`) on a daylight-blue sky | 2 words max, "ROCKETS!" in heavy rounded sans with a dark outline | Awe + ambition | Rocket with `#FFAA3C` flame |
| B | **"Cash waterfall"** | Close-up conveyor feeding a truck stacked with cash; coins arcing to the camera | Cash green `#5AE66E`, gold `#FFC828`, dark background `#1C1E28` | Big "$$$" numbers like "$1B/s" | Greed / satisfaction | Overflowing truck |
| C | **"Friends run my factory"** | Two Roblox avatars on a lever and a belt; one high-fives | Warm orange + cyan | "PLAY WITH FRIENDS" small ribbon | Joy, social proof | The two avatars at the lever |
| D | **"Secret recipe"** | Mysterious glowing machine behind a question-mark curtain; rubber duck peeking out | Dark `#141418` + Mythic magenta `#E63CC8` glow | "SECRET!" | Curiosity | The glowing Secret machine |
| E | **"Empire cutaway"** | Cutaway side view of the tower with all five floors working, tiny workers, big arrow "from 1 smelter" | Bright toybox pastel with Neon belts | "FACTORY EMPIRE" | Cosy, satisfying | The tower and its belts |

**A/B test plan (CTR):** use Roblox's thumbnail experiment tooling if available (**VERIFY** current availability, impressions needed, and how many variants you may run; also **VERIFY** whether thumbnail personalisation is automatic). Plan: week 1 control A vs B vs D (three-way), keep the same icon and title; week 2 winner vs C vs E; week 3 test text overlay on/off and zoom level on the winner. Decision rule (assumption): run each variant to ≥ 5,000 impressions, accept a winner only with ≥ +10% relative CTR over control; otherwise keep the control. Success thresholds (assumptions, adjust to your category benchmark): thumbnail CTR ≥ 6% is healthy, ≥ 10% is excellent; play-through (click → ≥ 1 min session) ≥ 80%; icon refreshed with each major update if CTR drops > 15% from its 4-week average. Take screenshots from the real build (use `Config.Visuals` palette), not mock-ups, and use 3–5 thumbnails showing: the tower, a contract board with free blueprint odds, a rocket launch, the plaza with friends, and the R&D lab.

## 3. Title, description, tags and localization

**Title (EN):** `[🚀] Factory Empire: Idle Tycoon` — keyword-first ("factory", "idle", "tycoon"), the 🚀 tag is replaced by the current update tag (e.g. `[🎄]`) at each update. Check the title limit and the emoji/tag rules in titles (**VERIFY**). **Genre/subgenre:** Simulation → Tycoon (**VERIFY** the current genre/subgenre taxonomy and whether "Tycoon" is a subgenre). **Maturity:** Minimal (complete the questionnaire honestly: includes trading and in-experience purchases; **VERIFY** current questionnaire fields). **Tags / keywords (if the platform offers them; **VERIFY**):** idle, tycoon, factory, simulator, trading, friends, rockets.

### Localized titles and descriptions

Enable localization for the experience page (Creator Hub → Localization) and add these as manual translations (**VERIFY** whether automatic translation of the title/description is on and whether manual text overrides it; fix any machine-translated gaps by hand). Description limit is 1,000 characters (**VERIFY**); each text below is ≈ 600–700 characters.

**EN — English**
- Title: `[🚀] Factory Empire: Idle Tycoon`
- Description:
```
Build a tiny workshop into a GLOBAL FACTORY EMPIRE! 🏭
⚙️ Upgrade machines, speed up conveyors and fix bottlenecks
📦 Turn raw ore into gears, chips, cars, jets… and ROCKETS 🚀
📋 Complete contracts for big payouts and free machine blueprints
🔁 Expand for Shares, unlock 5 industries, then Franchise forever
🤝 Friends can run your lines — you BOTH earn more!
🔍 Discover SECRET recipes in the R&D Lab
💤 Earn cash even while you are away
✅ No loot boxes. No paid odds.
🎁 Like + Favorite and try code FACTORY!
New update every 2 weeks!
```

**RU — Русский**
- Title: `[🚀] Factory Empire: Idle Тайкун`
- Description:
```
Превратите маленькую мастерскую в МИРОВУЮ ФАБРИЧНУЮ ИМПЕРИЮ! 🏭
⚙️ Улучшайте станки, ускоряйте конвейеры и устраняйте узкие места
📦 Делайте из руды шестерёнки, чипы, машины, самолёты… и РАКЕТЫ 🚀
📋 Выполняйте контракты: большие награды и бесплатные чертежи машин
🔁 Расширяйтесь ради Долей, откройте 5 отраслей, а потом — Франшиза навсегда
🤝 Друзья могут управлять вашими линиями — выигрываете ОБА!
🔍 Находите СЕКРЕТНЫЕ рецепты в лаборатории
💤 Деньги капают, даже когда вы не в игре
✅ Никаких лутбоксов и платных шансов
🎁 Лайк + Избранное и введите код FACTORY!
Новое обновление каждые 2 недели!
```

**PT-BR — Português (Brasil)**
- Title: `[🚀] Factory Empire: Tycoon Idle`
- Description:
```
Transforme uma pequena oficina em um IMPÉRIO DE FÁBRICAS GLOBAL! 🏭
⚙️ Melhore máquinas, acelere esteiras e resolva gargalos
📦 Transforme minério em engrenagens, chips, carros, jatos… e FOGUETES 🚀
📋 Complete contratos para ganhar muito e receber projetos de máquinas grátis
🔁 Expanda para ganhar Ações, desbloqueie 5 indústrias e depois use a Franquia para sempre
🤝 Amigos podem operar suas linhas — vocês DOIS ganham mais!
🔍 Descubra receitas SECRETAS no Laboratório de P&D
💤 Ganhe dinheiro mesmo quando estiver offline
✅ Sem caixas de loot e sem chances pagas
🎁 Curta + Favorite e use o código FACTORY!
Atualização nova a cada 2 semanas!
```

**ES — Español**
- Title: `[🚀] Factory Empire: Tycoon Idle`
- Description:
```
¡Convierte un pequeño taller en un IMPERIO FABRIL MUNDIAL! 🏭
⚙️ Mejora máquinas, acelera cintas y elimina cuellos de botella
📦 Convierte mineral en engranajes, chips, coches, aviones… y COHETES 🚀
📋 Completa contratos para conseguir grandes premios y planos de máquinas gratis
🔁 Expande tu negocio para ganar Acciones, desbloquea 5 industrias y luego Franquicia para siempre
🤝 ¡Tus amigos pueden manejar tus líneas y los DOS ganáis más!
🔍 Descubre recetas SECRETAS en el Laboratorio de I+D
💤 Gana dinero incluso cuando no estás
✅ Sin cajas de botín ni probabilidades de pago
🎁 ¡Dale a Me gusta + Favorito y usa el código FACTORY!
¡Nueva actualización cada 2 semanas!
```

**DE — Deutsch**
- Title: `[🚀] Factory Empire: Idle Tycoon`
- Description:
```
Baue eine kleine Werkstatt zu einem WELTWEITEN FABRIK-IMPERIUM aus! 🏭
⚙️ Verbessere Maschinen, beschleunige Förderbänder und beseitige Engpässe
📦 Mach aus Erz Zahnräder, Chips, Autos, Jets … und RAKETEN 🚀
📋 Erfülle Aufträge für große Belohnungen und kostenlose Maschinen-Baupläne
🔁 Expandiere für Anteile, schalte 5 Branchen frei und werde danach für immer Franchise-Boss
🤝 Freunde können deine Linien bedienen – ihr verdient BEIDE mehr!
🔍 Entdecke GEHEIME Rezepte im Forschungslabor
💤 Verdiene Geld, auch wenn du nicht spielst
✅ Keine Lootboxen und keine bezahlten Zufallschancen
🎁 Like + Favorit und nutze den Code FACTORY!
Alle 2 Wochen ein neues Update!
```

**FR — Français**
- Title: `[🚀] Factory Empire: Tycoon Idle`
- Description:
```
Transforme un petit atelier en EMPIRE INDUSTRIEL MONDIAL ! 🏭
⚙️ Améliore tes machines, accélère les convoyeurs et élimine les goulots d'étranglement
📦 Transforme le minerai en engrenages, puces, voitures, jets… et FUSÉES 🚀
📋 Termine des contrats pour de gros gains et des plans de machines gratuits
🔁 Étends ton usine pour gagner des Parts, débloque 5 industries, puis passe en Franchise à l'infini
🤝 Tes amis peuvent faire tourner tes chaînes : vous gagnez TOUS LES DEUX plus !
🔍 Découvre des recettes SECRÈTES au labo R&D
💤 Gagne de l'argent même quand tu n'es pas là
✅ Pas de loot boxes, pas de chances payantes
🎁 Like + Favori et utilise le code FACTORY !
Une nouvelle mise à jour toutes les 2 semaines !
```

**TR — Türkçe**
- Title: `[🚀] Factory Empire: Idle Tycoon`
- Description:
```
Küçük bir atölyeyi DÜNYA ÇAPINDA BİR FABRİKA İMPARATORLUĞUNA dönüştür! 🏭
⚙️ Makineleri geliştir, bantları hızlandır, darboğazları çöz
📦 Cevheri dişliye, çipe, arabaya, jete… ve ROKETLERE dönüştür 🚀
📋 Büyük ödüller ve ücretsiz makine planları için sözleşmeleri tamamla
🔁 Hisse kazanmak için genişle, 5 sektörü aç, sonra sonsuza dek Franchise yap
🤝 Arkadaşların hatlarını çalıştırabilir, İKİNİZ de daha çok kazanırsınız!
🔍 Ar-Ge Laboratuvarında GİZLİ tarifler keşfet
💤 Oyunda olmasan bile para kazan
✅ Ganimet kutusu yok, ücretli şans yok
🎁 Beğen + Favorilere ekle ve FACTORY kodunu dene!
Her 2 haftada yeni güncelleme!
```

Localization notes: in-game text should be localized through the same table later (UI strings, `Config` names). Codes are case-insensitive English strings and stay identical in all languages. Have one native speaker per language skim the text before launch (community volunteers or a paid check).

## 4. First 30 days: live-ops calendar (biweekly Thursday updates)

Convention: **Day 1 = launch day, a Thursday.** Content updates ship on Thursdays every 2 weeks (Day 15, Day 29, then every 14 days); in between there are hotfixes and no-patch events. "Day 14" in the planning brief maps to the second Thursday (Day 15), and "Day 28–30" to Day 29. Weekend Rush (Fri 18:00 → Sun 23:59 UTC, cash ×2) and Rush Orders (00:00, 12:00, 18:00 UTC, 15 min, contract rewards ×2) run automatically every week; the community goal counts contracts completed by all servers in an ISO week (tiers 5,000 / 25,000 / 100,000).

| Day | Type | Content | Promo hooks | Codes | Monetization |
|---|---|---|---|---|---|
| **1 (Thu)** | **Launch** | Full game: 5 industries, contracts, R&D, trading, leaderboards. Soft launch to friends in the morning, public at peak hours of your target region | "Like + Favorite for codes", Discord opening, launch tweet/TikTok clip of the first rocket launch | `FACTORY` (50 Credits + 15 min 2x Cash) | Starter Pack after 12 min / first Expansion; Passes live; ads disabled until ad eligibility confirmed (**VERIFY**) |
| 2 (Fri 18:00 UTC) | Auto event | First **Weekend Rush** (×2 cash, Fri 18:00 → Sun 23:59) | "Double cash this weekend!" post | — | **Weekend Bundle** (199 R$) appears only in this window |
| **3 (Sat)** | **Hotfix / QoL + code drop** | Bug fixes from launch telemetry, UI/QoL tweaks, small number tuning via Config only (no new content) | Patch notes on Discord/Group wall, "we listened" post | `1KLIKES` (75 Credits) when the like milestone is reached | None new; verify Starter Pack take rate |
| **7 (Wed)** | **Event, no content patch** | **Community Goal week** in focus + Rush Orders spotlight (all driven by Config/MemoryStore, no update needed). Leaderboard titles for "This Week's Tycoons" | "Can we reach 25,000 contracts?" server-wide progress shown at the plaza Mega board | `ROCKETMAN` (100 Credits + 30 min 2x Cash) for creators and Discord | Boost 15/30/60 min suggestions during Rush; `Cash2x` pass card after the goal reward |
| 8 (Thu) | No update | Telemetry review; Day 7 retention readout | Dev diary (what changed, what is next) | — | A/B of the first-offer timing (`Config.Offers`) |
| **15 (Thu)** | **First content update (biweekly #1)** | **Seasonal Line** (`Config.Events.SeasonalLine`: set `Enabled = true`, Name, Start/End unix) + new machines (3–5), new quests; update tag in title | Trailer clip + thumbnail refresh, creator early-access day before | `SEASONAL` (Credits + 15 min 2x) | Seasonal bundle (income minutes + Credits + 2x Cash, fixed contents, 14-day window); limited countdown shown honestly |
| 16–17 | Auto event | Weekend Rush #3 + seasonal quest chain | "Collect all seasonal machines (free)" | — | Weekend Bundle |
| 21 (Thu) | No update | Hotfix day if needed; Community Goal #3 | Leaderboard reset recap, top 10 shout-out | creator-specific codes | Starter Pack week-3 refresh of the shop banner |
| **29 (Thu)** | **Major update (biweekly #2)** | **Corporations (clans)**: shared goal, corporation leaderboard, corporation title; fallback: a 6th industry ("Energy" floor, 6 lines, 7 machines) | Big trailer, creator event, Roblox sponsored ads burst, update tag change | `CORP` (Credits + 30 min 2x) | Corporation-themed bundle (cosmetic-free), Premium card in the corporation panel |
| 30 (Fri) | Auto event | Weekend Rush with corporations scoring | Announce winners | — | Weekend Bundle |

Codes `SEASONAL` and `CORP` and any per-creator codes are not in `Config.Codes` yet: add each as `NAME = { Credits = …, BoostKey = "Cash2x", Minutes = …, ExpiresUnix = … }` before the update that announces it (codes grant Credits/boosts only). Launch codes already in Config: `FACTORY`, `1KLIKES`, `ROCKETMAN`.

Cadence guardrails: every content update is announced ≥ 3 days before; any change touching economy numbers is re-simulated with `lune run tools/pacing_sim` first; `Config.Events.UpdateCadenceDays = 14` keeps the in-game "next update" countdown aligned.

## 5. Marketing plan

**Roblox sponsored ads / Ads Manager** (**VERIFY** current ad formats, bidding, minimum budgets, targeting options and payment method).

| Tier | Budget / month | What to buy | Use |
|---|---|---|---|
| 0 | 0 R$ | Organic only: codes, Discord, creators, thumbnails A/B | Launch baseline; prove D1 and D7 |
| 1 | 5,000 R$ | Experience sponsored ads on the best-CTR thumbnail, 1 audience | Validate CPI and D1 of paid users |
| 2 | 10,000 R$ | 2 audiences (Simulation/Tycoon fans, idle fans) + weekend boost | Day 15 and Day 29 update bursts |
| 3 | 20,000 R$ | Continuous campaigns in the 3 best regions + retargeting lapsed players (if offered) | Scale only when ROAS is positive |

Targeting: age bands appropriate for Minimal maturity, languages EN first then PT-BR, ES, RU, DE, FR, TR (one campaign per language/thumbnail pair). **ROAS tracking:** ROAS = revenue from paid-acquired players ÷ ad spend. Use the experience's analytics for payer conversion and revenue by acquisition source (**VERIFY** that the dashboard splits by sponsored source); break-even example (assumptions): a new player gives ≈ 3.9 active days in the first 30 days (retention 1 / 0.35 at D1 / 0.12 at D7 / 0.04 at D30 integrated) × gross ARPDAU (conservative 2.6 R$, base 6.5 R$ from `02-monetization.md`) × 0.70 platform share = **≈ 7.0 R$ (conservative) to 17.6 R$ (base) net per acquired player**; stop a campaign if the measured cost per new player is above that for two weeks, scale it if it is below 60% of it.

**Micro-influencers (YouTube / TikTok):** target 3–50k subscribers, tycoon/idle niche, ≥ 5 creators per update window.
- Outreach template: "Hi {Name}, I'm {Dev}, developer of Factory Empire: Idle Tycoon, a vertical factory tycoon with *no loot boxes and no paid odds*, friends running each other's lines, and public rocket launches. I'd love you to try it early: here's a private server link and a unique code **{CODE}** your viewers can redeem for Credits and a 2x Cash boost. No payment required; if you like it, we can talk about a paid video. I can send thumbnails/assets and answer any questions."
- One code per creator in `Config.Codes` (Credits and/or a boost only, never exclusive machines, 30-day expiry), e.g. `CREATORNAME` = 100 Credits + 30 min 2x Cash. Track redemptions per code to measure each creator (the `CodeService` logs redemptions).
- Brief them on the honesty points: show the odds table, no paid randomness, parents-friendly.

**Discord:** channels `#announcements`, `#patch-notes`, `#codes`, `#suggestions`, `#bug-reports`, `#trading` (rules: no scams, trades only through the in-game two-sided confirm), `#showcase` (rocket launches), `#creators`; roles Tycoon / Franchise / Creator; bot not required at launch. Pin the "no paid randomness" pledge and the update calendar.

**Roblox Group:** create the group, wall posts for every update, `Config.GroupId` set for the group bonus (+5% income and a one-time "Group Gizmo" machine).

**Code drops:** at like milestones (`1KLIKES`), at community goals, with each biweekly update, during creator videos; always Credits/boosts, never paid-odds items; codes expire (`ExpiresUnix`).

**UGC items (optional):** a small UGC collection (hard hat, golden gear) sold via the Avatar Shop as a discovery channel (**VERIFY** UGC creator requirements and fees); no in-game dependency.

**Collaborations:** swap-promotion with 2–3 non-competing small experiences (e.g. other idle/simulator games) via shared rewards (each other's code in Discord), and a joint community goal event.

## 6. Analytics scorecard

Review every week (Monday). Roblox Creator Analytics: retention, session length, concurrency, revenue/payers; **VERIFY** custom events and funnels in the Creator Dashboard (`AnalyticsService` custom/funnel events; availability and limits) and log tutorial steps, offers and purchases through it if it is available; otherwise log to your own DataStore/MemoryStore counters.

| Metric | Target | Notes |
|---|---|---|
| D1 / D7 / D30 retention | **> 35% / > 12% / > 4%** (D30 is an assumption) | by acquisition source and platform |
| Average session length | **> 20 min** | design target 25 min |
| Sessions per day | ≥ 2.5 (assumption) | idle games need returns |
| Payer conversion | **2–5%** | daily payers ÷ DAU |
| ARPPU / ARPDAU | tracked vs `02-monetization.md` base case (215 R$ / 6.5 R$ gross) | |
| Tutorial funnel | ≥ 85% finish `Done` (assumption) | steps from `Config.Tutorial.Steps`: TapBottleneck → UpgradeFive → CollectVault → Contract → BuyLine2 → Overdrive → EquipMachine → Done |
| Expansion 1 reach rate and time | ≥ 50% of D1 cohort within 3 sessions; median play time 30–40 min (sim: 29:01) | |
| Contract claim rate | ≥ 60% of D1 players claim ≥ 1 contract | |
| Trade volume | 0.5–3 completed trades per 100 DAU (assumption) | abnormal spikes = investigate |
| Exploit log rate | < 0.5% of sessions with strikes (assumption) | `AntiExploitService` log |

### Decision tree (metric below target → concrete fixes)

1. **D1 < 35%**
   - Open the tutorial funnel. Largest drop between two steps → fix that step: earlier steps (`TapBottleneck`, `UpgradeFive`) → raise `Config.Tutorial.WelcomeCrateCash` (100) or lower `UpgradeCount` (5); `CollectVault` → lengthen `Vault.TutorialCapacitySeconds`; `Contract` → lower `Contracts.Tutorial.Target` (50) / raise `RewardCash` (250) so Line 2 is exactly affordable.
   - Funnel clean but no return → strengthen the comeback hook: `Offline.Efficiency` (0.20 → 0.25) or `Offline.BaseCapHours` (2 → 3), `SupplyDrop.IntervalSeconds`, make the first daily reward visible (`DailyRewards.Cycle`); prompt Experience Notifications opt-in after the first Expansion (**VERIFY** the in-game opt-in prompt and the Open Cloud sending path).
2. **D7 < 12%**
   - Check Expansion 1 reach rate first. If < 50% by session 3 → pacing too slow: refit with `lune run tools/pacing_sim -- --fit` after lowering `Sim.TargetFirstRunMinutes`, paste the new `Config.Expansion.RequirementTable`; or reduce `Economy.UpgradeGrowth` (1.10 → 1.09), or `Economy.CostRatio`.
   - If E1 reach is healthy → mid-game lull: shorten `Contracts.RefillSeconds` (1200 → 900), add a weekly quest chain (`Quests.Weekly`), move the next machine/industry reveal earlier (`Halls[].UnlockExpansions` only with a re-simulation), adjust `Events.RushOrders.UtcHours` for your audience's time zone.
3. **Average session < 20 min**
   - Add beats per minute: `Overdrive.CooldownSeconds` (60 → 45) for a faster loop, `Quests.DailyCount` (3 → 4), `Contracts.Slots`, `Vault.CapacityMinutes` (smaller tiers make players return to the vault more often), `SupplyDrop.MaxStored`.
   - Check for dead time: the interval between upgrades/lines should follow the targets in `01-design.md`; re-run `lune run tools/pacing_sim` and compare the first-run timeline.
4. **Payer conversion < 2%**
   - Move the first offer earlier: `Offers.StarterPackShowAfterSeconds` (720 → 600; never below `FirstOfferMinPlaySeconds` = 600 and never in the tutorial); improve Starter Pack contents in `Bundles.StarterPack` (e.g. `Credits` 300 → 400) rather than lowering `DevProducts.StarterPack.Price` (99), because the "70% OFF" anchor still holds (see `02-monetization.md` §2).
   - Add a cheaper entry (the 25 R$ `OfflineDouble` / `AdBoost` are already the lowest); make the `AutoCollect` toast appear at the 3rd vault miss instead of the 5th; check the shop funnel (opened → viewed → prompted → purchased).
5. **ARPPU low (< 150 R$)**
   - Raise the visibility of `CashLarge` / `CreditsLarge` BEST VALUE cards, show `SharesPack` after each Expansion, run `WeekendBundle` every weekend, add a seasonal bundle; never add paid randomness.
6. **Expansion 1 reach time > 40 min (median)**
   - Run `lune run tools/pacing_sim -- --fit` and lower `Config.Expansion.RequirementTable[1]` (1.04e9), or raise `Config.Economy.MilestoneMult`/lower `MilestoneEvery` only after re-simulating; remember the sim ignores Overdrive, robots, machines and idle time, so compare with the real distribution first.
7. **Contract claim rate low**
   - Lower `Contracts.MinTarget` (10) or `Tiers.Bronze.TargetSeconds` (240); lengthen `DurationSeconds`; make the Contract Board visible earlier in the tutorial flow; show the odds panel once.
8. **Trade volume too low / too high**
   - Low: lower `Trade.MinPlaySeconds` (1200 → 900) or `Trade.CooldownSeconds` (30), promote `#trading` in Discord. High with exploit signals: raise `Trade.MinAccountAgeDays`, review `Trade.LopsidedWarnRatio`, freeze trading with `Trade.Enabled = false` as a kill switch.
9. **Exploit log rate above target**
   - Tighten `AntiExploit.SpeedTolerance` / `StrikesToKick`, lower `AntiExploit.Rates` for the hot remotes, use the admin panel to ban; check receipts for duplicate IDs; review the leaderboard top for impossible `TotalEarnings`.

## 7. 90-day roadmap to 10,000+ CCU

Assumptions: concurrent players ≈ DAU × (average session minutes ÷ 1,440) × peak factor; with 25-min sessions, ~1.4 sessions/day and a 2.5× peak factor, 10,000 CCU needs roughly 100,000–150,000 DAU (**assumption**, replace with measured CCU/DAU ratio from your analytics).

| Phase | Days | Goals | Actions | Gate to continue |
|---|---|---|---|---|
| Soft launch | 1–7 | 100–300 CCU, D1 > 35% | Launch Thursday, Weekend Rush, code drops, Discord, 5 micro-creators; hotfix Day 3 | D1 > 30% and no data-loss bug |
| Stabilize | 8–14 | 300–800 CCU | Fix funnel drops (§6), prepare update #1, thumbnail A/B | D7 trending > 10%, crash rate < 1% |
| Update #1 | 15–28 | 800–2,000 CCU | Seasonal Line, creator wave, sponsored ads tier 1–2, ASO and localized pages | positive ROAS ≥ 1.0 on paid, payer conv ≥ 2% |
| Update #2 | 29–45 | 2,000–4,000 CCU | Corporations (or 6th industry), tier 2–3 ads burst, collaboration event | D30 ≥ 4%, session ≥ 20 min |
| Compound | 46–60 | 4,000–6,000 CCU | Update #3 (biweekly), more languages, UGC item, creator affiliate codes | stable server performance with 8 plots full |
| Scale | 61–90 | 6,000–10,000+ CCU | Updates #4–#5, Franchise-focused content, weekly community goals, large events | Sustained retention targets |

Risks and fallbacks:

| Risk | Likelihood | Fallback |
|---|---|---|
| D1 or D7 below target | Medium | Follow §6 decision tree; delay paid ads until D1 > 30%; do not scale spend |
| Data loss or dupe exploit | Low–medium | Trade kill switch `Config.Trade.Enabled = false`; ban via admin panel; rollback to a known profile version; compensate with Credits codes |
| DataStore / MemoryStore throttling at scale | Medium | Raise `Leaderboards.WriteSeconds` and `Events.GlobalGoal.FlushSeconds`, lengthen `Data.Retry` delays; limits **VERIFY** |
| Policy blocks trading for some users | Medium | Trading is gated per player; keep the game fully playable without trading (**VERIFY** `IsPaidItemTradingAllowed`) |
| Rewarded ads unavailable / low eCPM | Medium | Set `Config.Ads.Enabled = false`; direct-purchase equivalents (`OfflineDouble`, `AdBoost`) stay; do not budget on ad income |
| Sponsored ads unprofitable | Medium | Stop at tier 0–1, invest in creators and thumbnails; re-test with a new thumbnail |
| Content burn (players finish updates quickly) | Medium | Franchise endgame, seasonal lines, corporations; keep 2 updates of buffer in the backlog |
| Update slips | Medium | Ship a no-patch event (Rush, Community Goal, codes) instead of delaying; never break the 14-day cadence with an unfinished feature |
| Moderation issue (chat, titles) | Low | Title input already length-limited (`Social.MaxTitleLength`); use Roblox filtering (`TextService`) for any player text |
| Roblox algorithm drop after a trending spike | Medium | Keep daily content hooks (Rush Orders 3×/day) and push update days; keep CTR and retention above the category average |

## 8. VERIFY items used in this document

Genre/subgenre taxonomy ("Simulation → Tycoon"); emoji/tag rules and length limits in titles and descriptions; localization (manual vs auto-translation); thumbnail experiments/personalisation; `PolicyService` `IsPaidItemTradingAllowed`; Experience Notifications (opt-in prompt in game, sending via Open Cloud); rewarded video ad eligibility; MemoryStore quotas and limits; Premium Payouts formula; sponsored ads / Ads Manager options and minimum budgets; Creator Analytics custom events and funnels; DataStore/Studio API access settings; UGC creator requirements; maturity questionnaire fields.

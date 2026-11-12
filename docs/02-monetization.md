# Stage 2: Monetization — Factory Empire: Idle Tycoon

Factory Empire earns Robux through eight Game Passes, seventeen Developer Products (including two limited offers), Roblox Premium engagement payouts and two opt-in rewarded-video placements. Everything sold is **deterministic and disclosed**: the player always sees exactly what a price buys. The pledge that anchors the whole store is **no paid randomness** — Robux never buys odds, crates, rerolls, contract completion or blueprint drops. This document defines every product, where it appears, when the first offer shows, and a revenue model per 1,000 daily active players (DAU) with its arithmetic and sensitivity. All prices below are quoted from `Config.GamePasses`, `Config.DevProducts`, `Config.Bundles`, `Config.Offers`, `Config.Premium` and `Config.Ads` in `src/ReplicatedStorage/Shared/Config.luau`; numbers that are **not** in Config (conversion rates, ad eCPM, DevEx rate) are labelled *assumption*. Platform-dependent claims are flagged **VERIFY**.

## 0. The no-paid-randomness pledge (trust + marketing point)

- Robux never buys a roll, crate, chance, reroll, pity progress, contract completion or blueprint drop. Nothing in `Config.GamePasses` or `Config.DevProducts` rolls a random number.
- Blueprint drops come **only from free contract rewards**; the odds and the Gold pity counter (`Config.Contracts.Tiers`) are shown in the Contracts panel: Bronze 3% Rare; Silver 2% Epic / 10% Rare; Gold 2% Legendary / 8% Epic / 25% Rare, pity guarantees a Legendary after 40 Gold claims.
- Secret machines are found through **deterministic recipes** in the R&D Lab (`Config.SecretRecipes`), not luck.
- Epic and Legendary machines can be bought directly for Credits at a fixed, visible price (`Config.MachineShop`: Epic 150, Legendary 800 Credits at hall 1, doubling per hall) — a known price for a known item.
- Use it as a store-page line and a shop banner: **"No loot boxes. No paid odds. You see what you buy."** (Banner copy in §6.)

## 1. Game Passes (`Config.GamePasses`)

Passes are permanent, account-wide, and re-checked on join (`PassService`); the server owns ownership truth. Ids are `0` in Config until you paste them from Creator Hub.

| # | Key | Price (R$) | Exact effect | Rationale | UI placement |
|---|---|---|---|---|---|
| 1 | `Cash2x` | 399 | ×2 on all income (`PassEffects.Cash2xMult = 2`); stacks multiplicatively with timed 2x Cash boosts | Flagship pass, highest-converting idle pass; sets the price anchor | Pinned first card on Shop › Passes; HUD "2x" button; contextual on the Expansion result screen (after the celebration, never over it) |
| 2 | `AutoCollect` | 149 | Vault cash goes straight to the wallet (skips the Vault pad). Vault capacity still applies as a speed bump only | Cheap entry pass; removes a chore, not a limit — good first purchase | Shop › Passes; contextual toast when the Vault is full and the player has collected ≥ 5 times |
| 3 | `ExtraRobots` | 299 | +2 robot workers (`Robots.PassBonus = 2`), each +25% line speed and auto-Overdrive | Mid-game power + visible workers on the floor | Shop › Passes; contextual on the Robots tab when all slots are filled |
| 4 | `TurboConveyors` | 279 | +30% production on every line (`TurboConveyorsMult = 1.30`) | Clear, honest number; sells to optimizers | Shop › Passes; contextual on first bottleneck-fix after Expansion 1 |
| 5 | `OfflineX2` | 149 | Offline cap ×2 (base 2 h → 4 h; efficiency stays 20%) | Retention pass: rewards players who leave and return | Shop › Passes; contextual on the Offline Earnings popup when earnings were capped |
| 6 | `VIP` | 499 | +10% income (`VIPIncomeBonus`), VIP tag, VIP Lounge access (plaza door), Golden Robot machine (`golden_robot`) | Status + social pass; top of the price ladder | Shop › Passes (gold card); the plaza VIP door shows "VIP — 499 R$" prompt; leaderboard rows show the tag |
| 7 | `ExtraBays` | 349 | +2 specialist machine bays (`Expansion.BaysPassBonus = 2`) | Collector pass; sells when the player has more machines than bays | Shop › Passes; contextual in the Machines panel when inventory > bays |
| 8 | `ContractMaster` | 249 | +1 contract slot (3 → 4) and refills 2× faster (1200 s → 600 s) | Contract-loop pass; increases blueprint-drop *attempts* only via free play, never via payment | Shop › Passes; contextual when a contract slot is empty and a refill timer is running |

Sum of all eight passes: **2,372 R$**. A "Complete Collection" pass bundle is intentionally not offered at launch (keeps the store honest and flat); add one later only if it is a real discount of the listed pass prices.

Design rules: no pass is required to progress; no pass affects odds; the strongest pass (`Cash2x`) is a flat multiplier visible in the HUD math; `VIP` is the only prestige-only item.

## 2. Developer Products (`Config.DevProducts`)

All products are consumable (except the one-time Starter Pack) and granted **only inside `ProcessReceipt`** through an idempotent ledger (`ReceiptLedger`): a replayed receipt never double-grants. "Income minutes" are computed from the player's current income at purchase time. Purchased cash does **not** count toward Expansion requirements (only collected Vault cash does), so cash packs cannot skip the pacing.

| Key | Price | Contents | Category | Badge | Rationale | Where shown |
|---|---|---|---|---|---|---|
| `StarterPack` | 99 | 2 h of income + 300 Credits + a Rare machine (highest unlocked hall) + 1 h 2x Cash; **one-time** | Offers | **70% OFF** | Converts new players cheaply; first purchase turns a non-payer into a payer | Home banner + Shop › Offers (48 h countdown; see §4) |
| `CashSmall` "Cash Crate" | 49 | 30 min of income | Cash | — | Entry price point | Shop › Cash |
| `CashMedium` "Cash Pallet" | 149 | 2 h of income | Cash | POPULAR | Middle of the 1:3:10 ladder; default selection | Shop › Cash |
| `CashLarge` "Cash Truck" | 499 | 10 h of income | Cash | BEST VALUE | Whale-friendly, best per-Robux value | Shop › Cash |
| `CreditsSmall` | 99 | 100 Credits | Credits | — | Credits are a soft currency also earned free (contracts, quests, daily) | Shop › Credits; Contract Shop and R&D Lab "need more Credits" link |
| `CreditsMedium` | 299 | 350 Credits | Credits | POPULAR | Mid pack | Shop › Credits |
| `CreditsLarge` | 899 | 1,200 Credits | Credits | BEST VALUE | Best value (0.75 R$/Credit) | Shop › Credits |
| `Boost15` | 49 | 2x Cash, 15 min (giftable) | Boosts | — | Cheap trial | Shop › Boosts; HUD boost widget |
| `Boost30` | 89 | 2x Cash, 30 min (giftable) | Boosts | POPULAR | Default boost | Shop › Boosts |
| `Boost60` | 149 | 2x Cash, 60 min (giftable) | Boosts | BEST VALUE | Best per-minute | Shop › Boosts |
| `SkipResearch` | 99 | Completes the running 4-hour R&D project | Utility | — | Impatience relief on a long timer; blocked server-side if nothing is researching | Research panel, next to the timer |
| `SkipPlating` | 49 | Completes Gold plating (1 h timer) | Utility | — | Same pattern for the merge timer | Machines panel, on the plating card |
| `ContractExtend` | 29 | +10 min on all running contracts | Utility | — | Fixes a missed deadline with a *known* price; no extra odds | Contracts panel when a running contract has < 2 min left |
| `SharesPack` | 199 | +5% of current Shares (minimum 5) | Utility | — | Late-game sink scaling with progress | Expansion result screen (after celebration) and Shop › Utility |
| `WeekendBundle` | 199 | 4 h of income + 200 Credits + 1 h 2x Cash | Offers | — | Recurring limited offer | Shop › Offers; HUD ribbon during Weekend Rush only |
| `OfflineDouble` | 25 | Doubles the offline cash you just collected | Utility | — | Impulse price at the best moment; **also the rewarded-ad reward** | Offline Earnings popup |
| `AdBoost` | 25 | 2x Cash for 10 min | Boosts | — | Direct purchase equivalent of the ad reward; **also the rewarded-ad reward** | HUD boost widget |

### Pack structure 1 : 3 : 10 and anchor pricing

- **Cash packs 49 / 149 / 499** follow the 1 : 3 : 10 price ladder and give 30 min / 2 h / 10 h of income — per-Robux value rises 0.61 → 0.81 → 1.20 income-minutes per R$, so the biggest pack is the clear best value without looking like a trap.
- **Credit packs 99 / 299 / 899** follow ≈ 1 : 3 : 9 and give 100 / 350 / 1,200 Credits (1.01 → 1.17 → 1.33 Credits per R$).
- **Boost ladder 49 / 89 / 149** (15 / 30 / 60 min) gives the middle option a POPULAR tag and the long option BEST VALUE.
- **Starter Pack "70% OFF"** is an honest anchor because every content item is also sold separately: 2 h income = `CashMedium` 149; 1 h 2x Cash = `Boost60` 149; 300 Credits ≥ 225 R$ at the best Credit rate (`CreditsLarge` 0.749 R$/Credit) and 297 R$ at the smallest. List value = 149 + 149 + 225…297 = **523–595 R$**, plus a Rare machine (not Robux-priced; counted as 0). 99 R$ is therefore **81–83% below list value**, so the shown "70% OFF" badge is conservative and always true.

## 3. Roblox Premium

**Premium Payouts** pay creators Robux based on Premium subscribers' engagement time in the experience (**VERIFY** the current formula, any minimum and the exact payout rate in Creator Hub; the revenue model below treats it as an *assumption*). In-game benefits (`Config.Premium`, `Config.Social.PremiumBonus`):

- **+10% income** (`Premium.IncomeBonus = 0.10`) — a flat, visible bonus in the multiplier breakdown.
- **20 Credits every day** (`Premium.DailyCredits = 20`) — claimed through the daily reward flow; the value is small so Premium never feels mandatory.
- A Premium badge on the HUD and leaderboard rows (cosmetic).

`PromptPremiumPurchase` placements (never during the tutorial, never more than once per session):
1. After a non-Premium player claims a daily reward, a small "Premium: +10% income, +20 Credits daily" card.
2. A permanent Premium card at the top of Shop › Passes.
3. The Offline Earnings popup footer line: "Premium players earn 10% more".
Only `MarketplaceService:PromptPremiumPurchase` is used; no custom purchase flow.

## 4. Limited-time offers

| Offer | Window | Mechanics (all from Config) | Honesty rule |
|---|---|---|---|
| **Starter Pack** (99 R$, one-time) | Shown after the first Expansion **or** 12 min of playtime (`StarterPackShowAfterSeconds = 720`), whichever is first; then **48 h** from the *first impression* (`StarterPackWindowHours = 48`) | `MarkOfferSeen` stamps `StarterPackFirstSeen`; the countdown is server time; after 48 h the server answers "Offer expired" and the card is **removed**, never repriced | The timer is real and the same for every player; after it ends the pack is genuinely unavailable (see compliance, §10) |
| **Weekend Bundle** (199 R$) | Only during Weekend Rush: Friday 18:00 → Sunday 23:59:59 UTC (`Config.Events.Weekend`; cash ×2 in that window) | `Offers.Limited = { WeekendBundle, Recurring = "Weekend" }`; countdown to Sunday 23:59:59 UTC | Hidden outside the window; the bundle is not shown with a fake "was" price |
| **Seasonal line bundles** | Per live-ops calendar (§4 of `06-launch-and-growth.md`); `Config.Events.SeasonalLine` (Enabled flag, Name, Start/End unix) controls the seasonal line itself | A seasonal bundle = cosmetic-free utility (income minutes + Credits + 2x Cash) tied to the seasonal line; cosmetics and a seasonal machine are earned **free** through the season's quest line | Never sells a seasonal machine for Robux with odds; any seasonal machine sold directly has a fixed visible price and stays obtainable free |

The update cadence is **every 2 weeks (biweekly Thursdays)**; `Config.Events.UpdateCadenceDays = 14` drives the "next update" countdown. Seasonal bundles therefore run 14 or 28 days.

## 5. Shop UX

- **Entry points:** HUD "Shop" button (always), contextual links (Offline popup, Vault full, Research timer, Contract timer, Expansion result), and the plaza VIP door.
- **Tabs (left to right):** Offers · Passes · Cash · Credits · Boosts · Utility. Offers is hidden when empty.
- **Sorting:** by `Order` from Config inside each tab; the item with a badge sits in the visual center; `OneTime` items sort last once bought.
- **Badges:** POPULAR and BEST VALUE come directly from `Config.DevProducts[...].Badge`; Starter Pack carries **70% OFF** (see §2 for proof). At most one badge per card; no flashing or rotating badges.
- **Owned states:** owned passes show a green "OWNED ✓" and a short description of the effect; purchased Starter Pack shows "Claimed". Passes can never be re-prompted when owned (server rejects `PromptPass` for owned keys).
- **Utility products are blocked when useless:** the server refuses a prompt for Finish Research with no research running, Finish Plating with nothing plating, Contract Extension with no running contract, Offline Double with nothing to double.
- **Gifting:** `Boost15/30/60` are `Giftable`. "Gift" opens a player picker (players in the server only); a gift intent is honoured for 120 s (`Shop.GiftIntentSeconds`) and the recipient receives the boost; the buyer sees a confirmation toast.
- **Price display:** real Robux price, plain contents list, "Buy" button; no countdown unless it is an actual window.
- **"No paid randomness" banner:** a one-line banner at the top of the Shop: "No loot boxes · No paid odds · Blueprint drops are free from contracts". Tapping it opens the disclosed contract odds table.
- **Mobile-first / gamepad:** cards use Scale sizing with `UIAspectRatioConstraint`; every Buy button ≥ `Config.UI.MinTapSize`; gamepad selection with ButtonB to close.
- **First-offer timing (`Config.Offers`):** no offers during the tutorial (first 3 minutes); no offer of any kind before `FirstOfferMinPlaySeconds = 600` (10 min); Starter Pack at the first Expansion or 12 min; at most one popup-style offer per session, everything else is passive (shop badge dot, HUD ribbon).

## 6. Rewarded video ads (opt-in)

Exactly **two** placements (`Config.Ads.Placements`), both opt-in buttons that say "Watch an ad" and are never auto-shown or auto-played:

1. **Offline ×2:** on the Offline Earnings popup, "Watch ad: double this" (product key `OfflineDouble`).
2. **10-minute 2x Cash boost:** on the HUD boost widget (product key `AdBoost`).

Flow: the client asks `AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)`; if available the button is shown. The `WatchAd` remote lets the server call `AdService:CreateAdRewardFromDevProductId(devProductId)` and `AdService:ShowRewardedVideoAdAsync(player, reward)`; the reward is granted through `ProcessReceipt` with `ProductPurchaseChannel.AdReward`, so ad rewards use the same idempotent ledger. Caps (`Config.Ads`): **10 min cooldown** (`CooldownSeconds = 600`), **max 6 per day** (`MaxPerDay = 6`), one ad at a time. Ads never interrupt play: no ad on join, no ad between actions, no ad at death/expansion; the player always chooses. Ad eligibility (account age, regions, creator eligibility) and current terms are **VERIFY** in Creator Hub. `Config.Ads.Enabled = false` disables both buttons without a code change.

## 7. Funnel: when each offer appears

| When | What the player sees | Offer |
|---|---|---|
| 0–3 min (first session) | Tutorial | **None** |
| 3–10 min | Quests, Overdrive, Vault | None (HUD shows free daily reward later) |
| ≥ 10 min | Shop is pushable | Contextual passive offers only (e.g. `AutoCollect` toast at a full Vault) |
| 12 min *or* at first Expansion (sim ≈ 29 min to E1) | Home banner | **Starter Pack** (99 R$) + 48 h countdown starts |
| First Expansion result screen (~30–40 min) | Celebration, Shares gained | After the celebration: `Cash2x` pass card and `SharesPack` (late) |
| End of session 1 | Offline popup on return | `OfflineDouble` (25 R$ or ad); `OfflineX2` card when capped |
| Day 1 (return) | Daily reward claimed | Premium card; 2x Cash 15-min boost suggestion |
| Day 2–3 | Contracts, R&D Lab | `ContractMaster`, `SkipResearch` at the 4-hour timer, Credit packs from the Contract Shop |
| Day 3 (hotfix + code drop) | Promo code | Free codes — no Robux offer |
| Day 2–4 (launch Thursday = Day 1) | First Weekend Rush | `WeekendBundle` ribbon; `Boost` packs |
| Day 7–14 | Expansion 2–3 | `TurboConveyors`, `ExtraRobots`, `ExtraBays` contextual; `VIP` after the first Gold contract |
| Day 15 (second Thursday) | Content update + seasonal line | Seasonal bundle, update banner |

## 8. Revenue model per 1,000 daily players

**Method.** Per day, per 1,000 DAU: payers = DAU × payer conversion; purchases = payers × purchases per payer; gross Robux = purchases × average purchase value; creator Robux = gross × 0.70 (the platform share is 30% — **VERIFY**). Add Premium Payouts (assumption) and rewarded-ad revenue (assumption), convert to USD at the DevEx rate, and report per day and per 30 days. Everything labelled *assumption* is a planning input, not a Roblox-published number.

### Product mix (assumption, by purchase count, steady-state mixed-age cohort)

| Category | Share of purchases | Average price (R$) | How the average is formed | Share of gross Robux |
|---|---|---|---|---|
| Game Passes | 8% | 296.5 | straight mean of the eight pass prices | 16.5% |
| Cash packs | 18% | 151.5 | 50/35/15 of 49/149/499 | 19.0% |
| Credits packs | 14% | 299.0 | 45/40/15 of 99/299/899 | 29.2% |
| Boosts | 22% | 85.0 | 40/40/20 of 49/89/149 | 13.0% |
| Utility | 20% | 80.2 | mean of 99, 49, 29, 199, 25 | 11.2% |
| Offers (Starter + Weekend) | 10% | 139.0 | 60/40 of 99/199 | 9.7% |
| Ad Boost (direct buy) | 8% | 25.0 | `AdBoost` price | 1.4% |
| **Weighted average purchase** | 100% | **143.5** | | 100% |

### Scenarios (per 1,000 DAU per day)

| Line | Conservative | Base | Optimistic | Source |
|---|---|---|---|---|
| Payer conversion (daily payers ÷ DAU) | 1.5% | 3.0% | 5.0% | assumption (target band 2–5%) |
| Payers | 15 | 30 | 50 | 1,000 × conversion |
| Purchases per payer per day | 1.2 | 1.5 | 1.9 | assumption |
| Purchases | 18 | 45 | 95 | payers × purchases/payer |
| ARPPU, gross (R$) | 172 | 215 | 273 | purchases/payer × 143.5 |
| **Gross Robux / day** | **2,584** | **6,459** | **13,635** | purchases × 143.5 |
| Creator Robux after 30% fee | 1,808 | 4,521 | 9,545 | gross × 0.70 (**VERIFY** fee) |
| Premium Payouts (R$/day) | 30 | 80 | 150 | assumption: 6/8/10% Premium DAU × 0.5/1.0/1.5 R$ per Premium DAU per day (**VERIFY** formula) |
| Rewarded ads: viewers / views per viewer | 100 / 1.5 | 200 / 2.0 | 300 / 2.5 | assumption: 10/20/30% of DAU opt in |
| Ad eCPM (USD per 1,000 views) | 5 | 10 | 15 | assumption (**VERIFY** payouts and eligibility) |
| Ad revenue (USD/day) | 0.75 | 4.00 | 11.25 | views × eCPM ÷ 1,000 |
| Robux-equivalent total / day | 2,053 | 5,744 | 12,909 | creator Robux + Premium + ads ÷ 0.0035 |
| **USD/day at DevEx 0.0035 USD/R$** | **7.18** | **20.10** | **45.18** | (creator Robux + Premium) × 0.0035 + ads |
| **USD per 30 days** | **≈ 216** | **≈ 603** | **≈ 1,355** | × 30 |
| Same, at DevEx 0.0038 USD/R$ (USD/day) | 7.74 | 21.48 | 48.09 | **VERIFY** the current published DevEx rate and minimum threshold |
| Gross ARPDAU (R$) | 2.58 | 6.46 | 13.64 | gross ÷ 1,000 |

Worked check (base): 30 payers × 1.5 = 45 purchases × 143.5 = 6,459 R$ gross; × 0.70 = 4,521 R$; + 80 Premium = 4,601 R$ × 0.0035 = **$16.10**; + $4.00 ads = **$20.10/day**; × 30 = **$603/month per 1,000 DAU**.

### Sensitivity (creator Robux per day per 1,000 DAU, before Premium/ads)

| Payer conversion | ARPPU 150 R$ | ARPPU 215 R$ (base) | ARPPU 300 R$ |
|---|---|---|---|
| 1.5% | 1,575 | 2,258 | 3,150 |
| 2% | 2,100 | 3,010 | 4,200 |
| 3% | 3,150 | 4,515 | 6,300 |
| 4% | 4,200 | 6,020 | 8,400 |
| 5% | 5,250 | 7,525 | 10,500 |

Reading it: revenue is linear in both axes; one point of payer conversion (≈ 1,500 R$/day at base ARPPU) is worth about as much as a 33% ARPPU gain at the base case, so the roadmap prioritises the **first purchase** (Starter Pack, `AutoCollect`, 15-min boost) over whale pricing. Credits are the largest revenue category in the mix; the free Credit sources (contracts, quests, daily) are tuned so Credits feel valuable but never gate progress.

## 9. Monetization KPIs (feed `06-launch-and-growth.md` §6)

Payer conversion (2–5% target), ARPPU, ARPDAU, Starter Pack take rate (target ≥ 25% of payers), % revenue from passes vs products, rewarded-ad opt-in rate and views/viewer, refund/support tickets per 1,000 payers, and Premium share of DAU.

## 10. Compliance checklist

- [ ] **No paid random items:** no product or pass changes odds; blueprint drops only from free contracts; odds + pity are disclosed in-game.
- [ ] **Clear prices:** every card shows the real Robux price and contents; no hidden currencies; badges are factual (70% OFF is provable, see §2).
- [ ] **No deceptive timers:** countdowns are server-time windows that really end; the Starter Pack disappears after its 48 h; the Weekend Bundle is hidden outside the weekend; no looping "last chance".
- [ ] **No pressure on the tutorial or on young players:** no offers in the first 3 minutes; ads opt-in only; maximum one popup-style offer per session; purchase prompts always dismissible.
- [ ] **Child-appropriate:** Minimal maturity target; no gambling mechanics, no chat-based sales; trading disabled per user when `PolicyService` does not allow paid-item trading (**VERIFY** `IsPaidItemTradingAllowed`) and limited to accounts ≥ 3 days old with ≥ 20 min playtime (`Config.Trade`).
- [ ] **Rewarded ads:** only after the player taps; eligibility, regions and age rules confirmed in Creator Hub (**VERIFY**).
- [ ] **Refunds / support path:** receipts are idempotent and logged; the experience description and Group wall list a support link and a how-to-request-a-refund note pointing to Roblox Support; the admin panel (owner UserId only) can grant a make-good for a verified failed purchase.
- [ ] **Premium:** benefits are small and disclosed; Premium Payouts formula and terms checked (**VERIFY**).
- [ ] **Policy re-read** at every release: Roblox Community Standards, Marketplace and Developer Product rules, and advertising rules (**VERIFY** current text).

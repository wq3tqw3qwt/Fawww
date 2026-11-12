# Factory Empire: Idle Tycoon

A Roblox idle tycoon (production chains, contracts, Expansion prestige, Franchise endgame) built as a
Rojo project. The whole world is generated at runtime from Parts, so the game is fully playable
without any Toolbox assets. **Every number lives in one file:**
`src/ReplicatedStorage/Shared/Config.luau`.

| Doc | Contents |
|---|---|
| [docs/01-design.md](docs/01-design.md) | Stage 1 design document (with real pacing-simulation output) |
| [docs/02-monetization.md](docs/02-monetization.md) | Stage 2 passes, products, offers, ads, revenue model |
| [docs/03-architecture.md](docs/03-architecture.md) | Stage 3 Explorer tree, modules, data flow, remotes, data schema |
| [docs/05-world-build.md](docs/05-world-build.md) | Stage 5 procedural map, lighting, palette, audio, asset swap guide |
| [docs/06-launch-and-growth.md](docs/06-launch-and-growth.md) | Stage 6 launch checklist, store page + localization, live ops, marketing, analytics |
| [tools/README.md](tools/README.md) | Pacing simulation: how to run it and what to tune |

## 1. Setup (one time)

1. **Install Rokit** (toolchain manager): https://github.com/rojo-rbx/rokit#installation
   ```bash
   rokit install          # installs rojo, wally, lune, selene, stylua, luau-lsp from rokit.toml
   ```
   (Aftman users: `aftman install` reads `aftman.toml`.)
2. **Install packages** (ProfileStore):
   ```bash
   wally install          # creates ServerPackages/ (git-ignored)
   ```
3. **Install the Rojo Studio plugin**: `rojo plugin install`, or install "Rojo" from the Creator Store.

## 2. Run in Studio

1. In Roblox Studio create a new **Baseplate** place and delete the default `Baseplate` part.
2. In a terminal at the repository root: `rojo serve`
3. In Studio: **Plugins → Rojo → Connect** (default `localhost:34872`). The project syncs into
   ReplicatedStorage, ServerScriptService, ServerStorage, StarterPlayerScripts and StarterGui.
4. **Game Settings → Security → Enable Studio Access to API Services** (needed for DataStores,
   MemoryStore and MessagingService). Without it, player data uses ProfileStore's in-memory mock and
   nothing is saved; that is fine for quick tests.
5. Press **Play**. Use **Test → Clients and Servers** with 2+ players to test trading and operators,
   and **Device emulator** for phones.

Build a place file without Studio: `rojo build default.project.json -o FactoryEmpire.rbxl`.

## 3. Publish

1. **File → Publish to Roblox As…** → create a new experience (owner: you or your group).
2. Keep Rojo connected while you iterate; publish again from Studio after syncing.
3. In Creator Hub → your experience → **Configure**:
   - **Basic info**: title, description and genre (see docs/06-launch-and-growth.md).
   - **Maturity & compliance questionnaire**: complete it (target: Minimal).
   - **Places → Settings**: enable **Streaming** is already set by the project
     (`Workspace.StreamingEnabled = true`).
   - **Access**: Public once the pre-release checklist in docs/06 passes.

## 4. Manual checklist in Creator Hub

- [ ] Create the experience and publish the place (above).
- [ ] **Game Passes** (Monetization → Passes): create all 8 with the names and prices in
      `Config.GamePasses` (2x Cash 399, Auto-Collect 149, Hire Extra Robots 299, Turbo Conveyors 279,
      Offline Cap x2 149, VIP Office 499, Extra Machine Bays 349, Contract Master 249), then paste each
      **Pass ID** into `Config.GamePasses.<Key>.Id`.
- [ ] **Developer Products** (Monetization → Developer Products): create one per entry in
      `Config.DevProducts` (17 products) with the listed price, then paste each **Product ID** into
      `Config.DevProducts.<Key>.Id`. Products with `Id = 0` show "Not configured yet" in the shop.
- [ ] **Server size**: Configure → Places → set **Max players = 8** (one plot per player; the 9th
      player would wait for a plot). Matches `Config.World.PlotCount`.
- [ ] **Launch date**: set `Config.Events.UpdateEpochUnix` to 00:00 UTC of your launch Thursday so the
      "next update" countdown follows your biweekly schedule.
- [ ] **Rewarded video ads**: if your account is eligible, enable ads for the experience and keep
      `Config.Ads.Enabled = true`; the rewards use the `AdBoost` and `OfflineDouble` products above.
- [ ] **Admin**: the experience creator is admin automatically (user-owned places). For extra admins
      or a group-owned experience add UserIds to `Config.Admin.UserIds` (find your UserId in your
      profile URL: `roblox.com/users/<UserId>/profile`). In Studio play-tests every tester is admin
      so you can try the panel; live servers apply the rules above.
- [ ] **Group** (optional): create a Roblox group and set `Config.GroupId` for the +5% bonus and the
      Group Gizmo machine.
- [ ] **Icon and thumbnails**: generate them from the 5 concepts in docs/06 and upload them in
      Configure → Places/Experience → Icon & Thumbnails.
- [ ] **Promo codes**: edit `Config.Codes` (expiry is a Unix timestamp, UTC).
- [ ] **Audio**: the default sounds are built-in client sounds; replace them with licensed audio IDs in
      `Config.Visuals.Sounds` (see docs/05).
- [ ] **Localization**: paste the translated title/description from docs/06 in Configure →
      Localization.

## 5. Verify locally

```bash
./scripts/check.sh      # rojo build, strict type-check (luau-lsp), selene, stylua --check, unit tests
lune run tests/run      # unit tests only
lune run tools/pacing_sim -- --franchise   # pacing simulation
```

## 6. Project layout

```
src/ReplicatedStorage/Shared     Config, Formulas, Types, Net, data template + migrations, pure logic
src/ServerScriptService          Main.server.luau, Server/ helpers, Services/ (23 services)
src/ServerStorage/Builders       procedural world, plots and machine models
src/StarterPlayer/StarterPlayerScripts  ClientMain, UI/UIKit, Controllers/ (UI, HUD, visuals…)
src/StarterGui/FactoryUI         ScreenGui shell (filled at runtime)
tests/                           Lune unit tests (economy, Shares, odds, trades, offline, receipts, migrations)
tools/                           pacing simulation
docs/                            Stages 1, 2, 3, 5, 6
```

## 7. VERIFY: platform assumptions to confirm before launch

These depend on current Roblox platform rules or APIs that cannot be tested outside Roblox. Each one
is also marked **VERIFY** in the code or docs where it is used.

| # | Assumption | Where it matters | How to verify |
|---|---|---|---|
| 1 | Genre "Simulation", subgenre "Tycoon" exists in the current genre taxonomy | Experience page | Creator Hub → Configure → Basic info → Genre dropdown |
| 2 | `PolicyService:GetPolicyInfoForPlayerAsync(player).IsPaidItemTradingAllowed` is the right gate for trading machines (the code denies trading if the call fails) | TradeService | Creator Hub docs for PolicyService; test with an account from a restricted region |
| 3 | `Player:GetJoinData().ReferredByPlayerId` is set when a friend joins from an invite | SocialBonusService invite rewards | Invite a test account with `SocialService:PromptGameInvite` in a live server and log the join data |
| 4 | MemoryStore quotas and size limits are enough for the weekly global goal (one SortedMap key per week, one `UpdateAsync` per server per minute) | EventService | Creator Hub → MemoryStore limits; watch the MemoryStore dashboard under load |
| 5 | Experience Notifications: the in-game opt-in prompt works, but *sending* notifications requires Open Cloud from an external backend | SettingsController opt-in, Stage 6 reminders | Creator Hub docs "Experience notifications" |
| 6 | Rewarded video ads: eligibility (creator, user age, region, device) and that rewards arrive via ProcessReceipt with `ProductPurchaseChannel.AdReward` | ShopService, OfflineController, ShopController | Creator Hub docs "Rewarded video ads"; test in a live server |
| 7 | Built-in sound paths in `Config.Visuals.Sounds` (`rbxasset://sounds/...`) exist on all clients | SoundController | Play in Studio and on a phone; replace with uploaded audio if silent |
| 8 | Premium Payouts formula and `PromptPremiumPurchase` behaviour | docs/02 revenue model | Creator Hub → Premium Payouts docs |
| 9 | `ExperienceNotificationService`, `AdService` and `PolicyService` method names on the current engine version | Code paths wrapped in `pcall` | Studio script analysis; run once live |
| 10 | Emoji and bracket tags in the experience title are allowed | Store page | Creator Hub title validation |
| 11 | DevEx rate, sponsored-ads minimum budgets and Ads Manager targeting options | docs/02, docs/06 | Creator Hub → DevEx and Ads Manager |
| 12 | `GroupService:GetGroupsAsync` returns the player's rank per group (used instead of the deprecated `Player:GetRankInGroupAsync`) | Group bonus, group-owned admin check | Join your group with a test account and check the +5% bonus |
| 13 | `PersistentPerPlayer` model streaming keeps each owner's plot loaded on phones | PlotService | Play on a low-memory phone and walk to the plaza and back |

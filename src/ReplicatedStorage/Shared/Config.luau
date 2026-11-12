--!strict
--[[
	Config: the single source of truth for every tunable number in Factory Empire.

	Rules:
	- No other module may hardcode costs, multipliers, odds, timers or prices.
	- Monetization IDs default to 0. Paste real IDs from Creator Hub (see README).
	- Visual parameters (colors, sizes, sounds) live under Config.Visuals so real
	  models can be swapped in later via Config.Visuals.ModelOverrides.
	- The pacing simulation (tools/pacing_sim.luau) reads this file directly, so
	  changing a number here and re-running the sim shows the pacing impact.
]]

local Config = {}

Config.GameName = "Factory Empire: Idle Tycoon"
Config.DataVersion = 2

--------------------------------------------------------------------------------
-- Ownership / admin
--------------------------------------------------------------------------------
Config.Admin = {
	-- The experience creator (user-owned place) is always admin. Add extra UserIds here.
	UserIds = {} :: { number },
	-- When the experience is group-owned, members at or above this rank are admins.
	GroupAdminMinRank = 255,
	-- Sanity bounds for admin command arguments and the metrics payload.
	Limits = {
		MaxEventMinutes = 720,
		MaxBanMinutes = 525600, -- 0 = permanent
		MaxGrantAmount = 1e100,
		MaxTextLength = 140,
		LogTail = 30,
		PushSeconds = 10,
	},
}

-- Roblox group for the +5% bonus and Group Gizmo. 0 disables group features.
Config.GroupId = 0

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------
Config.Data = {
	ProfileStoreName = "FactoryEmpire_PlayerData_v1",
	BanStoreName = "FactoryEmpire_Bans_v1",
	ExploitLogStoreName = "FactoryEmpire_ExploitLog_v1",
	-- Studio without API access falls back to ProfileStore.Mock automatically.
	ReplicationFlushSeconds = 0.25,
	PurchaseIdCacheSize = 100,
	WaitForTimeoutSeconds = 30, -- default DataService.WaitFor timeout
	LeaderstatsRefreshSeconds = 2,
	MultiplierRefreshSeconds = 5, -- expiry of boosts/events is picked up at this cadence
	Retry = {
		Attempts = 5,
		BaseDelaySeconds = 1,
		MaxDelaySeconds = 16,
	},
}

--------------------------------------------------------------------------------
-- Industries (floors) and production lines
--------------------------------------------------------------------------------
export type HallDef = {
	Id: string,
	Name: string,
	UnlockExpansions: number,
	Color: Color3,
	AccentColor: Color3,
}

Config.Halls = {
	{
		Id = "metal",
		Name = "Metalworks",
		UnlockExpansions = 0,
		Color = Color3.fromRGB(255, 140, 40),
		AccentColor = Color3.fromRGB(150, 160, 175),
	},
	{
		Id = "electronics",
		Name = "Electronics",
		UnlockExpansions = 1,
		Color = Color3.fromRGB(40, 210, 255),
		AccentColor = Color3.fromRGB(235, 245, 255),
	},
	{
		Id = "auto",
		Name = "Automobiles",
		UnlockExpansions = 3,
		Color = Color3.fromRGB(235, 55, 60),
		AccentColor = Color3.fromRGB(40, 40, 48),
	},
	{
		Id = "aviation",
		Name = "Aviation",
		UnlockExpansions = 6,
		Color = Color3.fromRGB(110, 180, 255),
		AccentColor = Color3.fromRGB(245, 250, 255),
	},
	{
		Id = "aerospace",
		Name = "Aerospace",
		UnlockExpansions = 10,
		Color = Color3.fromRGB(150, 90, 255),
		AccentColor = Color3.fromRGB(25, 30, 70),
	},
} :: { HallDef }

export type LineDef = {
	Name: string,
	Hall: number,
	Raw: string,
}

-- 30 lines, 6 per hall, in unlock order. Line k must be owned before line k+1.
Config.Lines = {
	{ Name = "Nails", Hall = 1, Raw = "Iron Ore" },
	{ Name = "Pipes", Hall = 1, Raw = "Iron Ore" },
	{ Name = "Gears", Hall = 1, Raw = "Steel" },
	{ Name = "Wrenches", Hall = 1, Raw = "Steel" },
	{ Name = "Steel Beams", Hall = 1, Raw = "Steel" },
	{ Name = "Engine Blocks", Hall = 1, Raw = "Cast Iron" },
	{ Name = "Copper Wire", Hall = 2, Raw = "Copper" },
	{ Name = "Circuit Board", Hall = 2, Raw = "Fiberglass" },
	{ Name = "Microchip", Hall = 2, Raw = "Silicon" },
	{ Name = "Battery Pack", Hall = 2, Raw = "Lithium" },
	{ Name = "Smartphone", Hall = 2, Raw = "Glass" },
	{ Name = "Robot Arm", Hall = 2, Raw = "Servo Kit" },
	{ Name = "Tire", Hall = 3, Raw = "Rubber" },
	{ Name = "Car Seat", Hall = 3, Raw = "Fabric" },
	{ Name = "Car Engine", Hall = 3, Raw = "Engine Block" },
	{ Name = "Chassis", Hall = 3, Raw = "Steel Beam" },
	{ Name = "Electric Motor", Hall = 3, Raw = "Copper Coil" },
	{ Name = "Sports Car", Hall = 3, Raw = "Body Panel" },
	{ Name = "Propeller", Hall = 4, Raw = "Aluminium" },
	{ Name = "Jet Turbine", Hall = 4, Raw = "Titanium" },
	{ Name = "Landing Gear", Hall = 4, Raw = "Hydraulics" },
	{ Name = "Wing", Hall = 4, Raw = "Carbon Fiber" },
	{ Name = "Cockpit", Hall = 4, Raw = "Avionics" },
	{ Name = "Jumbo Jet", Hall = 4, Raw = "Fuselage" },
	{ Name = "Heat Shield", Hall = 5, Raw = "Ceramic" },
	{ Name = "Rocket Nozzle", Hall = 5, Raw = "Niobium" },
	{ Name = "Fuel Tank", Hall = 5, Raw = "Cryo Alloy" },
	{ Name = "Satellite", Hall = 5, Raw = "Solar Cell" },
	{ Name = "Space Capsule", Hall = 5, Raw = "Life Support" },
	{ Name = "Rocket", Hall = 5, Raw = "Booster" },
} :: { LineDef }

Config.LinesPerHall = 6

Config.Economy = {
	-- Product value of line k:  ValueBase * ValueRatio^(k-1)
	ValueBase = 2,
	ValueRatio = 7,
	-- Unlock cost of line k (k >= 2):  CostBase * CostRatio^(k-2) * HallCostMult[hall]
	CostBase = 250,
	CostRatio = 15,
	-- Per-hall premium on line costs (entry cost smoothing; tuned with tools/pacing_sim.luau).
	HallCostMult = { 1, 1, 1, 1, 1 },
	-- Stage upgrade cost: ProductValue * UpgradeBaseSeconds * StageWeight * UpgradeGrowth^(L-1)
	UpgradeBaseSeconds = 4,
	UpgradeGrowth = 1.10,
	StageNames = { "Conveyor", "Processor", "Assembler", "Packer" },
	StageWeights = { 0.8, 1.0, 1.2, 0.9 },
	-- Stage speed(L) = L * MilestoneMult^floor(L / MilestoneEvery)
	MilestoneEvery = 25,
	MilestoneMult = 2,
	MaxStageLevel = 2000,
	-- Max levels bought by one "Max" press (protects the server from huge loops).
	MaxBulkLevels = 500,
	-- Server production tick (FactoryService) and the most seconds one tick may credit (lag protection).
	TickSeconds = 1,
	MaxTickSeconds = 5,
	-- Numbers are clamped below this to stay far from double overflow.
	NumberCeiling = 1e300,
}

Config.Overdrive = {
	Multiplier = 3,
	DurationSeconds = 20,
	CooldownSeconds = 60,
}

Config.Robots = {
	BaseCount = 1,
	-- +1 robot at each of these Expansion counts.
	BonusAtExpansions = { 2, 5, 8 },
	PassBonus = 2, -- "Hire Extra Robots" game pass
	SpeedBonus = 0.25, -- per robot assigned to a line
	MaxPerLine = 1,
	AutoOverdrive = true,
}

Config.Vault = {
	-- Capacity in minutes of current income for each vault tier.
	CapacityMinutes = { 10, 20, 30, 45, 60 },
	-- Tier t (t >= 2) costs the unlock cost of line (t + 1) of Metalworks scaled by the
	-- player's highest hall (so it stays relevant after Expansion).
	CostLineOffset = 1,
	CollectDistance = 60, -- studs from your vault pad for the HUD collect button
	TutorialCapacitySeconds = 20,
}

Config.Packaging = {
	Names = { "Plain Box", "Shrink Wrap", "Branded Box", "Premium Crate", "Luxury Case" },
	Bonus = { 0, 0.10, 0.25, 0.50, 1.00 },
	-- Tier t (t >= 2) costs the unlock cost of the hall's line t+1 times this.
	CostMult = 1.0,
}

--------------------------------------------------------------------------------
-- Expansion (prestige) and Franchise (endgame prestige layer)
--------------------------------------------------------------------------------
Config.Expansion = {
	-- Earnings in the current run needed for Expansion n (index = n).
	-- Fitted by tools/pacing_sim.luau --fit so run lengths grow smoothly.
	RequirementTable = {
		1.04e9,
		1.72e11,
		6.14e13,
		2.39e16,
		1.04e19,
		1.35e22,
		4.65e25,
		3.51e29,
		2.08e31,
		1.06e32,
		8.78e36,
		5.22e38,
	} :: { number },
	-- Beyond the table: Req(n) = Req(last) * BeyondGrowth^(n - last)
	BeyondGrowth = 60,
	MaxExpansions = 12, -- = Franchise.UnlockExpansions: past this point the endgame loop is Franchise
	-- Total Shares = floor(SharesK * (franchiseLifetimeEarnings / SharesDivisor)^SharesExponent)
	SharesK = 25,
	SharesDivisor = 1e9,
	SharesExponent = 0.2,
	BonusPerShare = 0.04,
	-- Machine bays: Base, +1 at each listed Expansion count.
	BaysBase = 3,
	BaysAtExpansions = { 1, 3, 6, 10 },
	BaysPassBonus = 2,
	StartingCash = 10, -- covers the first tutorial upgrade (~$6) before the Vault is introduced
}

Config.Franchise = {
	-- Franchise unlocks once the current franchise has reached this many Expansions.
	UnlockExpansions = 12,
	-- Permanent income multiplier: 1 + MultPerLevel * FranchiseLevel
	MultPerLevel = 1.0,
	-- Credits granted per Franchise level reached.
	CreditsPerLevel = 500,
	TitlePrefix = "Tycoon",
}

--------------------------------------------------------------------------------
-- Specialist machines
--------------------------------------------------------------------------------
Config.Rarities = {
	Order = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Special" },
	Colors = {
		Common = Color3.fromRGB(170, 172, 180),
		Rare = Color3.fromRGB(76, 217, 100),
		Epic = Color3.fromRGB(47, 128, 237),
		Legendary = Color3.fromRGB(255, 176, 32),
		Mythic = Color3.fromRGB(230, 60, 200),
		Secret = Color3.fromRGB(20, 20, 24),
		Special = Color3.fromRGB(255, 220, 90),
	} :: { [string]: Color3 },
}

export type AbilityKind =
	"CashBurst"
	| "NightShift"
	| "BigVault"
	| "OverdrivePlus"
	| "ContractPro"
	| "LabRat"
	| "Teamwork"
	| "RushHour"
	| "Bargain"

Config.AbilityCaps = {
	CashBurst = 0.50, -- +sale value fraction
	NightShift = 0.30, -- +offline efficiency (fraction points)
	BigVault = 2.00, -- +vault capacity fraction
	OverdrivePlus = 20, -- +seconds
	ContractPro = 0.50, -- +contract reward fraction
	LabRat = 0.30, -- -research time fraction
	Teamwork = 0.50, -- +income fraction while operated
	RushHour = 1, -- boolean-like: doubles machine power during Rush Orders
	Bargain = 0.20, -- -upgrade cost fraction
} :: { [string]: number }

Config.AbilityLabels = {
	CashBurst = "+%d%% sale value",
	NightShift = "+%d%% offline rate",
	BigVault = "+%d%% vault size",
	OverdrivePlus = "+%ds Overdrive",
	ContractPro = "+%d%% contract rewards",
	LabRat = "-%d%% research time",
	Teamwork = "+%d%% when operated",
	RushHour = "x2 power in Rush Orders",
	Bargain = "-%d%% upgrade cost",
} :: { [string]: string }

export type MachineVisual = {
	Shape: string, -- key understood by ServerStorage/Builders/MachineModelBuilder
	Primary: Color3,
	Secondary: Color3,
	Neon: Color3?,
	Particle: string?, -- "Sparks" | "Steam" | "Embers" | "Bubbles" | "Sparkles" | "Clouds" | "Coins" | nil
}

export type MachineDef = {
	Id: string,
	Name: string,
	Rarity: string,
	Hall: number, -- 0 = not tied to a hall
	Power: number, -- +% income while equipped
	Ability: { Kind: AbilityKind, Value: number }?,
	Source: string, -- "Shop" | "Credits" | "Contract" | "Mythic" | "Secret" | "Special" | "Pass"
	Tradable: boolean,
	Visual: MachineVisual,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Config.Machines = {
	-- Metalworks
	{
		Id = "rivet_bot",
		Name = "Rivet Bot",
		Rarity = "Common",
		Hall = 1,
		Power = 10,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "CubeBot", Primary = rgb(160, 165, 175), Secondary = rgb(90, 95, 105) },
	},
	{
		Id = "bolt_buddy",
		Name = "Bolt Buddy",
		Rarity = "Common",
		Hall = 1,
		Power = 10,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "HexBot", Primary = rgb(140, 150, 160), Secondary = rgb(255, 140, 40) },
	},
	{
		Id = "spark_welder",
		Name = "Spark Welder",
		Rarity = "Rare",
		Hall = 1,
		Power = 25,
		Source = "Shop",
		Tradable = true,
		Visual = {
			Shape = "Arm",
			Primary = rgb(255, 140, 40),
			Secondary = rgb(60, 60, 70),
			Neon = rgb(80, 180, 255),
			Particle = "Sparks",
		},
	},
	{
		Id = "steam_hammer",
		Name = "Steam Hammer",
		Rarity = "Rare",
		Hall = 1,
		Power = 25,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Press", Primary = rgb(120, 120, 130), Secondary = rgb(200, 90, 40), Particle = "Steam" },
	},
	{
		Id = "furnace_golem",
		Name = "Furnace Golem",
		Rarity = "Epic",
		Hall = 1,
		Power = 60,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "NightShift", Value = 0.10 },
		Visual = {
			Shape = "Golem",
			Primary = rgb(150, 70, 50),
			Secondary = rgb(60, 50, 50),
			Neon = rgb(255, 120, 20),
			Particle = "Embers",
		},
	},
	{
		Id = "crane_claw",
		Name = "Crane Claw",
		Rarity = "Epic",
		Hall = 1,
		Power = 60,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "BigVault", Value = 0.20 },
		Visual = { Shape = "Crane", Primary = rgb(255, 200, 40), Secondary = rgb(50, 50, 55) },
	},
	{
		Id = "titan_forge",
		Name = "Titan Forge",
		Rarity = "Legendary",
		Hall = 1,
		Power = 150,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "Bargain", Value = 0.05 },
		Visual = {
			Shape = "Forge",
			Primary = rgb(70, 60, 60),
			Secondary = rgb(255, 176, 32),
			Neon = rgb(255, 90, 0),
			Particle = "Embers",
		},
	},
	-- Electronics
	{
		Id = "solder_drone",
		Name = "Solder Drone",
		Rarity = "Common",
		Hall = 2,
		Power = 30,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Drone", Primary = rgb(235, 245, 255), Secondary = rgb(40, 210, 255) },
	},
	{
		Id = "chip_sorter",
		Name = "Chip Sorter",
		Rarity = "Common",
		Hall = 2,
		Power = 30,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Box", Primary = rgb(30, 120, 70), Secondary = rgb(220, 220, 230), Neon = rgb(80, 255, 140) },
	},
	{
		Id = "circuit_spider",
		Name = "Circuit Spider",
		Rarity = "Rare",
		Hall = 2,
		Power = 75,
		Source = "Shop",
		Tradable = true,
		Visual = {
			Shape = "Spider",
			Primary = rgb(20, 110, 60),
			Secondary = rgb(230, 200, 60),
			Neon = rgb(80, 255, 140),
		},
	},
	{
		Id = "laser_etcher",
		Name = "Laser Etcher",
		Rarity = "Rare",
		Hall = 2,
		Power = 75,
		Source = "Shop",
		Tradable = true,
		Visual = {
			Shape = "Gantry",
			Primary = rgb(220, 225, 235),
			Secondary = rgb(60, 60, 70),
			Neon = rgb(255, 40, 60),
		},
	},
	{
		Id = "server_tower",
		Name = "Server Tower",
		Rarity = "Epic",
		Hall = 2,
		Power = 180,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "ContractPro", Value = 0.10 },
		Visual = { Shape = "Tower", Primary = rgb(25, 25, 32), Secondary = rgb(60, 60, 70), Neon = rgb(40, 210, 255) },
	},
	{
		Id = "quantum_tester",
		Name = "Quantum Tester",
		Rarity = "Epic",
		Hall = 2,
		Power = 180,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "LabRat", Value = 0.10 },
		Visual = {
			Shape = "Orb",
			Primary = rgb(200, 240, 255),
			Secondary = rgb(60, 60, 80),
			Neon = rgb(150, 90, 255),
			Particle = "Sparkles",
		},
	},
	{
		Id = "mainframe_prime",
		Name = "Mainframe Prime",
		Rarity = "Legendary",
		Hall = 2,
		Power = 450,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "CashBurst", Value = 0.15 },
		Visual = {
			Shape = "ScreenWall",
			Primary = rgb(30, 35, 45),
			Secondary = rgb(255, 176, 32),
			Neon = rgb(40, 210, 255),
		},
	},
	-- Automobiles
	{
		Id = "wrench_arm",
		Name = "Wrench Arm",
		Rarity = "Common",
		Hall = 3,
		Power = 90,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Arm", Primary = rgb(235, 55, 60), Secondary = rgb(40, 40, 48) },
	},
	{
		Id = "tire_roller",
		Name = "Tire Roller",
		Rarity = "Common",
		Hall = 3,
		Power = 90,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Roller", Primary = rgb(30, 30, 34), Secondary = rgb(200, 200, 205) },
	},
	{
		Id = "paint_booth",
		Name = "Paint Booth",
		Rarity = "Rare",
		Hall = 3,
		Power = 225,
		Source = "Shop",
		Tradable = true,
		Visual = {
			Shape = "Booth",
			Primary = rgb(240, 240, 245),
			Secondary = rgb(235, 55, 60),
			Neon = rgb(255, 80, 200),
			Particle = "Sparkles",
		},
	},
	{
		Id = "torque_bot",
		Name = "Torque Bot",
		Rarity = "Rare",
		Hall = 3,
		Power = 225,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "CubeBot", Primary = rgb(255, 210, 40), Secondary = rgb(40, 40, 48) },
	},
	{
		Id = "crash_tester",
		Name = "Crash Tester",
		Rarity = "Epic",
		Hall = 3,
		Power = 540,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "OverdrivePlus", Value = 5 },
		Visual = { Shape = "Dummy", Primary = rgb(255, 220, 40), Secondary = rgb(30, 30, 34) },
	},
	{
		Id = "assembly_arm_x",
		Name = "Assembly Arm X",
		Rarity = "Epic",
		Hall = 3,
		Power = 540,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "Bargain", Value = 0.05 },
		Visual = { Shape = "TwinArm", Primary = rgb(235, 55, 60), Secondary = rgb(220, 220, 225) },
	},
	{
		Id = "turbo_press",
		Name = "Turbo Press",
		Rarity = "Legendary",
		Hall = 3,
		Power = 1350,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "RushHour", Value = 1 },
		Visual = {
			Shape = "Press",
			Primary = rgb(40, 40, 48),
			Secondary = rgb(235, 55, 60),
			Neon = rgb(255, 120, 20),
			Particle = "Embers",
		},
	},
	-- Aviation
	{
		Id = "rivet_drone",
		Name = "Rivet Drone",
		Rarity = "Common",
		Hall = 4,
		Power = 270,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Drone", Primary = rgb(110, 180, 255), Secondary = rgb(245, 250, 255) },
	},
	{
		Id = "wing_sander",
		Name = "Wing Sander",
		Rarity = "Common",
		Hall = 4,
		Power = 270,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Arm", Primary = rgb(245, 250, 255), Secondary = rgb(110, 180, 255) },
	},
	{
		Id = "wind_tunnel",
		Name = "Wind Tunnel",
		Rarity = "Rare",
		Hall = 4,
		Power = 675,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Ring", Primary = rgb(200, 220, 240), Secondary = rgb(60, 70, 90), Particle = "Clouds" },
	},
	{
		Id = "jet_balancer",
		Name = "Jet Balancer",
		Rarity = "Rare",
		Hall = 4,
		Power = 675,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Turbine", Primary = rgb(180, 185, 195), Secondary = rgb(110, 180, 255) },
	},
	{
		Id = "hangar_hauler",
		Name = "Hangar Hauler",
		Rarity = "Epic",
		Hall = 4,
		Power = 1620,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "BigVault", Value = 0.30 },
		Visual = { Shape = "Tug", Primary = rgb(255, 200, 40), Secondary = rgb(245, 250, 255) },
	},
	{
		Id = "autopilot_ai",
		Name = "Autopilot AI",
		Rarity = "Epic",
		Hall = 4,
		Power = 1620,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "Teamwork", Value = 0.20 },
		Visual = { Shape = "Orb", Primary = rgb(245, 250, 255), Secondary = rgb(25, 40, 90), Neon = rgb(110, 180, 255) },
	},
	{
		Id = "sky_foundry",
		Name = "Sky Foundry",
		Rarity = "Legendary",
		Hall = 4,
		Power = 4050,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "NightShift", Value = 0.15 },
		Visual = {
			Shape = "Platform",
			Primary = rgb(245, 250, 255),
			Secondary = rgb(255, 176, 32),
			Particle = "Clouds",
		},
	},
	-- Aerospace
	{
		Id = "orbit_bolter",
		Name = "Orbit Bolter",
		Rarity = "Common",
		Hall = 5,
		Power = 810,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "Satellite", Primary = rgb(200, 200, 210), Secondary = rgb(40, 70, 180) },
	},
	{
		Id = "thermal_tiler",
		Name = "Thermal Tiler",
		Rarity = "Common",
		Hall = 5,
		Power = 810,
		Source = "Shop",
		Tradable = true,
		Visual = { Shape = "CubeBot", Primary = rgb(30, 30, 36), Secondary = rgb(150, 90, 255) },
	},
	{
		Id = "fuel_mixer",
		Name = "Fuel Mixer",
		Rarity = "Rare",
		Hall = 5,
		Power = 2025,
		Source = "Shop",
		Tradable = true,
		Visual = {
			Shape = "Tanks",
			Primary = rgb(220, 225, 235),
			Secondary = rgb(25, 30, 70),
			Neon = rgb(80, 255, 200),
			Particle = "Bubbles",
		},
	},
	{
		Id = "orbital_welder",
		Name = "Orbital Welder",
		Rarity = "Rare",
		Hall = 5,
		Power = 2025,
		Source = "Shop",
		Tradable = true,
		Visual = {
			Shape = "Arm",
			Primary = rgb(25, 30, 70),
			Secondary = rgb(220, 225, 235),
			Neon = rgb(150, 90, 255),
			Particle = "Sparks",
		},
	},
	{
		Id = "launch_tower",
		Name = "Launch Tower",
		Rarity = "Epic",
		Hall = 5,
		Power = 4860,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "RushHour", Value = 1 },
		Visual = {
			Shape = "Tower",
			Primary = rgb(200, 60, 50),
			Secondary = rgb(220, 225, 235),
			Neon = rgb(255, 60, 60),
		},
	},
	{
		Id = "zero_g_printer",
		Name = "Zero-G Printer",
		Rarity = "Epic",
		Hall = 5,
		Power = 4860,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "LabRat", Value = 0.10 },
		Visual = {
			Shape = "GlassCube",
			Primary = rgb(200, 240, 255),
			Secondary = rgb(25, 30, 70),
			Neon = rgb(150, 90, 255),
		},
	},
	{
		Id = "star_forge",
		Name = "Star Forge",
		Rarity = "Legendary",
		Hall = 5,
		Power = 12150,
		Source = "Credits",
		Tradable = true,
		Ability = { Kind = "CashBurst", Value = 0.25 },
		Visual = {
			Shape = "Ring",
			Primary = rgb(25, 30, 70),
			Secondary = rgb(255, 176, 32),
			Neon = rgb(150, 90, 255),
			Particle = "Sparkles",
		},
	},
	-- Mythic (weekly global goal / Mega Contracts)
	{
		Id = "infinity_belt",
		Name = "Infinity Belt",
		Rarity = "Mythic",
		Hall = 0,
		Power = 3000,
		Source = "Mythic",
		Tradable = true,
		Ability = { Kind = "OverdrivePlus", Value = 10 },
		Visual = {
			Shape = "Ring",
			Primary = rgb(40, 40, 48),
			Secondary = rgb(230, 60, 200),
			Neon = rgb(255, 120, 230),
			Particle = "Sparkles",
		},
	},
	{
		Id = "atomic_assembler",
		Name = "Atomic Assembler",
		Rarity = "Mythic",
		Hall = 0,
		Power = 10000,
		Source = "Mythic",
		Tradable = true,
		Ability = { Kind = "Bargain", Value = 0.10 },
		Visual = {
			Shape = "Orb",
			Primary = rgb(220, 250, 255),
			Secondary = rgb(230, 60, 200),
			Neon = rgb(80, 255, 200),
			Particle = "Sparkles",
		},
	},
	{
		Id = "gold_rush_refinery",
		Name = "Gold Rush Refinery",
		Rarity = "Mythic",
		Hall = 0,
		Power = 25000,
		Source = "Mythic",
		Tradable = true,
		Ability = { Kind = "CashBurst", Value = 0.30 },
		Visual = {
			Shape = "Tower",
			Primary = rgb(255, 200, 40),
			Secondary = rgb(230, 60, 200),
			Neon = rgb(255, 230, 120),
			Particle = "Coins",
		},
	},
	{
		Id = "quantum_warehouse",
		Name = "Quantum Warehouse",
		Rarity = "Mythic",
		Hall = 0,
		Power = 60000,
		Source = "Mythic",
		Tradable = true,
		Ability = { Kind = "BigVault", Value = 1.00 },
		Visual = {
			Shape = "GlassCube",
			Primary = rgb(230, 60, 200),
			Secondary = rgb(40, 40, 48),
			Neon = rgb(255, 120, 230),
			Particle = "Sparkles",
		},
	},
	-- Secret (hidden R&D recipes). Rule: Power never exceeds the Legendary of the same hall.
	{
		Id = "rubber_duck_factory",
		Name = "Rubber Duck Factory",
		Rarity = "Secret",
		Hall = 1,
		Power = 120,
		Source = "Secret",
		Tradable = true,
		Ability = { Kind = "Teamwork", Value = 0.25 },
		Visual = {
			Shape = "DuckFactory",
			Primary = rgb(255, 220, 40),
			Secondary = rgb(255, 140, 40),
			Neon = rgb(255, 240, 120),
			Particle = "Bubbles",
		},
	},
	{
		Id = "pizza_printer",
		Name = "Pizza Printer",
		Rarity = "Secret",
		Hall = 2,
		Power = 400,
		Source = "Secret",
		Tradable = true,
		Ability = { Kind = "ContractPro", Value = 0.25 },
		Visual = {
			Shape = "Printer",
			Primary = rgb(240, 240, 245),
			Secondary = rgb(220, 60, 40),
			Neon = rgb(255, 200, 80),
		},
	},
	{
		Id = "toaster_rocket",
		Name = "Toaster Rocket",
		Rarity = "Secret",
		Hall = 4,
		Power = 3600,
		Source = "Secret",
		Tradable = true,
		Ability = { Kind = "RushHour", Value = 1 },
		Visual = {
			Shape = "Toaster",
			Primary = rgb(200, 205, 215),
			Secondary = rgb(255, 120, 20),
			Neon = rgb(255, 90, 0),
			Particle = "Embers",
		},
	},
	{
		Id = "cloud_maker",
		Name = "Cloud Maker",
		Rarity = "Secret",
		Hall = 5,
		Power = 11000,
		Source = "Secret",
		Tradable = true,
		Ability = { Kind = "NightShift", Value = 0.30 },
		Visual = { Shape = "Chimney", Primary = rgb(240, 245, 255), Secondary = rgb(150, 90, 255), Particle = "Clouds" },
	},
	-- Specials (never tradable)
	{
		Id = "founder_bot",
		Name = "Founder Bot",
		Rarity = "Special",
		Hall = 0,
		Power = 50,
		Source = "Special",
		Tradable = false,
		Visual = {
			Shape = "CubeBot",
			Primary = rgb(255, 210, 60),
			Secondary = rgb(40, 40, 48),
			Neon = rgb(255, 240, 160),
		},
	},
	{
		Id = "group_gizmo",
		Name = "Group Gizmo",
		Rarity = "Special",
		Hall = 0,
		Power = 40,
		Source = "Special",
		Tradable = false,
		Visual = { Shape = "HexBot", Primary = rgb(90, 200, 255), Secondary = rgb(255, 255, 255) },
	},
	{
		Id = "buddy_bot",
		Name = "Buddy Bot",
		Rarity = "Special",
		Hall = 0,
		Power = 180,
		Source = "Special",
		Tradable = false,
		Visual = { Shape = "CubeBot", Primary = rgb(76, 217, 100), Secondary = rgb(255, 255, 255) },
	},
	{
		Id = "party_crane",
		Name = "Party Crane",
		Rarity = "Special",
		Hall = 0,
		Power = 1350,
		Source = "Special",
		Tradable = false,
		Visual = { Shape = "Crane", Primary = rgb(255, 80, 200), Secondary = rgb(255, 220, 40), Particle = "Sparkles" },
	},
	{
		Id = "streak_steamer",
		Name = "Streak Steamer",
		Rarity = "Special",
		Hall = 0,
		Power = 540,
		Source = "Special",
		Tradable = false,
		Visual = { Shape = "Press", Primary = rgb(76, 217, 100), Secondary = rgb(40, 40, 48), Particle = "Steam" },
	},
	{
		Id = "loyalty_locomotive",
		Name = "Loyalty Locomotive",
		Rarity = "Special",
		Hall = 0,
		Power = 4050,
		Source = "Special",
		Tradable = false,
		Visual = { Shape = "Locomotive", Primary = rgb(255, 176, 32), Secondary = rgb(40, 40, 48), Particle = "Steam" },
	},
	{
		Id = "golden_robot",
		Name = "Golden Robot",
		Rarity = "Special",
		Hall = 0,
		Power = 250,
		Source = "Pass",
		Tradable = false,
		Ability = { Kind = "CashBurst", Value = 0.10 },
		Visual = {
			Shape = "CubeBot",
			Primary = rgb(255, 200, 40),
			Secondary = rgb(255, 240, 160),
			Neon = rgb(255, 240, 160),
			Particle = "Sparkles",
		},
	},
	{
		Id = "rivet_bot_tutorial",
		Name = "Rivet Bot",
		Rarity = "Common",
		Hall = 1,
		Power = 10,
		Source = "Special",
		Tradable = false,
		Visual = { Shape = "CubeBot", Primary = rgb(160, 165, 175), Secondary = rgb(90, 95, 105) },
	},
} :: { MachineDef }

Config.MachineGrades = {
	Names = { "Standard", "Chrome", "Gold-Plated" },
	PowerMult = { 1, 2, 4 },
	ChromeMergeCount = 3, -- 3 identical Standard -> 1 Chrome (instant)
	GoldMergeCount = 3, -- 3 identical Chrome -> 1 Gold-Plated after the plating timer
	PlatingSeconds = 3600,
	InventoryLimit = 150,
}

Config.MachineShop = {
	-- Cash price of Common/Rare = unlock cost of this line number inside the machine's hall.
	CommonCostLine = 3,
	RareCostLine = 5,
	-- Credits price for Epic/Legendary = Base * 2^(hall - 1).
	EpicCredits = 150,
	LegendaryCredits = 800,
}

Config.SecretRecipes = {
	-- The R&D Lab accepts exactly three different lines. A recipe matches when the three
	-- lines equal the set below and each is at least MinLevel. Discovery is deterministic.
	{
		MachineId = "rubber_duck_factory",
		Lines = { 1, 3, 5 },
		MinLevel = 75,
		Hint = "Something that floats... made of Nails, Gears and Steel Beams?",
	},
	{
		MachineId = "pizza_printer",
		Lines = { 4, 9, 10 },
		MinLevel = 50,
		Hint = "Wrenches, Microchips and Batteries walk into a kitchen...",
	},
	{
		MachineId = "toaster_rocket",
		Lines = { 11, 17, 20 },
		MinLevel = 50,
		Hint = "Smartphone + Electric Motor + Jet Turbine = breakfast?",
	},
	{
		MachineId = "cloud_maker",
		Lines = { 5, 19, 25 },
		MinLevel = 50,
		Hint = "Steel Beams, Propellers and a Heat Shield. Look up.",
	},
}

--------------------------------------------------------------------------------
-- Contracts (active layer). Odds apply to FREE rewards only. Robux never rolls.
--------------------------------------------------------------------------------
export type ContractTierDef = {
	Name: string,
	Weight: number,
	DurationSeconds: number,
	TargetSeconds: number, -- target = line output/s at offer time * TargetSeconds
	RewardIncomeMinutes: number,
	Credits: number,
	-- Ordered rarest first. Probabilities are absolute per completion.
	Odds: { { Rarity: string, Chance: number } },
	PityLegendary: number?, -- guaranteed Legendary blueprint on this completion count
}

Config.Contracts = {
	Slots = 3,
	ContractMasterExtraSlots = 1,
	RefillSeconds = 1200,
	ContractMasterRefillMult = 0.5,
	MinTarget = 10,
	TopLinesPool = 3, -- contracts pick from the player's N highest owned lines
	Tiers = {
		Bronze = {
			Name = "Bronze",
			Weight = 60,
			DurationSeconds = 300,
			TargetSeconds = 240,
			RewardIncomeMinutes = 10,
			Credits = 10,
			Odds = { { Rarity = "Rare", Chance = 0.03 } },
		},
		Silver = {
			Name = "Silver",
			Weight = 30,
			DurationSeconds = 1200,
			TargetSeconds = 900,
			RewardIncomeMinutes = 45,
			Credits = 30,
			Odds = { { Rarity = "Epic", Chance = 0.02 }, { Rarity = "Rare", Chance = 0.10 } },
		},
		Gold = {
			Name = "Gold",
			Weight = 10,
			DurationSeconds = 3600,
			TargetSeconds = 2700,
			RewardIncomeMinutes = 180,
			Credits = 100,
			Odds = {
				{ Rarity = "Legendary", Chance = 0.02 },
				{ Rarity = "Epic", Chance = 0.08 },
				{ Rarity = "Rare", Chance = 0.25 },
			},
			PityLegendary = 40,
		},
	} :: { [string]: ContractTierDef },
	TierOrder = { "Bronze", "Silver", "Gold" },
	ExtendSeconds = 600, -- "Contract Extend" developer product
	Tutorial = {
		Line = 1,
		Target = 50,
		DurationSeconds = 120,
		RewardCash = 250,
		RewardCredits = 10,
	},
	Mega = {
		JoinWindowSeconds = 60,
		DurationSeconds = 1800,
		TargetSeconds = 1200,
		MinPlayers = 2,
		MaxPlayers = 4,
		PointsPerWin = 1,
		PointsForMythic = 10,
		CooldownSeconds = 300,
	},
}

--------------------------------------------------------------------------------
-- R&D Lab (4-hour timers, permanent research)
--------------------------------------------------------------------------------
export type ResearchDef = {
	Id: string,
	Name: string,
	MaxLevel: number,
	BaseCredits: number,
	CostGrowth: number,
	DurationSeconds: number,
	Effect: string, -- "IncomeMult" | "OfflineHours" | "ExtraBay" | "ContractReward" | "UpgradeDiscount"
	ValuePerLevel: number,
}

Config.Research = {
	{
		Id = "lean",
		Name = "Lean Manufacturing",
		MaxLevel = 10,
		BaseCredits = 150,
		CostGrowth = 1.5,
		DurationSeconds = 14400,
		Effect = "IncomeMult",
		ValuePerLevel = 0.10,
	},
	{
		Id = "night_office",
		Name = "Night Shift Office",
		MaxLevel = 4,
		BaseCredits = 100,
		CostGrowth = 2,
		DurationSeconds = 14400,
		Effect = "OfflineHours",
		ValuePerLevel = 1,
	},
	{
		Id = "extra_bay",
		Name = "Bay Extension",
		MaxLevel = 1,
		BaseCredits = 2000,
		CostGrowth = 1,
		DurationSeconds = 14400,
		Effect = "ExtraBay",
		ValuePerLevel = 1,
	},
	{
		Id = "contract_desk",
		Name = "Contract Desk",
		MaxLevel = 5,
		BaseCredits = 200,
		CostGrowth = 1.6,
		DurationSeconds = 14400,
		Effect = "ContractReward",
		ValuePerLevel = 0.10,
	},
	{
		Id = "fast_tooling",
		Name = "Fast Tooling",
		MaxLevel = 3,
		BaseCredits = 300,
		CostGrowth = 2,
		DurationSeconds = 14400,
		Effect = "UpgradeDiscount",
		ValuePerLevel = 0.05,
	},
} :: { ResearchDef }

--------------------------------------------------------------------------------
-- Product catalog (permanent collection)
--------------------------------------------------------------------------------
Config.Catalog = {
	StampNames = { "Bronze", "Silver", "Gold", "Diamond" },
	-- Stamp s is earned when the line's lowest stage level reaches Thresholds[s].
	Thresholds = { 1, 50, 100, 200 },
	-- Income bonus added by each stamp (cumulative per line).
	Bonus = { 0.01, 0.02, 0.05, 0.10 },
	Credits = { 5, 10, 25, 50 },
	-- Completing Gold on all six lines of a hall.
	HallGoldBonus = 0.10,
}

--------------------------------------------------------------------------------
-- Retention
--------------------------------------------------------------------------------
export type DailyRewardDef = {
	Kind: string, -- "IncomeMinutes" | "Credits" | "Boost" | "MachineChoice"
	Amount: number,
	BoostKey: string?,
	Rarity: string?,
}

Config.DailyRewards = {
	Cycle = {
		{ Kind = "IncomeMinutes", Amount = 15 },
		{ Kind = "Credits", Amount = 25 },
		{ Kind = "Boost", Amount = 15, BoostKey = "Cash2x" },
		{ Kind = "IncomeMinutes", Amount = 30 },
		{ Kind = "Credits", Amount = 50 },
		{ Kind = "Boost", Amount = 30, BoostKey = "OverdriveAll" },
		{ Kind = "MachineChoice", Amount = 100, Rarity = "Rare" }, -- Rare machine of choice + 100 Credits
	} :: { DailyRewardDef },
	Milestones = {
		{ Day = 14, MachineId = "streak_steamer" },
		{ Day = 30, MachineId = "loyalty_locomotive", Title = "Industrialist" },
	},
	ClaimCooldownHours = 20,
	StreakGraceHours = 48,
	FreeShieldsPerWeek = 1,
	MaxShields = 3,
	ShieldCreditCost = 50,
}

export type QuestDef = {
	Id: string,
	Text: string, -- %s is replaced by the formatted target
	Kind: string, -- event counter key (see ServerSignals)
	TargetMode: string, -- "Fixed" | "OutputSeconds" | "IncomeSeconds"
	Base: number,
	Credits: number,
}

Config.Quests = {
	DailyCount = 3,
	WeeklyCount = 3,
	AllDailyBonusCredits = 30,
	Daily = {
		{
			Id = "ship",
			Text = "Ship %s products",
			Kind = "ProductsShipped",
			TargetMode = "OutputSeconds",
			Base = 600,
			Credits = 20,
		},
		{
			Id = "contracts",
			Text = "Complete %s contracts",
			Kind = "ContractsCompleted",
			TargetMode = "Fixed",
			Base = 3,
			Credits = 40,
		},
		{
			Id = "overdrive",
			Text = "Use Overdrive %s times",
			Kind = "OverdriveUsed",
			TargetMode = "Fixed",
			Base = 10,
			Credits = 20,
		},
		{
			Id = "upgrades",
			Text = "Buy %s machine upgrades",
			Kind = "UpgradesBought",
			TargetMode = "Fixed",
			Base = 50,
			Credits = 25,
		},
		{
			Id = "operate",
			Text = "Operate a friend's line for %s minutes",
			Kind = "OperateSeconds",
			TargetMode = "Fixed",
			Base = 300,
			Credits = 50,
		},
		{
			Id = "vault",
			Text = "Collect the Vault %s times",
			Kind = "VaultCollected",
			TargetMode = "Fixed",
			Base = 5,
			Credits = 20,
		},
		{
			Id = "earn",
			Text = "Earn %s cash",
			Kind = "CashEarned",
			TargetMode = "IncomeSeconds",
			Base = 1800,
			Credits = 30,
		},
		{
			Id = "supply",
			Text = "Open %s Supply Drops",
			Kind = "SupplyOpened",
			TargetMode = "Fixed",
			Base = 1,
			Credits = 20,
		},
	} :: { QuestDef },
	Weekly = {
		{
			Id = "w_expand",
			Text = "Expand %s time(s)",
			Kind = "Expanded",
			TargetMode = "Fixed",
			Base = 1,
			Credits = 200,
		},
		{
			Id = "w_gold",
			Text = "Complete %s Gold contract(s)",
			Kind = "GoldContracts",
			TargetMode = "Fixed",
			Base = 1,
			Credits = 200,
		},
		{
			Id = "w_contracts",
			Text = "Complete %s contracts",
			Kind = "ContractsCompleted",
			TargetMode = "Fixed",
			Base = 25,
			Credits = 200,
		},
		{
			Id = "w_upgrades",
			Text = "Buy %s machine upgrades",
			Kind = "UpgradesBought",
			TargetMode = "Fixed",
			Base = 1000,
			Credits = 200,
		},
		{
			Id = "w_ship",
			Text = "Ship %s products",
			Kind = "ProductsShipped",
			TargetMode = "OutputSeconds",
			Base = 14400,
			Credits = 200,
		},
	} :: { QuestDef },
	WeeklyBoostKey = "Cash2x",
	WeeklyBoostMinutes = 60,
}

Config.SupplyDrop = {
	IntervalSeconds = 4 * 3600,
	MaxStored = 2,
	IncomeMinutes = 30,
	Credits = 10,
}

Config.Offline = {
	Efficiency = 0.20,
	BaseCapHours = 2,
	PassCapMult = 2,
	MinSeconds = 60,
	CheckpointSeconds = 60, -- LastSeen/LastIncome refresh while online (crash safety)
	DoubleWithAd = true,
}

--------------------------------------------------------------------------------
-- Boosts (timed multipliers). Durations come from products/rewards.
--------------------------------------------------------------------------------
Config.Boosts = {
	Cash2x = { Name = "2x Cash", IncomeMult = 2 },
	OverdriveAll = { Name = "Overdrive All", IncomeMult = 1.5 },
	GoalBoost = { Name = "Community Boost", IncomeMult = 1.25 },
	Apprentice = { Name = "Apprentice", IncomeMult = 1.25 },
} :: { [string]: { Name: string, IncomeMult: number } }

--------------------------------------------------------------------------------
-- Events (server time, UTC)
--------------------------------------------------------------------------------
export type RewardDef = {
	Count: number?,
	Credits: number?,
	MachineId: string?,
	BoostKey: string?,
	Minutes: number?,
	Title: string?,
	MythicOfWeek: boolean?,
}

Config.Events = {
	RushOrders = {
		UtcHours = { 0, 12, 18 },
		DurationMinutes = 15,
		ContractRewardMult = 2,
	},
	Weekend = {
		-- os.date("!*t").wday: Sunday = 1 ... Saturday = 7
		StartWday = 6,
		StartHour = 18,
		EndWday = 1, -- inclusive through 23:59:59 UTC Sunday
		CashMult = 2,
	},
	GlobalGoal = {
		MapName = "FactoryEmpire_GlobalGoal",
		FlushSeconds = 60,
		PollSeconds = 60,
		-- Contracts completed by all servers in an ISO week.
		Tiers = { 5000, 25000, 100000 },
		MinPersonalContracts = 3,
		Rewards = {
			{ Credits = 100 },
			{ BoostKey = "GoalBoost", Minutes = 24 * 60 },
			{ MythicOfWeek = true },
		} :: { RewardDef },
		MythicRotation = { "infinity_belt", "atomic_assembler", "gold_rush_refinery", "quantum_warehouse" },
		ExpirationSeconds = 14 * 24 * 3600,
	},
	MessagingTopic = "FactoryEmpire_Global",
	StateBroadcastSeconds = 5, -- EventState push cadence
	MaxForcedMinutes = 24 * 60, -- sanity cap for admin-forced events received over MessagingService
	AnnounceRarities = { "Legendary", "Mythic", "Secret" },
	-- Biweekly update cadence (used by the "next update" countdown in the HUD).
	UpdateCadenceDays = 14,
	UpdateEpochUnix = 1795046400, -- Thursday 2026-11-19 00:00 UTC; set to your launch Thursday
	SeasonalLine = {
		Enabled = false,
		Name = "Snow Globes",
		StartUnix = 0,
		EndUnix = 0,
		ValueMultOfTopLine = 1.5,
	},
}

--------------------------------------------------------------------------------
-- Social
--------------------------------------------------------------------------------
Config.Social = {
	OperatorBonusPerOperator = 0.25,
	MaxOperators = 2,
	OperatorMaxDistance = 40,
	OperatorTimeoutSeconds = 30, -- operator counts while they pulled a lever in the last N seconds
	ApprenticeAfterSeconds = 300,
	ApprenticeMinutes = 15,
	FriendsOnlyOperators = true,
	GroupBonus = 0.05,
	GroupMachineId = "group_gizmo", -- one-time machine for group members
	MaxTitleLength = 40,
	PremiumBonus = 0.10,
	ReferralMinPlaySeconds = 300,
	InviteRewards = {
		{ Count = 1, MachineId = "buddy_bot" },
		{ Count = 3, BoostKey = "Cash2x", Minutes = 60 },
		{ Count = 5, MachineId = "party_crane" },
		{ Count = 10, Title = "Tycoon Recruiter" },
	} :: { RewardDef },
	PlotsPerServer = 8,
}

Config.Trade = {
	Enabled = true,
	MaxItemsPerSide = 6,
	CountdownSeconds = 3,
	CooldownSeconds = 30,
	MinAccountAgeDays = 3,
	MinPlaySeconds = 1200,
	RequestTimeoutSeconds = 30,
	MaxSessionSeconds = 300,
	-- Warn when one side's total Power is this many times the other's.
	LopsidedWarnRatio = 3,
	LogStoreName = "FactoryEmpire_TradeLog_v1",
}

--------------------------------------------------------------------------------
-- Monetization. Paste IDs from Creator Hub; prices are shown in UI and docs.
-- NO paid randomness: nothing sold here rolls odds or completes a contract.
--------------------------------------------------------------------------------
export type PassDef = { Id: number, Price: number, Name: string, Description: string, Order: number }
export type ProductDef = {
	Id: number,
	Price: number,
	Name: string,
	Description: string,
	Grant: string, -- handler key in ShopService
	Amount: number?,
	BoostKey: string?,
	Minutes: number?,
	OneTime: boolean?,
	Badge: string?, -- "BEST VALUE" | "POPULAR" | nil
	Order: number,
	Category: string, -- "Cash" | "Credits" | "Boosts" | "Utility" | "Offers"
	Giftable: boolean?,
}

Config.GamePasses = {
	Cash2x = { Id = 0, Price = 399, Name = "2x Cash", Description = "Double all income forever.", Order = 1 },
	AutoCollect = {
		Id = 0,
		Price = 149,
		Name = "Auto-Collect",
		Description = "Vault cash goes straight to your wallet.",
		Order = 2,
	},
	ExtraRobots = {
		Id = 0,
		Price = 299,
		Name = "Hire Extra Robots",
		Description = "+2 robot workers that boost lines and auto-Overdrive.",
		Order = 3,
	},
	TurboConveyors = {
		Id = 0,
		Price = 279,
		Name = "Turbo Conveyors",
		Description = "+30% production on every line.",
		Order = 4,
	},
	OfflineX2 = {
		Id = 0,
		Price = 149,
		Name = "Offline Cap x2",
		Description = "Earn offline for twice as long.",
		Order = 5,
	},
	VIP = {
		Id = 0,
		Price = 499,
		Name = "VIP Office",
		Description = "+10% income, VIP tag, VIP lounge, Golden Robot.",
		Order = 6,
	},
	ExtraBays = {
		Id = 0,
		Price = 349,
		Name = "Extra Machine Bays",
		Description = "+2 specialist machine bays.",
		Order = 7,
	},
	ContractMaster = {
		Id = 0,
		Price = 249,
		Name = "Contract Master",
		Description = "+1 contract slot and 2x faster refills.",
		Order = 8,
	},
} :: { [string]: PassDef }

Config.PassEffects = {
	Cash2xMult = 2,
	TurboConveyorsMult = 1.30,
	VIPIncomeBonus = 0.10,
	VIPMachineId = "golden_robot",
}

Config.DevProducts = {
	CashSmall = {
		Id = 0,
		Price = 49,
		Name = "Cash Crate",
		Description = "30 minutes of income.",
		Grant = "IncomeMinutes",
		Amount = 30,
		Order = 1,
		Category = "Cash",
	},
	CashMedium = {
		Id = 0,
		Price = 149,
		Name = "Cash Pallet",
		Description = "2 hours of income.",
		Grant = "IncomeMinutes",
		Amount = 120,
		Badge = "POPULAR",
		Order = 2,
		Category = "Cash",
	},
	CashLarge = {
		Id = 0,
		Price = 499,
		Name = "Cash Truck",
		Description = "10 hours of income.",
		Grant = "IncomeMinutes",
		Amount = 600,
		Badge = "BEST VALUE",
		Order = 3,
		Category = "Cash",
	},
	CreditsSmall = {
		Id = 0,
		Price = 99,
		Name = "100 Credits",
		Description = "Spend in the Contract Shop and R&D Lab.",
		Grant = "Credits",
		Amount = 100,
		Order = 4,
		Category = "Credits",
	},
	CreditsMedium = {
		Id = 0,
		Price = 299,
		Name = "350 Credits",
		Description = "Spend in the Contract Shop and R&D Lab.",
		Grant = "Credits",
		Amount = 350,
		Badge = "POPULAR",
		Order = 5,
		Category = "Credits",
	},
	CreditsLarge = {
		Id = 0,
		Price = 899,
		Name = "1,200 Credits",
		Description = "Spend in the Contract Shop and R&D Lab.",
		Grant = "Credits",
		Amount = 1200,
		Badge = "BEST VALUE",
		Order = 6,
		Category = "Credits",
	},
	Boost15 = {
		Id = 0,
		Price = 49,
		Name = "2x Cash (15 min)",
		Description = "Double income for 15 minutes.",
		Grant = "Boost",
		BoostKey = "Cash2x",
		Minutes = 15,
		Order = 7,
		Category = "Boosts",
		Giftable = true,
	},
	Boost30 = {
		Id = 0,
		Price = 89,
		Name = "2x Cash (30 min)",
		Description = "Double income for 30 minutes.",
		Grant = "Boost",
		BoostKey = "Cash2x",
		Minutes = 30,
		Badge = "POPULAR",
		Order = 8,
		Category = "Boosts",
		Giftable = true,
	},
	Boost60 = {
		Id = 0,
		Price = 149,
		Name = "2x Cash (60 min)",
		Description = "Double income for 60 minutes.",
		Grant = "Boost",
		BoostKey = "Cash2x",
		Minutes = 60,
		Badge = "BEST VALUE",
		Order = 9,
		Category = "Boosts",
		Giftable = true,
	},
	SkipResearch = {
		Id = 0,
		Price = 99,
		Name = "Finish Research",
		Description = "Complete the running R&D project now.",
		Grant = "SkipResearch",
		Order = 10,
		Category = "Utility",
	},
	SkipPlating = {
		Id = 0,
		Price = 49,
		Name = "Finish Plating",
		Description = "Complete Gold plating now.",
		Grant = "SkipPlating",
		Order = 11,
		Category = "Utility",
	},
	ContractExtend = {
		Id = 0,
		Price = 29,
		Name = "Contract Extension",
		Description = "+10 minutes on all running contracts.",
		Grant = "ContractExtend",
		Order = 12,
		Category = "Utility",
	},
	SharesPack = {
		Id = 0,
		Price = 199,
		Name = "Investor Shares",
		Description = "+5% of your Shares (minimum 5).",
		Grant = "Shares",
		Amount = 0.05,
		Order = 13,
		Category = "Utility",
	},
	StarterPack = {
		Id = 0,
		Price = 99,
		Name = "Starter Pack",
		Description = "2h of income, 300 Credits, a Rare machine and 1h 2x Cash.",
		Grant = "StarterPack",
		OneTime = true,
		Badge = "70% OFF",
		Order = 0,
		Category = "Offers",
	},
	WeekendBundle = {
		Id = 0,
		Price = 199,
		Name = "Weekend Bundle",
		Description = "4h of income, 200 Credits, 1h 2x Cash.",
		Grant = "Bundle",
		Order = 14,
		Category = "Offers",
	},
	OfflineDouble = {
		Id = 0,
		Price = 25,
		Name = "Double Offline Earnings",
		Description = "Double the offline cash you just collected.",
		Grant = "OfflineDouble",
		Order = 15,
		Category = "Utility",
	},
	AdBoost = {
		Id = 0,
		Price = 25,
		Name = "Ad Boost",
		Description = "2x Cash for 10 minutes (also earned by watching an ad).",
		Grant = "Boost",
		BoostKey = "Cash2x",
		Minutes = 10,
		Order = 16,
		Category = "Boosts",
	},
} :: { [string]: ProductDef }

Config.Shop = {
	-- Credits granted when a skip product finds nothing to skip by the time the receipt is processed.
	FallbackCreditsPerRobux = 1,
	ProfileWaitSeconds = 30, -- how long ProcessReceipt waits for a joining player's profile
	GiftIntentSeconds = 120, -- a gift prompt is honoured for this long
}

Config.Bundles = {
	StarterPack = {
		IncomeMinutes = 120,
		Credits = 300,
		RareOfHighestHall = true,
		BoostKey = "Cash2x",
		BoostMinutes = 60,
	},
	WeekendBundle = { IncomeMinutes = 240, Credits = 200, BoostKey = "Cash2x", BoostMinutes = 60 },
}

Config.Offers = {
	-- The Starter Pack is offered after the first Expansion OR 12 minutes of playtime (whichever first),
	-- then stays in the shop with a 48h countdown from the first impression.
	StarterPackShowAfterSeconds = 720,
	StarterPackWindowHours = 48,
	-- Limited-time offers keyed by product; shown with a countdown while active.
	Limited = {
		{ ProductKey = "WeekendBundle", Recurring = "Weekend" },
	},
	FirstOfferMinPlaySeconds = 600,
}

Config.Premium = {
	IncomeBonus = 0.10,
	DailyCredits = 20,
}

Config.Ads = {
	-- Rewarded video ads (VERIFY eligibility). Rewards are dev products granted via ProcessReceipt
	-- with ProductPurchaseChannel.AdReward.
	Enabled = true,
	Placements = {
		OfflineDouble = "OfflineDouble",
		Boost = "AdBoost",
	},
	CooldownSeconds = 600,
	MaxPerDay = 6,
}

--------------------------------------------------------------------------------
-- Promo codes (unix expiry, UTC). Codes give Credits/boosts only.
--------------------------------------------------------------------------------
Config.Codes = {
	FACTORY = { Credits = 50, BoostKey = "Cash2x", Minutes = 15, ExpiresUnix = 1830211200 },
	["1KLIKES"] = { Credits = 75, ExpiresUnix = 1830211200 },
	ROCKETMAN = { Credits = 100, BoostKey = "Cash2x", Minutes = 30, ExpiresUnix = 1830211200 },
} :: { [string]: { Credits: number?, BoostKey: string?, Minutes: number?, ExpiresUnix: number } }

--------------------------------------------------------------------------------
-- Leaderboards (OrderedDataStore stores integers -> log10 encoding)
--------------------------------------------------------------------------------
Config.Leaderboards = {
	LogScale = 1e6, -- stored = floor(log10(x) * LogScale)
	TopN = 50,
	RefreshSeconds = 120,
	WriteSeconds = 180,
	Boards = {
		{
			Key = "Richest",
			Title = "Richest Factory",
			Store = "FE_LB_Richest_v1",
			Stat = "TotalEarnings",
			Encoding = "Log",
		},
		{
			Key = "Shipped",
			Title = "Most Products Shipped",
			Store = "FE_LB_Shipped_v1",
			Stat = "ProductsShipped",
			Encoding = "Log",
		},
		{
			Key = "Industry",
			Title = "Highest Industry",
			Store = "FE_LB_Industry_v1",
			Stat = "IndustryScore",
			Encoding = "Int",
		},
		{
			Key = "Weekly",
			Title = "This Week's Tycoons",
			Store = "FE_LB_Weekly_v1",
			Stat = "WeeklyEarnings",
			Encoding = "Log",
			Weekly = true,
		},
	},
	WeeklyTopRewardTitle = "Weekly Tycoon",
	-- Industry board score = Franchise * IndustryFranchiseWeight + Expansions (weight > MaxExpansions).
	IndustryFranchiseWeight = 1000,
	-- Rows drawn on the physical plaza boards.
	PhysicalRows = 10,
}

--------------------------------------------------------------------------------
-- Anti-exploit
--------------------------------------------------------------------------------
Config.AntiExploit = {
	CheckIntervalSeconds = 1,
	WalkSpeed = 16,
	SpeedTolerance = 1.6, -- allowed horizontal speed = WalkSpeed * tolerance
	TeleportStuds = 80, -- per check interval; above this and not server-teleported => strike
	StrikesToKick = 6,
	StrikeDecaySeconds = 60,
	DefaultRate = { Calls = 20, PerSeconds = 10 },
	Rates = {
		UpgradeStage = { Calls = 60, PerSeconds = 10 },
		Overdrive = { Calls = 10, PerSeconds = 10 },
		TradeSetOffer = { Calls = 15, PerSeconds = 10 },
		RedeemCode = { Calls = 5, PerSeconds = 60 },
		AdminCommand = { Calls = 30, PerSeconds = 10 },
	} :: { [string]: { Calls: number, PerSeconds: number } },
	LogFlushSeconds = 60,
	MaxLogEntriesPerFlush = 50,
	LogRingSize = 200,
	TeleportAllowSeconds = 3, -- default window opened by AllowTeleport
	BanCacheSeconds = 60,
}

--------------------------------------------------------------------------------
-- Tutorial (first 3 minutes)
--------------------------------------------------------------------------------
Config.Tutorial = {
	WelcomeCrateCash = 100,
	FreeMachineId = "rivet_bot_tutorial",
	Steps = {
		"TapBottleneck", -- 0-10s: arrow to the bottleneck, "TAP"
		"UpgradeFive", -- 10-40s: welcome crate + 5 upgrades
		"CollectVault", -- 40-70s
		"Contract", -- 70-120s: Make 50 Nails
		"BuyLine2", -- build Pipes
		"Overdrive", -- 120-150s: HOLD the lever
		"EquipMachine", -- 150-180s: free Rivet Bot
		"Done",
	},
	UpgradeCount = 5,
}

--------------------------------------------------------------------------------
-- Plots & world layout (studs)
--------------------------------------------------------------------------------
Config.World = {
	PlotCount = 8,
	PlotRingRadius = 230,
	PlotSize = Vector3.new(110, 1, 130),
	FloorHeight = 26,
	LineSpacing = 16,
	LineLength = 70,
	PlazaRadius = 70,
	SpawnHeight = 4,
	RocketLaunchEvery = 200, -- Rockets shipped per visible launch
}

--------------------------------------------------------------------------------
-- Visuals (procedural generation). Swap any procedural model for a real one by
-- putting a Model named after the key in ServerStorage/ModelOverrides and listing it here.
--------------------------------------------------------------------------------
export type ParticlePreset = {
	Texture: string,
	Rate: number,
	LifetimeMin: number,
	LifetimeMax: number,
	SpeedMin: number,
	SpeedMax: number,
	Spread: number, -- degrees
	Size: number,
	SizeEnd: number,
	Color: Color3,
	LightEmission: number,
	Transparency: number, -- start value, fades to 1
	Acceleration: Vector3,
}

Config.Visuals = {
	ModelOverrides = {} :: { [string]: string },
	Palette = {
		Ground = Color3.fromRGB(110, 200, 120),
		Plaza = Color3.fromRGB(235, 235, 240),
		Road = Color3.fromRGB(60, 62, 70),
		PlotBase = Color3.fromRGB(205, 210, 220),
		Conveyor = Color3.fromRGB(45, 48, 56),
		ConveyorStripe = Color3.fromRGB(255, 200, 40),
		Truck = Color3.fromRGB(255, 255, 255),
		Bottleneck = Color3.fromRGB(255, 60, 60),
		Cash = Color3.fromRGB(90, 230, 110),
		Credits = Color3.fromRGB(80, 190, 255),
		UIBackground = Color3.fromRGB(28, 30, 40),
		UIPanel = Color3.fromRGB(42, 45, 60),
		UIAccent = Color3.fromRGB(255, 176, 32),
		UIText = Color3.fromRGB(255, 255, 255),
		UIGood = Color3.fromRGB(76, 217, 100),
		UIBad = Color3.fromRGB(235, 70, 70),
	},
	-- Machine colour by the line's lowest stage level.
	LevelTiers = {
		{ MinLevel = 0, Color = Color3.fromRGB(170, 172, 180) },
		{ MinLevel = 25, Color = Color3.fromRGB(76, 217, 100) },
		{ MinLevel = 50, Color = Color3.fromRGB(47, 128, 237) },
		{ MinLevel = 75, Color = Color3.fromRGB(160, 80, 240) },
		{ MinLevel = 100, Color = Color3.fromRGB(255, 176, 32) },
		{ MinLevel = 200, Color = Color3.fromRGB(255, 60, 120) },
	},
	Conveyor = {
		MaxItemsPerLine = 10, -- pooled parts per line (client)
		ItemSize = Vector3.new(1.2, 1.2, 1.2),
		BaseItemSpeed = 6, -- studs/s at speed 1
		MaxItemSpeed = 22,
		VisibleRadius = 180, -- only lines within this distance animate
		SpeedPerDecade = 0.8, -- studs/s added per power of ten of line Output
		OtherPlayerSpeed = 10, -- fixed speed on other players' plots
		ItemSpacing = 6, -- studs between pooled items
		ScanSeconds = 0.5, -- how often the client re-checks which plots/lines are near
		LowGraphicsScale = 0.5, -- pooled item multiplier with Settings.LowGraphics
	},
	TruckIntervalSeconds = 8,
	FloatingTextSeconds = 1.2,
	Truck = {
		Size = Vector3.new(7, 3.6, 3.4), -- cargo box; cab and wheels derive from it
		DriveSeconds = 5,
		CabColor = Color3.fromRGB(235, 70, 70),
		WheelColor = Color3.fromRGB(30, 30, 34),
		TextRise = 6, -- studs the "+$" label floats above the truck
	},
	Rocket = {
		BodyHeight = 9,
		BodyDiameter = 2.6,
		BodyColor = Color3.fromRGB(245, 248, 255),
		NoseColor = Color3.fromRGB(235, 55, 60),
		FinColor = Color3.fromRGB(235, 55, 60),
		WindowColor = Color3.fromRGB(110, 200, 255),
		FlameColor = Color3.fromRGB(255, 170, 60),
		FlightSeconds = 6,
		FlightHeight = 520,
		FlameSize = Vector3.new(1.8, 4, 1.8),
	},
	Effects = {
		BurstCount = 40,
		MilestoneText = "x2 SPEED!",
		MilestoneColor = Color3.fromRGB(255, 220, 90),
		TextSeconds = 1.6,
		TextRise = 7,
		LineDropHeight = 16,
		LineDropSeconds = 0.55,
		CoinSeconds = 1.6,
		ShockwaveRadius = 110,
		ShockwaveSeconds = 1.1,
		ExpansionColor = Color3.fromRGB(255, 220, 90),
		FranchiseColor = Color3.fromRGB(255, 80, 200),
	},
	Bottleneck = {
		Radius = 70, -- only stages this close to the player get a ring
		Diameter = 9,
		Thickness = 0.4,
		PulseSeconds = 0.7,
		MinTransparency = 0.25,
		MaxTransparency = 0.8,
	},
	VIPDoor = { OpenTransparency = 0.75 },
	Labels = {
		Font = Enum.Font.GothamBlack,
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(20, 22, 30),
		StrokeTransparency = 0.35,
		MaxDistance = 140,
		BillboardSize = UDim2.fromOffset(260, 64),
		PixelsPerStud = 40,
	},
	Particles = {
		Sparks = {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Rate = 14,
			LifetimeMin = 0.25,
			LifetimeMax = 0.6,
			SpeedMin = 8,
			SpeedMax = 16,
			Spread = 70,
			Size = 0.35,
			SizeEnd = 0,
			Color = Color3.fromRGB(255, 210, 90),
			LightEmission = 1,
			Transparency = 0,
			Acceleration = Vector3.new(0, -25, 0),
		},
		Steam = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 6,
			LifetimeMin = 1,
			LifetimeMax = 1.8,
			SpeedMin = 2,
			SpeedMax = 4,
			Spread = 15,
			Size = 1.2,
			SizeEnd = 3,
			Color = Color3.fromRGB(240, 245, 255),
			LightEmission = 0,
			Transparency = 0.5,
			Acceleration = Vector3.new(0, 3, 0),
		},
		Embers = {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Rate = 8,
			LifetimeMin = 1.2,
			LifetimeMax = 2.2,
			SpeedMin = 2,
			SpeedMax = 5,
			Spread = 30,
			Size = 0.3,
			SizeEnd = 0.05,
			Color = Color3.fromRGB(255, 120, 40),
			LightEmission = 1,
			Transparency = 0.1,
			Acceleration = Vector3.new(0, 4, 0),
		},
		Bubbles = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 5,
			LifetimeMin = 1.5,
			LifetimeMax = 2.5,
			SpeedMin = 1,
			SpeedMax = 3,
			Spread = 25,
			Size = 0.5,
			SizeEnd = 0.8,
			Color = Color3.fromRGB(170, 225, 255),
			LightEmission = 0.3,
			Transparency = 0.4,
			Acceleration = Vector3.new(0, 2, 0),
		},
		Sparkles = {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Rate = 10,
			LifetimeMin = 0.8,
			LifetimeMax = 1.4,
			SpeedMin = 1,
			SpeedMax = 3,
			Spread = 180,
			Size = 0.6,
			SizeEnd = 0,
			Color = Color3.fromRGB(255, 255, 200),
			LightEmission = 1,
			Transparency = 0,
			Acceleration = Vector3.new(0, 0, 0),
		},
		Clouds = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 4,
			LifetimeMin = 2.5,
			LifetimeMax = 4,
			SpeedMin = 1,
			SpeedMax = 2,
			Spread = 20,
			Size = 2,
			SizeEnd = 5,
			Color = Color3.fromRGB(255, 255, 255),
			LightEmission = 0,
			Transparency = 0.45,
			Acceleration = Vector3.new(0, 1.5, 0),
		},
		Coins = {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Rate = 20,
			LifetimeMin = 0.9,
			LifetimeMax = 1.4,
			SpeedMin = 14,
			SpeedMax = 22,
			Spread = 25,
			Size = 0.6,
			SizeEnd = 0.3,
			Color = Color3.fromRGB(255, 210, 60),
			LightEmission = 0.6,
			Transparency = 0,
			Acceleration = Vector3.new(0, -45, 0),
		},
		Fire = {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Rate = 60,
			LifetimeMin = 0.3,
			LifetimeMax = 0.6,
			SpeedMin = 6,
			SpeedMax = 12,
			Spread = 12,
			Size = 2.2,
			SizeEnd = 0.4,
			Color = Color3.fromRGB(255, 150, 50),
			LightEmission = 1,
			Transparency = 0,
			Acceleration = Vector3.new(0, 0, 0),
		},
	} :: { [string]: ParticlePreset },
	-- Specialist machine models (ServerStorage/Builders/MachineModelBuilder).
	Machine = {
		Footprint = 4, -- studs; every shape is authored for 4 and scaled
		DarkColor = Color3.fromRGB(45, 48, 56),
		GlassColor = Color3.fromRGB(170, 220, 255),
		GlassTransparency = 0.45,
		ChromeColor = Color3.fromRGB(215, 220, 230),
		ChromeBlend = 0.55,
		ChromeReflectance = 0.35,
		GoldColor = Color3.fromRGB(255, 200, 60),
		GoldNeon = Color3.fromRGB(255, 235, 140),
		GoldReflectance = 0.25,
		GradeParticle = "Sparkles",
		ParticleHeight = 4.6,
		GlowRange = 10,
		RarityGlow = { Legendary = 0.8, Mythic = 1.2, Secret = 1.2, Special = 1 } :: { [string]: number },
	},
	-- Production stage models (Conveyor / Processor / Assembler / Packer).
	Stage = {
		Scale = 1,
		MetalColor = Color3.fromRGB(150, 158, 170),
		DarkColor = Color3.fromRGB(45, 48, 56),
		GlassColor = Color3.fromRGB(170, 220, 255),
		TierStripeHeight = 0.5,
	},
	-- Plot layout in plot-local studs: X right, Y up, Z back (front/-Z faces the plaza).
	Plot = {
		LineStartX = -20,
		BeltHeight = 1.2,
		BeltThickness = 0.8,
		BeltWidth = 3.2,
		LeverOffsetX = -4, -- from the belt start
		LeverPromptDistance = 14,
		BuildPadWidth = 11,
		BuildPadAlpha = 0.45,
		BuildPromptDistance = 16,
		SlabBackZ = 52, -- upper slabs end here; the stair well sits behind
		StairZ = 58.5,
		StairWidth = 11,
		StairLandingDepth = 10,
		StairThickness = 1.2,
		RailHeight = 3,
		RailThickness = 0.5,
		PillarSize = 2.5,
		FloorTint = 0.14,
		BaysX = { -47, -35 } :: { number },
		BaysZStart = -34,
		BaysZStep = 10,
		BayPadSize = Vector3.new(7, 0.6, 7),
		VaultOffset = Vector3.new(-30, 0, -47),
		VaultPadSize = Vector3.new(10, 0.8, 10),
		DockZ = -58,
		DockSize = Vector3.new(100, 0.4, 8),
		SpawnOffset = Vector3.new(0, 0, -45),
		SpawnSize = Vector3.new(5, 0.4, 5),
		SignOffset = Vector3.new(0, 16, -63),
		SignSize = Vector3.new(34, 7, 1),
		ContractBoardOffset = Vector3.new(-45, 0, -52),
		ContractBoardSize = Vector3.new(10, 7, 0.8),
		RocketPadSize = Vector3.new(14, 0.6, 14),
		RocketPadOffset = Vector3.new(15, 0, 0),
		GhostColor = Color3.fromRGB(190, 200, 220),
		GhostAlpha = 0.75,
		FreeSignText = "Free plot",
		RoofColor = Color3.fromRGB(80, 86, 100),
	},
	-- Central plaza, roads and props (ServerStorage/Builders/WorldBuilder).
	Plaza = {
		Thickness = 0.8,
		InnerRingColor = Color3.fromRGB(255, 176, 32),
		RoadWidth = 14,
		RoadThickness = 0.2,
		RingRoadMargin = 12, -- ring road distance in front of the plot fronts
		GroundMargin = 400,
		SpawnSize = Vector3.new(16, 1, 16),
		SpawnOffset = Vector3.new(0, 0, 18),
		StatueHeight = 14,
		BoardSize = Vector3.new(12, 16, 1),
		BoardRadius = 56,
		BoardAngleStepDegrees = 15,
		BoardCenterAngleDegrees = 90,
		BoardCanvas = Vector2.new(600, 800),
		MegaBoardAngleDegrees = 270,
		MegaBoardSize = Vector3.new(30, 14, 1),
		TradeAngleDegrees = 0,
		TradeRadius = 44,
		TradePadRadius = 11,
		VIPAngleDegrees = 180,
		VIPRadius = 52,
		VIPSize = Vector3.new(26, 12, 22),
		VIPDoorSize = Vector3.new(9, 9, 1),
		VIPColor = Color3.fromRGB(255, 200, 60),
		FenceSegments = 48,
		FenceHeight = 2.4,
	},
	Props = {
		Seed = 20240611,
		TreeCount = 80,
		TreeMinRadius = 85,
		LampsPerRoad = 5,
		TrunkColor = Color3.fromRGB(125, 85, 55),
		LeafColors = {
			Color3.fromRGB(70, 175, 85),
			Color3.fromRGB(90, 195, 95),
			Color3.fromRGB(60, 150, 80),
		} :: { Color3 },
		LampColor = Color3.fromRGB(255, 240, 190),
	},
	-- Built-in client sounds (VERIFY they exist in your client; swap for uploaded IDs anytime).
	Sounds = {
		Click = "rbxasset://sounds/button.wav",
		Upgrade = "rbxasset://sounds/electronicpingshort.wav",
		Coins = "rbxasset://sounds/electronicpingshort.wav",
		Whoosh = "rbxasset://sounds/swoosh.wav",
		Error = "rbxasset://sounds/clickfast.wav",
		Fanfare = "rbxasset://sounds/electronicpingshort.wav",
		Music = "",
	} :: { [string]: string },
	Lighting = {
		ClockTime = 14.5,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(120, 120, 130),
		OutdoorAmbient = Color3.fromRGB(150, 150, 160),
		AtmosphereDensity = 0.28,
		AtmosphereHaze = 1.2,
		AtmosphereColor = Color3.fromRGB(200, 220, 255),
		BloomIntensity = 0.6,
		BloomSize = 24,
		BloomThreshold = 1.4,
		Saturation = 0.15,
		Contrast = 0.08,
		TintColor = Color3.fromRGB(255, 250, 245),
	},
}

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
Config.UI = {
	MinTapSize = 0.11, -- fraction of the short screen side (~44px on small phones)
	ToastSeconds = 3,
	BulkBuyOptions = { 1, 10, 0 }, -- 0 = Max
}

--------------------------------------------------------------------------------
-- Pacing simulation assumptions (tools/pacing_sim.luau only)
--------------------------------------------------------------------------------
Config.Sim = {
	CollectionEfficiency = 0.9,
	SaveForLineSeconds = 180, -- save up for the next line when it costs <= this much income
	TickSeconds = 1,
	-- Target first-run time to Expansion 1 and the per-Expansion growth of run length used by --fit.
	TargetFirstRunMinutes = 29,
	TargetRunGrowth = 1.06,
	MaxRunMinutes = 600,
	-- --fit binary search: orders of magnitude searched above the previous requirement, and iterations.
	FitSearchOrders = 8,
	FitIterations = 20,
	-- Franchise cycles reported by `--franchise`.
	FranchiseCycles = 3,
}

return Config

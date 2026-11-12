--!strict
--[[
	Types: the persisted player data schema (see docs/03-architecture.md).
	Bump Config.DataVersion and add a step to Migrations.luau whenever this changes.
]]

export type MachineItem = {
	Id: string,
	Grade: number, -- 0 Standard, 1 Chrome, 2 Gold-Plated
	Locked: boolean,
	At: number, -- unix time acquired
}

export type PlatingState = {
	Id: string, -- machine definition id being plated ("" = idle)
	EndsAt: number,
}

export type ContractSlot = {
	Tier: string, -- "" means the slot is empty and waiting for a refill
	Line: number,
	Target: number,
	Progress: number,
	EndsAt: number,
	Done: boolean,
}

export type QuestState = {
	Id: string,
	Target: number,
	Progress: number,
	Claimed: boolean,
}

export type PlayerData = {
	Version: number,

	-- Currencies
	Cash: number,
	Credits: number,
	Vault: number,

	-- Earnings trackers
	RunEarnings: number, -- since the last Expansion
	FranchiseEarnings: number, -- since the last Franchise (drives Shares)
	TotalEarnings: number, -- all time (leaderboard)
	WeeklyEarnings: number,
	WeeklyKey: string,

	-- Prestige
	Shares: number,
	BonusShares: number, -- from the Investor Shares product; survives Expansion
	Expansions: number,
	Franchise: number,

	-- Factory
	Lines: { { number } }, -- Lines[k] = stage levels {Conveyor, Processor, Assembler, Packer}
	Packaging: { number }, -- tier per hall (1..5)
	VaultTier: number,
	RobotAssignments: { number }, -- robot i -> line index (0 = idle)

	Machines: {
		Inventory: { [string]: MachineItem },
		Bays: { string }, -- uid or "" for an empty bay
		Plating: PlatingState,
	},

	Catalog: {
		Stamps: { number }, -- per line, 0..4
		Secrets: { [string]: boolean },
	},

	Contracts: {
		Slots: { ContractSlot },
		NextRefillAt: number,
		GoldSinceLegendary: number,
		TutorialDone: boolean,
		MegaPoints: number,
	},

	Research: {
		Levels: { [string]: number },
		ActiveId: string,
		EndsAt: number,
	},

	Quests: {
		DailyDay: number,
		Daily: { QuestState },
		DailyBonusClaimed: boolean,
		WeekKey: string,
		Weekly: { QuestState },
	},

	Daily: {
		Streak: number,
		LastClaimUnix: number,
		Shields: number,
		ShieldWeek: string,
		Milestones: { [string]: boolean },
		PremiumDay: number,
	},

	Supply: {
		Stored: number,
		LastGrantUnix: number,
	},

	Offline: {
		LastSeenUnix: number,
		LastIncome: number,
		PendingCash: number,
		PendingSeconds: number,
		DoubleAvailable: boolean,
	},

	Boosts: { [string]: number }, -- boost key -> unix expiry

	Purchases: {
		PurchaseIdCache: { string },
		StarterPackBought: boolean,
		StarterPackFirstSeen: number,
		RobuxSpent: number,
	},

	Passes: { [string]: boolean }, -- cache, re-verified each session

	Codes: { [string]: boolean },

	Social: {
		InvitesCredited: number,
		InviteRewardsClaimed: { [string]: boolean },
		ReferredBy: number,
		ReferralPaid: boolean,
		GroupRewardClaimed: boolean,
		Titles: { [string]: boolean },
		Title: string,
	},

	Tutorial: {
		Step: number, -- index into Config.Tutorial.Steps
		Done: boolean,
		Upgrades: number,
	},

	Stats: {
		ProductsShipped: number,
		ContractsCompleted: number,
		GoldContracts: number,
		UpgradesBought: number,
		OverdriveUsed: number,
		VaultCollected: number,
		SupplyOpened: number,
		PlaySeconds: number,
		Trades: number,
		RocketsShipped: number,
		OperateSeconds: number,
		Expanded: number,
	},

	Settings: {
		Music: boolean,
		Sfx: boolean,
		LowGraphics: boolean,
	},

	GlobalGoal: {
		WeekKey: string,
		Contracts: number,
		ClaimedTier: number,
	},

	Ads: {
		Day: number,
		Count: number,
		LastUnix: number,
	},
}

-- Standard response for every client -> server RemoteFunction.
export type Response = {
	Ok: boolean,
	Error: string?,
	Data: any?,
}

return {}

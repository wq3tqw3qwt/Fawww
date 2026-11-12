--!strict
--[[
	DataTemplate: default values for a brand new player (ProfileStore template).
	Template() returns a fresh deep copy so callers can mutate it safely.
]]

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local DataTemplate = {}

local function zeros(n: number): { number }
	local t = table.create(n, 0)
	return t
end

local function ones(n: number): { number }
	return table.create(n, 1)
end

function DataTemplate.Template(): Types.PlayerData
	return {
		Version = Config.DataVersion,

		Cash = Config.Expansion.StartingCash,
		Credits = 0,
		Vault = 0,

		RunEarnings = 0,
		FranchiseEarnings = 0,
		TotalEarnings = 0,
		WeeklyEarnings = 0,
		WeeklyKey = "",

		Shares = 0,
		BonusShares = 0,
		Expansions = 0,
		Franchise = 0,

		Lines = { { 1, 1, 1, 1 } },
		Packaging = ones(#Config.Halls),
		VaultTier = 1,
		RobotAssignments = { 1 },

		Machines = {
			Inventory = {},
			Bays = { "", "", "" },
			Plating = { Id = "", EndsAt = 0 },
		},

		Catalog = {
			Stamps = zeros(#Config.Lines),
			Secrets = {},
		},

		Contracts = {
			Slots = {},
			NextRefillAt = 0,
			GoldSinceLegendary = 0,
			TutorialDone = false,
			MegaPoints = 0,
		},

		Research = {
			Levels = {},
			ActiveId = "",
			EndsAt = 0,
		},

		Quests = {
			DailyDay = 0,
			Daily = {},
			DailyBonusClaimed = false,
			WeekKey = "",
			Weekly = {},
		},

		Daily = {
			Streak = 0,
			LastClaimUnix = 0,
			Shields = 1,
			ShieldWeek = "",
			Milestones = {},
			PremiumDay = 0,
		},

		Supply = {
			Stored = 1,
			LastGrantUnix = 0,
		},

		Offline = {
			LastSeenUnix = 0,
			LastIncome = 0,
			PendingCash = 0,
			PendingSeconds = 0,
			DoubleAvailable = false,
		},

		Boosts = {},

		Purchases = {
			PurchaseIdCache = {},
			StarterPackBought = false,
			StarterPackFirstSeen = 0,
			RobuxSpent = 0,
		},

		Passes = {},
		Codes = {},

		Social = {
			InvitesCredited = 0,
			InviteRewardsClaimed = {},
			ReferredBy = 0,
			ReferralPaid = false,
			GroupRewardClaimed = false,
			Titles = {},
			Title = "",
		},

		Tutorial = {
			Step = 1,
			Done = false,
			Upgrades = 0,
		},

		Stats = {
			ProductsShipped = 0,
			ContractsCompleted = 0,
			GoldContracts = 0,
			UpgradesBought = 0,
			OverdriveUsed = 0,
			VaultCollected = 0,
			SupplyOpened = 0,
			PlaySeconds = 0,
			Trades = 0,
			RocketsShipped = 0,
			OperateSeconds = 0,
			Expanded = 0,
		},

		Settings = {
			Music = true,
			Sfx = true,
			LowGraphics = false,
		},

		GlobalGoal = {
			WeekKey = "",
			Contracts = 0,
			ClaimedTier = 0,
		},

		Ads = {
			Day = 0,
			Count = 0,
			LastUnix = 0,
		},
	}
end

-- Recursively fills keys missing from `data` using `template` (does not overwrite).
-- Arrays are treated as values: an existing array is kept as-is.
function DataTemplate.Reconcile(data: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if data[key] == nil then
			if type(value) == "table" then
				data[key] = table.clone(value)
				DataTemplate.Reconcile(data[key], value)
			else
				data[key] = value
			end
		elseif type(value) == "table" and type(data[key]) == "table" and #value == 0 and next(value) ~= nil then
			DataTemplate.Reconcile(data[key], value)
		end
	end
end

return DataTemplate

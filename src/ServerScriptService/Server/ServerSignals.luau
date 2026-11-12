--!strict
--[[
	ServerSignals: in-process events that decouple services (no service requires a
	higher-layer service). Fire from the owning service; subscribe in Start().
]]

local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)

local ServerSignals = {
	-- (player, lineIndex, productsShipped, cashValue)
	Produced = Signal.new() :: Signal.Signal<Player, number, number, number>,
	-- (player, amount, source)
	CashEarned = Signal.new() :: Signal.Signal<Player, number, string>,
	-- (player, statKey, amount) every StatsService.Increment
	StatChanged = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, lineIndex) a line was bought or its levels changed
	LinesChanged = Signal.new() :: Signal.Signal<Player, number>,
	-- (player, tierName)
	ContractCompleted = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, newExpansionCount)
	Expanded = Signal.new() :: Signal.Signal<Player, number>,
	-- (player, newFranchiseLevel)
	Franchised = Signal.new() :: Signal.Signal<Player, number>,
	-- (player) equipped machines, boosts, passes or research changed: recompute multipliers
	MultipliersDirty = Signal.new() :: Signal.Signal<Player>,
	-- (player, machineId, source) a machine entered the inventory
	MachineGranted = Signal.new() :: Signal.Signal<Player, string, string>,
	-- (player, passKey)
	PassOwned = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, eventName) tutorial-relevant actions: "Upgrade", "VaultCollected", "ContractClaimed",
	-- "LineBought", "Overdrive", "MachineEquipped"
	TutorialAction = Signal.new() :: Signal.Signal<Player, string>,
	-- (operator, host, seconds) seconds spent operating a friend's line
	Operated = Signal.new() :: Signal.Signal<Player, Player, number>,
}

return ServerSignals

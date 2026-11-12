--!strict
--[[
	RuntimeState: per-player, non-persisted state shared between services
	(income, overdrive timers, operators, trade cooldowns). Cleared on leave.
]]

export type PlayerRuntime = {
	IncomePerSecond: number, -- after all multipliers (what the player actually earns)
	LineOutputs: { number }, -- products/s per owned line
	OverdriveUntil: { [number]: number }, -- line -> os.clock() deadline
	OverdriveReadyAt: { [number]: number }, -- line -> os.clock() when lever is ready again
	Operators: { [number]: number }, -- operator userId -> os.clock() of last lever pull
	OperatingHost: number, -- userId of the host this player is operating for (0 = none)
	OperateStartedAt: number,
	LastTradeAt: number,
	JoinedAt: number,
	VaultCapacity: number,
	PendingOfflineCash: number,
	Flags: { [string]: boolean },
}

local RuntimeState = {}

local states: { [Player]: PlayerRuntime } = {}

function RuntimeState.Get(player: Player): PlayerRuntime
	local state = states[player]
	if not state then
		state = {
			IncomePerSecond = 0,
			LineOutputs = {},
			OverdriveUntil = {},
			OverdriveReadyAt = {},
			Operators = {},
			OperatingHost = 0,
			OperateStartedAt = 0,
			LastTradeAt = 0,
			JoinedAt = os.clock(),
			VaultCapacity = 0,
			PendingOfflineCash = 0,
			Flags = {},
		}
		-- Don't store state for players who already left (leave handlers run in any order).
		if player.Parent ~= nil then
			states[player] = state
		end
	end
	return state
end

function RuntimeState.Clear(player: Player)
	states[player] = nil
end

return RuntimeState

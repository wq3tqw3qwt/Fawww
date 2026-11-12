--!strict
--[[
	Remote: binds a handler to a RemoteFunction with the server-side safety net:
	- rate limiting per player per remote (Config.AntiExploit.Rates), with strikes
	- refuses calls before the player's data is loaded
	- pcall around the handler; errors become { Ok = false } responses
	Handlers return (ok, errorMessage?, data?) and never trust their arguments.
]]

local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local Remote = {}

export type Handler = (player: Player, ...any) -> (boolean, string?, any?)

-- Injected by Main to avoid a require cycle (AntiExploitService / DataService also use Remote).
local rateCheck: ((Player, string) -> boolean)? = nil
local readyCheck: ((Player) -> boolean)? = nil

function Remote.Configure(checkRate: (Player, string) -> boolean, isReady: (Player) -> boolean)
	rateCheck = checkRate
	readyCheck = isReady
end

function Remote.Handle(name: string, handler: Handler, options: { AllowBeforeLoad: boolean? }?)
	local rf = Net.Function(name)
	local allowBeforeLoad = options ~= nil and options.AllowBeforeLoad == true
	rf.OnServerInvoke = function(player: Player, ...: any): Types.Response
		if rateCheck and not rateCheck(player, name) then
			return { Ok = false, Error = "Slow down!" }
		end
		if not allowBeforeLoad and readyCheck and not readyCheck(player) then
			return { Ok = false, Error = "Still loading your factory..." }
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(string.format("[Remote] %s error for %s: %s", name, player.Name, tostring(results[2])))
			return { Ok = false, Error = "Something went wrong" }
		end
		local ok = results[2] == true
		return { Ok = ok, Error = if ok then nil else (results[3] or "Not allowed"), Data = results[4] }
	end
end

-- Fire a server -> client event to one player.
function Remote.Fire(name: string, player: Player, ...: any)
	Net.Event(name):FireClient(player, ...)
end

function Remote.FireAll(name: string, ...: any)
	Net.Event(name):FireAllClients(...)
end

-- Convenience toast.
function Remote.Notify(player: Player, kind: "Info" | "Success" | "Error" | "Reward", text: string, payload: any?)
	Net.Event("Notify"):FireClient(player, kind, text, payload)
end

return Remote

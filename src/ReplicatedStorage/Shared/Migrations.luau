--!strict
--[[
	Migrations: versioned, ordered upgrades for persisted player data.

	Each entry Steps[v] upgrades data from version v-1 to version v. Migrate() runs every
	step above the stored version, then reconciles missing keys against the template.
	Never edit a shipped step; add a new one and bump Config.DataVersion.
]]

local Config = require(script.Parent.Config)
local DataTemplate = require(script.Parent.DataTemplate)

local Migrations = {}

type AnyTable = { [any]: any }

Migrations.Steps = {
	-- v1: first internal playtest schema (pre-release). Nothing to transform.
	[1] = function(_data: AnyTable) end,

	-- v2: "Gems" was renamed to "Credits", line stamps became a fixed-size array,
	-- and machine bays became a contiguous array of uids ("" = empty).
	[2] = function(data: AnyTable)
		if type(data.Gems) == "number" then
			data.Credits = (data.Credits or 0) + data.Gems
			data.Gems = nil
		end
		if type(data.Catalog) == "table" and type(data.Catalog.Stamps) == "table" then
			local stamps = data.Catalog.Stamps
			for k = 1, #Config.Lines do
				if type(stamps[k]) ~= "number" then
					stamps[k] = 0
				end
			end
		end
		if type(data.Machines) == "table" and type(data.Machines.Bays) == "table" then
			local bays = data.Machines.Bays
			local fixed = {}
			local count = 0
			for _, uid in bays do
				count += 1
				fixed[count] = if type(uid) == "string" then uid else ""
			end
			data.Machines.Bays = fixed
		end
	end,
} :: { [number]: (AnyTable) -> () }

-- Upgrades `data` in place to Config.DataVersion. Returns the version it started from.
function Migrations.Migrate(data: AnyTable): number
	local from = if type(data.Version) == "number" then data.Version else 0
	for v = from + 1, Config.DataVersion do
		local step = Migrations.Steps[v]
		if step then
			step(data)
		end
		data.Version = v
	end
	DataTemplate.Reconcile(data, DataTemplate.Template() :: any)
	return from
end

return Migrations

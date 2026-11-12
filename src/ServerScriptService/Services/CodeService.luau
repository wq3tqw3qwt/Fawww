--!strict
--[[
	CodeService (L5): promo codes. Codes give Credits and boosts only; each is redeemable
	once per player and expires at a fixed UTC time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent.Server

local Config = require(Shared.Config)
local Grants = require(Server.Grants)
local Guard = require(Server.Guard)
local Remote = require(Server.Remote)
local DataService = require(script.Parent.DataService)

local CodeService = {}

-- Upper-cased code -> canonical Config key, so lookups are case-insensitive.
local canonical: { [string]: string } = {}
for key in Config.Codes do
	canonical[string.upper(key)] = key
end

local function redeemCode(player: Player, codeArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local raw = Guard.String(codeArg, 32)
	if not data or not raw then
		return false, "Enter a code"
	end
	local trimmed = string.upper((string.gsub(raw, "^%s+", ""):gsub("%s+$", "")))
	local key = canonical[trimmed]
	local def = if key then Config.Codes[key] else nil
	if not key or not def then
		return false, "That code doesn't exist"
	end
	if os.time() > def.ExpiresUnix then
		return false, "That code has expired"
	end
	if data.Codes[key] then
		return false, "You already redeemed that code"
	end
	data.Codes[key] = true
	DataService.MarkDirty(player, "Codes")
	if def.Credits then
		Grants.GrantCredits(player, def.Credits, "Code")
	end
	if def.BoostKey and def.Minutes then
		Grants.GrantBoost(player, def.BoostKey, def.Minutes)
	end
	return true, nil, { Credits = def.Credits, BoostKey = def.BoostKey, Minutes = def.Minutes }
end

function CodeService.Init()
	Remote.Handle("RedeemCode", redeemCode)
end

function CodeService.Start() end

return CodeService

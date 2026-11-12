--!strict
--[[
	AdminService (L7): owner-only commands and a metrics feed.
	Admins: the place creator (user-owned experience), Config.Admin.UserIds, group rank at or above
	Config.Admin.GroupAdminMinRank (group-owned experience), and anyone in Studio.
	Every command is validated per command and logged through AntiExploitService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DataTemplate = require(Shared:WaitForChild("DataTemplate"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Guard = require(script.Parent.Parent.Server.Guard)
local Grants = require(script.Parent.Parent.Server.Grants)
local Remote = require(script.Parent.Parent.Server.Remote)
local GroupRank = require(script.Parent.Parent.Server.GroupRank)
local ServerSignals = require(script.Parent.Parent.Server.ServerSignals)
local Types = require(Shared:WaitForChild("Types"))

local AntiExploitService = require(script.Parent.AntiExploitService)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local FactoryService = require(script.Parent.FactoryService)

local AdminService = {}

type PlayerData = Types.PlayerData
type Args = { [string]: any }
type Command = (admin: Player, args: Args) -> (boolean, string?, any?)

local MAX_USER_ID = 2 ^ 53
local EVENT_KINDS = { Rush = true, Weekend = true }

-- Resolved admin status per player (group lookups are cached for the session).
local adminCache: { [Player]: boolean } = {}
local limits = Config.Admin.Limits

local function isListedAdmin(userId: number): boolean
	if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
		return true
	end
	return table.find(Config.Admin.UserIds, userId) ~= nil
end

-- May yield once per player for the group rank lookup.
function AdminService.IsAdmin(player: Player): boolean
	local cached = adminCache[player]
	if cached ~= nil then
		return cached
	end
	local result = RunService:IsStudio() or isListedAdmin(player.UserId)
	if not result and game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = GroupRank.GetAsync(player.UserId, game.CreatorId)
		result = ok and rank >= Config.Admin.GroupAdminMinRank
		if not ok then
			return false -- not cached: try again next time
		end
	end
	adminCache[player] = result
	return result
end

--------------------------------------------------------------------------------
-- Argument helpers
--------------------------------------------------------------------------------
local function userIdArg(args: Args): number?
	return Guard.Integer(args.userId, 1, MAX_USER_ID)
end

local function onlineTarget(args: Args): (Player?, string?)
	local userId = userIdArg(args)
	if not userId then
		return nil, "Invalid userId"
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or not DataService.IsLoaded(target) then
		return nil, "Player not in this server"
	end
	return target, nil
end

local function textArg(value: any): string?
	return Guard.String(value, limits.MaxTextLength)
end

--------------------------------------------------------------------------------
-- Metrics
--------------------------------------------------------------------------------
local function scrub(entry: any): any
	if type(entry) ~= "table" then
		return tostring(entry)
	end
	local out: { [string]: any } = {}
	for key, value in entry do
		local t = type(value)
		out[tostring(key)] = if t == "string" or t == "number" or t == "boolean" then value else tostring(value)
	end
	return out
end

local function buildMetrics(): { [string]: any }
	local playerRows = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data then
			table.insert(playerRows, {
				UserId = player.UserId,
				Name = player.Name,
				Income = FactoryService.GetIncome(player),
				Cash = data.Cash,
				Credits = data.Credits,
				Expansions = data.Expansions,
				Franchise = data.Franchise,
				RobuxSpent = data.Purchases.RobuxSpent,
				PlaySeconds = data.Stats.PlaySeconds,
			})
		end
	end

	local logs = AntiExploitService.GetRecentLogs()
	local tail = {}
	for i = math.max(1, #logs - limits.LogTail + 1), #logs do
		table.insert(tail, scrub(logs[i]))
	end

	local state = EventService.GetState()
	return {
		ServerTime = os.time(),
		UptimeSeconds = time(),
		JobId = game.JobId,
		PlaceVersion = game.PlaceVersion,
		PlayerCount = #Players:GetPlayers(),
		MaxPlayers = Players.MaxPlayers,
		MemoryMb = Stats:GetTotalMemoryUsageMb(),
		Players = playerRows,
		ExploitLog = tail,
		GlobalGoal = state.GlobalGoal,
		Event = {
			RushActive = state.RushActive,
			WeekendActive = state.WeekendActive,
		},
	}
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
local commands: { [string]: Command } = {}

commands.GiveCash = function(_admin, args)
	local target, err = onlineTarget(args)
	local amount = Guard.Number(args.amount, 0, limits.MaxGrantAmount)
	if not target or not amount then
		return false, err or "Invalid amount"
	end
	-- Not counted as earnings: admin cash must not move leaderboards or Shares.
	CurrencyService.AddCash(target, amount, "Admin", false)
	return true
end

commands.GiveCredits = function(_admin, args)
	local target, err = onlineTarget(args)
	local amount = Guard.Integer(args.amount, 0, limits.MaxGrantAmount)
	if not target or not amount then
		return false, err or "Invalid amount"
	end
	CurrencyService.AddCredits(target, amount, "Admin")
	return true
end

commands.GiveMachine = function(_admin, args)
	local target, err = onlineTarget(args)
	local machineId = Guard.String(args.machineId, 64)
	if not target or not machineId then
		return false, err or "Invalid machineId"
	end
	if not Formulas.GetMachine(machineId) then
		return false, "Unknown machine"
	end
	local uid = Grants.GrantMachine(target, machineId, "Admin")
	if not uid then
		return false, "Inventory full"
	end
	return true
end

commands.SetExpansions = function(_admin, args)
	local target, err = onlineTarget(args)
	local count = Guard.Integer(args.count, 0, Config.Expansion.MaxExpansions)
	local data = if target then DataService.Get(target) else nil
	if not target or not data or not count then
		return false, err or "Invalid count"
	end
	data.Expansions = count
	DataService.MarkDirty(target, "Expansions")
	ServerSignals.MultipliersDirty:Fire(target)
	-- Lets plots, bays and halls catch up with the new count.
	ServerSignals.Expanded:Fire(target, count)
	return true
end

commands.ForceEvent = function(_admin, args)
	local kind = Guard.String(args.kind, 16)
	local minutes = Guard.Number(args.minutes, 1, limits.MaxEventMinutes)
	local global = Guard.Boolean(args.global)
	if not kind or not EVENT_KINDS[kind] or not minutes or global == nil then
		return false, "Invalid event"
	end
	EventService.ForceEvent(kind, minutes, global)
	return true
end

commands.Ban = function(admin, args)
	local userId = userIdArg(args)
	local minutes = Guard.Number(args.minutes, 0, limits.MaxBanMinutes)
	local reason = textArg(args.reason)
	if not userId or not minutes or not reason then
		return false, "Invalid ban"
	end
	if isListedAdmin(userId) or userId == admin.UserId then
		return false, "Cannot ban an admin"
	end
	local online = Players:GetPlayerByUserId(userId)
	if online and AdminService.IsAdmin(online) then
		return false, "Cannot ban an admin"
	end
	if not AntiExploitService.BanAsync(userId, reason, minutes) then
		return false, "Ban could not be saved"
	end
	if online then
		online:Kick("Banned: " .. reason)
	end
	return true
end

commands.Unban = function(_admin, args)
	local userId = userIdArg(args)
	if not userId then
		return false, "Invalid userId"
	end
	if not AntiExploitService.UnbanAsync(userId) then
		return false, "Unban failed"
	end
	return true
end

commands.Kick = function(_admin, args)
	local userId = userIdArg(args)
	local reason = textArg(args.reason)
	if not userId or not reason then
		return false, "Invalid kick"
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target then
		return false, "Player not in this server"
	end
	target:Kick(reason)
	return true
end

commands.Announce = function(_admin, args)
	local text = textArg(args.text)
	local global = Guard.Boolean(args.global)
	if not text or global == nil then
		return false, "Invalid announcement"
	end
	EventService.Announce(text, Config.Visuals.Palette.UIAccent, global)
	return true
end

commands.ResetTutorial = function(_admin, args)
	local target, err = onlineTarget(args)
	local data = if target then DataService.Get(target) else nil
	if not target or not data then
		return false, err or "Player not in this server"
	end
	local fresh = DataTemplate.Template().Tutorial
	data.Tutorial.Step = fresh.Step
	data.Tutorial.Done = fresh.Done
	data.Tutorial.Upgrades = fresh.Upgrades
	DataService.MarkDirty(target, "Tutorial")
	return true
end

commands.Metrics = function(_admin, _args)
	return true, nil, buildMetrics()
end

local function adminCommand(player: Player, cmdArg: any, argsArg: any): (boolean, string?, any?)
	if not AdminService.IsAdmin(player) then
		AntiExploitService.Strike(player, "AdminCommandDenied")
		return false, "Not allowed"
	end
	local cmd = Guard.Key(cmdArg, commands)
	if not cmd then
		return false, "Unknown command"
	end
	local args: Args = if type(argsArg) == "table" then argsArg else {}
	local ok, err, data = commands[cmd](player, args)
	-- Metrics polling would drown the log; everything else is recorded with its outcome.
	if cmd ~= "Metrics" then
		local logged: { [string]: any } = { Cmd = cmd, Ok = ok }
		for key, value in args do
			local t = type(value)
			if t == "string" or t == "number" or t == "boolean" then
				logged[tostring(key)] = value
			end
		end
		AntiExploitService.Log("Admin", player, logged)
	end
	return ok, err, data
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function AdminService.Init()
	Remote.Handle("AdminCommand", function(player, cmd, args)
		return adminCommand(player, cmd, args)
	end)
end

function AdminService.Start()
	local function resolve(player: Player)
		AdminService.IsAdmin(player)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(resolve, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(resolve, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		adminCache[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(limits.PushSeconds)
			local metrics: { [string]: any }? = nil
			for player, isAdmin in adminCache do
				if isAdmin and player.Parent == Players then
					metrics = metrics or buildMetrics()
					Remote.Fire("AdminData", player, metrics)
				end
			end
		end
	end)
end

return AdminService

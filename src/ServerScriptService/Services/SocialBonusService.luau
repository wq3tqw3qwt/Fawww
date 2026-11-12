--!strict
--[[
	SocialBonusService (L2): operators (friends pulling a host's Overdrive lever), the
	Apprentice buff, group membership, referrals / invite rewards and titles.

	Contract deviation: RegisterOperatorPull takes (operator, host, line) instead of
	(operator, host) so the lever distance can be validated here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent.Server

local Config = require(Shared.Config)
local Maid = require(Shared.Maid)
local Types = require(Shared.Types)
local Grants = require(Server.Grants)
local Remote = require(Server.Remote)
local Retry = require(Server.Retry)
local GroupRank = require(Server.GroupRank)
local RuntimeState = require(Server.RuntimeState)
local ServerSignals = require(Server.ServerSignals)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StatsService = require(script.Parent.StatsService)

local SocialBonusService = {}

local cfg = Config.Social

type Session = {
	OperateSeconds: number, -- seconds operated this session (Apprentice)
	ApprenticeGranted: boolean,
	PlaySeconds: number, -- seconds in this session (referral qualification)
	ReferralAttempted: boolean,
	InGroup: boolean,
}

local sessions: { [Player]: Session } = {}
local playerMaids: { [Player]: Maid.Maid } = {}
local friendCache: { [string]: boolean } = {}
local globalMaid = Maid.new()

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

local function isFriend(a: Player, b: Player): boolean
	local key = pairKey(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = Retry.Call("IsFriendsWith", function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	-- A failed lookup is not cached so the next pull retries it.
	if not ok then
		return false
	end
	friendCache[key] = result == true
	return friendCache[key]
end

local function isFresh(pulledAt: number?): boolean
	return pulledAt ~= nil and os.clock() - pulledAt <= cfg.OperatorTimeoutSeconds
end

function SocialBonusService.GetOperatorCount(host: Player): number
	local count = 0
	for _, pulledAt in RuntimeState.Get(host).Operators do
		if isFresh(pulledAt) then
			count += 1
		end
	end
	return math.min(count, cfg.MaxOperators)
end

function SocialBonusService.GetTeamworkActive(host: Player): boolean
	return SocialBonusService.GetOperatorCount(host) > 0
end

function SocialBonusService.IsInGroup(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.InGroup
end

-- Called by FactoryService when `operator` pulls `host`'s lever for `line`.
function SocialBonusService.RegisterOperatorPull(operator: Player, host: Player, line: number): (boolean, string?)
	if operator == host then
		return false, "You can't operate your own line for a bonus"
	end
	if not (DataService.IsLoaded(operator) and DataService.IsLoaded(host)) then
		return false, "Player data is not ready"
	end
	local hostData = DataService.Get(host)
	if not hostData or line ~= math.floor(line) or line < 1 or line > #hostData.Lines then
		return false, "That line isn't available"
	end
	if cfg.FriendsOnlyOperators and not isFriend(operator, host) then
		return false, "Only friends can operate this line"
	end

	local lever = PlotService.GetLeverPosition(host, line)
	local root = operator.Character and operator.Character:FindFirstChild("HumanoidRootPart")
	if lever == nil or root == nil or not root:IsA("BasePart") then
		return false, "Move closer to the lever"
	end
	if (root.Position - lever).Magnitude > cfg.OperatorMaxDistance then
		return false, "Too far from the lever"
	end

	local hostState = RuntimeState.Get(host)
	local operatorState = RuntimeState.Get(operator)
	local now = os.clock()
	-- Only an existing live operator slot or a free one may be used (MaxOperators cap).
	if
		not isFresh(hostState.Operators[operator.UserId])
		and SocialBonusService.GetOperatorCount(host) >= cfg.MaxOperators
	then
		return false, "This factory already has enough operators"
	end
	hostState.Operators[operator.UserId] = now
	if operatorState.OperatingHost ~= host.UserId then
		operatorState.OperatingHost = host.UserId
		operatorState.OperateStartedAt = now
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Operating time -> stats, Apprentice buff
--------------------------------------------------------------------------------
local function tickOperating(player: Player, session: Session)
	local state = RuntimeState.Get(player)
	if state.OperatingHost == 0 then
		return
	end
	local host = Players:GetPlayerByUserId(state.OperatingHost)
	if not host or not isFresh(RuntimeState.Get(host).Operators[player.UserId]) then
		state.OperatingHost = 0
		return
	end
	StatsService.Increment(player, "OperateSeconds", 1)
	ServerSignals.Operated:Fire(player, host, 1)
	session.OperateSeconds += 1
	if not session.ApprenticeGranted and session.OperateSeconds >= cfg.ApprenticeAfterSeconds then
		session.ApprenticeGranted = true
		Grants.GrantBoost(player, "Apprentice", cfg.ApprenticeMinutes)
	end
end

--------------------------------------------------------------------------------
-- Invite rewards and referrals
--------------------------------------------------------------------------------
local function checkInviteRewards(player: Player, data: Types.PlayerData)
	local social = data.Social
	local changed = false
	for _, reward in cfg.InviteRewards do
		local count = reward.Count or 0
		local key = tostring(count)
		if social.InvitesCredited >= count and not social.InviteRewardsClaimed[key] then
			local granted = true
			if reward.MachineId then
				granted = Grants.GrantMachine(player, reward.MachineId, "Invite") ~= nil
			end
			if granted then
				if reward.BoostKey and reward.Minutes then
					Grants.GrantBoost(player, reward.BoostKey, reward.Minutes)
				end
				if reward.Title then
					Grants.GrantTitle(player, reward.Title)
				end
				social.InviteRewardsClaimed[key] = true
				changed = true
			end
		end
	end
	if changed then
		DataService.MarkDirty(player, "Social")
	end
end

local function creditInvite(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Social.InvitesCredited += 1
	DataService.MarkDirty(player, "Social")
	Remote.Notify(player, "Reward", "A friend you invited joined and played!")
	checkInviteRewards(player, data)
end

local function tryPayReferral(player: Player, data: Types.PlayerData, session: Session)
	local social = data.Social
	if social.ReferredBy == 0 or social.ReferralPaid or session.ReferralAttempted then
		return
	end
	local played = math.max(session.PlaySeconds, data.Stats.PlaySeconds)
	if played < cfg.ReferralMinPlaySeconds then
		return
	end
	session.ReferralAttempted = true
	local referrer = Players:GetPlayerByUserId(social.ReferredBy)
	local paid = false
	if referrer and DataService.IsLoaded(referrer) then
		creditInvite(referrer)
		paid = true
	else
		paid = DataService.MessageUserAsync(social.ReferredBy, { Kind = "Referral", From = player.UserId })
	end
	if paid then
		social.ReferralPaid = true
		DataService.MarkDirty(player, "Social")
	else
		-- Allow another attempt on the next session.
		warn("[Social] referral credit failed for " .. player.Name)
	end
end

local function readReferral(player: Player, data: Types.PlayerData)
	if data.Social.ReferredBy ~= 0 then
		return
	end
	-- VERIFY: ReferredByPlayerId is only present when the player joined through a friend's
	-- join link/invite; confirm behaviour in the current Roblox docs before relying on it.
	local joinData = player:GetJoinData()
	local referrer = (joinData :: any).ReferredByPlayerId
	if type(referrer) == "number" and referrer > 0 and referrer ~= player.UserId then
		data.Social.ReferredBy = referrer
		DataService.MarkDirty(player, "Social")
	end
end

--------------------------------------------------------------------------------
-- Group
--------------------------------------------------------------------------------
local function checkGroup(player: Player, data: Types.PlayerData, session: Session)
	if Config.GroupId == 0 then
		return
	end
	local ok, rank = GroupRank.GetAsync(player.UserId, Config.GroupId)
	if not ok or not player.Parent then
		return
	end
	session.InGroup = rank > 0
	if not session.InGroup then
		return
	end
	if not data.Social.GroupRewardClaimed then
		if Grants.GrantMachine(player, cfg.GroupMachineId, "Group") ~= nil then
			data.Social.GroupRewardClaimed = true
			DataService.MarkDirty(player, "Social")
		end
	end
	ServerSignals.MultipliersDirty:Fire(player)
end

--------------------------------------------------------------------------------
-- Titles
--------------------------------------------------------------------------------
local function setTitle(player: Player, title: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	if type(title) ~= "string" or #title > cfg.MaxTitleLength then
		return false, "Invalid title"
	end
	if title ~= "" and not data.Social.Titles[title] then
		return false, "You haven't unlocked that title"
	end
	data.Social.Title = title
	DataService.MarkDirty(player, "Social")
	return true, nil, { Title = title }
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function onLoaded(player: Player, data: Types.PlayerData)
	if sessions[player] then
		return
	end
	local session: Session = {
		OperateSeconds = 0,
		ApprenticeGranted = false,
		PlaySeconds = 0,
		ReferralAttempted = false,
		InGroup = false,
	}
	sessions[player] = session
	playerMaids[player] = Maid.new()
	readReferral(player, data)
	checkInviteRewards(player, data)
	task.spawn(checkGroup, player, data, session)
end

local function onRemoving(player: Player)
	local maid = playerMaids[player]
	if maid then
		maid:Clean()
	end
	playerMaids[player] = nil
	sessions[player] = nil
	local prefix = tostring(player.UserId)
	for key in table.clone(friendCache) do
		local a, b = string.match(key, "^(%d+):(%d+)$")
		if a == prefix or b == prefix then
			friendCache[key] = nil
		end
	end
	-- Hosts forget this player as an operator; operators of this host stop operating.
	for other in sessions do
		local otherState = RuntimeState.Get(other)
		otherState.Operators[player.UserId] = nil
		if otherState.OperatingHost == player.UserId then
			otherState.OperatingHost = 0
		end
	end
end

local function runLoop()
	while true do
		task.wait(1)
		for player, session in sessions do
			local data = DataService.Get(player)
			if data then
				session.PlaySeconds += 1
				tickOperating(player, session)
				tryPayReferral(player, data, session)
			end
		end
	end
end

function SocialBonusService.Init()
	Remote.Handle("SetTitle", setTitle)
end

function SocialBonusService.Start()
	globalMaid:Add(DataService.Loaded:Connect(onLoaded))
	globalMaid:Add(Players.PlayerRemoving:Connect(onRemoving))
	globalMaid:Add(DataService.MessageReceived:Connect(function(player: Player, message: any)
		if type(message) == "table" and message.Kind == "Referral" and type(message.From) == "number" then
			creditInvite(player)
		end
	end))
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data then
			onLoaded(player, data)
		end
	end
	runLoop()
end

return SocialBonusService

--!strict
--[[
	TradeService (L6): two-sided machine trading.
	Request -> accept -> both edit offers (every edit bumps the revision and clears Ready)
	-> both Ready -> countdown -> both Confirm -> TradeLogic.Execute on the LIVE profiles in one
	non-yielding block (no dupes: either both inventories change or neither). Logging and the
	extra profile saves happen asynchronously after the swap.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Guard = require(script.Parent.Parent.Server.Guard)
local Remote = require(script.Parent.Parent.Server.Remote)
local Retry = require(script.Parent.Parent.Server.Retry)
local RuntimeState = require(script.Parent.Parent.Server.RuntimeState)
local TradeLogic = require(Shared:WaitForChild("TradeLogic"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)

local TradeService = {}

type PlayerData = Types.PlayerData

type Session = {
	Id: string,
	A: Player,
	B: Player,
	Offers: { [number]: { string } }, -- userId -> uids
	Ready: { [number]: boolean },
	Confirmed: { [number]: boolean },
	Revision: number,
	ReadyAt: number, -- os.clock() when the later player became Ready (0 = not both ready)
	Closed: boolean,
}

type Request = {
	Id: string,
	From: Player,
	To: Player,
	Expires: number,
}

local sessions: { [Player]: Session } = {}
local requests: { [string]: Request } = {}
local outgoing: { [Player]: Request } = {}
local incoming: { [Player]: Request } = {}
-- IsPaidItemTradingAllowed per user; only successful lookups are cached.
local policyAllowed: { [number]: boolean } = {}

local function other(session: Session, player: Player): Player
	return if session.A == player then session.B else session.A
end

--------------------------------------------------------------------------------
-- Eligibility
--------------------------------------------------------------------------------
-- VERIFY: PolicyService:GetPolicyInfoForPlayerAsync(...).IsPaidItemTradingAllowed is the intended
-- regional/age gate for player-to-player trading; confirm in the Roblox docs/policies before launch.
local function isTradingAllowedByPolicy(player: Player): boolean
	local cached = policyAllowed[player.UserId]
	if cached ~= nil then
		return cached
	end
	local ok, info = Retry.Call("GetPolicyInfoForPlayerAsync", function(): any
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok or type(info) ~= "table" then
		return false -- deny when the policy cannot be read
	end
	local allowed = info.IsPaidItemTradingAllowed == true
	policyAllowed[player.UserId] = allowed
	return allowed
end

-- Returns nil when the player may trade, otherwise a short reason.
local function ineligibleReason(player: Player): string?
	if not Config.Trade.Enabled then
		return "Trading is disabled"
	end
	local data = DataService.Get(player)
	if not data or not DataService.IsLoaded(player) then
		return "Still loading"
	end
	if player.AccountAge < Config.Trade.MinAccountAgeDays then
		return string.format("Account must be %d days old", Config.Trade.MinAccountAgeDays)
	end
	if data.Stats.PlaySeconds < Config.Trade.MinPlaySeconds then
		return string.format(
			"Play %d more minutes to unlock trading",
			math.ceil((Config.Trade.MinPlaySeconds - data.Stats.PlaySeconds) / 60)
		)
	end
	if not isTradingAllowedByPolicy(player) then
		return "Trading is not available for this account"
	end
	if sessions[player] then
		return "Already trading"
	end
	local last = RuntimeState.Get(player).LastTradeAt
	if last > 0 and os.clock() - last < Config.Trade.CooldownSeconds then
		return string.format("Trade cooldown: %ds", math.ceil(Config.Trade.CooldownSeconds - (os.clock() - last)))
	end
	return nil
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------
local function describeOffer(owner: Player, uids: { string }): { any }
	local data = DataService.Get(owner)
	local out = {}
	for _, uid in uids do
		local item = if data then data.Machines.Inventory[uid] else nil
		if item then
			table.insert(out, { Uid = uid, Id = item.Id, Grade = item.Grade })
		end
	end
	return out
end

local function offerPower(owner: Player, uids: { string }): number
	local data = DataService.Get(owner)
	return if data then TradeLogic.OfferPower(data.Machines.Inventory, uids) else 0
end

local function viewFor(session: Session, player: Player): { [string]: any }
	local partner = other(session, player)
	local mine, theirs = session.Offers[player.UserId], session.Offers[partner.UserId]
	local myPower, theirPower = offerPower(player, mine), offerPower(partner, theirs)
	local countdown = 0
	if session.ReadyAt > 0 then
		countdown = math.max(0, session.ReadyAt + Config.Trade.CountdownSeconds - os.clock())
	end
	return {
		Active = true,
		SessionId = session.Id,
		Revision = session.Revision,
		PartnerUserId = partner.UserId,
		PartnerName = partner.DisplayName,
		MyOffer = describeOffer(player, mine),
		TheirOffer = describeOffer(partner, theirs),
		MyPower = myPower,
		TheirPower = theirPower,
		Lopsided = TradeLogic.IsLopsided(myPower, theirPower),
		MyReady = session.Ready[player.UserId] == true,
		TheirReady = session.Ready[partner.UserId] == true,
		MyConfirmed = session.Confirmed[player.UserId] == true,
		TheirConfirmed = session.Confirmed[partner.UserId] == true,
		CountdownLeft = countdown,
		CountdownTotal = Config.Trade.CountdownSeconds,
	}
end

local function broadcast(session: Session)
	if session.Closed then
		return
	end
	Remote.Fire("TradeUpdate", session.A, viewFor(session, session.A))
	Remote.Fire("TradeUpdate", session.B, viewFor(session, session.B))
end

local function closeSession(session: Session, result: "Completed" | "Cancelled", message: string)
	if session.Closed then
		return
	end
	session.Closed = true
	sessions[session.A] = nil
	sessions[session.B] = nil
	for _, player in { session.A, session.B } do
		if player.Parent == Players then
			Remote.Fire(
				"TradeUpdate",
				player,
				{ Active = false, SessionId = session.Id, Result = result, Message = message }
			)
			if result == "Cancelled" then
				Remote.Notify(player, "Info", message)
			end
		end
	end
end

local function removeRequest(request: Request)
	requests[request.Id] = nil
	if outgoing[request.From] == request then
		outgoing[request.From] = nil
	end
	if incoming[request.To] == request then
		incoming[request.To] = nil
	end
end

--------------------------------------------------------------------------------
-- Execution
--------------------------------------------------------------------------------
local function snapshotItems(data: PlayerData, uids: { string }): { any }
	local out = {}
	for _, uid in uids do
		local item = data.Machines.Inventory[uid]
		if item then
			table.insert(out, { Uid = uid, Id = item.Id, Grade = item.Grade, At = item.At })
		end
	end
	return out
end

local function logTrade(session: Session, record: { [string]: any }, profiles: { any })
	-- Extra saves shrink the window in which a server crash could roll back one side only.
	for _, profile in profiles do
		task.spawn(function()
			pcall(function()
				profile:Save()
			end)
		end)
	end
	local store = DataStoreService:GetDataStore(Config.Trade.LogStoreName)
	Retry.Call("TradeLog", function()
		store:SetAsync(session.Id, record)
	end)
end

local function execute(session: Session)
	-- Everything from here to the end of TradeLogic.Execute must not yield.
	local a, b = session.A, session.B
	if a.Parent ~= Players or b.Parent ~= Players then
		closeSession(session, "Cancelled", "Trade partner left")
		return
	end
	local dataA, dataB = DataService.Get(a), DataService.Get(b)
	local profileA, profileB = DataService.GetProfile(a) :: any, DataService.GetProfile(b) :: any
	if
		not dataA
		or not dataB
		or not profileA
		or not profileB
		or not DataService.IsLoaded(a)
		or not DataService.IsLoaded(b)
		or not profileA:IsActive()
		or not profileB:IsActive()
	then
		closeSession(session, "Cancelled", "Trade failed: data not available")
		return
	end

	local offerA, offerB = session.Offers[a.UserId], session.Offers[b.UserId]
	local itemsA, itemsB = snapshotItems(dataA, offerA), snapshotItems(dataB, offerB)
	local ok, err = TradeLogic.Execute(
		dataA.Machines.Inventory,
		TradeLogic.EquippedSet(dataA.Machines.Bays),
		offerA,
		dataB.Machines.Inventory,
		TradeLogic.EquippedSet(dataB.Machines.Bays),
		offerB
	)
	if not ok then
		closeSession(session, "Cancelled", err or "Trade failed")
		return
	end
	DataService.MarkDirty(a, "Machines")
	DataService.MarkDirty(b, "Machines")
	-- The swap is final; the rest may yield.
	local clock = os.clock()
	RuntimeState.Get(a).LastTradeAt = clock
	RuntimeState.Get(b).LastTradeAt = clock
	StatsService.Increment(a, "Trades", 1)
	StatsService.Increment(b, "Trades", 1)
	closeSession(session, "Completed", "Trade complete!")
	Remote.Notify(a, "Success", "Trade complete!")
	Remote.Notify(b, "Success", "Trade complete!")

	local record = {
		SessionId = session.Id,
		A = a.UserId,
		B = b.UserId,
		OfferA = itemsA,
		OfferB = itemsB,
		Time = os.time(),
	}
	task.spawn(logTrade, session, record, { profileA, profileB })
end

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------
local function tradeRequest(player: Player, targetArg: any): (boolean, string?, any?)
	local targetId = Guard.Integer(targetArg, 1, 2 ^ 53)
	if not targetId then
		return false, "Invalid player"
	end
	local target = Players:GetPlayerByUserId(targetId)
	if not target or target == player then
		return false, "Player not in this server"
	end
	if outgoing[player] or incoming[player] then
		return false, "Finish your current request first"
	end
	if incoming[target] or outgoing[target] then
		return false, target.DisplayName .. " has a pending request"
	end
	local mine = ineligibleReason(player)
	if mine then
		return false, mine
	end
	local theirs = ineligibleReason(target)
	if theirs then
		return false, target.DisplayName .. " can't trade yet"
	end
	-- Eligibility checks can yield; re-check state afterwards.
	if sessions[player] or sessions[target] or outgoing[player] or incoming[target] or target.Parent ~= Players then
		return false, "Try again in a moment"
	end

	local request: Request = {
		Id = HttpService:GenerateGUID(false),
		From = player,
		To = target,
		Expires = os.clock() + Config.Trade.RequestTimeoutSeconds,
	}
	requests[request.Id] = request
	outgoing[player] = request
	incoming[target] = request
	Remote.Fire("TradePrompt", target, request.Id, player.UserId, player.DisplayName)
	task.delay(Config.Trade.RequestTimeoutSeconds, function()
		if requests[request.Id] == request then
			removeRequest(request)
			Remote.Notify(player, "Info", target.DisplayName .. " didn't respond")
		end
	end)
	return true
end

local function openSession(request: Request)
	local a, b = request.From, request.To
	local session: Session = {
		Id = HttpService:GenerateGUID(false),
		A = a,
		B = b,
		Offers = { [a.UserId] = {}, [b.UserId] = {} },
		Ready = {},
		Confirmed = {},
		Revision = 0,
		ReadyAt = 0,
		Closed = false,
	}
	sessions[a] = session
	sessions[b] = session
	broadcast(session)
	task.delay(Config.Trade.MaxSessionSeconds, function()
		closeSession(session, "Cancelled", "Trade timed out")
	end)
end

local function tradeRespond(player: Player, requestIdArg: any, acceptArg: any): (boolean, string?, any?)
	local requestId = Guard.String(requestIdArg, 64)
	local accept = Guard.Boolean(acceptArg)
	if not requestId or accept == nil then
		return false, "Invalid request"
	end
	local request = requests[requestId]
	if not request or request.To ~= player or os.clock() > request.Expires then
		return false, "Request expired"
	end
	removeRequest(request)
	if not accept then
		Remote.Notify(request.From, "Info", player.DisplayName .. " declined the trade")
		return true
	end
	if request.From.Parent ~= Players then
		return false, "Player left"
	end
	local mine = ineligibleReason(player)
	if mine then
		return false, mine
	end
	local theirs = ineligibleReason(request.From)
	if theirs then
		Remote.Notify(request.From, "Info", theirs)
		return false, request.From.DisplayName .. " can't trade right now"
	end
	if sessions[player] or sessions[request.From] or request.From.Parent ~= Players or player.Parent ~= Players then
		return false, "Try again in a moment"
	end
	openSession(request)
	return true
end

local function mySession(player: Player): Session?
	local session = sessions[player]
	if session and not session.Closed then
		return session
	end
	return nil
end

-- Re-validates both current offers; closes the session when one is no longer legal.
local function offersStillValid(session: Session): boolean
	for _, player in { session.A, session.B } do
		local data = DataService.Get(player)
		if not data then
			closeSession(session, "Cancelled", "Trade failed: data not available")
			return false
		end
		local ok, err = TradeLogic.ValidateOffer(
			data.Machines.Inventory,
			TradeLogic.EquippedSet(data.Machines.Bays),
			session.Offers[player.UserId]
		)
		if not ok then
			closeSession(session, "Cancelled", string.format("%s: %s", player.DisplayName, err or "invalid offer"))
			return false
		end
	end
	return true
end

local function tradeSetOffer(player: Player, uidsArg: any): (boolean, string?, any?)
	local session = mySession(player)
	if not session then
		return false, "No active trade"
	end
	local uids = Guard.StringArray(uidsArg, Config.Trade.MaxItemsPerSide, 64)
	if not uids then
		return false, "Invalid offer"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Still loading"
	end
	local ok, err = TradeLogic.ValidateOffer(data.Machines.Inventory, TradeLogic.EquippedSet(data.Machines.Bays), uids)
	if not ok then
		return false, err
	end
	session.Offers[player.UserId] = uids
	session.Ready = {}
	session.Confirmed = {}
	session.ReadyAt = 0
	session.Revision += 1
	broadcast(session)
	return true
end

local function tradeReady(player: Player, readyArg: any, revisionArg: any): (boolean, string?, any?)
	local session = mySession(player)
	local ready = Guard.Boolean(readyArg)
	local revision = Guard.Integer(revisionArg, 0, 2 ^ 31)
	if not session or ready == nil or not revision then
		return false, "No active trade"
	end
	if revision ~= session.Revision then
		return false, "The offer just changed"
	end
	if ready then
		if not offersStillValid(session) then
			return false, "Trade cancelled"
		end
		session.Ready[player.UserId] = true
		if session.Ready[session.A.UserId] and session.Ready[session.B.UserId] then
			session.ReadyAt = os.clock()
		end
	else
		session.Ready[player.UserId] = nil
		session.Confirmed = {}
		session.ReadyAt = 0
	end
	broadcast(session)
	return true
end

local function tradeConfirm(player: Player, revisionArg: any): (boolean, string?, any?)
	local session = mySession(player)
	local revision = Guard.Integer(revisionArg, 0, 2 ^ 31)
	if not session or not revision then
		return false, "No active trade"
	end
	if revision ~= session.Revision then
		return false, "The offer just changed"
	end
	if not (session.Ready[session.A.UserId] and session.Ready[session.B.UserId]) or session.ReadyAt == 0 then
		return false, "Both players must be ready"
	end
	if os.clock() - session.ReadyAt < Config.Trade.CountdownSeconds then
		return false, "Wait for the countdown"
	end
	session.Confirmed[player.UserId] = true
	if session.Confirmed[session.A.UserId] and session.Confirmed[session.B.UserId] then
		execute(session)
	else
		broadcast(session)
	end
	return true
end

local function tradeCancel(player: Player): (boolean, string?, any?)
	local request = outgoing[player]
	if request then
		removeRequest(request)
	end
	local session = mySession(player)
	if session then
		closeSession(session, "Cancelled", player.DisplayName .. " cancelled the trade")
	end
	return true
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function dropPlayer(player: Player, reason: string)
	local session = sessions[player]
	if session then
		closeSession(session, "Cancelled", reason)
	end
	local out, inc = outgoing[player], incoming[player]
	if out then
		removeRequest(out)
	end
	if inc then
		removeRequest(inc)
	end
end

function TradeService.IsTrading(player: Player): boolean
	return mySession(player) ~= nil
end

function TradeService.Cancel(player: Player, reason: string)
	dropPlayer(player, reason)
end

function TradeService.Init()
	Remote.Handle("TradeRequest", function(player, target)
		return tradeRequest(player, target)
	end)
	Remote.Handle("TradeRespond", function(player, requestId, accept)
		return tradeRespond(player, requestId, accept)
	end)
	Remote.Handle("TradeSetOffer", function(player, uids)
		return tradeSetOffer(player, uids)
	end)
	Remote.Handle("TradeReady", function(player, ready, revision)
		return tradeReady(player, ready, revision)
	end)
	Remote.Handle("TradeConfirm", function(player, revision)
		return tradeConfirm(player, revision)
	end)
	Remote.Handle("TradeCancel", function(player)
		return tradeCancel(player)
	end)
end

function TradeService.Start()
	-- Warm the policy cache so the first request does not wait on the network.
	local function warm(player: Player)
		task.spawn(isTradingAllowedByPolicy, player)
	end
	for _, player in Players:GetPlayers() do
		warm(player)
	end
	Players.PlayerAdded:Connect(warm)
	Players.PlayerRemoving:Connect(function(player: Player)
		dropPlayer(player, player.DisplayName .. " left the trade")
		policyAllowed[player.UserId] = nil
	end)
	-- A profile ending while the player is still in game also ends their trade.
	DataService.Releasing:Connect(function(player: Player)
		dropPlayer(player, "Trade cancelled")
	end)
end

return TradeService

--!strict
--[[
	ShopService (L6): Game Pass / Developer Product prompts, idempotent ProcessReceipt, gifts,
	rewarded ads and Premium refresh. Paid rewards are granted ONLY from ProcessReceipt
	(rewarded-video ads included: the reward is a dev product delivered with
	ProductPurchaseChannel.AdReward). Nothing sold here rolls odds or completes contracts.
]]

local AdService = game:GetService("AdService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Guard = require(script.Parent.Parent.Server.Guard)
local Grants = require(script.Parent.Parent.Server.Grants)
local ReceiptLedger = require(Shared:WaitForChild("ReceiptLedger"))
local Remote = require(script.Parent.Parent.Server.Remote)
local Retry = require(script.Parent.Parent.Server.Retry)
local ServerSignals = require(script.Parent.Parent.Server.ServerSignals)
local Types = require(Shared:WaitForChild("Types"))

local ContractService = require(script.Parent.ContractService)
local DataService = require(script.Parent.DataService)
local MachineService = require(script.Parent.MachineService)
local OfflineEarningsService = require(script.Parent.OfflineEarningsService)
local PassService = require(script.Parent.PassService)
local ResearchService = require(script.Parent.ResearchService)

local ShopService = {}

type PlayerData = Types.PlayerData
type ProductDef = Config.ProductDef

type Profile = {
	Data: PlayerData,
	LastSavedData: any,
	OnAfterSave: { Wait: (any) -> any },
	Save: (Profile) -> (),
	IsActive: (Profile) -> boolean,
}

type GrantContext = {
	Buyer: Player,
	Recipient: Player,
	Data: PlayerData, -- recipient's data
	Key: string,
	Product: ProductDef,
}

-- Returns false when there was nothing to grant (the caller then pays out the fallback).
type Handler = (ctx: GrantContext) -> boolean

type GiftIntent = { ProductKey: string, TargetUserId: number, Expires: number }

local giftIntents: { [number]: GiftIntent } = {}
local inFlightReceipts: { [string]: boolean } = {}
local watchingAd: { [Player]: boolean } = {}

local function now(): number
	return os.time()
end

local function productKeyById(productId: number): (string?, ProductDef?)
	for key, def in Config.DevProducts do
		if def.Id ~= 0 and def.Id == productId then
			return key, def
		end
	end
	return nil, nil
end

local function mark(player: Player, key: string)
	DataService.MarkDirty(player, key)
end

local function hasActiveResearch(data: PlayerData): boolean
	return data.Research.ActiveId ~= "" and data.Research.EndsAt > now()
end

local function hasActivePlating(data: PlayerData): boolean
	return data.Machines.Plating.Id ~= "" and data.Machines.Plating.EndsAt > now()
end

local function hasRunningContract(data: PlayerData): boolean
	for _, slot in data.Contracts.Slots do
		if slot.Tier ~= "" and not slot.Done and slot.EndsAt > now() then
			return true
		end
	end
	return false
end

-- Prompt-time guard: refuse products that would have no effect right now.
local function nothingToDo(data: PlayerData, product: ProductDef): string?
	local grant = product.Grant
	if grant == "SkipResearch" and not hasActiveResearch(data) then
		return "No research is running"
	elseif grant == "SkipPlating" and not hasActivePlating(data) then
		return "Nothing is being plated"
	elseif grant == "ContractExtend" and not hasRunningContract(data) then
		return "No running contracts"
	elseif grant == "OfflineDouble" and not data.Offline.DoubleAvailable then
		return "No offline earnings to double"
	elseif grant == "StarterPack" and data.Purchases.StarterPackBought then
		return "Already purchased"
	end
	return nil
end

local function firstRareOfHighestHall(data: PlayerData): string?
	local hall = Formulas.HighestHall(data.Expansions)
	for _, def in Config.Machines do
		if def.Rarity == "Rare" and def.Hall == hall then
			return def.Id
		end
	end
	return nil
end

local function grantBundle(ctx: GrantContext): boolean
	local bundle = (Config.Bundles :: { [string]: any })[ctx.Key]
	if not bundle then
		return false
	end
	local player = ctx.Recipient
	if bundle.IncomeMinutes then
		Grants.GrantIncomeMinutes(player, bundle.IncomeMinutes, "Bundle")
	end
	if bundle.Credits then
		Grants.GrantCredits(player, bundle.Credits, "Bundle")
	end
	if bundle.RareOfHighestHall then
		local id = firstRareOfHighestHall(ctx.Data)
		if id then
			Grants.GrantMachine(player, id, "Bundle")
		end
	end
	if bundle.BoostKey and bundle.BoostMinutes then
		Grants.GrantBoost(player, bundle.BoostKey, bundle.BoostMinutes)
	end
	return true
end

local handlers: { [string]: Handler } = {
	IncomeMinutes = function(ctx)
		Grants.GrantIncomeMinutes(ctx.Recipient, ctx.Product.Amount or 0, "Shop")
		return true
	end,
	Credits = function(ctx)
		Grants.GrantCredits(ctx.Recipient, ctx.Product.Amount or 0, "Shop")
		return true
	end,
	Boost = function(ctx)
		local boostKey, minutes = ctx.Product.BoostKey, ctx.Product.Minutes
		if not boostKey or not minutes then
			return false
		end
		Grants.GrantBoost(ctx.Recipient, boostKey, minutes)
		return true
	end,
	SkipResearch = function(ctx)
		return ResearchService.SkipResearch(ctx.Recipient)
	end,
	SkipPlating = function(ctx)
		return MachineService.SkipPlating(ctx.Recipient)
	end,
	ContractExtend = function(ctx)
		return ContractService.ExtendAll(ctx.Recipient, Config.Contracts.ExtendSeconds)
	end,
	Shares = function(ctx)
		local data = ctx.Data
		local gain = math.max(5, math.floor((data.Shares + data.BonusShares) * (ctx.Product.Amount or 0)))
		-- BonusShares survives Expansion; MultiplierService adds Shares + BonusShares, so only this changes.
		data.BonusShares += gain
		mark(ctx.Recipient, "BonusShares")
		ServerSignals.MultipliersDirty:Fire(ctx.Recipient)
		return true
	end,
	StarterPack = function(ctx)
		-- A second concurrent purchase must not duplicate the one-time pack.
		if ctx.Data.Purchases.StarterPackBought then
			return false
		end
		local ok = grantBundle(ctx)
		if ok then
			ctx.Data.Purchases.StarterPackBought = true
			mark(ctx.Recipient, "Purchases")
		end
		return ok
	end,
	Bundle = grantBundle,
	OfflineDouble = function(ctx)
		return OfflineEarningsService.Double(ctx.Recipient)
	end,
}

local function consumeGiftTarget(buyer: Player, key: string, product: ProductDef): Player?
	local intent = giftIntents[buyer.UserId]
	if not intent or intent.ProductKey ~= key then
		return nil
	end
	giftIntents[buyer.UserId] = nil
	if not product.Giftable or os.clock() > intent.Expires then
		return nil
	end
	local target = Players:GetPlayerByUserId(intent.TargetUserId)
	if target and target ~= buyer and DataService.IsLoaded(target) then
		return target
	end
	return nil
end

local function runGrant(buyer: Player, buyerData: PlayerData, key: string, product: ProductDef, viaAd: boolean)
	local recipient = if viaAd then buyer else (consumeGiftTarget(buyer, key, product) or buyer)
	local giftData = if recipient == buyer then nil else DataService.Get(recipient)
	if recipient ~= buyer and not giftData then
		recipient = buyer
	end
	local ctx: GrantContext = {
		Buyer = buyer,
		Recipient = recipient,
		Data = giftData or buyerData,
		Key = key,
		Product = product,
	}

	local handler = handlers[product.Grant]
	local granted = false
	if handler then
		granted = handler(ctx)
	else
		warn("[ShopService] no handler for Grant = " .. tostring(product.Grant))
	end

	if not granted and handler and not viaAd then
		-- A skip raced with completion: pay out something fair instead of nothing.
		local credits = math.floor(product.Price * Config.Shop.FallbackCreditsPerRobux)
		if credits > 0 then
			Grants.GrantCredits(recipient, credits, "ShopFallback")
			Remote.Notify(recipient, "Info", string.format("Nothing to finish - got %d Credits instead", credits))
		end
	elseif granted then
		if recipient ~= buyer then
			Remote.Notify(buyer, "Success", string.format("%s sent to %s!", product.Name, recipient.DisplayName))
			Remote.Notify(recipient, "Reward", string.format("%s gifted you %s!", buyer.DisplayName, product.Name))
		else
			Remote.Notify(buyer, "Reward", string.format("%s delivered!", product.Name))
		end
	end

	if not viaAd then
		buyerData.Purchases.RobuxSpent += product.Price
	end
	mark(buyer, "Purchases")
end

local function buildAdapter(profile: Profile, data: PlayerData): ReceiptLedger.Adapter
	return {
		IsActive = function()
			return profile:IsActive()
		end,
		LiveCache = function()
			return data.Purchases.PurchaseIdCache
		end,
		SavedCache = function()
			local saved = profile.LastSavedData
			if type(saved) ~= "table" or type(saved.Purchases) ~= "table" then
				return nil
			end
			return saved.Purchases.PurchaseIdCache
		end,
		SaveAndWait = function()
			local before = profile.LastSavedData
			profile:Save()
			if profile.LastSavedData == before then
				profile.OnAfterSave:Wait()
			end
		end,
		RetryDelay = function(seconds: number)
			task.wait(seconds)
		end,
		MaxSize = Config.Data.PurchaseIdCacheSize,
	}
end

local function processReceiptInner(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local purchaseId = tostring(receipt.PurchaseId)
	if inFlightReceipts[purchaseId] then
		return notYet
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return notYet
	end
	local data = DataService.WaitFor(player, Config.Shop.ProfileWaitSeconds)
	local profile = DataService.GetProfile(player) :: Profile?
	if not data or not profile then
		return notYet
	end

	local key, product = productKeyById(receipt.ProductId)
	if not key or not product then
		warn("[ShopService] receipt for unknown product " .. tostring(receipt.ProductId))
		return notYet
	end
	local viaAd = receipt.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward

	inFlightReceipts[purchaseId] = true
	local ok, outcome = pcall(ReceiptLedger.Process, buildAdapter(profile, data), purchaseId, function()
		runGrant(player, data, key, product, viaAd)
	end)
	inFlightReceipts[purchaseId] = nil
	if not ok then
		warn("[ShopService] ledger error: " .. tostring(outcome))
		return notYet
	end
	return if outcome == "PurchaseGranted"
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Must never throw: an error would make Roblox retry the receipt in a loop.
function ShopService.ProcessReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local ok, decision = pcall(processReceiptInner, receipt)
	if ok then
		return decision
	end
	warn("[ShopService] ProcessReceipt failed: " .. tostring(decision))
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function promptPass(player: Player, passKey: any): (boolean, string?, any?)
	local key = Guard.Key(passKey, Config.GamePasses)
	if not key then
		return false, "Unknown pass"
	end
	local def = Config.GamePasses[key]
	if def.Id == 0 then
		return false, "Not configured yet"
	end
	if PassService.Owns(player, key) then
		return false, "You already own this"
	end
	local ok = Retry.Call("PromptGamePassPurchase", function()
		MarketplaceService:PromptGamePassPurchase(player, def.Id)
	end)
	return ok, if ok then nil else "Shop unavailable"
end

local function promptProduct(player: Player, productKey: any, giftUserId: any): (boolean, string?, any?)
	local key = Guard.Key(productKey, Config.DevProducts)
	if not key then
		return false, "Unknown product"
	end
	local product = Config.DevProducts[key]
	if product.Id == 0 then
		return false, "Not configured yet"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Still loading"
	end
	local blocked = nothingToDo(data, product)
	if blocked then
		return false, blocked
	end
	if product.Grant == "StarterPack" and data.Purchases.StarterPackFirstSeen > 0 then
		local expiresAt = data.Purchases.StarterPackFirstSeen + Config.Offers.StarterPackWindowHours * 3600
		if now() > expiresAt then
			return false, "Offer expired"
		end
	end

	if giftUserId ~= nil then
		local targetId = Guard.Integer(giftUserId, 1, 2 ^ 53)
		if not targetId or not product.Giftable then
			return false, "This cannot be gifted"
		end
		local target = Players:GetPlayerByUserId(targetId)
		if not target or target == player or not DataService.IsLoaded(target) then
			return false, "Player not in this server"
		end
		giftIntents[player.UserId] = {
			ProductKey = key,
			TargetUserId = targetId,
			Expires = os.clock() + Config.Shop.GiftIntentSeconds,
		}
	else
		giftIntents[player.UserId] = nil
	end

	local ok = Retry.Call("PromptProductPurchase", function()
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)
	return ok, if ok then nil else "Shop unavailable"
end

local function watchAd(player: Player, placementArg: any): (boolean, string?, any?)
	if not Config.Ads.Enabled then
		return false, "Ads are not available"
	end
	local placement = Guard.Key(placementArg, Config.Ads.Placements)
	if not placement then
		return false, "Unknown placement"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Still loading"
	end
	local productKey = (Config.Ads.Placements :: { [string]: string })[placement]
	local product = Config.DevProducts[productKey]
	if not product or product.Id == 0 then
		return false, "Not configured yet"
	end
	if watchingAd[player] then
		return false, "Ad already playing"
	end
	local blocked = nothingToDo(data, product)
	if blocked then
		return false, blocked
	end

	local ads = data.Ads
	local today = Formulas.DayNumber(now())
	if ads.Day ~= today then
		ads.Day, ads.Count = today, 0
	end
	if ads.Count >= Config.Ads.MaxPerDay then
		return false, "No more ads today"
	end
	local wait = ads.LastUnix + Config.Ads.CooldownSeconds - now()
	if wait > 0 then
		return false, string.format("Next ad in %ds", math.ceil(wait))
	end

	watchingAd[player] = true
	local ok, reward = Retry.Call("CreateAdReward", function(): any
		return (AdService :: any):CreateAdRewardFromDevProductId(product.Id)
	end)
	local result: any = nil
	if ok then
		-- Not retried: a retry would show a second ad.
		local shown, value = pcall(function(): any
			return (AdService :: any):ShowRewardedVideoAdAsync(player, reward)
		end)
		if shown then
			result = value
		else
			warn("[ShopService] ShowRewardedVideoAdAsync failed: " .. tostring(value))
		end
	end
	watchingAd[player] = nil

	if result ~= Enum.ShowAdResult.ShowCompleted then
		return false, "No ad available right now"
	end
	-- Count the view; the reward itself arrives through ProcessReceipt.
	if DataService.Get(player) == data then
		ads.Day, ads.Count, ads.LastUnix = today, ads.Count + 1, now()
		mark(player, "Ads")
	end
	return true, nil, { Placement = placement }
end

local function markOfferSeen(player: Player, offerArg: any): (boolean, string?, any?)
	local key = Guard.Key(offerArg, Config.DevProducts)
	if not key or Config.DevProducts[key].Category ~= "Offers" then
		return false, "Unknown offer"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Still loading"
	end
	if Config.DevProducts[key].Grant == "StarterPack" and data.Purchases.StarterPackFirstSeen == 0 then
		data.Purchases.StarterPackFirstSeen = now()
		mark(player, "Purchases")
	end
	return true
end

function ShopService.Init()
	Remote.Handle("PromptPass", function(player, passKey)
		return promptPass(player, passKey)
	end)
	Remote.Handle("PromptProduct", function(player, productKey, giftUserId)
		return promptProduct(player, productKey, giftUserId)
	end)
	Remote.Handle("WatchAd", function(player, placement)
		return watchAd(player, placement)
	end)
	Remote.Handle("MarkOfferSeen", function(player, offer)
		return markOfferSeen(player, offer)
	end)
	local marketplace: any = MarketplaceService
	marketplace.ProcessReceipt = ShopService.ProcessReceipt
end

function ShopService.Start()
	Players.PlayerMembershipChanged:Connect(function(player: Player)
		task.spawn(function()
			PassService.Refresh(player)
			ServerSignals.MultipliersDirty:Fire(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		giftIntents[player.UserId] = nil
		watchingAd[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			local data = DataService.Get(player)
			if not data then
				return
			end
			for _, def in Config.GamePasses do
				if def.Id ~= 0 and def.Id == passId then
					data.Purchases.RobuxSpent += def.Price
					mark(player, "Purchases")
					break
				end
			end
		end
	)
end

return ShopService

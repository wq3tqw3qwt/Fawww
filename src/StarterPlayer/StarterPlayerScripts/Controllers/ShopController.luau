--!strict
--[[
	ShopController: the "Shop" panel (Offers, Passes, Cash, Credits, Boosts, Utility).
	Every price comes from Config; purchases are intent-only (PromptPass / PromptProduct),
	the server prompts Marketplace and grants through ProcessReceipt. No paid randomness.
]]

local AdService = game:GetService("AdService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ShopController = {}

local PANEL = "Shop"
local TABS = { "Offers", "Passes", "Cash", "Credits", "Boosts", "Utility" }
local OTHER_PANELS = {
	"Machines",
	"Contracts",
	"Research",
	"Catalog",
	"Quests",
	"Trade",
	"Leaderboards",
	"Codes",
	"Admin",
}
local AD_RECHECK_SECONDS = 30

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Offers"
local timers: { () -> () } = {}
local tickToken = 0
local markRequested = false
local autoOpened = false
local adAvailable = false
local adCheckedAt = -math.huge
local busy = false

type ProductDef = Config.ProductDef

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function toastError(text: string?)
	NotificationController.Toast("Error", text or "Something went wrong")
	SoundController.Play("Error")
end

local function priceText(price: number): string
	return "R$ " .. NumberFormat.Commas(price)
end

local function sortedProducts(category: string): { { Key: string, Def: ProductDef } }
	local list = {}
	for key, def in Config.DevProducts do
		if def.Category == category then
			table.insert(list, { Key = key, Def = def })
		end
	end
	table.sort(list, function(a, b)
		return a.Def.Order < b.Def.Order
	end)
	return list
end

-- Cheapest R$ per unit across stand-alone products, so the Starter Pack "value" anchor is conservative.
local function bestRate(match: (ProductDef) -> number?): number
	local best = math.huge
	for _, def in Config.DevProducts do
		local units = match(def)
		if units and units > 0 then
			best = math.min(best, def.Price / units)
		end
	end
	return if best == math.huge then 0 else best
end

local function bundleValue(bundle: { [string]: any }): number
	local total = 0
	if bundle.IncomeMinutes then
		total += bestRate(function(def)
			return if def.Grant == "IncomeMinutes" then def.Amount else nil
		end) * bundle.IncomeMinutes
	end
	if bundle.Credits then
		total += bestRate(function(def)
			return if def.Grant == "Credits" then def.Amount else nil
		end) * bundle.Credits
	end
	if bundle.BoostKey and bundle.BoostMinutes then
		total += bestRate(function(def)
			return if def.Grant == "Boost" and def.BoostKey == bundle.BoostKey then def.Minutes else nil
		end) * bundle.BoostMinutes
	end
	return math.floor(total + 0.5)
end

local function bundleLines(bundle: { [string]: any }): string
	local lines = {}
	if bundle.IncomeMinutes then
		table.insert(lines, NumberFormat.Duration(bundle.IncomeMinutes * 60) .. " of income")
	end
	if bundle.Credits then
		table.insert(lines, NumberFormat.Commas(bundle.Credits) .. " Credits")
	end
	if bundle.RareOfHighestHall then
		table.insert(lines, "a Rare machine from your highest industry")
	end
	if bundle.BoostKey and bundle.BoostMinutes then
		local boost = Config.Boosts[bundle.BoostKey]
		table.insert(lines, (if boost then boost.Name else bundle.BoostKey) .. " for " .. bundle.BoostMinutes .. " min")
	end
	return table.concat(lines, "  •  ")
end

--------------------------------------------------------------------------------
-- Purchasing
--------------------------------------------------------------------------------
local function purchase(remote: string, key: string, giftUserId: number?)
	if busy then
		return
	end
	busy = true
	local res = if giftUserId then Net.Request(remote, key, giftUserId) else Net.Request(remote, key)
	busy = false
	if not res.Ok then
		toastError(res.Error)
	end
end

local function showGiftPicker(productKey: string, def: ProductDef)
	local overlay = UIKit.Create("TextButton", {
		Name = "GiftPicker",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 20,
		Parent = panel.Root,
	})
	local card = UIKit.Card(overlay, UDim2.fromScale(0.85, 0.7), nil)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = 21
	UIKit.Label({
		Text = "Gift " .. def.Name .. " to…",
		Size = UDim2.fromScale(0.9, 0.1),
		Position = UDim2.fromScale(0.05, 0.03),
		ZIndex = 22,
		Parent = card,
	})
	local list = UIKit.Scroll(card, UDim2.fromScale(0.92, 0.62), UDim2.fromScale(0.04, 0.15))
	UIKit.List(list, 0.02)
	local first: GuiObject? = nil
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer then
			count += 1
			local btn = UIKit.Button({
				Text = other.DisplayName .. "  (@" .. other.Name .. ")",
				Size = UDim2.fromScale(1, 0),
				LayoutOrder = count,
				ZIndex = 22,
				Parent = list,
				OnClick = function()
					overlay:Destroy()
					purchase("PromptProduct", productKey, other.UserId)
				end,
			})
			UIKit.Aspect(btn, 6)
			first = first or btn
		end
	end
	if count == 0 then
		UIKit.Label({
			Text = "No other players in this server yet.",
			Size = UDim2.fromScale(1, 0),
			ZIndex = 22,
			Parent = list,
		})
	end
	local cancel = UIKit.Button({
		Text = "Cancel",
		Size = UDim2.fromScale(0.5, 0.12),
		Position = UDim2.fromScale(0.25, 0.84),
		Color = palette.UIBad,
		ZIndex = 22,
		Parent = card,
		OnClick = function()
			overlay:Destroy()
		end,
	})
	GuiService.SelectedObject = first or cancel
end

--------------------------------------------------------------------------------
-- Card building
--------------------------------------------------------------------------------
local function itemCard(parent: Instance, order: number, title: string, desc: string, extra: string?): Frame
	local card = UIKit.Card(parent, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 3.4)
	UIKit.Label({
		Text = title,
		Size = UDim2.fromScale(0.58, 0.28),
		Position = UDim2.fromScale(0.03, 0.05),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
		Parent = card,
	})
	UIKit.Label({
		Text = desc,
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.58, 0.36),
		Position = UDim2.fromScale(0.03, 0.34),
		Alignment = Enum.TextXAlignment.Left,
		Color = Color3.fromRGB(215, 218, 230),
		MaxTextSize = 18,
		Parent = card,
	})
	if extra then
		UIKit.Label({
			Text = extra,
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.58, 0.24),
			Position = UDim2.fromScale(0.03, 0.72),
			Alignment = Enum.TextXAlignment.Left,
			Color = palette.Cash,
			MaxTextSize = 17,
			Parent = card,
		})
	end
	return card
end

local function badgeLabel(card: Frame, text: string?)
	if not text or text == "" then
		return
	end
	local badge = UIKit.Label({
		Text = text,
		Size = UDim2.fromScale(0.22, 0.2),
		Position = UDim2.fromScale(0.62, -0.06),
		MaxTextSize = 16,
		ZIndex = 3,
		Parent = card,
	})
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = palette.UIAccent
	badge.TextColor3 = Color3.new(0, 0, 0)
	UIKit.Corner(badge, 0.4)
end

local function buyButton(card: Frame, text: string, onClick: () -> ()): TextButton
	return UIKit.Button({
		Text = text,
		Size = UDim2.fromScale(0.34, 0.4),
		Position = UDim2.fromScale(0.63, 0.14),
		Color = palette.UIGood,
		Parent = card,
		OnClick = onClick,
	})
end

local function ownedLabel(card: Frame)
	UIKit.Label({
		Text = "OWNED",
		Size = UDim2.fromScale(0.34, 0.4),
		Position = UDim2.fromScale(0.63, 0.14),
		Color = palette.UIGood,
		Parent = card,
	})
end

local function productCard(parent: Instance, order: number, key: string, def: ProductDef, extra: string?): Frame
	local card = itemCard(parent, order, def.Name, def.Description, extra)
	badgeLabel(card, def.Badge)
	buyButton(card, priceText(def.Price), function()
		purchase("PromptProduct", key)
	end)
	if def.Giftable then
		UIKit.Button({
			Text = "Gift to a friend",
			Size = UDim2.fromScale(0.34, 0.28),
			Position = UDim2.fromScale(0.63, 0.62),
			Color = palette.UIAccent,
			MaxTextSize = 20,
			Parent = card,
			OnClick = function()
				showGiftPicker(key, def)
			end,
		})
	end
	return card
end

local function heading(parent: Instance, order: number, text: string): TextLabel
	local label = UIKit.Label({
		Text = text,
		Size = UDim2.fromScale(1, 0),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Aspect(label, 12)
	return label
end

local function note(parent: Instance, order: number, text: string, color: Color3?): TextLabel
	local label = UIKit.Label({
		Text = text,
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(1, 0),
		Color = color or Color3.fromRGB(215, 218, 230),
		MaxTextSize = 18,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Aspect(label, 11)
	return label
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------
local function weekendSecondsLeft(): number
	local events = DataController.GetEvents()
	local now = serverNow()
	local forced = if events then (events.ForcedWeekendUntil or 0) - now else 0
	local t = os.date("!*t", math.floor(now))
	local weekend = Config.Events.Weekend
	local daysAhead = (weekend.EndWday - t.wday) % 7
	local natural = (daysAhead + 1) * 86400 - (t.hour * 3600 + t.min * 60 + t.sec)
	return math.max(forced, natural)
end

local function adsLeftToday(data: any): number
	local ads = data.Ads
	local used = if ads.Day == Formulas.DayNumber(math.floor(serverNow())) then ads.Count else 0
	return math.max(0, Config.Ads.MaxPerDay - used)
end

local function renderAd(body: Instance, order: number, data: any)
	local placement = Config.Ads.Placements.Boost
	local product = if placement then Config.DevProducts[placement] else nil
	if not (Config.Ads.Enabled and adAvailable and product and product.BoostKey) then
		return
	end
	local boost = Config.Boosts[product.BoostKey]
	local card = itemCard(
		body,
		order,
		"Watch an ad: " .. (if boost then boost.Name else product.BoostKey) .. " " .. (product.Minutes or 0) .. " min",
		"Free reward for watching a short video.",
		adsLeftToday(data) .. " left today"
	)
	buyButton(card, "Watch", function()
		if busy then
			return
		end
		busy = true
		local res = Net.Request("WatchAd", "Boost")
		busy = false
		if not res.Ok then
			toastError(res.Error)
		end
	end).BackgroundColor3 =
		palette.UIAccent
end

local function renderBundle(body: Instance, order: number, key: string, data: any, active: boolean, label: string)
	local def = Config.DevProducts[key]
	local bundle = (Config.Bundles :: any)[key]
	if not def or not bundle then
		return
	end
	local value = bundleValue(bundle)
	local extra = "Contents worth " .. priceText(value)
	local card = itemCard(body, order, def.Name, bundleLines(bundle), extra)
	badgeLabel(card, def.Badge)
	if key == "StarterPack" and data.Purchases.StarterPackBought then
		ownedLabel(card)
		return
	end
	local timerLabel = UIKit.Label({
		Text = "",
		Size = UDim2.fromScale(0.34, 0.2),
		Position = UDim2.fromScale(0.63, 0.58),
		Color = palette.UIAccent,
		MaxTextSize = 18,
		Parent = card,
	})
	if not active then
		timerLabel.Text = label
		return
	end
	buyButton(card, priceText(def.Price), function()
		purchase("PromptProduct", key)
	end)
	table.insert(timers, function()
		if key == "StarterPack" then
			local seen = data.Purchases.StarterPackFirstSeen
			local left = if seen > 0
				then seen + Config.Offers.StarterPackWindowHours * 3600 - serverNow()
				else Config.Offers.StarterPackWindowHours * 3600
			timerLabel.Text = "Ends in " .. NumberFormat.Duration(left)
		else
			timerLabel.Text = "Ends in " .. NumberFormat.Duration(weekendSecondsLeft())
		end
	end)
end

local function renderOffers(body: Instance, data: any)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	renderAd(body, nextOrder(), data)

	local seen = data.Purchases.StarterPackFirstSeen
	local starter = Config.DevProducts.StarterPack
	local starterExpired = seen > 0 and serverNow() > seen + Config.Offers.StarterPackWindowHours * 3600
	if starter and not (starterExpired and not data.Purchases.StarterPackBought) then
		heading(body, nextOrder(), "Starter Pack")
		renderBundle(body, nextOrder(), "StarterPack", data, true, "")
	end

	for _, offer in Config.Offers.Limited do
		local def = Config.DevProducts[offer.ProductKey]
		if def then
			local events = DataController.GetEvents()
			local weekend = events ~= nil and events.WeekendActive == true
			if offer.Recurring ~= "Weekend" or weekend then
				heading(body, nextOrder(), "Limited offer")
				renderBundle(body, nextOrder(), offer.ProductKey, data, true, "")
			else
				heading(body, nextOrder(), "Weekend Bundle")
				renderBundle(body, nextOrder(), offer.ProductKey, data, false, "Returns every weekend")
			end
		end
	end

	heading(body, nextOrder(), "Roblox Premium")
	note(
		body,
		nextOrder(),
		string.format(
			"Premium members get +%s income and %d free Credits every day.",
			NumberFormat.Percent(Config.Premium.IncomeBonus),
			Config.Premium.DailyCredits
		),
		palette.UIAccent
	)
	note(body, nextOrder(), "No paid randomness: everything here is exactly what you see.", palette.UIGood)
end

local function renderPasses(body: Instance, data: any)
	local list = {}
	for key, def in Config.GamePasses do
		table.insert(list, { Key = key, Def = def })
	end
	table.sort(list, function(a, b)
		return a.Def.Order < b.Def.Order
	end)
	for i, entry in list do
		local card = itemCard(body, i, entry.Def.Name, entry.Def.Description, nil)
		if data.Passes[entry.Key] then
			ownedLabel(card)
		else
			buyButton(card, priceText(entry.Def.Price), function()
				purchase("PromptPass", entry.Key)
			end)
		end
	end
	note(body, #list + 1, "Passes are permanent and shared across all your sessions.")
end

local function renderProducts(body: Instance, category: string)
	local runtime = DataController.GetRuntime()
	local income: number? = if runtime then runtime.Income else nil
	for i, entry in sortedProducts(category) do
		local extra: string? = nil
		if entry.Def.Grant == "IncomeMinutes" and entry.Def.Amount then
			extra = if income and income > 0
				then "≈ " .. NumberFormat.Cash(income * entry.Def.Amount * 60) .. " at your income today"
				else "Scales with your income"
		elseif entry.Def.Grant == "Credits" and entry.Def.Amount then
			extra = NumberFormat.Commas(entry.Def.Amount) .. " Credits"
		end
		productCard(body, i, entry.Key, entry.Def, extra)
	end
	if category == "Boosts" then
		local label = note(body, 0, "", palette.Cash)
		table.insert(timers, function()
			local data = DataController.Get()
			if not data then
				return
			end
			local parts = {}
			for key, expiry in data.Boosts do
				local left = expiry - serverNow()
				if left > 0 then
					local boost = Config.Boosts[key]
					table.insert(parts, (if boost then boost.Name else key) .. " " .. NumberFormat.Duration(left))
				end
			end
			label.Text = if #parts > 0 then "Active: " .. table.concat(parts, "  •  ") else "No boosts running"
		end)
	end
end

local function render()
	tickToken += 1
	timers = {}
	clear(panel.Body)
	local data = DataController.Get()
	if not data then
		return
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then palette.UIAccent else palette.UIPanel
	end
	if currentTab == "Offers" then
		renderOffers(panel.Body, data)
		if data.Purchases.StarterPackFirstSeen == 0 and not data.Purchases.StarterPackBought and not markRequested then
			markRequested = true
			task.spawn(Net.Request, "MarkOfferSeen", "StarterPack")
		end
	elseif currentTab == "Passes" then
		renderPasses(panel.Body, data)
	else
		renderProducts(panel.Body, currentTab)
	end

	local token = tickToken
	task.spawn(function()
		while tickToken == token and UIController.IsOpen(PANEL) do
			for _, fn in timers do
				fn()
			end
			task.wait(0.5)
		end
	end)
end

local function refreshAd()
	if not Config.Ads.Enabled or serverNow() - adCheckedAt < AD_RECHECK_SECONDS then
		return
	end
	adCheckedAt = serverNow()
	-- Client-only API; any failure simply hides the entry.
	local ok, result = pcall(function()
		return (AdService :: any):GetAdAvailabilityNowAsync((Enum :: any).AdFormat.RewardedVideo)
	end)
	local available = ok and result ~= nil and result.IsAvailable == true
	if available ~= adAvailable then
		adAvailable = available
		if UIController.IsOpen(PANEL) and currentTab == "Offers" then
			render()
		end
	end
end

local function selectTab(name: string)
	currentTab = name
	render()
end

function ShopController.Init()
	panel = UIKit.Panel(PANEL, "Shop", UIController.GetLayer("Panels"), palette.UIAccent)

	local bar = UIKit.Create("Frame", {
		Name = "Tabs",
		Size = UDim2.fromScale(0.96, 0.08),
		Position = UDim2.fromScale(0.02, 0.135),
		BackgroundTransparency = 1,
		Parent = panel.Root,
	})
	UIKit.List(bar, 0.008, true)
	for i, name in TABS do
		tabButtons[name] = UIKit.Button({
			Text = name,
			Size = UDim2.fromScale(1 / #TABS - 0.01, 1),
			LayoutOrder = i,
			MaxTextSize = 22,
			Parent = bar,
			OnClick = function()
				selectTab(name)
			end,
		})
	end
	panel.Body.Size = UDim2.fromScale(0.96, 0.75)
	panel.Body.Position = UDim2.fromScale(0.02, 0.23)
	UIKit.List(panel.Body, 0.02)

	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = function()
			task.spawn(refreshAd)
			render()
		end,
		OnClose = function()
			tickToken += 1
		end,
	})
end

local function anyPanelOpen(): boolean
	if UIController.IsOpen(PANEL) then
		return true
	end
	for _, name in OTHER_PANELS do
		if UIController.IsOpen(name) then
			return true
		end
	end
	return false
end

function ShopController.Start()
	DataController.WaitForData()
	local function relevant()
		if UIController.IsOpen(PANEL) then
			render()
		end
	end
	for _, key in { "Passes", "Purchases", "Boosts", "Ads" } do
		maid:Add(DataController.OnKey(key, relevant))
	end

	-- Starter Pack: open once, after enough play time, never during the tutorial.
	task.spawn(function()
		while not autoOpened do
			task.wait(5)
			local data = DataController.Get()
			local product = Config.DevProducts.StarterPack
			if
				data
				and product
				and product.Id ~= 0
				and data.Tutorial.Done
				and not data.Purchases.StarterPackBought
				and data.Purchases.StarterPackFirstSeen == 0
				and data.Stats.PlaySeconds >= Config.Offers.FirstOfferMinPlaySeconds
				and not anyPanelOpen()
			then
				autoOpened = true
				currentTab = "Offers"
				UIController.Open(PANEL)
			end
		end
	end)
end

return ShopController

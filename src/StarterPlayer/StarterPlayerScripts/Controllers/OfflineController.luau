--!strict
--[[
	OfflineController: "Welcome back!" popup for offline earnings. The factory stays visible behind a
	semi-transparent shade. Collect pays the pending cash; the x2 options (rewarded ad or Robux)
	let the server double it. The server owns every amount: values shown here come from replicated data.
]]

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local OfflineController = {}

local Palette = UIKit.Palette
local SHADE_TRANSPARENCY = 0.6
local GREY = Color3.fromRGB(80, 84, 100)

local maid = Maid.new()
local popupMaid = Maid.new()
local popupOpen = false
local shownThisSession = false
local amountLabel: TextLabel? = nil
local timeLabel: TextLabel? = nil
local adButton: TextButton? = nil
local buyButton: TextButton? = nil
local fallbackSeconds = 0
local busy = false

local function adAvailable(): boolean
	if not Config.Ads.Enabled then
		return false
	end
	-- VERIFY: AdService rewarded video availability depends on region/age and the experience being eligible.
	local ok, result = pcall(function()
		return (AdService :: any):GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	if not ok then
		return false
	end
	local info = result :: any
	return type(info) == "table" and info.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

local function refreshTexts()
	local data = DataController.Get()
	if data == nil then
		return
	end
	local offline = data.Offline
	if amountLabel then
		amountLabel.Text = NumberFormat.Cash(offline.PendingCash)
	end
	if timeLabel then
		local seconds = if offline.PendingSeconds > 0 then offline.PendingSeconds else fallbackSeconds
		timeLabel.Text = `Away for {NumberFormat.Duration(seconds)}`
	end
	local canDouble = offline.DoubleAvailable
	if buyButton then
		buyButton.Visible = canDouble
	end
	if adButton and not canDouble then
		adButton.Visible = false
	end
end

local function close()
	popupMaid:Clean()
	popupOpen = false
	amountLabel, timeLabel, adButton, buyButton = nil, nil, nil, nil
end

local function collect()
	if busy then
		return
	end
	busy = true
	local response = NotificationController.Request("ClaimOffline")
	busy = false
	if response.Ok then
		local data: any = response.Data
		local cash = if type(data) == "table" and type(data.Cash) == "number" then data.Cash else 0
		NotificationController.Toast("Reward", `+{NumberFormat.Cash(cash)} collected!`)
		SoundController.Play("Coins")
		close()
	end
end

local function doubleWithAd()
	if busy then
		return
	end
	busy = true
	local response = NotificationController.Request("WatchAd", Config.Ads.Placements.OfflineDouble)
	busy = false
	if response.Ok then
		NotificationController.Toast("Success", "Doubled! Tap Collect")
		refreshTexts()
	end
end

local function doubleWithRobux()
	if busy then
		return
	end
	busy = true
	NotificationController.Request("PromptProduct", "OfflineDouble")
	busy = false
end

local function show(seconds: number)
	if popupOpen then
		fallbackSeconds = math.max(fallbackSeconds, seconds)
		refreshTexts()
		return
	end
	popupOpen = true
	fallbackSeconds = seconds
	UIController.CloseAll()

	local shade = UIKit.Create("Frame", {
		Name = "OfflinePopup",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = SHADE_TRANSPARENCY,
		Parent = UIController.GetLayer("Overlay"),
	})
	popupMaid:Add(shade)
	local card = UIKit.Card(shade, UDim2.fromScale(0.7, 0), Palette.UIBackground)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	UIKit.Aspect(card, 1.9)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(760, 400), Parent = card })
	UIKit.Pop(card, 0.08)

	UIKit.Label({
		Text = "Welcome back!",
		Size = UDim2.fromScale(0.9, 0.18),
		Position = UDim2.fromScale(0.05, 0.04),
		MaxTextSize = 44,
		Parent = card,
	})
	timeLabel = UIKit.Label({
		Size = UDim2.fromScale(0.9, 0.1),
		Position = UDim2.fromScale(0.05, 0.22),
		Color = Color3.fromRGB(200, 205, 220),
		MaxTextSize = 24,
		Parent = card,
	})
	amountLabel = UIKit.Label({
		Size = UDim2.fromScale(0.9, 0.22),
		Position = UDim2.fromScale(0.05, 0.33),
		Color = Palette.Cash,
		MaxTextSize = 64,
		Parent = card,
	})
	local collectButton = UIKit.Button({
		Name = "Collect",
		Text = "COLLECT",
		Size = UDim2.fromScale(0.9, 0.2),
		Position = UDim2.fromScale(0.05, 0.58),
		Color = Palette.UIGood,
		MaxTextSize = 40,
		Parent = card,
		OnClick = collect,
	})
	local ad = UIKit.Button({
		Name = "DoubleAd",
		Text = "x2  Watch ad",
		Size = UDim2.fromScale(0.44, 0.15),
		Position = UDim2.fromScale(0.05, 0.82),
		Color = Palette.UIAccent,
		Parent = card,
		OnClick = doubleWithAd,
	})
	ad.Visible = false
	adButton = ad
	buyButton = UIKit.Button({
		Name = "DoubleBuy",
		Text = "x2  Robux",
		Size = UDim2.fromScale(0.44, 0.15),
		Position = UDim2.fromScale(0.51, 0.82),
		Color = GREY,
		Parent = card,
		OnClick = doubleWithRobux,
	})
	refreshTexts()
	UIKit.Select(collectButton)

	task.spawn(function()
		local data = DataController.Get()
		if data and data.Offline.DoubleAvailable and adAvailable() and adButton == ad and ad.Parent then
			ad.Visible = true
		end
	end)
end

local function onEffect(kind: any, payload: any)
	if kind ~= "Offline" or type(payload) ~= "table" then
		return
	end
	shownThisSession = false
	local seconds: number = if type(payload.Seconds) == "number" then payload.Seconds else 0
	task.spawn(function()
		DataController.WaitForData()
		show(seconds)
	end)
end

function OfflineController.Init()
	maid:Add(Net.Event("Effect").OnClientEvent:Connect(onEffect))
end

function OfflineController.Start()
	maid:Add(DataController.OnKey("Offline", function(value: any)
		if type(value) ~= "table" then
			return
		end
		if popupOpen then
			refreshTexts()
			if value.PendingCash <= 0 then
				close()
			end
		elseif value.PendingCash > 0 and not shownThisSession then
			shownThisSession = true
			show(value.PendingSeconds or 0)
		end
	end))
end

return OfflineController

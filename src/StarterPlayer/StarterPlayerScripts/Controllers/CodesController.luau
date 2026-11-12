--!strict
--[[
	CodesController: the "Codes" panel. Promo codes only ever grant Credits and boosts (see Config.Codes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CodesController = {}

local PANEL = "Codes"
-- Mirrors the server-side length guard on RedeemCode.
local MAX_CODE_LENGTH = 32

local palette = UIKit.Palette
local panel: UIKit.Panel
local input: TextBox
local busy = false

local function rewardText(data: any): string
	local parts = {}
	if type(data) == "table" then
		if type(data.Credits) == "number" and data.Credits > 0 then
			table.insert(parts, NumberFormat.Commas(data.Credits) .. " Credits")
		end
		if type(data.BoostKey) == "string" and type(data.Minutes) == "number" then
			local boost = Config.Boosts[data.BoostKey]
			table.insert(parts, string.format("%s %d min", if boost then boost.Name else data.BoostKey, data.Minutes))
		end
	end
	return if #parts > 0 then table.concat(parts, " + ") else "reward"
end

local function redeem()
	if busy then
		return
	end
	local code = string.gsub(input.Text, "%s+", "")
	if code == "" then
		NotificationController.Toast("Error", "Enter a code first.")
		return
	end
	busy = true
	local res = NotificationController.Request("RedeemCode", string.sub(code, 1, MAX_CODE_LENGTH))
	busy = false
	if res.Ok then
		input.Text = ""
		NotificationController.Toast("Reward", "Code redeemed: " .. rewardText(res.Data))
		SoundController.Play("Fanfare")
	else
		SoundController.Play("Error")
	end
end

function CodesController.Init()
	panel = UIKit.Panel(PANEL, "Codes", UIController.GetLayer("Panels"), palette.UIAccent)
	UIKit.List(panel.Body, 0.03)

	local info = UIKit.Label({
		Text = "Enter a promo code for free Credits and boosts. Follow our group and social pages for new codes!",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 1,
		MaxTextSize = 22,
		Parent = panel.Body,
	})
	UIKit.Aspect(info, 4)

	local box = UIKit.Card(panel.Body, UDim2.fromScale(1, 0), palette.UIBackground, 2)
	UIKit.Aspect(box, 6)
	input = UIKit.Create("TextBox", {
		Size = UDim2.fromScale(0.94, 0.7),
		Position = UDim2.fromScale(0.03, 0.15),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Enter code",
		PlaceholderColor3 = Color3.fromRGB(150, 153, 165),
		TextColor3 = palette.UIText,
		Font = UIKit.Font,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = box,
	})
	UIKit.Create("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 10, Parent = input })
	input.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			redeem()
		end
	end)

	local button = UIKit.Button({
		Text = "Redeem",
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 3,
		Color = palette.UIGood,
		Parent = panel.Body,
		OnClick = redeem,
	})
	UIKit.Aspect(button, 6)

	UIController.RegisterPanel(PANEL, { Root = panel.Root })
end

return CodesController

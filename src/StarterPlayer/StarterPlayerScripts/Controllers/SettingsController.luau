--!strict
--[[
	SettingsController: the "Settings" panel. Toggles (Music, SFX, Low graphics) are saved by the
	server (SetSetting) and mirrored through the Settings data key; also the title picker, the
	Experience Notifications opt-in prompt and a credits line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maid = require(ReplicatedStorage.Shared.Maid)
local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SettingsController = {}

local Palette = UIKit.Palette
local GREY = Color3.fromRGB(80, 84, 100)
local TOGGLES: { { key: string, label: string } } = {
	{ key = "Music", label = "Music" },
	{ key = "Sfx", label = "Sound effects" },
	{ key = "LowGraphics", label = "Low graphics" },
}

type Ratio = { Constraint: UIAspectRatioConstraint, Wide: number, Tall: number }

local maid = Maid.new()
local titleMaid = Maid.new()
local panel: UIKit.Panel? = nil
local ratios: { Ratio } = {}
local toggleButtons: { [string]: TextButton } = {}
local titleRows: { Frame } = {}

local function applyRatios()
	local camera = workspace.CurrentCamera
	local wide = camera == nil or camera.ViewportSize.X >= camera.ViewportSize.Y * 1.2
	for index = #ratios, 1, -1 do
		local entry = ratios[index]
		if entry.Constraint.Parent == nil then
			table.remove(ratios, index)
		else
			entry.Constraint.AspectRatio = if wide then entry.Wide else entry.Tall
		end
	end
end

local function newRow(body: Instance, order: number): Frame
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	table.insert(ratios, { Constraint = UIKit.Aspect(card, 6), Wide = 6, Tall = 3.4 })
	applyRatios()
	return card
end

local function rowLabel(row: Frame, text: string): TextLabel
	return UIKit.Label({
		Text = text,
		Size = UDim2.fromScale(0.58, 0.8),
		Position = UDim2.fromScale(0.03, 0.1),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = row,
	})
end

local function rowButton(row: Frame, text: string, onClick: () -> ()): TextButton
	return UIKit.Button({
		Text = text,
		Size = UDim2.fromScale(0.34, 0.7),
		Position = UDim2.fromScale(0.63, 0.15),
		Parent = row,
		OnClick = onClick,
	})
end

local function refreshToggles()
	local settings: any = DataController.GetKey("Settings")
	if type(settings) ~= "table" then
		return
	end
	for key, button in toggleButtons do
		local on = settings[key] == true
		button.Text = if on then "ON" else "OFF"
		button.BackgroundColor3 = if on then Palette.UIGood else GREY
	end
end

local function rebuildTitles()
	local current = panel
	if current == nil then
		return
	end
	titleMaid:Clean()
	table.clear(titleRows)
	local social: any = DataController.GetKey("Social")
	if type(social) ~= "table" then
		return
	end
	local owned: { string } = {}
	for title, has in social.Titles do
		if has then
			table.insert(owned, title)
		end
	end
	table.sort(owned)
	table.insert(owned, 1, "")
	for index, title in owned do
		local row = newRow(current.Body, 100 + index)
		titleMaid:Add(row)
		local equipped = social.Title == title
		rowLabel(row, if title == "" then "No title" else title)
		local button = rowButton(row, if equipped then "EQUIPPED" else "EQUIP", function()
			task.spawn(NotificationController.Request, "SetTitle", title)
		end)
		button.BackgroundColor3 = if equipped then GREY else Palette.UIAccent
		table.insert(titleRows, row)
	end
end

local function promptNotifications()
	-- VERIFY: Experience Notifications must be enabled for the experience and the player eligible.
	local ok, err = pcall(function()
		local service = game:GetService("ExperienceNotificationService") :: any
		if service:CanPromptOptInAsync() then
			service:PromptOptIn()
		else
			NotificationController.Toast("Info", "Notifications are not available for your account")
		end
	end)
	if not ok then
		warn("[SettingsController] notification opt-in failed: " .. tostring(err))
		NotificationController.Toast("Info", "Notifications are not available right now")
	end
end

local function buildPanel()
	local created = UIKit.Panel("Settings", "Settings", UIController.GetLayer("Panels"), Palette.UIAccent)
	panel = created
	maid:Add(created.Root)
	UIKit.List(created.Body, 0.015)
	UIKit.Padding(created.Body, 0.01)
	local body = created.Body

	for index, toggle in TOGGLES do
		local row = newRow(body, index)
		rowLabel(row, toggle.label)
		toggleButtons[toggle.key] = rowButton(row, "", function()
			local settings: any = DataController.GetKey("Settings")
			local on = type(settings) == "table" and settings[toggle.key] == true
			task.spawn(NotificationController.Request, "SetSetting", toggle.key, not on)
		end)
	end

	local notifications = newRow(body, 10)
	rowLabel(notifications, "Game notifications")
	rowButton(notifications, "ENABLE", promptNotifications)

	local header = newRow(body, 20)
	UIKit.Label({
		Text = "Titles",
		Size = UDim2.fromScale(0.9, 0.8),
		Position = UDim2.fromScale(0.05, 0.1),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		Parent = header,
	})

	local credits = newRow(body, 1000)
	UIKit.Label({
		Text = `{Config.GameName}  ·  data v{Config.DataVersion}`,
		Size = UDim2.fromScale(0.94, 0.8),
		Position = UDim2.fromScale(0.03, 0.1),
		Color = Color3.fromRGB(200, 205, 220),
		MaxTextSize = 20,
		Parent = credits,
	})

	UIController.RegisterPanel("Settings", {
		Root = created.Root,
		OnOpen = function()
			refreshToggles()
			rebuildTitles()
		end,
	})
end

function SettingsController.Start()
	buildPanel()
	maid:Add(DataController.OnKey("Settings", refreshToggles))
	maid:Add(DataController.OnKey("Social", function()
		local current = panel
		if current and current.Root.Visible then
			rebuildTitles()
		end
	end))
	local camera = workspace.CurrentCamera
	if camera then
		maid:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyRatios))
	end
end

return SettingsController

--!strict
--[[
	HUDController: mobile-first HUD on the HUD layer.
	  top centre: Cash / Credits / Income / Shares; below it the Rush/Weekend strip
	  left: grid of round panel buttons (3 columns keeps the thumbstick area free)
	  right: boost chips, EXPAND and COLLECT (vault) buttons
	  bottom centre: Supply Drop badge and "next update" countdown
	All sizes are Scale; the nav grid is recomputed from the viewport so every button stays
	>= Config.UI.MinTapSize of the short screen side.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HUDController = {}

local Palette = UIKit.Palette
local MAX_CHIPS = 3
local MAX_PER_ROW = 3

local NAV: { { name: string, icon: string, admin: boolean? } } = {
	{ name = "Factory", icon = "🏭" },
	{ name = "Contracts", icon = "📜" },
	{ name = "Machines", icon = "🤖" },
	{ name = "Quests", icon = "✅" },
	{ name = "Shop", icon = "🛒" },
	{ name = "Catalog", icon = "📖" },
	{ name = "Research", icon = "🔬" },
	{ name = "Leaderboards", icon = "🏆" },
	{ name = "Trade", icon = "🔁" },
	{ name = "Codes", icon = "🎁" },
	{ name = "Settings", icon = "⚙️" },
	{ name = "Admin", icon = "🛡️", admin = true },
}

type NavButton = { Name: string, Button: TextButton, Badge: TextLabel, Admin: boolean }

local maid = Maid.new()
local root: Frame
local navButtons: { NavButton } = {}
local navByName: { [string]: NavButton } = {}
local topCells: { [string]: TextLabel } = {}
local topBar: Frame
local eventStrip: Frame
local eventLabel: TextLabel
local chipsFrame: Frame
local actionFrame: Frame
local collectFrame: Frame
local collectButton: TextButton
local collectBar: UIKit.ProgressBar
local expandButton: TextButton
local supplyButton: TextButton
local updateLabel: TextLabel
local chips: { [string]: { Frame: Frame, Label: TextLabel } } = {}
local eventsAt = 0
local stopCollectPulse: (() -> ())? = nil
local stopExpandPulse: (() -> ())? = nil

-- Adds a looping highlight stroke to any GuiObject; returns a function that removes it.
function HUDController.Pulse(target: GuiObject, color: Color3?): () -> ()
	local stroke = UIKit.Create("UIStroke", {
		Name = "PulseStroke",
		Color = color or Palette.UIAccent,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = target,
	})
	local tween = TweenService:Create(
		stroke,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Thickness = 9, Transparency = 0.5 }
	)
	tween:Play()
	return function()
		tween:Cancel()
		stroke:Destroy()
	end
end

function HUDController.GetButton(name: string): TextButton?
	local entry = navByName[name]
	return if entry then entry.Button else nil
end

function HUDController.GetCollectButton(): TextButton?
	return if collectFrame and collectFrame.Visible then collectButton else nil
end

local function setPulse(current: (() -> ())?, active: boolean, target: GuiObject): (() -> ())?
	if active and current == nil then
		return HUDController.Pulse(target)
	elseif not active and current then
		current()
		return nil
	end
	return current
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
local function layout()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local vp = camera.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then
		return
	end
	local inset = GuiService:GetGuiInset()
	local top = math.max(0.03, inset.Y / vp.Y + 0.01)
	local short = math.min(vp.X, vp.Y)

	topBar.Position = UDim2.fromScale(0.5, top)
	eventStrip.Position = UDim2.fromScale(0.5, top + 0.105)
	chipsFrame.Position = UDim2.fromScale(0.97, top + 0.095)

	local visible: { NavButton } = {}
	for _, entry in navButtons do
		local show = not entry.Admin or DataController.IsAdmin()
		entry.Button.Visible = show
		if show then
			table.insert(visible, entry)
		end
	end
	local rows = math.max(1, math.ceil(#visible / MAX_PER_ROW))
	local gridTop = top + 0.11
	local availablePx = math.max(0.1, 0.8 - gridTop) * vp.Y
	local sidePx = math.min(Config.UI.MinTapSize * short * 1.15, availablePx / (rows + 0.2))
	local cx, cy = sidePx / vp.X, sidePx / vp.Y
	local gx, gy = 0.18 * cx, 0.18 * cy
	for index, entry in visible do
		local col = (index - 1) % MAX_PER_ROW
		local row = (index - 1) // MAX_PER_ROW
		entry.Button.Size = UDim2.fromScale(cx, cy)
		entry.Button.Position = UDim2.fromScale(0.03 + col * (cx + gx), gridTop + row * (cy + gy))
	end
end

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------
local function buildTopBar(parent: Frame)
	topBar = UIKit.Create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.56, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.Aspect(topBar, 9)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(780, 90), Parent = topBar })
	UIKit.List(topBar, 0.012, true)
	local defs = {
		{ key = "Cash", color = Palette.Cash },
		{ key = "Credits", color = Palette.Credits },
		{ key = "Income", color = Palette.UIAccent },
		{ key = "Shares", color = Color3.fromRGB(190, 140, 255) },
	}
	for order, def in defs do
		local cell = UIKit.Card(topBar, UDim2.fromScale(0.24, 1), Palette.UIBackground, order)
		cell.BackgroundTransparency = 0.25
		topCells[def.key] = UIKit.Label({
			Name = def.key,
			Size = UDim2.fromScale(0.92, 0.7),
			Position = UDim2.fromScale(0.04, 0.15),
			Color = def.color,
			MaxTextSize = 28,
			Parent = cell,
		})
	end
end

local function buildNav(parent: Frame)
	for _, def in NAV do
		local button = UIKit.Button({
			Name = def.name,
			Size = UDim2.fromScale(0.07, 0.12),
			Color = Palette.UIPanel,
			Parent = parent,
			OnClick = function()
				UIController.Toggle(def.name)
			end,
		})
		local corner = button:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0.5, 0)
		end
		UIKit.Aspect(button, 1)
		button.Text = ""
		UIKit.Label({
			Name = "Icon",
			Text = def.icon,
			Size = UDim2.fromScale(1, 0.62),
			Position = UDim2.fromScale(0, 0.02),
			MaxTextSize = 40,
			Parent = button,
		})
		UIKit.Label({
			Name = "Caption",
			Text = def.name,
			Size = UDim2.fromScale(1.1, 0.26),
			Position = UDim2.fromScale(-0.05, 0.7),
			MaxTextSize = 14,
			Parent = button,
		})
		local badge = UIKit.Label({
			Name = "Badge",
			Text = "!",
			Size = UDim2.fromScale(0.4, 0.4),
			Position = UDim2.fromScale(0.72, -0.1),
			Color = Palette.UIText,
			MaxTextSize = 20,
			Parent = button,
		})
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Palette.UIBad
		badge.Visible = false
		UIKit.Corner(badge, 0.5)
		local entry: NavButton = { Name = def.name, Button = button, Badge = badge, Admin = def.admin == true }
		table.insert(navButtons, entry)
		navByName[def.name] = entry
	end
end

local function buildRight(parent: Frame)
	chipsFrame = UIKit.Create("Frame", {
		Name = "BoostChips",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromScale(0.17, 0.3),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.List(chipsFrame, 0.02, false, Enum.HorizontalAlignment.Right)

	actionFrame = UIKit.Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.97, 0.8),
		Size = UDim2.fromScale(0.17, 0.4),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local list = UIKit.List(actionFrame, 0.03, false, Enum.HorizontalAlignment.Right)
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom

	expandButton = UIKit.Button({
		Name = "Expand",
		Text = "EXPAND",
		Size = UDim2.fromScale(1, 0),
		Color = Palette.UIAccent,
		LayoutOrder = 1,
		Parent = actionFrame,
		OnClick = function()
			UIController.Open("Expansion")
		end,
	})
	UIKit.Aspect(expandButton, 2.6)

	collectFrame = UIKit.Create("Frame", {
		Name = "CollectVault",
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = actionFrame,
	})
	UIKit.Aspect(collectFrame, 1.7)
	collectButton = UIKit.Button({
		Name = "Collect",
		Text = "COLLECT",
		Size = UDim2.fromScale(1, 0.62),
		Color = Palette.UIGood,
		Parent = collectFrame,
		OnClick = function()
			NotificationController.Request("CollectVault")
		end,
	})
	collectBar = UIKit.ProgressBar(collectFrame, UDim2.fromScale(1, 0.3), Palette.Cash)
	collectBar.Root.Position = UDim2.fromScale(0, 0.68)
end

local function buildBottom(parent: Frame)
	supplyButton = UIKit.Button({
		Name = "SupplyDrop",
		Text = "🎁 SUPPLY DROP",
		Size = UDim2.fromScale(0.22, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.885),
		Color = Palette.UIAccent,
		Parent = parent,
		OnClick = function()
			NotificationController.Request("ClaimSupplyDrop")
		end,
	})
	UIKit.Aspect(supplyButton, 4)
	supplyButton.Visible = false

	updateLabel = UIKit.Label({
		Name = "NextUpdate",
		Size = UDim2.fromScale(0.3, 0.04),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.93),
		MaxTextSize = 16,
		Parent = parent,
	})
	updateLabel.TextTransparency = 0.25
end

local function buildEventStrip(parent: Frame)
	eventStrip = UIKit.Card(parent, UDim2.fromScale(0.46, 0), Color3.fromRGB(120, 40, 160))
	eventStrip.AnchorPoint = Vector2.new(0.5, 0)
	eventStrip.Visible = false
	UIKit.Aspect(eventStrip, 12)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(640, 60), Parent = eventStrip })
	eventLabel = UIKit.Label({
		Size = UDim2.fromScale(0.96, 0.8),
		Position = UDim2.fromScale(0.02, 0.1),
		MaxTextSize = 22,
		Parent = eventStrip,
	})
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------
local function updateCurrencies()
	local data = DataController.Get()
	if data == nil then
		return
	end
	topCells.Cash.Text = NumberFormat.Cash(data.Cash)
	topCells.Credits.Text = "💎 " .. NumberFormat.Short(data.Credits)
	local multiplier = Formulas.SharesMultiplier(data.Shares + data.BonusShares)
	topCells.Shares.Text = string.format("🏦 ×%.2f", multiplier)
end

local function updateIncome()
	local runtime = DataController.GetRuntime()
	local income = if runtime then runtime.Income else 0
	topCells.Income.Text = "⚡" .. NumberFormat.Cash(income or 0) .. "/s"
end

local function updateVault()
	local data = DataController.Get()
	if data == nil then
		return
	end
	local autoCollect = data.Passes.AutoCollect == true
	collectFrame.Visible = not autoCollect
	if autoCollect then
		return
	end
	local runtime = DataController.GetRuntime()
	local capacity = if runtime then runtime.VaultCapacity else 0
	local fraction = if capacity and capacity > 0 then data.Vault / capacity else 0
	collectBar.Set(fraction, NumberFormat.Cash(data.Vault))
	local full = fraction >= 0.98
	collectButton.BackgroundColor3 = if full then Palette.UIAccent else Palette.UIGood
	collectButton.Text = if full then "FULL! COLLECT" else "COLLECT"
	stopCollectPulse = setPulse(stopCollectPulse, full, collectButton)
end

local function updateExpand()
	local data = DataController.Get()
	if data == nil then
		return
	end
	local canExpand = Formulas.CanExpand(data.Expansions, data.RunEarnings)
	local canFranchise = data.Expansions >= Config.Expansion.MaxExpansions and Formulas.CanFranchise(data.Expansions)
	local maxed = data.Expansions >= Config.Expansion.MaxExpansions
	expandButton.Visible = not maxed or canFranchise
	if canFranchise then
		expandButton.Text = "FRANCHISE!"
	elseif canExpand then
		expandButton.Text = "EXPAND!"
	else
		local requirement = Formulas.ExpansionRequirement(data.Expansions + 1)
		expandButton.Text = "EXPAND " .. NumberFormat.Percent(math.min(1, data.RunEarnings / requirement))
	end
	expandButton.BackgroundColor3 = if canExpand or canFranchise then Palette.UIGood else Palette.UIPanel
	stopExpandPulse = setPulse(stopExpandPulse, canExpand or canFranchise, expandButton)
end

local function updateBadges()
	local data = DataController.Get()
	if data == nil then
		return
	end
	local contractReady = false
	for _, slot in data.Contracts.Slots do
		if slot.Tier ~= "" and (slot.Done or slot.Progress >= slot.Target) then
			contractReady = true
		end
	end
	navByName.Contracts.Badge.Visible = contractReady
	local questReady = false
	for _, list in { data.Quests.Daily, data.Quests.Weekly } do
		for _, quest in list do
			if not quest.Claimed and quest.Progress >= quest.Target then
				questReady = true
			end
		end
	end
	navByName.Quests.Badge.Visible = questReady
end

local function updateSupply()
	local data = DataController.Get()
	if data == nil then
		return
	end
	local stored = data.Supply.Stored
	supplyButton.Visible = stored >= 1
	supplyButton.Text = if stored > 1 then string.format("🎁 SUPPLY DROP x%d", stored) else "🎁 SUPPLY DROP"
end

local function secondsLeft(value: number): number
	return math.max(0, value - (os.clock() - eventsAt))
end

local function updateEvents()
	local events = DataController.GetEvents()
	if events == nil then
		eventStrip.Visible = false
		updateLabel.Text = ""
		return
	end
	local parts: { string } = {}
	if events.RushActive then
		table.insert(
			parts,
			string.format(
				"⚡ RUSH %s  contracts ×%s",
				NumberFormat.Duration(secondsLeft(events.RushSecondsLeft or 0)),
				NumberFormat.Short(Config.Events.RushOrders.ContractRewardMult)
			)
		)
	end
	if events.WeekendActive then
		table.insert(parts, string.format("🎉 WEEKEND cash ×%s", NumberFormat.Short(Config.Events.Weekend.CashMult)))
	end
	eventStrip.Visible = #parts > 0
	eventLabel.Text = table.concat(parts, "   ")
	local nextUpdate = events.NextUpdateUnix
	if type(nextUpdate) == "number" and nextUpdate > 0 then
		updateLabel.Text = "Next update in " .. NumberFormat.Duration(nextUpdate - DataController.ServerNow())
	else
		updateLabel.Text = ""
	end
end

local function updateChips()
	local data = DataController.Get()
	if data == nil then
		return
	end
	local now = DataController.ServerNow()
	local live: { { key: string, left: number } } = {}
	for key, expiry in data.Boosts do
		if type(expiry) == "number" and expiry > now then
			table.insert(live, { key = key, left = expiry - now })
		end
	end
	table.sort(live, function(a, b)
		return a.left < b.left
	end)
	local wanted: { [string]: boolean } = {}
	for index, boost in live do
		if index > MAX_CHIPS then
			break
		end
		wanted[boost.key] = true
		local chip = chips[boost.key]
		if chip == nil then
			local frame = UIKit.Card(chipsFrame, UDim2.fromScale(1, 0), Palette.UIPanel, index)
			UIKit.Aspect(frame, 4.5)
			local label = UIKit.Label({
				Size = UDim2.fromScale(0.94, 0.8),
				Position = UDim2.fromScale(0.03, 0.1),
				Color = Palette.UIAccent,
				MaxTextSize = 20,
				Parent = frame,
			})
			chip = { Frame = frame, Label = label }
			chips[boost.key] = chip
		end
		local def = Config.Boosts[boost.key]
		local chipRef = chip :: { Frame: Frame, Label: TextLabel }
		chipRef.Frame.LayoutOrder = index
		chipRef.Label.Text = `{if def then def.Name else boost.key} {NumberFormat.Duration(boost.left)}`
	end
	for key, chip in chips do
		if not wanted[key] then
			chip.Frame:Destroy()
			chips[key] = nil
		end
	end
end

local function refreshSlow()
	updateEvents()
	updateChips()
end

function HUDController.Start()
	local layer = UIController.GetLayer("HUD")
	root = UIKit.Create("Frame", {
		Name = "Hud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	maid:Add(root)
	buildTopBar(root)
	buildEventStrip(root)
	buildNav(root)
	buildRight(root)
	buildBottom(root)
	eventsAt = os.clock()
	layout()

	local camera = workspace.CurrentCamera
	if camera then
		maid:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
	end
	maid:Add(DataController.AdminChanged:Connect(layout))
	maid:Add(DataController.Changed:Connect(function(key: string)
		if key == "Cash" or key == "Credits" or key == "Shares" or key == "BonusShares" then
			updateCurrencies()
		end
		if key == "Vault" or key == "Passes" then
			updateVault()
		end
		if key == "RunEarnings" or key == "Expansions" then
			updateExpand()
		end
		if key == "Contracts" or key == "Quests" then
			updateBadges()
		end
		if key == "Supply" then
			updateSupply()
		end
		if key == "Boosts" then
			updateChips()
		end
	end))
	maid:Add(DataController.RuntimeChanged:Connect(function()
		updateIncome()
		updateVault()
	end))
	maid:Add(DataController.EventsChanged:Connect(function()
		eventsAt = os.clock()
		updateEvents()
	end))

	updateCurrencies()
	updateIncome()
	updateVault()
	updateExpand()
	updateBadges()
	updateSupply()
	refreshSlow()
	maid:Add(task.spawn(function()
		while true do
			task.wait(1)
			refreshSlow()
		end
	end))
end

return HUDController

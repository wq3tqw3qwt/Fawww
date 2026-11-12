--!strict
--[[
	ExpansionController: the "Expansion" panel (prestige preview + confirm, Franchise section) and the
	full-screen celebration for the Expansion / Franchise effects. The server decides everything;
	numbers here are previews computed with Formulas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ExpansionController = {}

local Palette = UIKit.Palette
local GREY = Color3.fromRGB(80, 84, 100)
local CELEBRATION_SECONDS = 4.5
local RESETS_TEXT = "Cash, lines and upgrades, vault, packaging, robot posts"
local STAYS_TEXT = "Shares, machines, credits, research, catalog, quests"

type Ratio = { Constraint: UIAspectRatioConstraint, Wide: number, Tall: number }

local maid = Maid.new()
local celebrationMaid = Maid.new()
local panel: UIKit.Panel? = nil
local ratios: { Ratio } = {}
local progressBar: UIKit.ProgressBar? = nil
local progressLabel: TextLabel? = nil
local sharesLabel: TextLabel? = nil
local nextLabel: TextLabel? = nil
local expandButton: TextButton? = nil
local franchiseCard: Frame? = nil
local franchiseLabel: TextLabel? = nil
local lastShares = 0
local prevShares = 0

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

local function newCard(body: Instance, order: number, wide: number, tall: number): Frame
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	table.insert(ratios, { Constraint = UIKit.Aspect(card, wide), Wide = wide, Tall = tall })
	applyRatios()
	return card
end

local function textBlock(parent: Instance, size: UDim2, position: UDim2, maxSize: number): TextLabel
	return UIKit.Label({
		Size = size,
		Position = position,
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = maxSize,
		Parent = parent,
	})
end

local function setText(label: any, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

-- Shares and income multiplier the next Expansion would give (server uses the same formulas).
local function preview(data: any): (number, number, number, number)
	local after = math.max(data.Shares, Formulas.SharesTotal(data.FranchiseEarnings))
	local multNow = Formulas.SharesMultiplier(data.Shares + data.BonusShares)
	local multAfter = Formulas.SharesMultiplier(after + data.BonusShares)
	return data.Shares, after, multNow, multAfter
end

local function nextUnlockText(expansions: number): string
	local lines: { string } = {}
	local upcoming = expansions + 1
	for _, hall in Config.Halls do
		if hall.UnlockExpansions == upcoming then
			table.insert(lines, `<font color="#5ae66e">Next Expansion builds the {hall.Name} floor!</font>`)
		end
	end
	if table.find(Config.Robots.BonusAtExpansions, upcoming) then
		table.insert(lines, "+1 Robot worker")
	end
	if table.find(Config.Expansion.BaysAtExpansions, upcoming) then
		table.insert(lines, "+1 machine bay")
	end
	if #lines == 0 then
		local nextHall: Config.HallDef? = nil
		for _, hall in Config.Halls do
			if
				hall.UnlockExpansions > expansions
				and (nextHall == nil or hall.UnlockExpansions < nextHall.UnlockExpansions)
			then
				nextHall = hall
			end
		end
		if nextHall then
			table.insert(lines, `{nextHall.Name} floor unlocks at Expansion {nextHall.UnlockExpansions}`)
		else
			table.insert(lines, "All floors built - Franchise to keep growing")
		end
	end
	return table.concat(lines, "\n")
end

local function refresh()
	local data: any = DataController.Get()
	if data == nil then
		return
	end
	local expansions: number = data.Expansions
	local maxed = expansions >= Config.Expansion.MaxExpansions
	local requirement = Formulas.ExpansionRequirement(expansions + 1)
	local run: number = data.RunEarnings
	if progressBar then
		progressBar.Set(
			if maxed then 1 else run / requirement,
			if maxed then "MAX EXPANSIONS" else `{NumberFormat.Cash(run)} / {NumberFormat.Cash(requirement)}`
		)
	end
	setText(progressLabel, `Expansion {expansions + 1} · this run`)
	local sharesNow, sharesAfter, multNow, multAfter = preview(data)
	setText(
		sharesLabel,
		string.format(
			'Shares  <b>%s</b> → <font color="#5ae66e">%s</font>  (+%s)\nIncome  ×%.2f → <font color="#5ae66e">×%.2f</font>',
			NumberFormat.Short(sharesNow),
			NumberFormat.Short(sharesAfter),
			NumberFormat.Short(sharesAfter - sharesNow),
			multNow,
			multAfter
		)
	)
	setText(nextLabel, nextUnlockText(expansions))
	local button = expandButton
	if button then
		local can = Formulas.CanExpand(expansions, run)
		setText(button, if maxed then "MAX - FRANCHISE" elseif can then "EXPAND NOW" else "NOT YET")
		button.BackgroundColor3 = if can then Palette.UIGood else GREY
	end
	local card = franchiseCard
	if card then
		local can = Formulas.CanFranchise(expansions)
		card.Visible = can
		if can then
			local level: number = data.Franchise + 1
			setText(
				franchiseLabel,
				string.format(
					"<b>FRANCHISE %d</b>\nPermanent income ×%s, +%d Credits.\nExpansions and Shares restart.",
					level,
					NumberFormat.Short(Formulas.FranchiseMultiplier(level)),
					Config.Franchise.CreditsPerLevel * level
				)
			)
		end
	end
end

local function confirmExpand()
	local data: any = DataController.Get()
	if data == nil then
		return
	end
	if not Formulas.CanExpand(data.Expansions, data.RunEarnings) then
		NotificationController.Toast("Info", "Earn more this run first")
		return
	end
	local _, after, _, multAfter = preview(data)
	UIController.Confirm(
		string.format(
			"Expand now?\nYour run restarts. Shares → %s (×%.2f income).",
			NumberFormat.Short(after),
			multAfter
		),
		function()
			task.spawn(NotificationController.Request, "Expand")
		end,
		"EXPAND"
	)
end

local function confirmFranchise()
	local data: any = DataController.Get()
	if data == nil or not Formulas.CanFranchise(data.Expansions) then
		return
	end
	local level: number = data.Franchise + 1
	UIController.Confirm(
		string.format(
			"Franchise %d?\nExpansions and Shares restart. Income ×%s forever.",
			level,
			NumberFormat.Short(Formulas.FranchiseMultiplier(level))
		),
		function()
			task.spawn(NotificationController.Request, "Franchise")
		end,
		"FRANCHISE"
	)
end

local function buildPanel()
	local created = UIKit.Panel("Expansion", "Expansion", UIController.GetLayer("Panels"), Color3.fromRGB(255, 220, 90))
	panel = created
	maid:Add(created.Root)
	UIKit.List(created.Body, 0.015)
	UIKit.Padding(created.Body, 0.01)
	local body = created.Body

	local progress = newCard(body, 1, 4, 2.2)
	progressLabel = UIKit.Label({
		Size = UDim2.fromScale(0.94, 0.34),
		Position = UDim2.fromScale(0.03, 0.08),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = progress,
	})
	local bar = UIKit.ProgressBar(progress, UDim2.fromScale(0.94, 0.38), Palette.Cash)
	bar.Root.Position = UDim2.fromScale(0.03, 0.5)
	progressBar = bar

	local shares = newCard(body, 2, 3.4, 2)
	sharesLabel = textBlock(shares, UDim2.fromScale(0.94, 0.84), UDim2.fromScale(0.03, 0.08), 24)

	local resets = newCard(body, 3, 2.4, 1.3)
	textBlock(resets, UDim2.fromScale(0.94, 0.88), UDim2.fromScale(0.03, 0.06), 20).Text =
		`<font color="#ff6a6a"><b>Resets:</b></font> {RESETS_TEXT}\n<font color="#5ae66e"><b>Stays:</b></font> {STAYS_TEXT}`

	local nextCard = newCard(body, 4, 4.4, 2.4)
	nextLabel = textBlock(nextCard, UDim2.fromScale(0.94, 0.8), UDim2.fromScale(0.03, 0.1), 22)

	local expandCard = newCard(body, 5, 3.4, 2.2)
	expandButton = UIKit.Button({
		Name = "ExpandNow",
		Text = "EXPAND NOW",
		Size = UDim2.fromScale(0.94, 0.78),
		Position = UDim2.fromScale(0.03, 0.11),
		MaxTextSize = 44,
		Parent = expandCard,
		OnClick = confirmExpand,
	})

	local franchise = newCard(body, 6, 2.6, 1.5)
	franchise.BackgroundColor3 = Color3.fromRGB(70, 36, 80)
	franchiseCard = franchise
	franchiseLabel = textBlock(franchise, UDim2.fromScale(0.6, 0.84), UDim2.fromScale(0.03, 0.08), 20)
	UIKit.Button({
		Name = "FranchiseNow",
		Text = "FRANCHISE",
		Size = UDim2.fromScale(0.32, 0.6),
		Position = UDim2.fromScale(0.65, 0.2),
		Color = Config.Visuals.Effects.FranchiseColor,
		Parent = franchise,
		OnClick = confirmFranchise,
	})

	UIController.RegisterPanel("Expansion", {
		Root = created.Root,
		OnOpen = refresh,
	})
end

--------------------------------------------------------------------------------
-- Celebration
--------------------------------------------------------------------------------
local function celebrate(color: Color3, title: string, sub: string, footer: string)
	celebrationMaid:Clean()
	local overlay = UIController.GetLayer("Overlay")
	local root = UIKit.Create("Frame", {
		Name = "Celebration",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	celebrationMaid:Add(root)
	local flash = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6),
		BackgroundTransparency = 0.1,
		Parent = root,
	})
	UIKit.Tween(flash, { BackgroundTransparency = 1 }, 1.2)

	local box = UIKit.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.9, 0),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.Aspect(box, 3)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(980, 330), Parent = box })
	UIKit.Label({
		Text = title,
		Color = color,
		Size = UDim2.fromScale(1, 0.46),
		MaxTextSize = 80,
		Parent = box,
	})
	UIKit.Label({
		Text = sub,
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.48),
		MaxTextSize = 44,
		Parent = box,
	})
	UIKit.Label({
		Text = footer,
		Size = UDim2.fromScale(1, 0.2),
		Position = UDim2.fromScale(0, 0.8),
		Color = Palette.UIGood,
		MaxTextSize = 30,
		Parent = box,
	})
	UIKit.Pop(box, 0.25)
	celebrationMaid:Add(task.delay(CELEBRATION_SECONDS, function()
		celebrationMaid:Clean()
	end))
end

local function onEffect(kind: any, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if kind == "Expansion" then
		UIController.Close("Expansion")
		local count: number = payload.Count or 0
		local shares: number = payload.Shares or 0
		local before = if lastShares == shares then prevShares else lastShares
		local footer = "Your factory restarts - bigger and stronger"
		for _, hall in Config.Halls do
			if hall.UnlockExpansions == count and count > 0 then
				footer = `{hall.Name} building rises!`
			end
		end
		celebrate(
			Config.Visuals.Effects.ExpansionColor,
			`EXPANSION {count}!`,
			string.format(
				"SHARES +%s → ×%.2f income",
				NumberFormat.Short(math.max(0, shares - before)),
				payload.Mult or 1
			),
			footer
		)
	elseif kind == "Franchise" then
		UIController.Close("Expansion")
		local level: number = payload.Level or 1
		celebrate(
			Config.Visuals.Effects.FranchiseColor,
			`FRANCHISE {level}!`,
			string.format("Permanent income ×%s", NumberFormat.Short(Formulas.FranchiseMultiplier(level))),
			`+{Config.Franchise.CreditsPerLevel * level} Credits`
		)
	end
end

function ExpansionController.Init()
	maid:Add(Net.Event("Effect").OnClientEvent:Connect(onEffect))
end

function ExpansionController.Start()
	buildPanel()
	maid:Add(DataController.OnKey("Shares", function(value: any)
		if type(value) == "number" and value ~= lastShares then
			prevShares = lastShares
			lastShares = value
		end
	end))
	maid:Add(DataController.Changed:Connect(function(key: string)
		local current = panel
		if current and current.Root.Visible then
			if
				key == "RunEarnings"
				or key == "Shares"
				or key == "BonusShares"
				or key == "Expansions"
				or key == "Franchise"
			then
				refresh()
			end
		end
	end))
	local camera = workspace.CurrentCamera
	if camera then
		maid:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyRatios))
	end
end

return ExpansionController

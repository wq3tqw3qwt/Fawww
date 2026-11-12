--!strict
--[[
	QuestsController: the "Quests" panel. Daily and Weekly quests, the 7-day Daily Reward strip with
	streak/shields/milestones, the Supply Drop and the Community Goal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ContractOdds = require(ReplicatedStorage.Shared.ContractOdds)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Types = require(ReplicatedStorage.Shared.Types)

local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local QuestsController = {}

local PANEL = "Quests"
local TABS = { "Daily", "Weekly", "Daily Reward", "Supply Drop", "Community Goal" }
local SECONDS_PER_DAY = 86400
local RENDER_DEBOUNCE = 0.4
local STRIP_CELL = 0.235

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Daily"
local timers: { () -> () } = {}
local tickToken = 0
local renderQueued = false
local lastQuestSignature = ""
local choiceId: string? = nil

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

local function heading(parent: Instance, order: number, text: string, color: Color3?): TextLabel
	local label = UIKit.Label({
		Text = text,
		Size = UDim2.fromScale(1, 0),
		Alignment = Enum.TextXAlignment.Left,
		Color = color,
		MaxTextSize = 28,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Aspect(label, 12)
	return label
end

local function note(parent: Instance, order: number, text: string, color: Color3?, ratio: number?): TextLabel
	local label = UIKit.Label({
		Text = text,
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(1, 0),
		Color = color or Color3.fromRGB(215, 218, 230),
		MaxTextSize = 18,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Aspect(label, ratio or 9)
	return label
end

local function wrapGrid(parent: Instance, order: number): Frame
	local frame = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Wraps = true,
		Padding = UDim.new(0.012, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = frame,
	})
	return frame
end

local function bigButton(parent: Instance, order: number, text: string, color: Color3, onClick: () -> ()): TextButton
	local button = UIKit.Button({
		Text = text,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = order,
		Color = color,
		Parent = parent,
		OnClick = onClick,
	})
	UIKit.Aspect(button, 7)
	return button
end

-- Seconds until the next UTC midnight / Monday 00:00 UTC (quest rollovers).
local function secondsToDayReset(): number
	return SECONDS_PER_DAY - (math.floor(serverNow()) % SECONDS_PER_DAY)
end

local function secondsToWeekReset(): number
	local t = os.date("!*t", math.floor(serverNow()))
	local days = (9 - t.wday) % 7
	if days == 0 then
		days = 7
	end
	return days * SECONDS_PER_DAY - (t.hour * 3600 + t.min * 60 + t.sec)
end

--------------------------------------------------------------------------------
-- Daily / Weekly quests
--------------------------------------------------------------------------------
local function questDef(pool: { Config.QuestDef }, id: string): Config.QuestDef?
	for _, def in pool do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function amountText(def: Config.QuestDef, value: number): string
	if def.Kind == "OperateSeconds" then
		return NumberFormat.Short(math.floor(value / 60))
	end
	return NumberFormat.Short(value)
end

local function questSignature(data: Types.PlayerData): string
	local parts = {}
	for _, list in { data.Quests.Daily, data.Quests.Weekly } do
		for _, quest in list do
			table.insert(parts, quest.Id .. ":" .. tostring(quest.Claimed) .. ":" .. quest.Target)
		end
	end
	return table.concat(parts, "|") .. tostring(data.Quests.DailyBonusClaimed) .. data.Quests.WeekKey
end

local function renderQuests(body: Instance, kind: string, data: Types.PlayerData)
	local list: { Types.QuestState } = if kind == "Daily" then data.Quests.Daily else data.Quests.Weekly
	local pool = if kind == "Daily" then Config.Quests.Daily else Config.Quests.Weekly
	local order = 1
	local resetLabel = note(body, order, "", palette.UIAccent, 12)
	table.insert(timers, function()
		local left = if kind == "Daily" then secondsToDayReset() else secondsToWeekReset()
		resetLabel.Text = "New " .. string.lower(kind) .. " quests in " .. NumberFormat.Duration(left)
	end)

	for index, quest in list do
		order += 1
		local def = questDef(pool, quest.Id)
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 3.6)
		UIKit.Label({
			Text = if def then string.format(def.Text, amountText(def, quest.Target)) else quest.Id,
			Size = UDim2.fromScale(0.6, 0.34),
			Position = UDim2.fromScale(0.03, 0.06),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 24,
			Parent = card,
		})
		local bar = UIKit.ProgressBar(card, UDim2.fromScale(0.6, 0.24), palette.UIGood)
		bar.Root.Position = UDim2.fromScale(0.03, 0.46)
		UIKit.Label({
			Text = "+" .. (if def then def.Credits else 0) .. " Credits",
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.6, 0.2),
			Position = UDim2.fromScale(0.03, 0.74),
			Alignment = Enum.TextXAlignment.Left,
			Color = palette.Credits,
			MaxTextSize = 16,
			Parent = card,
		})
		local button = UIKit.Button({
			Text = "Claim",
			Size = UDim2.fromScale(0.34, 0.6),
			Position = UDim2.fromScale(0.63, 0.2),
			Color = palette.UIPanel,
			Parent = card,
			OnClick = function()
				local latest = DataController.Get()
				local current = if latest
					then (if kind == "Daily" then latest.Quests.Daily else latest.Quests.Weekly)[index]
					else nil
				if not current or current.Claimed or current.Progress < current.Target then
					NotificationController.Toast("Info", "Not finished yet.")
					return
				end
				local res = NotificationController.Request("ClaimQuest", kind, index)
				if res.Ok then
					NotificationController.Toast("Reward", "Quest complete!")
					SoundController.Play("Coins")
				end
			end,
		})
		table.insert(timers, function()
			local latest = DataController.Get()
			local current = if latest
				then (if kind == "Daily" then latest.Quests.Daily else latest.Quests.Weekly)[index]
				else nil
			if not current then
				return
			end
			local shown = math.min(current.Progress, current.Target)
			bar.Set(
				shown / math.max(1, current.Target),
				(if def then amountText(def, shown) else NumberFormat.Short(shown))
					.. " / "
					.. (if def then amountText(def, current.Target) else NumberFormat.Short(current.Target))
			)
			if current.Claimed then
				button.Text = "Claimed"
				button.BackgroundColor3 = palette.UIPanel
			else
				button.Text = "Claim"
				button.BackgroundColor3 = if current.Progress >= current.Target then palette.UIGood else palette.UIPanel
			end
		end)
	end

	order += 1
	if kind == "Daily" then
		local allClaimed = #list > 0
		for _, quest in list do
			allClaimed = allClaimed and quest.Claimed
		end
		local claimed = data.Quests.DailyBonusClaimed
		bigButton(
			body,
			order,
			if claimed
				then "All-quests bonus claimed"
				else string.format(
					"All %d done bonus: +%d Credits",
					Config.Quests.DailyCount,
					Config.Quests.AllDailyBonusCredits
				),
			if allClaimed and not claimed then palette.UIGood else palette.UIPanel,
			function()
				if claimed or not allClaimed then
					NotificationController.Toast("Info", "Claim every daily quest first.")
					return
				end
				local res = NotificationController.Request("ClaimDailyQuestBonus")
				if res.Ok then
					SoundController.Play("Fanfare")
				end
			end
		)
	else
		local boost = Config.Boosts[Config.Quests.WeeklyBoostKey]
		note(
			body,
			order,
			string.format(
				"Each weekly claim also grants %s for %d minutes.",
				if boost then boost.Name else Config.Quests.WeeklyBoostKey,
				Config.Quests.WeeklyBoostMinutes
			),
			palette.UIGood
		)
	end
end

--------------------------------------------------------------------------------
-- Daily Reward
--------------------------------------------------------------------------------
local function rewardText(reward: Config.DailyRewardDef): string
	if reward.Kind == "IncomeMinutes" then
		return NumberFormat.Duration(reward.Amount * 60) .. " of income"
	elseif reward.Kind == "Credits" then
		return NumberFormat.Commas(reward.Amount) .. " Credits"
	elseif reward.Kind == "Boost" and reward.BoostKey then
		local boost = Config.Boosts[reward.BoostKey]
		return string.format("%s %d min", if boost then boost.Name else reward.BoostKey, reward.Amount)
	elseif reward.Kind == "MachineChoice" then
		return string.format("%s machine + %d Credits", reward.Rarity or "Rare", reward.Amount)
	end
	return reward.Kind
end

-- Mirrors the server's streak resolution (display only): returns streak after grace/shields and shields burnt.
local function projectedStreak(data: Types.PlayerData): (number, number)
	local cfg = Config.DailyRewards
	local daily = data.Daily
	if daily.LastClaimUnix == 0 then
		return 0, 0
	end
	local gap = serverNow() - daily.LastClaimUnix
	local grace = cfg.StreakGraceHours * 3600
	if gap <= grace then
		return daily.Streak, 0
	end
	local missed = math.ceil((gap - grace) / (cfg.ClaimCooldownHours * 3600))
	if daily.Shields >= missed then
		return daily.Streak, missed
	end
	return 0, 0
end

local function choiceOptions(data: Types.PlayerData, rarity: string): { Config.MachineDef }
	local options = {}
	for _, def in Config.Machines do
		if
			def.Rarity == rarity
			and def.Hall >= 1
			and Formulas.HallUnlocked(def.Hall, data.Expansions)
			and table.find(ContractOdds.BlueprintPool(rarity, def.Hall), def.Id)
		then
			table.insert(options, def)
		end
	end
	return options
end

local function renderDailyReward(body: Instance, data: Types.PlayerData)
	local cfg = Config.DailyRewards
	local daily = data.Daily
	local streak, shieldsUsed = projectedStreak(data)
	local cycle = #cfg.Cycle
	local nextDay = (streak % cycle) + 1
	local order = 1

	local grid = wrapGrid(body, order)
	for day, reward in cfg.Cycle do
		local done = day < nextDay and streak > 0
		local current = day == nextDay
		local card = UIKit.Card(
			grid,
			UDim2.fromScale(STRIP_CELL, 0),
			if current then palette.UIAccent:Lerp(Color3.new(0, 0, 0), 0.4) else nil,
			day
		)
		UIKit.Aspect(card, 1.1)
		if current then
			UIKit.Stroke(card, palette.UIAccent, 3)
		end
		UIKit.Label({
			Text = (if done then "✔ " else "") .. "Day " .. day,
			Size = UDim2.fromScale(0.94, 0.28),
			Position = UDim2.fromScale(0.03, 0.04),
			Color = if done then palette.UIGood else palette.UIText,
			MaxTextSize = 20,
			Parent = card,
		})
		UIKit.Label({
			Text = rewardText(reward),
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.94, 0.6),
			Position = UDim2.fromScale(0.03, 0.34),
			MaxTextSize = 15,
			Parent = card,
		})
	end
	order += 1

	local info = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(info, 4)
	UIKit.Label({
		Text = string.format("Streak: %d day(s)   •   Shields: %d/%d", streak, daily.Shields, cfg.MaxShields),
		Size = UDim2.fromScale(0.94, 0.3),
		Position = UDim2.fromScale(0.03, 0.05),
		MaxTextSize = 24,
		Parent = info,
	})
	local lines = {}
	for _, milestone in cfg.Milestones do
		local def = Formulas.GetMachine(milestone.MachineId)
		local got = daily.Milestones[tostring(milestone.Day)] == true
		table.insert(
			lines,
			string.format(
				"%s Day %d: %s%s",
				if got then "✔" else "•",
				milestone.Day,
				if def then def.Name else milestone.MachineId,
				if milestone.Title then " + title " .. milestone.Title else ""
			)
		)
	end
	table.insert(
		lines,
		string.format(
			"A free shield arrives weekly (max %d). A shield saves your streak if you miss a day.",
			cfg.MaxShields
		)
	)
	if shieldsUsed > 0 then
		table.insert(lines, string.format("Claiming now uses %d shield(s) to keep your streak.", shieldsUsed))
	elseif daily.Streak > 0 and streak == 0 then
		table.insert(lines, "Your streak ran out. Claim to start a new one.")
	end
	UIKit.Label({
		Text = table.concat(lines, "\n"),
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.58),
		Position = UDim2.fromScale(0.03, 0.36),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		Parent = info,
	})
	order += 1

	local reward = cfg.Cycle[nextDay]
	local needsChoice = reward.Kind == "MachineChoice"
	if needsChoice then
		local options = choiceOptions(data, reward.Rarity or "Rare")
		local valid = false
		for _, def in options do
			valid = valid or def.Id == choiceId
		end
		if not valid then
			choiceId = if options[1] then options[1].Id else nil
		end
		heading(body, order, "Pick your " .. (reward.Rarity or "Rare") .. " machine")
		order += 1
		local picker = wrapGrid(body, order)
		for i, def in options do
			local on = def.Id == choiceId
			local button = UIKit.Button({
				Text = def.Name .. "\n+" .. NumberFormat.Short(def.Power) .. "%",
				Size = UDim2.fromScale(STRIP_CELL, 0),
				LayoutOrder = i,
				Color = if on then palette.UIAccent else palette.UIPanel,
				TextColor = if on then Color3.new(0, 0, 0) else palette.UIText,
				MaxTextSize = 16,
				Parent = picker,
				OnClick = function()
					choiceId = def.Id
					QuestsController.Render()
				end,
			})
			UIKit.Aspect(button, 1.3)
		end
		order += 1
	end

	local claim = bigButton(body, order, "", palette.UIGood, function()
		local res = NotificationController.Request("ClaimDaily", if needsChoice then choiceId else nil)
		if res.Ok then
			NotificationController.Toast("Reward", "Daily reward claimed: " .. rewardText(reward))
			SoundController.Play("Fanfare")
		end
	end)
	table.insert(timers, function()
		local latest = DataController.Get()
		if not latest then
			return
		end
		local readyAt = latest.Daily.LastClaimUnix + cfg.ClaimCooldownHours * 3600
		local left = readyAt - serverNow()
		if latest.Daily.LastClaimUnix > 0 and left > 0 then
			claim.Text = "Next reward in " .. NumberFormat.Duration(left)
			claim.BackgroundColor3 = palette.UIPanel
		else
			claim.Text = "Claim day " .. nextDay
			claim.BackgroundColor3 = palette.UIGood
		end
	end)
end

--------------------------------------------------------------------------------
-- Supply Drop
--------------------------------------------------------------------------------
local function renderSupply(body: Instance)
	local drop = Config.SupplyDrop
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, 1)
	UIKit.Aspect(card, 2.6)
	UIKit.Label({
		Text = "Supply Drop",
		Size = UDim2.fromScale(0.94, 0.18),
		Position = UDim2.fromScale(0.03, 0.05),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
		Parent = card,
	})
	UIKit.Label({
		Text = string.format(
			"Every %s: %s of income + %d Credits. Stores up to %d.",
			NumberFormat.Duration(drop.IntervalSeconds),
			NumberFormat.Duration(drop.IncomeMinutes * 60),
			drop.Credits,
			drop.MaxStored
		),
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.2),
		Position = UDim2.fromScale(0.03, 0.25),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Parent = card,
	})
	local status = UIKit.Label({
		Text = "",
		Size = UDim2.fromScale(0.94, 0.2),
		Position = UDim2.fromScale(0.03, 0.48),
		Alignment = Enum.TextXAlignment.Left,
		Color = palette.UIAccent,
		MaxTextSize = 24,
		Parent = card,
	})
	local claim = UIKit.Button({
		Text = "Claim",
		Size = UDim2.fromScale(0.9, 0.22),
		Position = UDim2.fromScale(0.05, 0.73),
		Color = palette.UIPanel,
		Parent = card,
		OnClick = function()
			local res = NotificationController.Request("ClaimSupplyDrop")
			if res.Ok then
				local reward = res.Data
				local text = "Supply drop opened!"
				if type(reward) == "table" and type(reward.Cash) == "number" then
					text = string.format(
						"Supply drop: %s + %d Credits",
						NumberFormat.Cash(reward.Cash),
						reward.Credits or 0
					)
				end
				NotificationController.Toast("Reward", text)
				SoundController.Play("Coins")
			end
		end,
	})
	table.insert(timers, function()
		local latest = DataController.Get()
		if not latest then
			return
		end
		local supply = latest.Supply
		local now = serverNow()
		local stored = supply.Stored
		local nextAt = 0
		if supply.LastGrantUnix > 0 and stored < drop.MaxStored then
			local intervals = math.floor((now - supply.LastGrantUnix) / drop.IntervalSeconds)
			stored = math.min(drop.MaxStored, stored + intervals)
			nextAt = supply.LastGrantUnix + (intervals + 1) * drop.IntervalSeconds
		end
		local text = string.format("Stored: %d / %d", stored, drop.MaxStored)
		if stored >= drop.MaxStored then
			text ..= "  (full, claim to restart the timer)"
		elseif nextAt > 0 then
			text ..= "  •  next in " .. NumberFormat.Duration(nextAt - now)
		end
		status.Text = text
		claim.BackgroundColor3 = if stored >= 1 then palette.UIGood else palette.UIPanel
	end)
end

--------------------------------------------------------------------------------
-- Community Goal
--------------------------------------------------------------------------------
local function goalRewardText(index: number): string
	local reward = Config.Events.GlobalGoal.Rewards[index]
	if not reward then
		return ""
	end
	local parts = {}
	if reward.Credits then
		table.insert(parts, reward.Credits .. " Credits")
	end
	if reward.BoostKey and reward.Minutes then
		local boost = Config.Boosts[reward.BoostKey]
		table.insert(
			parts,
			(if boost then boost.Name else reward.BoostKey) .. " " .. NumberFormat.Duration(reward.Minutes * 60)
		)
	end
	if reward.MythicOfWeek then
		table.insert(parts, "the Mythic machine of the week")
	end
	return table.concat(parts, " + ")
end

local function renderGoal(body: Instance, data: Types.PlayerData)
	local goalCfg = Config.Events.GlobalGoal
	local events = DataController.GetEvents()
	local goal = if events then events.GlobalGoal else nil
	local order = 1
	if not goal then
		note(body, order, "Community goal data is loading…")
		return
	end
	local total: number = goal.Total or 0
	local tiers: { number } = goal.Tiers or goalCfg.Tiers
	local sameWeek = data.GlobalGoal.WeekKey == goal.WeekKey
	local personal = if sameWeek then data.GlobalGoal.Contracts else 0
	local claimedTier = if sameWeek then data.GlobalGoal.ClaimedTier else 0

	heading(body, order, "Everyone completes contracts together", palette.UIAccent)
	order += 1
	local bar = UIKit.ProgressBar(body, UDim2.fromScale(1, 0), palette.UIGood, order)
	UIKit.Aspect(bar.Root, 10)
	bar.Set(
		total / math.max(1, tiers[#tiers] or 1),
		string.format(
			"%s / %s contracts this week",
			NumberFormat.Commas(total),
			NumberFormat.Commas(tiers[#tiers] or 0)
		)
	)

	for i, tier in tiers do
		order += 1
		local reached = total >= tier
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 6)
		UIKit.Label({
			Text = string.format(
				"%s %s contracts",
				if i <= claimedTier then "✔" elseif reached then "★" else "•",
				NumberFormat.Commas(tier)
			),
			Size = UDim2.fromScale(0.94, 0.45),
			Position = UDim2.fromScale(0.03, 0.06),
			Alignment = Enum.TextXAlignment.Left,
			Color = if reached then palette.UIGood else palette.UIText,
			MaxTextSize = 24,
			Parent = card,
		})
		UIKit.Label({
			Text = "Reward: " .. goalRewardText(i),
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.94, 0.38),
			Position = UDim2.fromScale(0.03, 0.55),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 17,
			Parent = card,
		})
	end

	order += 1
	note(
		body,
		order,
		string.format(
			"Your contracts this week: %d / %d needed to claim rewards.",
			personal,
			goalCfg.MinPersonalContracts
		),
		if personal >= goalCfg.MinPersonalContracts then palette.UIGood else palette.UIAccent
	)
	order += 1
	local nextTier = tiers[claimedTier + 1]
	local claimable = nextTier ~= nil and total >= nextTier and personal >= goalCfg.MinPersonalContracts
	bigButton(body, order, "Claim rewards", if claimable then palette.UIGood else palette.UIPanel, function()
		if not claimable then
			NotificationController.Toast("Info", "Reach the next tier and finish your personal contracts to claim.")
			return
		end
		local res = NotificationController.Request("ClaimGlobalGoal")
		if res.Ok then
			NotificationController.Toast("Reward", "Community rewards claimed!")
			SoundController.Play("Fanfare")
		end
	end)
	order += 1
	local reset = note(body, order, "", nil, 12)
	table.insert(timers, function()
		reset.Text = "Resets in " .. NumberFormat.Duration(secondsToWeekReset())
	end)
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------
function QuestsController.Render()
	tickToken += 1
	timers = {}
	clear(panel.Body)
	local data = DataController.Get()
	if not data then
		return
	end
	lastQuestSignature = questSignature(data)
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then palette.UIAccent else palette.UIPanel
	end
	if currentTab == "Daily" or currentTab == "Weekly" then
		renderQuests(panel.Body, currentTab, data)
	elseif currentTab == "Daily Reward" then
		renderDailyReward(panel.Body, data)
	elseif currentTab == "Supply Drop" then
		renderSupply(panel.Body)
	else
		renderGoal(panel.Body, data)
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

local function scheduleRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.delay(RENDER_DEBOUNCE, function()
		renderQueued = false
		if UIController.IsOpen(PANEL) then
			QuestsController.Render()
		end
	end)
end

function QuestsController.Init()
	panel = UIKit.Panel(PANEL, "Quests & Rewards", UIController.GetLayer("Panels"), palette.UIGood)

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
			MaxTextSize = 18,
			Parent = bar,
			OnClick = function()
				currentTab = name
				QuestsController.Render()
			end,
		})
	end
	panel.Body.Size = UDim2.fromScale(0.96, 0.75)
	panel.Body.Position = UDim2.fromScale(0.02, 0.23)
	UIKit.List(panel.Body, 0.02)

	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = QuestsController.Render,
		OnClose = function()
			tickToken += 1
		end,
	})
end

function QuestsController.Start()
	DataController.WaitForData()
	-- Quest progress ticks constantly; the timers repaint bars, so only structural changes rebuild.
	maid:Add(DataController.OnKey("Quests", function()
		local data = DataController.Get()
		if data and UIController.IsOpen(PANEL) and questSignature(data) ~= lastQuestSignature then
			scheduleRender()
		end
	end))
	for _, key in { "Daily", "Supply", "GlobalGoal", "Expansions" } do
		maid:Add(DataController.OnKey(key, function()
			if UIController.IsOpen(PANEL) then
				scheduleRender()
			end
		end))
	end
	maid:Add(DataController.EventsChanged:Connect(function()
		if UIController.IsOpen(PANEL) and currentTab == "Community Goal" then
			scheduleRender()
		end
	end))
end

return QuestsController

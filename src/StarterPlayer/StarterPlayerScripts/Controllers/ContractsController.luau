--!strict
--[[
	ContractsController: the "Contracts" panel. Slots with progress and reward previews, odds
	disclosure (blueprints are free rewards, never sold), Rush Orders, Mega Contracts and Extend.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ContractOdds = require(ReplicatedStorage.Shared.ContractOdds)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Types = require(ReplicatedStorage.Shared.Types)

local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ContractsController = {}

local PANEL = "Contracts"
-- Display-only tier tints (no matching Config entry exists yet).
local TIER_COLORS: { [string]: Color3 } = {
	Bronze = Color3.fromRGB(205, 127, 50),
	Silver = Color3.fromRGB(196, 202, 212),
	Gold = Color3.fromRGB(255, 200, 40),
}

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local timers: { () -> () } = {}
local tickToken = 0
local lastSignature = ""
local oddsTier: string? = nil
local megaState: any = nil
local megaOffer: any = nil
local rushEndsAt = 0

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

local function ordinal(n: number): string
	local last, lastTwo = n % 10, n % 100
	local suffix = "th"
	if lastTwo < 11 or lastTwo > 13 then
		suffix = if last == 1 then "st" elseif last == 2 then "nd" elseif last == 3 then "rd" else "th"
	end
	return n .. suffix
end

local function tierColor(tier: string): Color3
	return TIER_COLORS[tier] or palette.UIAccent
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

local function researchBonus(data: Types.PlayerData): number
	local total = 0
	for _, def in Config.Research do
		if def.Effect == "ContractReward" then
			total += (data.Research.Levels[def.Id] or 0) * def.ValuePerLevel
		end
	end
	return total
end

local function rewardPreview(data: Types.PlayerData, index: number, slot: Types.ContractSlot): (number, number)
	local tutorial = Config.Contracts.Tutorial
	if
		index == 1
		and not data.Contracts.TutorialDone
		and not data.Tutorial.Done
		and slot.Line == tutorial.Line
		and slot.Target == tutorial.Target
	then
		return tutorial.RewardCash, tutorial.RewardCredits
	end
	local tier = Config.Contracts.Tiers[slot.Tier]
	if not tier then
		return 0, 0
	end
	local runtime = DataController.GetRuntime()
	local events = DataController.GetEvents()
	local income = if runtime then runtime.Income else 0
	local abilities = if runtime and runtime.Abilities then runtime.Abilities else {}
	local cash = Formulas.ContractCashReward(
		income,
		tier,
		abilities.ContractPro or 0,
		researchBonus(data),
		events ~= nil and events.RushActive == true
	)
	return cash, tier.Credits
end

local function signature(data: Types.PlayerData): string
	local parts = {}
	for _, slot in data.Contracts.Slots do
		table.insert(
			parts,
			string.format("%s:%d:%d:%s:%d", slot.Tier, slot.Line, slot.Target, tostring(slot.Done), slot.EndsAt)
		)
	end
	return table.concat(parts, "|") .. "#" .. data.Contracts.NextRefillAt
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------
local function renderRush(body: Instance, order: number)
	local events = DataController.GetEvents()
	if not (events and events.RushActive) then
		return
	end
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), palette.UIAccent:Lerp(Color3.new(0, 0, 0), 0.55), order)
	UIKit.Aspect(card, 8)
	UIKit.Stroke(card, palette.UIAccent, 3)
	local label = UIKit.Label({
		Text = "",
		Size = UDim2.fromScale(0.94, 0.7),
		Position = UDim2.fromScale(0.03, 0.15),
		MaxTextSize = 26,
		Parent = card,
	})
	table.insert(timers, function()
		label.Text = string.format(
			"RUSH ORDERS! Contract rewards x%d  •  %s left",
			Config.Events.RushOrders.ContractRewardMult,
			NumberFormat.Duration(rushEndsAt - os.clock())
		)
	end)
end

local function renderSlots(body: Instance, order: number, data: Types.PlayerData): number
	for index, slot in data.Contracts.Slots do
		order += 1
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 3.3)
		if slot.Tier == "" then
			UIKit.Label({
				Text = "Empty slot",
				Size = UDim2.fromScale(0.5, 0.3),
				Position = UDim2.fromScale(0.03, 0.15),
				Alignment = Enum.TextXAlignment.Left,
				MaxTextSize = 26,
				Parent = card,
			})
			local label = UIKit.Label({
				Text = "",
				Font = UIKit.BodyFont,
				Size = UDim2.fromScale(0.94, 0.3),
				Position = UDim2.fromScale(0.03, 0.55),
				Alignment = Enum.TextXAlignment.Left,
				MaxTextSize = 20,
				Parent = card,
			})
			table.insert(timers, function()
				local latest = DataController.Get()
				local left = if latest then latest.Contracts.NextRefillAt - serverNow() else 0
				label.Text = if left > 0
					then "Next contract in " .. NumberFormat.Duration(left)
					else "A new contract is arriving…"
			end)
			continue
		end

		local color = tierColor(slot.Tier)
		local line = Config.Lines[slot.Line]
		UIKit.Stroke(card, color, 3)
		UIKit.Label({
			Text = string.format("%s  •  %s", slot.Tier, if line then line.Name else "Products"),
			Size = UDim2.fromScale(0.58, 0.24),
			Position = UDim2.fromScale(0.03, 0.06),
			Alignment = Enum.TextXAlignment.Left,
			Color = color,
			MaxTextSize = 26,
			Parent = card,
		})
		local bar = UIKit.ProgressBar(card, UDim2.fromScale(0.58, 0.22), color)
		bar.Root.Position = UDim2.fromScale(0.03, 0.36)
		local timeLabel = UIKit.Label({
			Text = "",
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.58, 0.2),
			Position = UDim2.fromScale(0.03, 0.66),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			Parent = card,
		})
		local cash, credits = rewardPreview(data, index, slot)
		UIKit.Label({
			Text = NumberFormat.Cash(cash) .. "\n+" .. NumberFormat.Commas(credits) .. " Credits",
			Size = UDim2.fromScale(0.34, 0.34),
			Position = UDim2.fromScale(0.63, 0.04),
			Color = palette.Cash,
			MaxTextSize = 20,
			Parent = card,
		})
		local claim = UIKit.Button({
			Text = "Claim",
			Size = UDim2.fromScale(0.34, 0.4),
			Position = UDim2.fromScale(0.63, 0.5),
			Color = palette.UIPanel,
			Parent = card,
			OnClick = function()
				local latest = DataController.Get()
				local current = if latest then latest.Contracts.Slots[index] else nil
				if not current or not (current.Done or current.Progress >= current.Target) then
					NotificationController.Toast("Info", "Keep producing to finish this contract.")
					return
				end
				local res = NotificationController.Request("ClaimContract", index)
				SoundController.Play(if res.Ok then "Coins" else "Error")
			end,
		})
		table.insert(timers, function()
			local latest = DataController.Get()
			local current = if latest then latest.Contracts.Slots[index] else nil
			if not current or current.Tier == "" then
				return
			end
			bar.Set(
				current.Progress / math.max(1, current.Target),
				NumberFormat.Short(current.Progress) .. " / " .. NumberFormat.Short(current.Target)
			)
			local ready = current.Done or current.Progress >= current.Target
			claim.BackgroundColor3 = if ready then palette.UIGood else palette.UIPanel
			local left = current.EndsAt - serverNow()
			timeLabel.Text = if ready
				then "Ready to claim!"
				elseif left > 0 then NumberFormat.Duration(left) .. " left"
				else "Expired"
		end)
	end
	return order
end

local function renderOdds(body: Instance, order: number, data: Types.PlayerData): number
	order += 1
	local row = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = body,
	})
	UIKit.Aspect(row, 8)
	UIKit.List(row, 0.015, true)
	for i, tierName in Config.Contracts.TierOrder do
		UIKit.Button({
			Text = tierName .. " odds",
			Size = UDim2.fromScale(0.32, 0.9),
			LayoutOrder = i,
			Color = tierColor(tierName):Lerp(Color3.new(0, 0, 0), if oddsTier == tierName then 0 else 0.5),
			TextColor = if oddsTier == tierName then Color3.new(0, 0, 0) else palette.UIText,
			MaxTextSize = 22,
			Parent = row,
			OnClick = function()
				oddsTier = if oddsTier == tierName then nil else tierName
				lastSignature = ""
				ContractsController.Render()
			end,
		})
	end

	local tierName = oddsTier
	if not tierName or not Config.Contracts.Tiers[tierName] then
		return order
	end
	local lines = {}
	for _, entry in ContractOdds.DisplayOdds(tierName) do
		table.insert(lines, string.format("%s: %s", entry.Label, NumberFormat.Percent(entry.Chance)))
	end
	local pity = Config.Contracts.Tiers.Gold.PityLegendary
	if tierName == "Gold" and pity then
		table.insert(
			lines,
			string.format(
				"Guaranteed Legendary blueprint by the %s Gold contract (%d/%d so far)",
				ordinal(pity),
				data.Contracts.GoldSinceLegendary,
				pity
			)
		)
	end
	table.insert(lines, "Blueprints are free rewards; they can never be bought.")
	order += 1
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 2.4)
	UIKit.Stroke(card, tierColor(tierName), 3)
	UIKit.Label({
		Text = table.concat(lines, "\n"),
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.9),
		Position = UDim2.fromScale(0.03, 0.05),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = card,
	})
	return order
end

local function renderExtend(body: Instance, order: number)
	local def = Config.DevProducts.ContractExtend
	if not def then
		return
	end
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 5)
	UIKit.Label({
		Text = string.format("Extend +%d min", Config.Contracts.ExtendSeconds // 60),
		Size = UDim2.fromScale(0.58, 0.4),
		Position = UDim2.fromScale(0.03, 0.08),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = card,
	})
	UIKit.Label({
		Text = "More time on every running contract. Never completes one for you.",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.58, 0.4),
		Position = UDim2.fromScale(0.03, 0.5),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = card,
	})
	UIKit.Button({
		Text = "R$ " .. NumberFormat.Commas(def.Price),
		Size = UDim2.fromScale(0.34, 0.6),
		Position = UDim2.fromScale(0.63, 0.2),
		Color = palette.UIAccent,
		Parent = card,
		OnClick = function()
			NotificationController.Request("PromptProduct", "ContractExtend")
		end,
	})
end

local function renderMega(body: Instance, order: number, data: Types.PlayerData): number
	local mega = Config.Contracts.Mega
	order += 1
	heading(body, order, "Mega Contract (co-op)", palette.UIAccent)
	order += 1
	note(
		body,
		order,
		string.format(
			"Team up with %d-%d players in this server. After a %ds join window each member must ship their own target "
				.. "within %d min. Win together: +%d point; %d points earn a Mythic machine.",
			mega.MinPlayers,
			mega.MaxPlayers,
			mega.JoinWindowSeconds,
			mega.DurationSeconds // 60,
			mega.PointsPerWin,
			mega.PointsForMythic
		),
		nil,
		4
	)

	order += 1
	local points = UIKit.ProgressBar(body, UDim2.fromScale(1, 0), palette.UIAccent, order)
	UIKit.Aspect(points.Root, 14)
	points.Set(
		data.Contracts.MegaPoints / mega.PointsForMythic,
		string.format("Mega points %d / %d", data.Contracts.MegaPoints, mega.PointsForMythic)
	)

	order += 1
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 3.2)
	if megaState and megaState.State ~= "Closed" then
		local status = UIKit.Label({
			Text = "",
			Size = UDim2.fromScale(0.94, 0.26),
			Position = UDim2.fromScale(0.03, 0.05),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 24,
			Parent = card,
		})
		local membersLabel = UIKit.Label({
			Text = "",
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.94, 0.38),
			Position = UDim2.fromScale(0.03, 0.32),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			Parent = card,
		})
		local bar = UIKit.ProgressBar(card, UDim2.fromScale(0.94, 0.16), palette.UIGood)
		bar.Root.Position = UDim2.fromScale(0.03, 0.78)
		table.insert(timers, function()
			local state = megaState
			if not state then
				return
			end
			local members = {}
			for _, member in state.Members or {} do
				table.insert(
					members,
					string.format(
						"%s %s/%s%s",
						member.Name,
						NumberFormat.Short(member.Progress),
						NumberFormat.Short(member.Target),
						if member.Done then " ✔" else ""
					)
				)
			end
			membersLabel.Text = table.concat(members, "\n")
			if state.State == "Joining" then
				status.Text = string.format(
					"%s's Mega Contract starts in %s",
					state.Host,
					NumberFormat.Duration(state.StartsAt - serverNow())
				)
			else
				status.Text = "Mega Contract: " .. NumberFormat.Duration(state.EndsAt - serverNow()) .. " left"
			end
			bar.Set((state.Progress or 0) / math.max(1, state.Target or 1), "Your line")
		end)
	else
		UIKit.Button({
			Text = "Start a Mega Contract",
			Size = UDim2.fromScale(0.9, 0.38),
			Position = UDim2.fromScale(0.05, 0.1),
			Color = palette.UIGood,
			Parent = card,
			OnClick = function()
				local res = NotificationController.Request("MegaCreate")
				if res.Ok and type(res.Data) == "table" then
					megaState = res.Data
					ContractsController.Render()
				end
			end,
		})
		local offer = megaOffer
		if offer and offer.StartsAt > serverNow() then
			UIKit.Button({
				Text = "Join " .. tostring(offer.Host) .. "'s Mega Contract",
				Size = UDim2.fromScale(0.9, 0.38),
				Position = UDim2.fromScale(0.05, 0.54),
				Color = palette.UIAccent,
				Parent = card,
				OnClick = function()
					local res = NotificationController.Request("MegaJoin", offer.MegaId)
					if res.Ok and type(res.Data) == "table" then
						megaState = res.Data
						megaOffer = nil
						ContractsController.Render()
					end
				end,
			})
		else
			UIKit.Label({
				Text = "No open Mega Contracts right now.",
				Font = UIKit.BodyFont,
				Size = UDim2.fromScale(0.9, 0.3),
				Position = UDim2.fromScale(0.05, 0.6),
				MaxTextSize = 18,
				Parent = card,
			})
		end
	end
	return order
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------
function ContractsController.Render()
	tickToken += 1
	timers = {}
	clear(panel.Body)
	local data = DataController.Get()
	if not data then
		return
	end
	lastSignature = signature(data)
	local body = panel.Body
	renderRush(body, 1)
	heading(body, 2, "Your contracts")
	local order = renderSlots(body, 3, data)
	order = renderOdds(body, order, data)
	order += 1
	renderExtend(body, order)
	order = renderMega(body, order + 1, data)

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

function ContractsController.Init()
	panel = UIKit.Panel(PANEL, "Contracts", UIController.GetLayer("Panels"), TIER_COLORS.Gold)
	UIKit.List(panel.Body, 0.02)
	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = ContractsController.Render,
		OnClose = function()
			tickToken += 1
		end,
	})
end

function ContractsController.Start()
	DataController.WaitForData()
	-- Slot progress changes every few ticks; only a structural change needs a rebuild.
	maid:Add(DataController.OnKey("Contracts", function()
		local data = DataController.Get()
		if data and UIController.IsOpen(PANEL) and signature(data) ~= lastSignature then
			ContractsController.Render()
		end
	end))
	for _, key in { "Research", "Tutorial" } do
		maid:Add(DataController.OnKey(key, function()
			if UIController.IsOpen(PANEL) then
				ContractsController.Render()
			end
		end))
	end
	maid:Add(DataController.EventsChanged:Connect(function(events: any)
		local was = rushEndsAt
		rushEndsAt = os.clock() + (if events and events.RushActive then events.RushSecondsLeft or 0 else 0)
		if UIController.IsOpen(PANEL) and (was > os.clock()) ~= (rushEndsAt > os.clock()) then
			ContractsController.Render()
		end
	end))
	local initial = DataController.GetEvents()
	if initial and initial.RushActive then
		rushEndsAt = os.clock() + (initial.RushSecondsLeft or 0)
	end

	maid:Add(Net.Event("Effect").OnClientEvent:Connect(function(kind: any, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if kind == "MegaState" then
			local before = megaState
			megaState = if payload.State == "Closed" then nil else payload
			-- Per-second progress pushes are picked up by the timers; rebuild only when the layout changes.
			local changed = (before == nil) ~= (megaState == nil) or (before ~= nil and before.State ~= payload.State)
			if changed and UIController.IsOpen(PANEL) then
				ContractsController.Render()
			end
		elseif kind == "MegaOpen" then
			megaOffer = payload
			if UIController.IsOpen(PANEL) then
				ContractsController.Render()
			end
		end
	end))
end

return ContractsController

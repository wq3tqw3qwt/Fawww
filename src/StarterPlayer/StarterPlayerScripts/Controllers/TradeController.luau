--!strict
--[[
	TradeController: the "Trade" panel and the incoming-request popup.
	Two-sided flow: both sides Ready (revision-checked), a short countdown, then both Confirm.
	Any change to either offer resets Ready, so nobody can be surprised. Trades are final.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local TradeLogic = require(ReplicatedStorage.Shared.TradeLogic)
local Types = require(ReplicatedStorage.Shared.Types)

local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local TradeController = {}

local PANEL = "Trade"
local GRID_CELL = 0.235

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local timers: { () -> () } = {}
local tickToken = 0
local session: any = nil
local countdownEndsAt = 0
local outgoing: { Name: string, Until: number }? = nil
local promptFrame: Frame? = nil
local promptToken = 0

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function rarityColor(rarity: string): Color3
	local color = Config.Rarities.Colors[rarity] or palette.UIText
	local _, _, v = color:ToHSV()
	return if v < 0.25 then color:Lerp(Color3.new(1, 1, 1), 0.4) else color
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

local function describeItem(entry: { Id: string, Grade: number }): string
	local def = Formulas.GetMachine(entry.Id)
	if not def then
		return entry.Id
	end
	local grade = Config.MachineGrades.Names[entry.Grade + 1] or ""
	return string.format("%s (%s) +%s%%", def.Name, grade, NumberFormat.Short(Formulas.MachinePower(def, entry.Grade)))
end

local function offerCard(body: Instance, order: number, title: string, offer: { any }, power: number, color: Color3)
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 3)
	UIKit.Stroke(card, color, 3)
	UIKit.Label({
		Text = string.format("%s   (total power +%s%%)", title, NumberFormat.Short(power)),
		Size = UDim2.fromScale(0.94, 0.2),
		Position = UDim2.fromScale(0.03, 0.04),
		Alignment = Enum.TextXAlignment.Left,
		Color = color,
		MaxTextSize = 22,
		Parent = card,
	})
	local lines = {}
	for _, entry in offer do
		table.insert(lines, describeItem(entry))
	end
	UIKit.Label({
		Text = if #lines > 0 then table.concat(lines, "\n") else "Nothing yet",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.7),
		Position = UDim2.fromScale(0.03, 0.26),
		Alignment = Enum.TextXAlignment.Left,
		Color = if #lines > 0 then palette.UIText else Color3.fromRGB(160, 163, 175),
		MaxTextSize = 16,
		Parent = card,
	})
end

--------------------------------------------------------------------------------
-- Lobby (no session)
--------------------------------------------------------------------------------
local function renderLobby(body: Instance)
	local order = 1
	note(body, order, "Trades are final. Both players must confirm, and nothing is refunded.", palette.UIAccent, 10)
	order += 1
	if not Config.Trade.Enabled then
		note(body, order, "Trading is turned off right now.", palette.UIBad)
		return
	end
	note(
		body,
		order,
		string.format(
			"Trading needs an account at least %d days old and %d minutes played in this game. "
				.. "You can trade up to %d machines each.",
			Config.Trade.MinAccountAgeDays,
			Config.Trade.MinPlaySeconds // 60,
			Config.Trade.MaxItemsPerSide
		),
		nil,
		6
	)

	local pending = outgoing
	if pending and pending.Until > os.clock() then
		order += 1
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 5)
		UIKit.Label({
			Text = "Waiting for " .. pending.Name .. " to answer…",
			Size = UDim2.fromScale(0.6, 0.6),
			Position = UDim2.fromScale(0.03, 0.2),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 22,
			Parent = card,
		})
		UIKit.Button({
			Text = "Cancel",
			Size = UDim2.fromScale(0.3, 0.6),
			Position = UDim2.fromScale(0.67, 0.2),
			Color = palette.UIBad,
			Parent = card,
			OnClick = function()
				outgoing = nil
				Net.Request("TradeCancel")
				TradeController.Render()
			end,
		})
	end

	order += 1
	heading(body, order, "Players in this server")
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer then
			count += 1
			order += 1
			local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
			UIKit.Aspect(card, 6)
			UIKit.Label({
				Text = other.DisplayName,
				Size = UDim2.fromScale(0.6, 0.6),
				Position = UDim2.fromScale(0.03, 0.2),
				Alignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Parent = card,
			})
			UIKit.Button({
				Text = "Request trade",
				Size = UDim2.fromScale(0.34, 0.7),
				Position = UDim2.fromScale(0.63, 0.15),
				Color = palette.UIGood,
				MaxTextSize = 22,
				Parent = card,
				OnClick = function()
					local res = NotificationController.Request("TradeRequest", other.UserId)
					if res.Ok then
						outgoing = { Name = other.DisplayName, Until = os.clock() + Config.Trade.RequestTimeoutSeconds }
						NotificationController.Toast("Info", "Trade request sent to " .. other.DisplayName)
						TradeController.Render()
						task.delay(Config.Trade.RequestTimeoutSeconds + 0.5, function()
							if UIController.IsOpen(PANEL) and session == nil then
								TradeController.Render()
							end
						end)
					end
				end,
			})
		end
	end
	if count == 0 then
		order += 1
		note(body, order, "Nobody else is here yet. Invite a friend!", nil, 10)
	end
end

--------------------------------------------------------------------------------
-- Active session
--------------------------------------------------------------------------------
local function myTradable(data: Types.PlayerData): { { Uid: string, Item: Types.MachineItem, Def: Config.MachineDef } }
	local equipped = TradeLogic.EquippedSet(data.Machines.Bays)
	local list = {}
	for uid, item in data.Machines.Inventory do
		local def = Formulas.GetMachine(item.Id)
		if def and def.Tradable and not item.Locked and not equipped[uid] then
			table.insert(list, { Uid = uid, Item = item, Def = def })
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = Formulas.MachinePower(a.Def, a.Item.Grade), Formulas.MachinePower(b.Def, b.Item.Grade)
		if pa ~= pb then
			return pa > pb
		end
		return a.Uid < b.Uid
	end)
	return list
end

local function setOffer(uids: { string })
	local res = NotificationController.Request("TradeSetOffer", uids)
	if not res.Ok then
		SoundController.Play("Error")
	end
end

local function renderSession(body: Instance, data: Types.PlayerData)
	local s = session
	local order = 1
	heading(body, order, "Trading with " .. tostring(s.PartnerName), palette.UIAccent)
	order += 1
	note(body, order, "Trades are final. Check both offers carefully.", palette.UIAccent, 12)

	order += 1
	offerCard(body, order, "You offer", s.MyOffer, s.MyPower, palette.UIGood)
	order += 1
	offerCard(body, order, tostring(s.PartnerName) .. " offers", s.TheirOffer, s.TheirPower, palette.Credits)

	if s.Lopsided then
		order += 1
		note(
			body,
			order,
			string.format(
				"Warning: this trade is very uneven (%d:1 power or more). Only confirm if you are sure.",
				Config.Trade.LopsidedWarnRatio
			),
			palette.UIBad,
			8
		)
	end

	order += 1
	local status = note(body, order, "", palette.UIText, 12)
	table.insert(timers, function()
		local parts = {
			if s.MyReady then "You: ready" else "You: not ready",
			if s.TheirReady then "They: ready" else "They: not ready",
		}
		if s.MyConfirmed then
			table.insert(parts, "You confirmed")
		end
		if s.TheirConfirmed then
			table.insert(parts, "They confirmed")
		end
		status.Text = table.concat(parts, "   •   ")
	end)

	order += 1
	local row = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = body,
	})
	UIKit.Aspect(row, 6)
	UIKit.List(row, 0.015, true)
	UIKit.Button({
		Text = if s.MyReady then "Not ready" else "Ready",
		Size = UDim2.fromScale(0.32, 1),
		LayoutOrder = 1,
		Color = if s.MyReady then palette.UIPanel else palette.UIGood,
		Parent = row,
		OnClick = function()
			NotificationController.Request("TradeReady", not s.MyReady, s.Revision)
		end,
	})
	local confirm = UIKit.Button({
		Text = "Confirm",
		Size = UDim2.fromScale(0.32, 1),
		LayoutOrder = 2,
		Color = palette.UIPanel,
		Parent = row,
		OnClick = function()
			if not (s.MyReady and s.TheirReady) then
				NotificationController.Toast("Info", "Both players must be ready first.")
			elseif s.MyConfirmed then
				NotificationController.Toast("Info", "Waiting for the other player.")
			elseif os.clock() < countdownEndsAt then
				NotificationController.Toast("Info", "Wait for the countdown.")
			else
				local res = NotificationController.Request("TradeConfirm", s.Revision)
				if not res.Ok then
					SoundController.Play("Error")
				end
			end
		end,
	})
	UIKit.Button({
		Text = "Cancel trade",
		Size = UDim2.fromScale(0.32, 1),
		LayoutOrder = 3,
		Color = palette.UIBad,
		Parent = row,
		OnClick = function()
			NotificationController.Request("TradeCancel")
		end,
	})
	table.insert(timers, function()
		if s.MyConfirmed then
			confirm.Text = "Waiting…"
			confirm.BackgroundColor3 = palette.UIPanel
		elseif s.MyReady and s.TheirReady then
			local left = countdownEndsAt - os.clock()
			if left > 0 then
				confirm.Text = string.format("Confirm in %ds", math.ceil(left))
				confirm.BackgroundColor3 = palette.UIPanel
			else
				confirm.Text = "Confirm"
				confirm.BackgroundColor3 = palette.UIAccent
			end
		else
			confirm.Text = "Confirm"
			confirm.BackgroundColor3 = palette.UIPanel
		end
	end)

	order += 1
	heading(body, order, string.format("Your machines (tap to add/remove, max %d)", Config.Trade.MaxItemsPerSide))
	order += 1
	local inOffer: { [string]: boolean } = {}
	local offered: { string } = {}
	for _, entry in s.MyOffer do
		inOffer[entry.Uid] = true
		table.insert(offered, entry.Uid)
	end
	local grid = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = body,
	})
	UIKit.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Wraps = true,
		Padding = UDim.new(0.012, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = grid,
	})
	local items = myTradable(data)
	for i, entry in items do
		local on = inOffer[entry.Uid] == true
		local button = UIKit.Button({
			Text = (describeItem({ Id = entry.Item.Id, Grade = entry.Item.Grade }):gsub(" %(", "\n(")),
			Size = UDim2.fromScale(GRID_CELL, 0),
			LayoutOrder = i,
			Color = rarityColor(entry.Def.Rarity):Lerp(Color3.new(0, 0, 0), 0.45),
			MaxTextSize = 15,
			Parent = grid,
			OnClick = function()
				local updated: { string } = {}
				for _, uid in offered do
					if uid ~= entry.Uid then
						table.insert(updated, uid)
					end
				end
				if not on then
					if #updated >= Config.Trade.MaxItemsPerSide then
						NotificationController.Toast(
							"Info",
							"You can offer at most " .. Config.Trade.MaxItemsPerSide .. " machines."
						)
						return
					end
					table.insert(updated, entry.Uid)
				end
				setOffer(updated)
			end,
		})
		UIKit.Aspect(button, 1.2)
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke and on then
			stroke.Color = Color3.new(1, 1, 1)
			stroke.Thickness = 4
		end
	end
	if #items == 0 then
		order += 1
		note(body, order, "You have no tradable machines (locked, equipped and special ones can't be traded).")
	end
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------
function TradeController.Render()
	tickToken += 1
	timers = {}
	clear(panel.Body)
	local data = DataController.Get()
	if not data then
		return
	end
	if session and session.Active then
		renderSession(panel.Body, data)
	else
		renderLobby(panel.Body)
	end

	local token = tickToken
	if #timers > 0 then
		task.spawn(function()
			while tickToken == token and UIController.IsOpen(PANEL) do
				for _, fn in timers do
					fn()
				end
				task.wait(0.5)
			end
		end)
	end
end

local function closePrompt()
	promptToken += 1
	if promptFrame then
		promptFrame:Destroy()
		promptFrame = nil
	end
end

local function showPrompt(requestId: string, fromName: string)
	closePrompt()
	local token = promptToken
	local shade = UIKit.Create("Frame", {
		Name = "TradePrompt",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Parent = UIController.GetLayer("Overlay"),
	})
	promptFrame = shade
	local card = UIKit.Card(shade, UDim2.fromScale(0.8, 0.4), nil)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(620, 320), Parent = card })
	UIKit.Label({
		Text = fromName .. " wants to trade with you.\nTrades are final.",
		Size = UDim2.fromScale(0.9, 0.5),
		Position = UDim2.fromScale(0.05, 0.06),
		MaxTextSize = 28,
		Parent = card,
	})
	local function answer(accept: boolean)
		closePrompt()
		local res = NotificationController.Request("TradeRespond", requestId, accept)
		if res.Ok and accept then
			UIController.Open(PANEL)
		end
	end
	local decline = UIKit.Button({
		Text = "Decline",
		Size = UDim2.fromScale(0.4, 0.28),
		Position = UDim2.fromScale(0.06, 0.66),
		Color = palette.UIBad,
		Parent = card,
		OnClick = function()
			answer(false)
		end,
	})
	UIKit.Button({
		Text = "Accept",
		Size = UDim2.fromScale(0.4, 0.28),
		Position = UDim2.fromScale(0.54, 0.66),
		Color = palette.UIGood,
		Parent = card,
		OnClick = function()
			answer(true)
		end,
	})
	if GuiService.SelectedObject == nil then
		UIKit.Select(decline)
	end
	task.delay(Config.Trade.RequestTimeoutSeconds, function()
		if promptToken == token then
			closePrompt()
		end
	end)
end

local function onUpdate(state: any)
	if type(state) ~= "table" then
		return
	end
	if state.Active then
		session = state
		outgoing = nil
		countdownEndsAt = os.clock() + (state.CountdownLeft or 0)
		closePrompt()
		if not UIController.IsOpen(PANEL) then
			UIController.Open(PANEL)
		else
			TradeController.Render()
		end
		return
	end
	local wasActive = session ~= nil
	session = nil
	if wasActive and state.Result == "Completed" then
		NotificationController.Toast("Reward", state.Message or "Trade complete!")
		SoundController.Play("Fanfare")
	end
	if UIController.IsOpen(PANEL) then
		TradeController.Render()
	end
end

function TradeController.Init()
	panel = UIKit.Panel(PANEL, "Trade", UIController.GetLayer("Panels"), palette.Credits)
	UIKit.List(panel.Body, 0.02)
	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = TradeController.Render,
		OnClose = function()
			tickToken += 1
		end,
	})
end

function TradeController.Start()
	DataController.WaitForData()
	maid:Add(Net.Event("TradeUpdate").OnClientEvent:Connect(onUpdate))
	maid:Add(Net.Event("TradePrompt").OnClientEvent:Connect(function(requestId: any, _fromUserId: any, fromName: any)
		if type(requestId) == "string" and type(fromName) == "string" then
			showPrompt(requestId, fromName)
		end
	end))
	local function lobbyChanged()
		if UIController.IsOpen(PANEL) and session == nil then
			TradeController.Render()
		end
	end
	maid:Add(Players.PlayerAdded:Connect(lobbyChanged))
	maid:Add(Players.PlayerRemoving:Connect(function()
		task.defer(lobbyChanged)
	end))
	maid:Add(DataController.OnKey("Machines", function()
		if UIController.IsOpen(PANEL) and session ~= nil then
			TradeController.Render()
		end
	end))
end

return TradeController

--!strict
--[[
	MachinesController: the "Machines" panel. Bays, inventory, merging/plating and the Machine Shop.
	Displays use Formulas; every action is an intent the server re-validates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Types = require(ReplicatedStorage.Shared.Types)

local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local MachinesController = {}

local PANEL = "Machines"
local TABS = { "Inventory", "Machine Shop" }
local GRID_CELL = 0.235

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Inventory"
local selectedUid: string? = nil
local choosingBay = false
local timers: { () -> () } = {}
local tickToken = 0
local platingWasDone = false

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

local function rarityColor(rarity: string): Color3
	local color = Config.Rarities.Colors[rarity] or palette.UIText
	-- Secret is near-black: lift it so text and borders stay readable on dark panels.
	local _, _, v = color:ToHSV()
	return if v < 0.25 then color:Lerp(Color3.new(1, 1, 1), 0.4) else color
end

local function rarityRank(rarity: string): number
	return table.find(Config.Rarities.Order, rarity) or 0
end

local function colored(text: string, color: Color3): string
	return string.format('<font color="#%s">%s</font>', color:ToHex(), text)
end

local function abilityText(def: Config.MachineDef): string?
	local ability = def.Ability
	if not ability then
		return nil
	end
	local label = Config.AbilityLabels[ability.Kind]
	if not label then
		return nil
	end
	local value = if ability.Kind == "OverdrivePlus" then ability.Value else ability.Value * 100
	return string.format(label, math.floor(value + 0.5))
end

local function powerText(power: number): string
	return "+" .. NumberFormat.Short(power) .. "% income"
end

local function bayCount(data: Types.PlayerData): number
	if #data.Machines.Bays > 0 then
		return #data.Machines.Bays
	end
	local research = 0
	for _, def in Config.Research do
		if def.Effect == "ExtraBay" then
			research += (data.Research.Levels[def.Id] or 0) * def.ValuePerLevel
		end
	end
	return Formulas.BaysFor(data.Expansions, data.Passes.ExtraBays == true, research)
end

local function equippedBayOf(data: Types.PlayerData, uid: string): number?
	for i, id in data.Machines.Bays do
		if id == uid then
			return i
		end
	end
	return nil
end

-- Identical, unlocked, unequipped copies at the same grade (the set the server merges from).
local function identicalCopies(data: Types.PlayerData, item: Types.MachineItem): number
	local equipped = {}
	for _, uid in data.Machines.Bays do
		equipped[uid] = true
	end
	local n = 0
	for uid, other in data.Machines.Inventory do
		if other.Id == item.Id and other.Grade == item.Grade and not other.Locked and not equipped[uid] then
			n += 1
		end
	end
	return n
end

local function act(name: string, successText: string?, ...: any): Types.Response
	local res = NotificationController.Request(name, ...)
	if res.Ok then
		if successText then
			NotificationController.Toast("Success", successText)
		end
		SoundController.Play("Upgrade")
	else
		SoundController.Play("Error")
	end
	return res
end

--------------------------------------------------------------------------------
-- Small widgets
--------------------------------------------------------------------------------
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

local function setStroke(button: TextButton, color: Color3, thickness: number)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
	end
end

--------------------------------------------------------------------------------
-- Inventory tab
--------------------------------------------------------------------------------
local render: () -> ()

local function renderSummary(body: Instance, order: number, data: Types.PlayerData)
	local equipped: { Formulas.EquippedMachine } = {}
	for _, uid in data.Machines.Bays do
		local item = data.Machines.Inventory[uid]
		if item then
			table.insert(equipped, { Id = item.Id, Grade = item.Grade })
		end
	end
	local events = DataController.GetEvents()
	local power, abilities = Formulas.MachineTotals(equipped, events ~= nil and events.RushActive == true)
	local lines = { "Total power: " .. powerText(power) }
	for kind, value in abilities do
		local label = Config.AbilityLabels[kind]
		if label then
			local shown = if kind == "OverdrivePlus" then value else value * 100
			table.insert(lines, string.format(label, math.floor(shown + 0.5)))
		end
	end
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 4.5)
	UIKit.Label({
		Text = lines[1],
		Size = UDim2.fromScale(0.94, 0.4),
		Position = UDim2.fromScale(0.03, 0.06),
		Color = palette.Cash,
		MaxTextSize = 30,
		Parent = card,
	})
	table.remove(lines, 1)
	UIKit.Label({
		Text = if #lines > 0 then table.concat(lines, "  •  ") else "Equip machines in your bays for bonuses.",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.42),
		Position = UDim2.fromScale(0.03, 0.5),
		MaxTextSize = 18,
		Parent = card,
	})
end

local function renderBays(body: Instance, order: number, data: Types.PlayerData)
	local grid = wrapGrid(body, order)
	for i = 1, bayCount(data) do
		local uid = data.Machines.Bays[i] or ""
		local item = if uid ~= "" then data.Machines.Inventory[uid] else nil
		local def = if item then Formulas.GetMachine(item.Id) else nil
		local text = "Bay " .. i .. "\nEmpty"
		local color = palette.UIPanel
		if item and def then
			text = def.Name .. "\n" .. powerText(Formulas.MachinePower(def, item.Grade))
			color = rarityColor(def.Rarity):Lerp(Color3.new(0, 0, 0), 0.5)
		end
		local button = UIKit.Button({
			Text = text,
			Size = UDim2.fromScale(GRID_CELL, 0),
			LayoutOrder = i,
			Color = color,
			MaxTextSize = 18,
			Parent = grid,
			OnClick = function()
				if choosingBay and selectedUid then
					local res = act("EquipMachine", nil, selectedUid, i)
					if res.Ok then
						choosingBay = false
					end
				elseif uid ~= "" then
					act("UnequipMachine", "Unequipped", i)
				end
			end,
		})
		UIKit.Aspect(button, 1.15)
		if choosingBay then
			setStroke(button, palette.UIAccent, 4)
		end
	end
end

local function renderPlating(body: Instance, order: number, data: Types.PlayerData)
	local plating = data.Machines.Plating
	if plating.Id == "" then
		return
	end
	local def = Formulas.GetMachine(plating.Id)
	local done = serverNow() >= plating.EndsAt
	platingWasDone = done
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 4)
	UIKit.Label({
		Text = "Gold plating: " .. (if def then def.Name else plating.Id),
		Size = UDim2.fromScale(0.58, 0.4),
		Position = UDim2.fromScale(0.03, 0.08),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = card,
	})
	local timerLabel = UIKit.Label({
		Text = "",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.58, 0.32),
		Position = UDim2.fromScale(0.03, 0.56),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = card,
	})
	if done then
		timerLabel.Text = "Ready!"
		UIKit.Button({
			Text = "Claim",
			Size = UDim2.fromScale(0.34, 0.6),
			Position = UDim2.fromScale(0.63, 0.2),
			Color = palette.UIGood,
			Parent = card,
			OnClick = function()
				act("ClaimPlating", "Gold-Plated machine claimed!")
			end,
		})
	else
		local skip = Config.DevProducts.SkipPlating
		UIKit.Button({
			Text = "Finish now R$ " .. (if skip then NumberFormat.Commas(skip.Price) else "?"),
			Size = UDim2.fromScale(0.34, 0.6),
			Position = UDim2.fromScale(0.63, 0.2),
			Color = palette.UIAccent,
			MaxTextSize = 22,
			Parent = card,
			OnClick = function()
				local res = NotificationController.Request("PromptProduct", "SkipPlating")
				if not res.Ok then
					SoundController.Play("Error")
				end
			end,
		})
		table.insert(timers, function()
			local left = plating.EndsAt - serverNow()
			if left <= 0 then
				if not platingWasDone then
					render()
				end
				return
			end
			timerLabel.Text = "Ready in " .. NumberFormat.Duration(left)
		end)
	end
end

local function renderDetails(body: Instance, order: number, data: Types.PlayerData)
	local uid = selectedUid
	local item = if uid then data.Machines.Inventory[uid] else nil
	local def = if item then Formulas.GetMachine(item.Id) else nil
	if not (uid and item and def) then
		selectedUid = nil
		choosingBay = false
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 8)
		UIKit.Label({
			Text = "Tap a machine below for details.",
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.94, 0.6),
			Position = UDim2.fromScale(0.03, 0.2),
			MaxTextSize = 20,
			Parent = card,
		})
		return
	end

	local color = rarityColor(def.Rarity)
	local grades = Config.MachineGrades
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 2.3)
	UIKit.Stroke(card, color, 3)
	UIKit.Label({
		Text = colored(def.Name, color) .. "  " .. (grades.Names[item.Grade + 1] or ""),
		Size = UDim2.fromScale(0.94, 0.16),
		Position = UDim2.fromScale(0.03, 0.03),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
		Parent = card,
	})
	local info = def.Rarity .. "  •  " .. powerText(Formulas.MachinePower(def, item.Grade))
	local ability = abilityText(def)
	if ability then
		info ..= "  •  " .. ability
	end
	if item.Locked then
		info ..= "  •  Locked"
	end
	UIKit.Label({
		Text = info,
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.16),
		Position = UDim2.fromScale(0.03, 0.2),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Parent = card,
	})

	local bay = equippedBayOf(data, uid)
	local buttons = UIKit.Create("Frame", {
		Size = UDim2.fromScale(0.94, 0.5),
		Position = UDim2.fromScale(0.03, 0.43),
		BackgroundTransparency = 1,
		Parent = card,
	})
	UIKit.List(buttons, 0.02, true)
	local function add(text: string, buttonColor: Color3, onClick: () -> ())
		UIKit.Button({
			Text = text,
			Size = UDim2.fromScale(0.31, 1),
			Color = buttonColor,
			MaxTextSize = 20,
			Parent = buttons,
			OnClick = onClick,
		})
	end

	if bay then
		add("Unequip", palette.UIBad, function()
			act("UnequipMachine", "Unequipped", bay)
		end)
	else
		add(if choosingBay then "Pick a bay above" else "Equip", palette.UIGood, function()
			choosingBay = not choosingBay
			render()
		end)
	end
	add(if item.Locked then "Unlock" else "Lock", palette.UIPanel, function()
		act("LockMachine", nil, uid, not item.Locked)
	end)

	local have = identicalCopies(data, item)
	if item.Grade == 0 then
		local need = grades.ChromeMergeCount
		add(string.format("Merge to Chrome %d/%d", math.min(have, need), need), palette.UIAccent, function()
			local res = act("MergeChrome", "Merged into Chrome!", uid)
			if res.Ok and type(res.Data) == "table" and type(res.Data.Uid) == "string" then
				selectedUid = res.Data.Uid
			end
		end)
	elseif item.Grade == 1 then
		local need = grades.GoldMergeCount
		add(string.format("Start Gold plating %d/%d", math.min(have, need), need), palette.UIAccent, function()
			act("StartPlating", "Plating started", uid)
		end)
	else
		add("Maxed", palette.UIPanel, function() end)
	end
end

local function renderInventory(body: Instance, order: number, data: Types.PlayerData)
	local list: { { Uid: string, Item: Types.MachineItem, Def: Config.MachineDef, Power: number } } = {}
	local count = 0
	for uid, item in data.Machines.Inventory do
		count += 1
		local def = Formulas.GetMachine(item.Id)
		if def then
			table.insert(list, { Uid = uid, Item = item, Def = def, Power = Formulas.MachinePower(def, item.Grade) })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = rarityRank(a.Def.Rarity), rarityRank(b.Def.Rarity)
		if ra ~= rb then
			return ra > rb
		end
		if a.Power ~= b.Power then
			return a.Power > b.Power
		end
		return a.Uid < b.Uid
	end)
	heading(body, order, string.format("Inventory %d/%d", count, Config.MachineGrades.InventoryLimit))
	local grid = wrapGrid(body, order + 1)
	for i, entry in list do
		local equipped = equippedBayOf(data, entry.Uid) ~= nil
		local tag = Config.MachineGrades.Names[entry.Item.Grade + 1] or ""
		local text = entry.Def.Name .. "\n" .. tag .. "  " .. powerText(entry.Power)
		if equipped then
			text ..= "\nEquipped"
		end
		if entry.Item.Locked then
			text ..= "  🔒"
		end
		local button = UIKit.Button({
			Text = text,
			Size = UDim2.fromScale(GRID_CELL, 0),
			LayoutOrder = i,
			Color = rarityColor(entry.Def.Rarity):Lerp(Color3.new(0, 0, 0), 0.45),
			MaxTextSize = 16,
			Parent = grid,
			OnClick = function()
				selectedUid = entry.Uid
				choosingBay = false
				render()
			end,
		})
		UIKit.Aspect(button, 1)
		if entry.Uid == selectedUid then
			setStroke(button, Color3.new(1, 1, 1), 4)
		end
	end
	if #list == 0 then
		heading(body, order + 2, "No machines yet. Visit the Machine Shop or finish contracts!")
	end
end

--------------------------------------------------------------------------------
-- Machine Shop tab
--------------------------------------------------------------------------------
local function renderShop(body: Instance, data: Types.PlayerData)
	local entries: { { Def: Config.MachineDef, Price: Formulas.Price } } = {}
	for _, def in Config.Machines do
		local price = Formulas.MachinePrice(def)
		if price then
			table.insert(entries, { Def = def, Price = price })
		end
	end
	table.sort(entries, function(a, b)
		if a.Def.Hall ~= b.Def.Hall then
			return a.Def.Hall < b.Def.Hall
		end
		local ra, rb = rarityRank(a.Def.Rarity), rarityRank(b.Def.Rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.Def.Id < b.Def.Id
	end)

	local owned: { [string]: number } = {}
	for _, item in data.Machines.Inventory do
		owned[item.Id] = (owned[item.Id] or 0) + 1
	end

	local order = 0
	local lastHall = -1
	for _, entry in entries do
		local def, price = entry.Def, entry.Price
		order += 1
		if def.Hall ~= lastHall then
			lastHall = def.Hall
			local hall = Config.Halls[def.Hall]
			heading(body, order, if hall then hall.Name else "Industry")
			order += 1
		end
		local unlocked = Formulas.HallUnlocked(def.Hall, data.Expansions)
		local color = rarityColor(def.Rarity)
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 4)
		UIKit.Label({
			Text = colored(def.Name, color) .. "  " .. def.Rarity,
			Size = UDim2.fromScale(0.6, 0.3),
			Position = UDim2.fromScale(0.03, 0.06),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 26,
			Parent = card,
		})
		local info = powerText(def.Power)
		local ability = abilityText(def)
		if ability then
			info ..= "  •  " .. ability
		end
		UIKit.Label({
			Text = info,
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.6, 0.3),
			Position = UDim2.fromScale(0.03, 0.4),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			Parent = card,
		})
		UIKit.Label({
			Text = "Owned: " .. (owned[def.Id] or 0),
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.6, 0.22),
			Position = UDim2.fromScale(0.03, 0.72),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 16,
			Parent = card,
		})

		local isCash = price.Currency == "Cash"
		local priceText = if isCash
			then NumberFormat.Cash(price.Amount)
			else NumberFormat.Commas(price.Amount) .. " Credits"
		if unlocked then
			local button = UIKit.Button({
				Text = "Buy " .. priceText,
				Size = UDim2.fromScale(0.34, 0.6),
				Position = UDim2.fromScale(0.63, 0.2),
				Color = palette.UIPanel,
				MaxTextSize = 22,
				Parent = card,
				OnClick = function()
					act("BuyMachine", "Bought " .. def.Name, def.Id)
				end,
			})
			table.insert(timers, function()
				local latest = DataController.Get()
				if latest then
					local wallet = if isCash then latest.Cash else latest.Credits
					button.BackgroundColor3 = if wallet >= price.Amount then palette.UIGood else palette.UIPanel
				end
			end)
		else
			local hall = Config.Halls[def.Hall]
			UIKit.Button({
				Text = "Locked: " .. (if hall then hall.Name else "industry") .. " at " .. (if hall
					then hall.UnlockExpansions
					else 0) .. " Exp.",
				Size = UDim2.fromScale(0.34, 0.6),
				Position = UDim2.fromScale(0.63, 0.2),
				Color = palette.UIBad:Lerp(Color3.new(0, 0, 0), 0.5),
				MaxTextSize = 16,
				Parent = card,
				OnClick = function()
					NotificationController.Toast("Info", "Expand your factory to unlock this industry.")
				end,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------
function render()
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
	if currentTab == "Inventory" then
		renderSummary(panel.Body, 1, data)
		renderBays(panel.Body, 2, data)
		renderPlating(panel.Body, 3, data)
		renderDetails(panel.Body, 4, data)
		renderInventory(panel.Body, 5, data)
	else
		renderShop(panel.Body, data)
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

function MachinesController.Init()
	panel = UIKit.Panel(PANEL, "Machines", UIController.GetLayer("Panels"), Config.Rarities.Colors.Epic)

	local bar = UIKit.Create("Frame", {
		Name = "Tabs",
		Size = UDim2.fromScale(0.96, 0.08),
		Position = UDim2.fromScale(0.02, 0.135),
		BackgroundTransparency = 1,
		Parent = panel.Root,
	})
	UIKit.List(bar, 0.01, true)
	for i, name in TABS do
		tabButtons[name] = UIKit.Button({
			Text = name,
			Size = UDim2.fromScale(1 / #TABS - 0.01, 1),
			LayoutOrder = i,
			Parent = bar,
			OnClick = function()
				currentTab = name
				choosingBay = false
				render()
			end,
		})
	end
	panel.Body.Size = UDim2.fromScale(0.96, 0.75)
	panel.Body.Position = UDim2.fromScale(0.02, 0.23)
	UIKit.List(panel.Body, 0.02)

	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = render,
		OnClose = function()
			tickToken += 1
			choosingBay = false
		end,
	})
end

function MachinesController.Start()
	DataController.WaitForData()
	local function relevant()
		if UIController.IsOpen(PANEL) then
			render()
		end
	end
	for _, key in { "Machines", "Expansions", "Passes", "Research" } do
		maid:Add(DataController.OnKey(key, relevant))
	end
end

return MachinesController

--!strict
--[[
	CatalogController: the "Catalog" panel. Permanent collection of product stamps per line,
	the total income bonus they give and the secret machines discovered so far.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Types = require(ReplicatedStorage.Shared.Types)

local DataController = require(script.Parent.DataController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CatalogController = {}

local PANEL = "Catalog"
local CELL_WIDTH = 0.32
local GOLD_STAMP = table.find(Config.Catalog.StampNames, "Gold") or 3
local RENDER_DEBOUNCE = 0.5
-- Display-only stamp tints, indexed like Config.Catalog.StampNames.
local STAMP_COLORS = {
	Color3.fromRGB(205, 127, 50),
	Color3.fromRGB(196, 202, 212),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(120, 225, 255),
}

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local renderQueued = false

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

local function renderSummary(body: Instance, order: number, stamps: { number })
	local earned, total = 0, #Config.Lines * #Config.Catalog.StampNames
	for _, s in stamps do
		earned += s
	end
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 3.4)
	UIKit.Label({
		Text = "Catalog bonus: +" .. NumberFormat.Percent(Formulas.CatalogBonus(stamps)) .. " income",
		Size = UDim2.fromScale(0.94, 0.28),
		Position = UDim2.fromScale(0.03, 0.06),
		Color = palette.Cash,
		MaxTextSize = 30,
		Parent = card,
	})
	UIKit.Label({
		Text = string.format("Stamps: %d / %d", earned, total),
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.18),
		Position = UDim2.fromScale(0.03, 0.36),
		MaxTextSize = 20,
		Parent = card,
	})
	local legend = {}
	for i, name in Config.Catalog.StampNames do
		table.insert(
			legend,
			string.format(
				"%s: Lv %d, +%s, %d Credits",
				name,
				Config.Catalog.Thresholds[i],
				NumberFormat.Percent(Config.Catalog.Bonus[i]),
				Config.Catalog.Credits[i]
			)
		)
	end
	UIKit.Label({
		Text = table.concat(legend, "   "),
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0.3),
		Position = UDim2.fromScale(0.03, 0.62),
		MaxTextSize = 15,
		Parent = card,
	})
end

local function renderHall(body: Instance, order: number, hallIndex: number, data: Types.PlayerData): number
	local hall = Config.Halls[hallIndex]
	local first = Formulas.HallFirstLine(hallIndex)
	local allGold = true
	for k = first, first + Config.LinesPerHall - 1 do
		if (data.Catalog.Stamps[k] or 0) < GOLD_STAMP then
			allGold = false
		end
	end
	local title = hall.Name
	if allGold then
		title ..= string.format("  (all Gold: +%s)", NumberFormat.Percent(Config.Catalog.HallGoldBonus))
	end
	heading(body, order, title, hall.Color)

	local grid = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order + 1,
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
	for k = first, first + Config.LinesPerHall - 1 do
		local line = Config.Lines[k]
		local owned = data.Lines[k] ~= nil
		local level = data.Catalog.Stamps[k] or 0
		local cell = UIKit.Card(grid, UDim2.fromScale(CELL_WIDTH, 0), if owned then nil else palette.UIBackground, k)
		UIKit.Aspect(cell, 1.5)
		UIKit.Label({
			Text = if owned then line.Name else "???",
			Size = UDim2.fromScale(0.94, 0.3),
			Position = UDim2.fromScale(0.03, 0.06),
			MaxTextSize = 20,
			Parent = cell,
		})
		UIKit.Label({
			Text = if level > 0 then Config.Catalog.StampNames[level] else (if owned then "No stamp yet" else "Locked"),
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.94, 0.2),
			Position = UDim2.fromScale(0.03, 0.38),
			Color = if level > 0 then STAMP_COLORS[level] else Color3.fromRGB(160, 163, 175),
			MaxTextSize = 14,
			Parent = cell,
		})
		local pips = UIKit.Create("Frame", {
			Size = UDim2.fromScale(0.92, 0.28),
			Position = UDim2.fromScale(0.04, 0.64),
			BackgroundTransparency = 1,
			Parent = cell,
		})
		UIKit.List(pips, 0.04, true)
		for s = 1, #Config.Catalog.StampNames do
			local pip = UIKit.Create("Frame", {
				Size = UDim2.fromScale(0.22, 1),
				BackgroundColor3 = if s <= level then STAMP_COLORS[s] else Color3.fromRGB(20, 20, 26),
				LayoutOrder = s,
				Parent = pips,
			})
			UIKit.Corner(pip, 0.3)
		end
	end
	return order + 1
end

local function renderSecrets(body: Instance, order: number, data: Types.PlayerData): number
	order += 1
	heading(body, order, "Secret machines", palette.UIAccent)
	for _, recipe in Config.SecretRecipes do
		order += 1
		local def = Formulas.GetMachine(recipe.MachineId)
		local found = data.Catalog.Secrets[recipe.MachineId] == true
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 6)
		UIKit.Label({
			Text = if found and def then def.Name else "???",
			Size = UDim2.fromScale(0.6, 0.5),
			Position = UDim2.fromScale(0.03, 0.08),
			Alignment = Enum.TextXAlignment.Left,
			Color = if found then palette.UIGood else palette.UIText,
			MaxTextSize = 24,
			Parent = card,
		})
		UIKit.Label({
			Text = if found and def
				then "+" .. NumberFormat.Short(def.Power) .. "% income"
				else "Discover it in the R&D Lab",
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.94, 0.34),
			Position = UDim2.fromScale(0.03, 0.58),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 16,
			Parent = card,
		})
	end
	return order
end

local function render()
	clear(panel.Body)
	local data = DataController.Get()
	if not data then
		return
	end
	local order = 1
	renderSummary(panel.Body, order, data.Catalog.Stamps)
	for hall = 1, #Config.Halls do
		order = renderHall(panel.Body, order + 1, hall, data)
	end
	order = renderSecrets(panel.Body, order, data)

	local seasonal = Config.Events.SeasonalLine
	if seasonal.Enabled then
		order += 1
		local card = UIKit.Card(panel.Body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 6)
		UIKit.Label({
			Text = "Seasonal product: " .. seasonal.Name,
			Size = UDim2.fromScale(0.94, 0.6),
			Position = UDim2.fromScale(0.03, 0.2),
			Alignment = Enum.TextXAlignment.Left,
			Color = palette.UIAccent,
			MaxTextSize = 24,
			Parent = card,
		})
	end
end

local function scheduleRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.delay(RENDER_DEBOUNCE, function()
		renderQueued = false
		if UIController.IsOpen(PANEL) then
			render()
		end
	end)
end

function CatalogController.Init()
	panel = UIKit.Panel(PANEL, "Product Catalog", UIController.GetLayer("Panels"), palette.UIGood)
	UIKit.List(panel.Body, 0.02)
	UIController.RegisterPanel(PANEL, { Root = panel.Root, OnOpen = render })
end

function CatalogController.Start()
	DataController.WaitForData()
	for _, key in { "Catalog", "Lines" } do
		maid:Add(DataController.OnKey(key, scheduleRender))
	end
end

return CatalogController

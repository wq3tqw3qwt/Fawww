--!strict
--[[
	FactoryController: the "Factory" panel. One card per owned line (4 stage upgrades, Overdrive),
	a build-next-line card, packaging per unlocked hall, vault upgrade and robot assignment.
	Structure is rebuilt only when the line/robot counts change; texts refresh at most 4x/s while open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local FactoryController = {}

local Palette = UIKit.Palette
local REFRESH_SECONDS = 0.25
local STAGES = #Config.Economy.StageNames
local GREY = Color3.fromRGB(80, 84, 100)
local BOTTLENECK_HEX = "#ff4a4a"

type StageRow = { Cell: Frame, Label: TextLabel, Button: TextButton }
type LineCard = {
	Card: Frame,
	Title: TextLabel,
	Stats: TextLabel,
	Stages: { StageRow },
	Overdrive: TextButton,
}
type RobotRow = { Card: Frame, Label: TextLabel, Button: TextButton }
type HallRow = { Card: Frame, Label: TextLabel, Button: TextButton }
type Ratio = { Constraint: UIAspectRatioConstraint, Wide: number, Tall: number }

local maid = Maid.new()
local openMaid = Maid.new()
local panel: UIKit.Panel? = nil
local bulkIndex = 1
local bulkButtons: { TextButton } = {}
local lineCards: { LineCard } = {}
local robotRows: { RobotRow } = {}
local hallRows: { HallRow } = {}
local ratios: { Ratio } = {}
local buildTitle: TextLabel? = nil
local buildInfo: TextLabel? = nil
local buildButton: TextButton? = nil
local vaultLabel: TextLabel? = nil
local vaultButton: TextButton? = nil
local robotHeader: Frame? = nil
local runtimeAt = 0
local isOpen = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function setText(label: any, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function setColor(button: GuiObject, color: Color3)
	if button.BackgroundColor3 ~= color then
		button.BackgroundColor3 = color
	end
end

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

-- Card whose height follows its width (Scale-only layout that is safe inside a scrolling list).
local function newCard(body: Instance, order: number, wide: number, tall: number): Frame
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	local constraint = UIKit.Aspect(card, wide)
	table.insert(ratios, { Constraint = constraint, Wide = wide, Tall = tall })
	applyRatios()
	return card
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------
local refresh: () -> ()

local function act(name: string, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local response = NotificationController.Request(name, table.unpack(args, 1, args.n))
		if response.Ok then
			SoundController.Play("Upgrade")
		end
		refresh()
	end)
end

local function nextRobotLine(data: any, robot: number): number
	local current = data.RobotAssignments[robot] or 0
	local taken: { [number]: boolean } = {}
	for index, line in data.RobotAssignments do
		if index ~= robot and line > 0 then
			taken[line] = true
		end
	end
	for candidate = current + 1, #data.Lines do
		if not taken[candidate] then
			return candidate
		end
	end
	return 0
end

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------
local function buildBulkCard(body: Instance)
	local card = newCard(body, 1, 5, 3)
	UIKit.Label({
		Text = "Buy",
		Size = UDim2.fromScale(0.16, 0.6),
		Position = UDim2.fromScale(0.02, 0.2),
		MaxTextSize = 26,
		Parent = card,
	})
	for index, option in Config.UI.BulkBuyOptions do
		local button = UIKit.Button({
			Text = if option == 0 then "MAX" else `x{option}`,
			Size = UDim2.fromScale(0.25, 0.7),
			Position = UDim2.fromScale(0.2 + (index - 1) * 0.27, 0.15),
			Parent = card,
			OnClick = function()
				bulkIndex = index
				refresh()
			end,
		})
		bulkButtons[index] = button
	end
end

local function buildLineCard(body: Instance, k: number): LineCard
	local hall = Config.Halls[Formulas.LineHall(k)]
	local card = newCard(body, 100 + k, 2.1, 1.2)
	local stripe = UIKit.Create("Frame", {
		Size = UDim2.fromScale(0.012, 0.9),
		Position = UDim2.fromScale(0.004, 0.05),
		BackgroundColor3 = hall.Color,
		Parent = card,
	})
	UIKit.Corner(stripe, 0.5)
	local title = UIKit.Label({
		Size = UDim2.fromScale(0.46, 0.2),
		Position = UDim2.fromScale(0.03, 0.02),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		Parent = card,
	})
	local stats = UIKit.Label({
		Size = UDim2.fromScale(0.5, 0.2),
		Position = UDim2.fromScale(0.48, 0.02),
		Alignment = Enum.TextXAlignment.Right,
		MaxTextSize = 22,
		Parent = card,
	})
	local stages: { StageRow } = {}
	for stage = 1, STAGES do
		local col, row = (stage - 1) % 2, (stage - 1) // 2
		local cell = UIKit.Create("Frame", {
			Name = "Stage" .. stage,
			Size = UDim2.fromScale(0.47, 0.27),
			Position = UDim2.fromScale(0.025 + col * 0.49, 0.25 + row * 0.29),
			BackgroundColor3 = Palette.UIBackground,
			Parent = card,
		})
		UIKit.Corner(cell, 0.15)
		local label = UIKit.Label({
			Size = UDim2.fromScale(0.48, 0.9),
			Position = UDim2.fromScale(0.02, 0.05),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 20,
			Parent = cell,
		})
		local button = UIKit.Button({
			Name = "Upgrade",
			Size = UDim2.fromScale(0.48, 0.84),
			Position = UDim2.fromScale(0.5, 0.08),
			Parent = cell,
			OnClick = function()
				act("UpgradeStage", k, stage, Config.UI.BulkBuyOptions[bulkIndex])
			end,
		})
		stages[stage] = { Cell = cell, Label = label, Button = button }
	end
	local overdrive = UIKit.Button({
		Name = "Overdrive",
		Size = UDim2.fromScale(0.95, 0.18),
		Position = UDim2.fromScale(0.025, 0.8),
		Parent = card,
		OnClick = function()
			act("Overdrive", k)
		end,
	})
	return { Card = card, Title = title, Stats = stats, Stages = stages, Overdrive = overdrive }
end

local function buildRobotRow(body: Instance, index: number): RobotRow
	local card = newCard(body, 1021 + index, 5, 3)
	local label = UIKit.Label({
		Size = UDim2.fromScale(0.62, 0.8),
		Position = UDim2.fromScale(0.03, 0.1),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = card,
	})
	local button = UIKit.Button({
		Text = "NEXT",
		Size = UDim2.fromScale(0.28, 0.7),
		Position = UDim2.fromScale(0.69, 0.15),
		Parent = card,
		OnClick = function()
			local data = DataController.Get()
			if data then
				act("AssignRobot", index, nextRobotLine(data, index))
			end
		end,
	})
	return { Card = card, Label = label, Button = button }
end

local function buildStaticCards(body: Instance)
	buildBulkCard(body)

	local card = newCard(body, 1000, 3.2, 1.8)
	buildTitle = UIKit.Label({
		Size = UDim2.fromScale(0.55, 0.45),
		Position = UDim2.fromScale(0.03, 0.08),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = card,
	})
	buildInfo = UIKit.Label({
		Size = UDim2.fromScale(0.55, 0.38),
		Position = UDim2.fromScale(0.03, 0.54),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Parent = card,
	})
	buildButton = UIKit.Button({
		Name = "BuildLine",
		Size = UDim2.fromScale(0.36, 0.7),
		Position = UDim2.fromScale(0.62, 0.15),
		Parent = card,
		OnClick = function()
			act("BuyLine")
		end,
	})

	for hall = 1, #Config.Halls do
		local row = newCard(body, 1001 + hall, 5, 3)
		local label = UIKit.Label({
			Size = UDim2.fromScale(0.58, 0.8),
			Position = UDim2.fromScale(0.03, 0.1),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 20,
			Parent = row,
		})
		local button = UIKit.Button({
			Size = UDim2.fromScale(0.34, 0.7),
			Position = UDim2.fromScale(0.63, 0.15),
			Parent = row,
			OnClick = function()
				act("BuyPackaging", hall)
			end,
		})
		hallRows[hall] = { Card = row, Label = label, Button = button }
	end

	local vault = newCard(body, 1010, 5, 3)
	vaultLabel = UIKit.Label({
		Size = UDim2.fromScale(0.58, 0.8),
		Position = UDim2.fromScale(0.03, 0.1),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = vault,
	})
	vaultButton = UIKit.Button({
		Size = UDim2.fromScale(0.34, 0.7),
		Position = UDim2.fromScale(0.63, 0.15),
		Parent = vault,
		OnClick = function()
			act("BuyVault")
		end,
	})

	local header = newCard(body, 1020, 8, 4)
	UIKit.Label({
		Text = "Robots",
		Size = UDim2.fromScale(0.9, 0.8),
		Position = UDim2.fromScale(0.05, 0.1),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = header,
	})
	robotHeader = header
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------
local function syncStructure(body: Instance, data: any)
	local lineCount = #data.Lines
	while #lineCards < lineCount do
		table.insert(lineCards, buildLineCard(body, #lineCards + 1))
	end
	while #lineCards > lineCount do
		local removed = table.remove(lineCards) :: LineCard
		removed.Card:Destroy()
	end
	local robotCount = #data.RobotAssignments
	while #robotRows < robotCount do
		table.insert(robotRows, buildRobotRow(body, #robotRows + 1))
	end
	while #robotRows > robotCount do
		local removed = table.remove(robotRows) :: RobotRow
		removed.Card:Destroy()
	end
	if robotHeader then
		robotHeader.Visible = robotCount > 0
	end
end

local function updateLine(data: any, runtime: any, k: number, discount: number)
	local view = lineCards[k]
	local levels: { number }? = data.Lines[k]
	if view == nil or levels == nil then
		return
	end
	local def = Config.Lines[k]
	local lineRuntime: any = if runtime and runtime.Lines then runtime.Lines[k] else nil
	local output = if lineRuntime then lineRuntime.Output else Formulas.LineOutput(levels)
	local multiplier = if runtime and runtime.Multiplier then runtime.Multiplier else 1
	local packaging = Formulas.PackagingBonus(data.Packaging[Formulas.LineHall(k)] or 1)
	local income = output * Formulas.LineValue(k) * (1 + packaging) * multiplier
	local robot = lineRuntime ~= nil and lineRuntime.Robot == true
	setText(view.Title, `{k}. {def.Name}{if robot then " 🤖" else ""}`)
	setText(view.Stats, `{NumberFormat.Short(output)}/s  <font color="#5ae66e">{NumberFormat.Cash(income)}/s</font>`)

	local bottleneck = Formulas.BottleneckStage(levels)
	local bulk = Config.UI.BulkBuyOptions[bulkIndex]
	for stage = 1, STAGES do
		local row = view.Stages[stage]
		local level = levels[stage]
		local isBottleneck = stage == bottleneck
		local text = `{Config.Economy.StageNames[stage]} Lv {NumberFormat.Short(level)}`
		if isBottleneck then
			text ..= `\n<font color="{BOTTLENECK_HEX}">BOTTLENECK</font>`
		end
		setText(row.Label, text)
		setColor(row.Cell, if isBottleneck then Color3.fromRGB(90, 30, 36) else Palette.UIBackground)
		if level >= Config.Economy.MaxStageLevel then
			setText(row.Button, "MAX")
			setColor(row.Button, GREY)
		else
			local count = if bulk == 0
				then math.max(1, Formulas.MaxAffordableLevels(k, stage, level, data.Cash, discount))
				else math.min(bulk, Config.Economy.MaxStageLevel - level)
			local cost = Formulas.BulkUpgradeCost(k, stage, level, count, discount)
			setText(row.Button, `+{count}  {NumberFormat.Cash(cost)}`)
			setColor(row.Button, if data.Cash >= cost then Palette.UIGood else GREY)
		end
	end

	local elapsed = os.clock() - runtimeAt
	local active = if lineRuntime then math.max(0, lineRuntime.OverdriveLeft - elapsed) else 0
	local cooldown = if lineRuntime then math.max(0, lineRuntime.CooldownLeft - elapsed) else 0
	if active > 0 then
		setText(view.Overdrive, `OVERDRIVE ×{Config.Overdrive.Multiplier}  {math.ceil(active)}s`)
		setColor(view.Overdrive, Palette.UIAccent)
	elseif cooldown > 0 then
		setText(view.Overdrive, `Overdrive ready in {math.ceil(cooldown)}s`)
		setColor(view.Overdrive, GREY)
	else
		setText(view.Overdrive, `OVERDRIVE ×{Config.Overdrive.Multiplier}`)
		setColor(view.Overdrive, Palette.UIGood)
	end
end

local function updateBuild(data: any)
	local title, info, button = buildTitle, buildInfo, buildButton
	if title == nil or info == nil or button == nil then
		return
	end
	local nextLine = #data.Lines + 1
	if nextLine > Formulas.LineCount() then
		setText(title, "All lines built!")
		setText(info, "Expand and Franchise to grow further")
		button.Visible = false
		return
	end
	button.Visible = true
	local def = Config.Lines[nextLine]
	local hall = Config.Halls[Formulas.LineHall(nextLine)]
	setText(title, `Build: {def.Name}`)
	if nextLine > Formulas.MaxLineForExpansions(data.Expansions) then
		setText(info, `🔒 Expand {hall.UnlockExpansions}x to unlock {hall.Name}`)
		setText(button, "LOCKED")
		setColor(button, GREY)
		return
	end
	local cost = Formulas.LineUnlockCost(nextLine)
	setText(info, `{hall.Name} · uses {def.Raw}`)
	setText(button, `BUILD {NumberFormat.Cash(cost)}`)
	setColor(button, if data.Cash >= cost then Palette.UIGood else GREY)
end

local function updatePackaging(data: any)
	local tierMax = #Config.Packaging.Bonus
	for hall, row in hallRows do
		local unlocked = Formulas.HallUnlocked(hall, data.Expansions)
		row.Card.Visible = unlocked
		if unlocked then
			local tier = data.Packaging[hall] or 1
			local bonus = math.floor(Formulas.PackagingBonus(tier) * 100)
			setText(row.Label, `{Config.Halls[hall].Name}: {Config.Packaging.Names[tier]} (+{bonus}%)`)
			if tier >= tierMax then
				setText(row.Button, "MAX")
				setColor(row.Button, GREY)
			else
				local cost = Formulas.PackagingCost(hall, tier + 1)
				setText(row.Button, NumberFormat.Cash(cost))
				setColor(row.Button, if data.Cash >= cost then Palette.UIGood else GREY)
			end
		end
	end
end

local function updateVault(data: any)
	local label, button = vaultLabel, vaultButton
	if label == nil or button == nil then
		return
	end
	local tierMax = #Config.Vault.CapacityMinutes
	local tier = data.VaultTier
	setText(label, `Vault tier {tier}/{tierMax}: {Config.Vault.CapacityMinutes[tier]} min of income`)
	if tier >= tierMax then
		setText(button, "MAX")
		setColor(button, GREY)
	else
		local cost = Formulas.VaultCost(tier + 1, Formulas.HighestHall(data.Expansions))
		setText(button, NumberFormat.Cash(cost))
		setColor(button, if data.Cash >= cost then Palette.UIGood else GREY)
	end
end

local function updateRobots(data: any)
	for index, row in robotRows do
		local line = data.RobotAssignments[index] or 0
		local def = Config.Lines[line]
		setText(row.Label, `🤖 Robot {index}: {if def then def.Name else "idle"}`)
		setColor(row.Button, Palette.UIAccent)
	end
end

refresh = function()
	local current = panel
	local data: any = DataController.Get()
	if data == nil or current == nil then
		return
	end
	local runtime: any = DataController.GetRuntime()
	local discount = if runtime and runtime.Discount then runtime.Discount else 0
	syncStructure(current.Body, data)
	for index, button in bulkButtons do
		setColor(button, if index == bulkIndex then Palette.UIGood else GREY)
	end
	for k = 1, #lineCards do
		updateLine(data, runtime, k, discount)
	end
	updateBuild(data)
	updatePackaging(data)
	updateVault(data)
	updateRobots(data)
end

--------------------------------------------------------------------------------
-- Public API (used by the tutorial)
--------------------------------------------------------------------------------
function FactoryController.GetUpgradeButton(line: number, stage: number): TextButton?
	local view = lineCards[line]
	if not isOpen or view == nil then
		return nil
	end
	local row = view.Stages[stage]
	return if row then row.Button else nil
end

function FactoryController.GetBuildButton(): TextButton?
	local button = buildButton
	return if isOpen and button and button.Visible then button else nil
end

function FactoryController.Start()
	local created = UIKit.Panel("Factory", "Factory", UIController.GetLayer("Panels"), Palette.UIAccent)
	panel = created
	UIKit.List(created.Body, 0.015)
	UIKit.Padding(created.Body, 0.01)
	maid:Add(created.Root)
	buildStaticCards(created.Body)

	UIController.RegisterPanel("Factory", {
		Root = created.Root,
		OnOpen = function()
			isOpen = true
			DataController.WaitForData()
			refresh()
			openMaid:Add(task.spawn(function()
				while true do
					task.wait(REFRESH_SECONDS)
					refresh()
				end
			end))
		end,
		OnClose = function()
			isOpen = false
			openMaid:Clean()
		end,
	})

	maid:Add(DataController.RuntimeChanged:Connect(function()
		runtimeAt = os.clock()
	end))
	local camera = workspace.CurrentCamera
	if camera then
		maid:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyRatios))
	end
end

return FactoryController

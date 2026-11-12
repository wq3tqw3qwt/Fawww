--!strict
--[[
	ResearchController: the "Research" panel (R&D Lab). Permanent upgrades on long timers, plus the
	Secret Recipe bench: pick three of your lines, the server checks the recipes deterministically.
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

local ResearchController = {}

local PANEL = "Research"
local CHIP_WIDTH = 0.235
local RECIPE_SIZE = #Config.SecretRecipes[1].Lines
local RENDER_DEBOUNCE = 0.5

-- Effect id -> UI text; %s receives the per-level value (percent or plain number).
local EFFECT_TEXT: { [string]: string } = {
	IncomeMult = "+%s income per level",
	OfflineHours = "+%s offline hour per level",
	ExtraBay = "+%s machine bay",
	ContractReward = "+%s contract rewards per level",
	UpgradeDiscount = "-%s upgrade cost per level",
}
local PERCENT_EFFECTS = { IncomeMult = true, ContractReward = true, UpgradeDiscount = true }

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local timers: { () -> () } = {}
local tickToken = 0
local renderQueued = false
local selected: { [number]: boolean } = {}
local activeWasDone = false

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

local function note(parent: Instance, order: number, text: string, ratio: number?): TextLabel
	local label = UIKit.Label({
		Text = text,
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(1, 0),
		Color = Color3.fromRGB(215, 218, 230),
		MaxTextSize = 18,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Aspect(label, ratio or 9)
	return label
end

local function effectText(def: Config.ResearchDef): string
	local template = EFFECT_TEXT[def.Effect] or "%s"
	local value = if PERCENT_EFFECTS[def.Effect]
		then NumberFormat.Percent(def.ValuePerLevel)
		else tostring(def.ValuePerLevel)
	return string.format(template, value)
end

local function researchById(id: string): Config.ResearchDef?
	for _, def in Config.Research do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function labRat(): number
	local runtime = DataController.GetRuntime()
	return if runtime and runtime.Abilities then runtime.Abilities.LabRat or 0 else 0
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------
local function renderActive(body: Instance, order: number, data: Types.PlayerData)
	local research = data.Research
	local def = if research.ActiveId ~= "" then researchById(research.ActiveId) else nil
	if not def then
		return
	end
	local done = serverNow() >= research.EndsAt
	activeWasDone = done
	local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
	UIKit.Aspect(card, 3.6)
	UIKit.Stroke(card, palette.Credits, 3)
	UIKit.Label({
		Text = string.format("In progress: %s → Lv %d", def.Name, (research.Levels[def.Id] or 0) + 1),
		Size = UDim2.fromScale(0.58, 0.36),
		Position = UDim2.fromScale(0.03, 0.08),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = card,
	})
	local timerLabel = UIKit.Label({
		Text = if done then "Finished!" else "",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.58, 0.3),
		Position = UDim2.fromScale(0.03, 0.55),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = card,
	})
	if done then
		UIKit.Button({
			Text = "Claim",
			Size = UDim2.fromScale(0.34, 0.6),
			Position = UDim2.fromScale(0.63, 0.2),
			Color = palette.UIGood,
			Parent = card,
			OnClick = function()
				local res = NotificationController.Request("ClaimResearch")
				if res.Ok then
					NotificationController.Toast("Reward", def.Name .. " upgraded!")
					SoundController.Play("Fanfare")
				end
			end,
		})
		return
	end
	local skip = Config.DevProducts.SkipResearch
	UIKit.Button({
		Text = "Finish now R$ " .. (if skip then NumberFormat.Commas(skip.Price) else "?"),
		Size = UDim2.fromScale(0.34, 0.6),
		Position = UDim2.fromScale(0.63, 0.2),
		Color = palette.UIAccent,
		MaxTextSize = 22,
		Parent = card,
		OnClick = function()
			NotificationController.Request("PromptProduct", "SkipResearch")
		end,
	})
	table.insert(timers, function()
		local left = research.EndsAt - serverNow()
		if left <= 0 then
			if not activeWasDone then
				ResearchController.Render()
			end
			return
		end
		timerLabel.Text = "Ready in " .. NumberFormat.Duration(left)
	end)
end

local function renderProjects(body: Instance, order: number, data: Types.PlayerData): number
	order += 1
	heading(body, order, "Projects")
	local busy = data.Research.ActiveId ~= ""
	for _, def in Config.Research do
		order += 1
		local level = data.Research.Levels[def.Id] or 0
		local maxed = level >= def.MaxLevel
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 3.8)
		UIKit.Label({
			Text = string.format("%s  Lv %d/%d", def.Name, level, def.MaxLevel),
			Size = UDim2.fromScale(0.6, 0.3),
			Position = UDim2.fromScale(0.03, 0.06),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 26,
			Parent = card,
		})
		UIKit.Label({
			Text = effectText(def),
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.6, 0.26),
			Position = UDim2.fromScale(0.03, 0.38),
			Alignment = Enum.TextXAlignment.Left,
			Color = palette.Cash,
			MaxTextSize = 18,
			Parent = card,
		})
		UIKit.Label({
			Text = if maxed
				then "Maxed out"
				else string.format("Takes %s", NumberFormat.Duration(Formulas.ResearchDuration(def, labRat()))),
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.6, 0.24),
			Position = UDim2.fromScale(0.03, 0.68),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 16,
			Parent = card,
		})
		if maxed then
			UIKit.Label({
				Text = "MAX",
				Size = UDim2.fromScale(0.34, 0.5),
				Position = UDim2.fromScale(0.63, 0.25),
				Color = palette.UIGood,
				Parent = card,
			})
		else
			local cost = Formulas.ResearchCost(def, level)
			local button = UIKit.Button({
				Text = "Start  " .. NumberFormat.Commas(cost) .. " Credits",
				Size = UDim2.fromScale(0.34, 0.6),
				Position = UDim2.fromScale(0.63, 0.2),
				Color = palette.UIPanel,
				MaxTextSize = 20,
				Parent = card,
				OnClick = function()
					if busy then
						NotificationController.Toast("Info", "Finish the running project first.")
						return
					end
					local res = NotificationController.Request("StartResearch", def.Id)
					if res.Ok then
						NotificationController.Toast("Success", def.Name .. " research started")
						SoundController.Play("Upgrade")
					end
				end,
			})
			table.insert(timers, function()
				local latest = DataController.Get()
				if latest then
					local ok = latest.Credits >= cost and not busy
					button.BackgroundColor3 = if ok then palette.UIGood else palette.UIPanel
				end
			end)
		end
	end
	return order
end

local function renderBench(body: Instance, order: number, data: Types.PlayerData): number
	order += 1
	heading(body, order, "Secret Recipe bench", palette.UIAccent)
	order += 1
	note(
		body,
		order,
		"Pick exactly "
			.. RECIPE_SIZE
			.. " of your product lines. The right combination at the right level discovers a secret machine. "
			.. "Always the same recipe, no luck involved.",
		4
	)

	order += 1
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
	local pickedCount = 0
	for _, on in selected do
		if on then
			pickedCount += 1
		end
	end
	for k, levels in data.Lines do
		local line = Config.Lines[k]
		if line then
			local on = selected[k] == true
			local chip = UIKit.Button({
				Text = string.format("%s\nLv %d", line.Name, Formulas.LineMinLevel(levels)),
				Size = UDim2.fromScale(CHIP_WIDTH, 0),
				LayoutOrder = k,
				Color = if on then palette.UIAccent else palette.UIPanel,
				TextColor = if on then Color3.new(0, 0, 0) else palette.UIText,
				MaxTextSize = 18,
				Parent = grid,
				OnClick = function()
					if not on and pickedCount >= RECIPE_SIZE then
						NotificationController.Toast(
							"Info",
							"Pick exactly " .. RECIPE_SIZE .. " lines. Tap one to deselect it first."
						)
						return
					end
					if on then
						selected[k] = nil
					else
						selected[k] = true
					end
					ResearchController.Render()
				end,
			})
			UIKit.Aspect(chip, 1.6)
		end
	end

	order += 1
	local try = UIKit.Button({
		Text = string.format("Try recipe (%d/%d picked)", pickedCount, RECIPE_SIZE),
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = order,
		Color = if pickedCount == RECIPE_SIZE then palette.UIGood else palette.UIPanel,
		Parent = body,
		OnClick = function()
			local lines = {}
			for k, on in selected do
				if on then
					table.insert(lines, k)
				end
			end
			if #lines ~= RECIPE_SIZE then
				NotificationController.Toast("Info", "Pick exactly " .. RECIPE_SIZE .. " lines first.")
				return
			end
			table.sort(lines)
			local res = NotificationController.Request("TrySecretRecipe", lines)
			if res.Ok then
				table.clear(selected)
				SoundController.Play("Fanfare")
				ResearchController.Render()
			end
		end,
	})
	UIKit.Aspect(try, 8)

	order += 1
	heading(body, order, "Secrets")
	for _, recipe in Config.SecretRecipes do
		order += 1
		local found = data.Catalog.Secrets[recipe.MachineId] == true
		local def = Formulas.GetMachine(recipe.MachineId)
		local card = UIKit.Card(body, UDim2.fromScale(1, 0), nil, order)
		UIKit.Aspect(card, 5)
		if found then
			local names = {}
			for _, k in recipe.Lines do
				table.insert(names, if Config.Lines[k] then Config.Lines[k].Name else "?")
			end
			UIKit.Label({
				Text = (if def then def.Name else recipe.MachineId) .. "  (discovered)",
				Size = UDim2.fromScale(0.94, 0.4),
				Position = UDim2.fromScale(0.03, 0.08),
				Alignment = Enum.TextXAlignment.Left,
				Color = palette.UIGood,
				MaxTextSize = 24,
				Parent = card,
			})
			UIKit.Label({
				Text = string.format("%s  •  Lv %d+", table.concat(names, " + "), recipe.MinLevel),
				Font = UIKit.BodyFont,
				Size = UDim2.fromScale(0.94, 0.38),
				Position = UDim2.fromScale(0.03, 0.54),
				Alignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				Parent = card,
			})
		else
			UIKit.Label({
				Text = "???",
				Size = UDim2.fromScale(0.94, 0.4),
				Position = UDim2.fromScale(0.03, 0.08),
				Alignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Parent = card,
			})
			UIKit.Label({
				Text = "Hint: " .. recipe.Hint,
				Font = UIKit.BodyFont,
				Size = UDim2.fromScale(0.94, 0.42),
				Position = UDim2.fromScale(0.03, 0.5),
				Alignment = Enum.TextXAlignment.Left,
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
function ResearchController.Render()
	tickToken += 1
	timers = {}
	clear(panel.Body)
	local data = DataController.Get()
	if not data then
		return
	end
	renderActive(panel.Body, 1, data)
	local order = renderProjects(panel.Body, 1, data)
	renderBench(panel.Body, order, data)

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
			ResearchController.Render()
		end
	end)
end

function ResearchController.Init()
	panel = UIKit.Panel(PANEL, "R&D Lab", UIController.GetLayer("Panels"), palette.Credits)
	UIKit.List(panel.Body, 0.02)
	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = ResearchController.Render,
		OnClose = function()
			tickToken += 1
		end,
	})
end

function ResearchController.Start()
	DataController.WaitForData()
	-- Lines changes on every upgrade, so rebuilds are debounced.
	for _, key in { "Research", "Catalog", "Lines" } do
		maid:Add(DataController.OnKey(key, scheduleRender))
	end
end

return ResearchController

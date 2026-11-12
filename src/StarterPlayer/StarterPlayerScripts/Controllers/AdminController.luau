--!strict
--[[
	AdminController: the "Admin" panel. Only usable when DataController.IsAdmin(); the server
	re-checks admin rights on every AdminCommand and strikes anyone else, so this UI is convenience only.
	Argument tables follow AdminService: {userId, amount}, {userId, machineId}, {kind, minutes, global}, ...
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local AdminController = {}

local PANEL = "Admin"
local EVENT_KINDS = { "Rush", "Weekend" }

type Field = {
	Key: string,
	Label: string,
	Kind: "number" | "text" | "choice" | "bool",
	Options: { string }?,
	Placeholder: string?,
}
type Command = { Cmd: string, Title: string, NeedsTarget: boolean, Fields: { Field }, Confirm: string? }

local COMMANDS: { Command } = {
	{
		Cmd = "GiveCash",
		Title = "Give cash",
		NeedsTarget = true,
		Fields = { { Key = "amount", Label = "Amount", Kind = "number", Placeholder = "1e6" } },
	},
	{
		Cmd = "GiveCredits",
		Title = "Give credits",
		NeedsTarget = true,
		Fields = { { Key = "amount", Label = "Amount", Kind = "number", Placeholder = "100" } },
	},
	{
		Cmd = "GiveMachine",
		Title = "Give machine",
		NeedsTarget = true,
		Fields = { { Key = "machineId", Label = "Machine id", Kind = "text", Placeholder = "rivet_bot" } },
	},
	{
		Cmd = "SetExpansions",
		Title = "Set expansions",
		NeedsTarget = true,
		Fields = { { Key = "count", Label = "Count", Kind = "number", Placeholder = "0" } },
	},
	{
		Cmd = "ForceEvent",
		Title = "Force event",
		NeedsTarget = false,
		Fields = {
			{ Key = "kind", Label = "Event", Kind = "choice", Options = EVENT_KINDS },
			{ Key = "minutes", Label = "Minutes", Kind = "number", Placeholder = "15" },
			{ Key = "global", Label = "All servers", Kind = "bool" },
		},
	},
	{
		Cmd = "Ban",
		Title = "Ban (0 minutes = permanent)",
		NeedsTarget = true,
		Confirm = "Ban this player?",
		Fields = {
			{ Key = "minutes", Label = "Minutes", Kind = "number", Placeholder = "0" },
			{ Key = "reason", Label = "Reason", Kind = "text", Placeholder = "Exploiting" },
		},
	},
	{ Cmd = "Unban", Title = "Unban", NeedsTarget = true, Fields = {} },
	{
		Cmd = "Kick",
		Title = "Kick",
		NeedsTarget = true,
		Confirm = "Kick this player?",
		Fields = { { Key = "reason", Label = "Reason", Kind = "text", Placeholder = "Reason" } },
	},
	{
		Cmd = "Announce",
		Title = "Announce",
		NeedsTarget = false,
		Fields = {
			{ Key = "text", Label = "Message", Kind = "text", Placeholder = "Hello!" },
			{ Key = "global", Label = "All servers", Kind = "bool" },
		},
	},
	{ Cmd = "ResetTutorial", Title = "Reset tutorial", NeedsTarget = true, Fields = {} },
}

local palette = UIKit.Palette
local maid = Maid.new()
local panel: UIKit.Panel
local targetBox: TextBox
local targetLabel: TextLabel
local playersFrame: Frame
local metricsFrame: Frame
local selectedUserId: number? = nil
local lastMetrics: any = nil

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
		Size = UDim2.fromScale(0.94, 0),
		Alignment = Enum.TextXAlignment.Left,
		Color = color,
		MaxTextSize = 26,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Aspect(label, 12)
	return label
end

local function textBox(parent: Instance, placeholder: string?, size: UDim2, position: UDim2): TextBox
	local holder = UIKit.Create("Frame", {
		Size = size,
		Position = position,
		BackgroundColor3 = palette.UIBackground,
		Parent = parent,
	})
	UIKit.Corner(holder, 0.2)
	local box = UIKit.Create("TextBox", {
		Size = UDim2.fromScale(0.94, 0.8),
		Position = UDim2.fromScale(0.03, 0.1),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = Color3.fromRGB(150, 153, 165),
		TextColor3 = palette.UIText,
		Font = UIKit.BodyFont,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = holder,
	})
	UIKit.Create("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 8, Parent = box })
	return box
end

-- Typed UserId wins over the picked player.
local function currentTarget(): number?
	local typed = tonumber(targetBox.Text)
	if typed and typed >= 1 and typed == math.floor(typed) then
		return typed
	end
	return selectedUserId
end

local function updateTargetLabel()
	local id = currentTarget()
	local name = if id then Players:GetPlayerByUserId(id) :: Player? else nil
	targetLabel.Text = if id
		then "Target: " .. (if name then name.DisplayName .. " " else "") .. "(" .. id .. ")"
		else "Target: none (pick a player or type a UserId)"
end

local function renderPlayers()
	clear(playersFrame)
	for i, player in Players:GetPlayers() do
		local on = selectedUserId == player.UserId
		local chip = UIKit.Button({
			Text = player.DisplayName,
			Size = UDim2.fromScale(0.3, 0),
			LayoutOrder = i,
			Color = if on then palette.UIAccent else palette.UIPanel,
			TextColor = if on then Color3.new(0, 0, 0) else palette.UIText,
			MaxTextSize = 18,
			Parent = playersFrame,
			OnClick = function()
				selectedUserId = player.UserId
				targetBox.Text = ""
				renderPlayers()
				updateTargetLabel()
			end,
		})
		UIKit.Aspect(chip, 2.4)
	end
end

--------------------------------------------------------------------------------
-- Metrics
--------------------------------------------------------------------------------
local function renderMetrics(metrics: any)
	clear(metricsFrame)
	if type(metrics) ~= "table" then
		return
	end
	local order = 0
	local function addLine(text: string, color: Color3?, ratio: number?)
		order += 1
		local label = UIKit.Label({
			Text = text,
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(0.94, 0),
			Alignment = Enum.TextXAlignment.Left,
			Color = color,
			MaxTextSize = 16,
			LayoutOrder = order,
			Parent = metricsFrame,
		})
		UIKit.Aspect(label, ratio or 18)
	end

	local event = metrics.Event or {}
	local goal = metrics.GlobalGoal or {}
	addLine(
		string.format(
			"Players %d/%d  •  Uptime %s  •  Memory %d MB  •  v%s",
			metrics.PlayerCount or 0,
			metrics.MaxPlayers or 0,
			NumberFormat.Duration(metrics.UptimeSeconds or 0),
			math.floor(metrics.MemoryMb or 0),
			tostring(metrics.PlaceVersion or "?")
		),
		palette.UIText,
		14
	)
	addLine(
		string.format(
			"Rush: %s  •  Weekend: %s  •  Community goal: %s contracts (%s)",
			if event.RushActive then "ON" else "off",
			if event.WeekendActive then "ON" else "off",
			NumberFormat.Commas(goal.Total or 0),
			tostring(goal.WeekKey or "?")
		),
		palette.UIAccent,
		14
	)
	addLine("Server " .. tostring(metrics.JobId or "?"), Color3.fromRGB(150, 153, 165), 20)

	for _, row in metrics.Players or {} do
		order += 1
		local button = UIKit.Button({
			Text = string.format(
				"%s  %s/s  %s  %s Cr  Exp %d  F%d  R$%s  %s",
				tostring(row.Name),
				NumberFormat.Short(row.Income or 0),
				NumberFormat.Cash(row.Cash or 0),
				NumberFormat.Short(row.Credits or 0),
				row.Expansions or 0,
				row.Franchise or 0,
				NumberFormat.Commas(row.RobuxSpent or 0),
				NumberFormat.Duration(row.PlaySeconds or 0)
			),
			Size = UDim2.fromScale(0.94, 0),
			LayoutOrder = order,
			Color = palette.UIPanel,
			MaxTextSize = 16,
			Parent = metricsFrame,
			OnClick = function()
				selectedUserId = row.UserId
				targetBox.Text = ""
				renderPlayers()
				updateTargetLabel()
			end,
		})
		UIKit.Aspect(button, 14)
	end

	addLine("Exploit log (latest last)", palette.UIBad, 16)
	for _, entry in metrics.ExploitLog or {} do
		addLine(
			string.format(
				"[%s] %s  user %s  %s",
				os.date("!%H:%M:%S", tonumber(entry.Time) or 0),
				tostring(entry.Kind),
				tostring(entry.UserId),
				tostring(entry.Details or "")
			),
			nil,
			22
		)
	end
end

local function refreshMetrics()
	local res = Net.Request("AdminCommand", "Metrics", {})
	if res.Ok then
		lastMetrics = res.Data
		renderMetrics(lastMetrics)
	end
end

--------------------------------------------------------------------------------
-- Command forms
--------------------------------------------------------------------------------
local function buildForm(parent: Instance, order: number, command: Command)
	local card = UIKit.Card(parent, UDim2.fromScale(1, 0), nil, order)
	card.AutomaticSize = Enum.AutomaticSize.Y
	UIKit.List(card, 0.015)
	heading(card, 0, command.Title, palette.UIAccent)

	local readers: { { Field: Field, Read: () -> any } } = {}
	for i, field in command.Fields do
		local row = UIKit.Create("Frame", {
			Size = UDim2.fromScale(0.94, 0),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = card,
		})
		UIKit.Aspect(row, 9)
		if field.Kind == "number" or field.Kind == "text" then
			UIKit.Label({
				Text = field.Label,
				Font = UIKit.BodyFont,
				Size = UDim2.fromScale(0.3, 0.8),
				Position = UDim2.fromScale(0, 0.1),
				Alignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				Parent = row,
			})
			local box = textBox(row, field.Placeholder, UDim2.fromScale(0.68, 1), UDim2.fromScale(0.32, 0))
			table.insert(readers, {
				Field = field,
				Read = function()
					if field.Kind == "number" then
						return tonumber(box.Text)
					end
					local text = string.gsub(box.Text, "^%s+", "")
					text = string.sub(text, 1, Config.Admin.Limits.MaxTextLength)
					return if text == "" then nil else text
				end,
			})
		elseif field.Kind == "choice" then
			local options = field.Options or {}
			local index = 1
			local button = UIKit.Button({
				Text = field.Label .. ": " .. (options[1] or "?"),
				Size = UDim2.fromScale(1, 1),
				Color = palette.UIPanel,
				MaxTextSize = 20,
				Parent = row,
			})
			button.Activated:Connect(function()
				index = index % #options + 1
				button.Text = field.Label .. ": " .. options[index]
			end)
			table.insert(readers, {
				Field = field,
				Read = function()
					return options[index]
				end,
			})
		else
			local on = false
			local button = UIKit.Button({
				Text = field.Label .. ": OFF",
				Size = UDim2.fromScale(1, 1),
				Color = palette.UIPanel,
				MaxTextSize = 20,
				Parent = row,
			})
			button.Activated:Connect(function()
				on = not on
				button.Text = field.Label .. ": " .. (if on then "ON" else "OFF")
				button.BackgroundColor3 = if on then palette.UIGood else palette.UIPanel
			end)
			table.insert(readers, {
				Field = field,
				Read = function()
					return on
				end,
			})
		end
	end

	local function execute(args: { [string]: any })
		local res = NotificationController.Request("AdminCommand", command.Cmd, args)
		if res.Ok then
			NotificationController.Toast("Success", command.Cmd .. " done")
			SoundController.Play("Upgrade")
		else
			SoundController.Play("Error")
		end
	end

	local run = UIKit.Button({
		Text = "Run",
		Size = UDim2.fromScale(0.94, 0),
		LayoutOrder = #command.Fields + 1,
		Color = palette.UIGood,
		Parent = card,
		OnClick = function()
			local args: { [string]: any } = {}
			if command.NeedsTarget then
				local target = currentTarget()
				if not target then
					NotificationController.Toast("Error", "Pick a target player or type a UserId first.")
					return
				end
				args.userId = target
			end
			for _, reader in readers do
				local value = reader.Read()
				if value == nil then
					NotificationController.Toast("Error", "Fill in: " .. reader.Field.Label)
					return
				end
				args[reader.Field.Key] = value
			end
			if command.Confirm then
				UIController.Confirm(command.Confirm, function()
					execute(args)
				end, "Do it")
			else
				execute(args)
			end
		end,
	})
	UIKit.Aspect(run, 9)
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------
function AdminController.Init()
	panel = UIKit.Panel(PANEL, "Admin", UIController.GetLayer("Panels"), palette.UIBad)
	UIKit.List(panel.Body, 0.02)
	local body = panel.Body

	heading(body, 1, "Target", palette.UIAccent)
	targetLabel = UIKit.Label({
		Text = "",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.94, 0),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		LayoutOrder = 2,
		Parent = body,
	})
	UIKit.Aspect(targetLabel, 16)

	playersFrame = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = body,
	})
	UIKit.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Wraps = true,
		Padding = UDim.new(0.015, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = playersFrame,
	})

	local typedRow = UIKit.Create("Frame", {
		Size = UDim2.fromScale(0.94, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = body,
	})
	UIKit.Aspect(typedRow, 9)
	UIKit.Label({
		Text = "UserId",
		Font = UIKit.BodyFont,
		Size = UDim2.fromScale(0.3, 0.8),
		Position = UDim2.fromScale(0, 0.1),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Parent = typedRow,
	})
	targetBox =
		textBox(typedRow, "Type a UserId (overrides the pick)", UDim2.fromScale(0.68, 1), UDim2.fromScale(0.32, 0))
	targetBox:GetPropertyChangedSignal("Text"):Connect(updateTargetLabel)

	local order = 5
	for _, command in COMMANDS do
		order += 1
		buildForm(body, order, command)
	end

	order += 1
	local refresh = UIKit.Button({
		Text = "Refresh metrics",
		Size = UDim2.fromScale(0.94, 0),
		LayoutOrder = order,
		Color = palette.UIAccent,
		Parent = body,
		OnClick = function()
			task.spawn(refreshMetrics)
		end,
	})
	UIKit.Aspect(refresh, 9)
	order += 1
	metricsFrame = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = body,
	})
	UIKit.List(metricsFrame, 0.008)

	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = function()
			if not DataController.IsAdmin() then
				NotificationController.Toast("Error", "Not allowed")
				UIController.Close(PANEL)
				return
			end
			renderPlayers()
			updateTargetLabel()
			renderMetrics(lastMetrics or DataController.GetAdminMetrics())
			refreshMetrics()
		end,
	})
end

function AdminController.Start()
	maid:Add(Net.Event("AdminData").OnClientEvent:Connect(function(metrics: any)
		if type(metrics) == "table" then
			lastMetrics = metrics
			if UIController.IsOpen(PANEL) then
				renderMetrics(metrics)
			end
		end
	end))
	local function playersChanged()
		if UIController.IsOpen(PANEL) then
			renderPlayers()
			updateTargetLabel()
		end
	end
	maid:Add(Players.PlayerAdded:Connect(playersChanged))
	maid:Add(Players.PlayerRemoving:Connect(function()
		task.defer(playersChanged)
	end))
	maid:Add(DataController.AdminChanged:Connect(function(isAdmin: boolean)
		if not isAdmin then
			UIController.Close(PANEL)
		end
	end))
end

return AdminController

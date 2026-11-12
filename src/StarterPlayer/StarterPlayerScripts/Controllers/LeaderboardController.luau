--!strict
--[[
	LeaderboardController: the "Leaderboards" panel. Reads the server's cached boards via
	GetLeaderboards; huge idle numbers arrive already formatted (Display), log-encoded server side.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local NotificationController = require(script.Parent.NotificationController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local LeaderboardController = {}

local PANEL = "Leaderboards"
local REFRESH_SECONDS = 60
local RANK_COLORS = {
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(196, 202, 212),
	Color3.fromRGB(205, 127, 50),
}

local palette = UIKit.Palette
local panel: UIKit.Panel
local tabButtons: { [string]: TextButton } = {}
local currentKey: string = Config.Leaderboards.Boards[1].Key
local boards: { [string]: any } = {}
local loaded = false
local pollToken = 0

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function render()
	clear(panel.Body)
	for key, button in tabButtons do
		button.BackgroundColor3 = if key == currentKey then palette.UIAccent else palette.UIPanel
	end
	local board = boards[currentKey]
	local order = 1
	local title = UIKit.Label({
		Text = if board and board.Title then board.Title else "Leaderboard",
		Size = UDim2.fromScale(1, 0),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		LayoutOrder = order,
		Parent = panel.Body,
	})
	UIKit.Aspect(title, 12)

	local entries: { any } = if board and board.Entries then board.Entries else {}
	if #entries == 0 then
		order += 1
		local empty = UIKit.Label({
			Text = if loaded then "No entries yet. Be the first!" else "Loading…",
			Font = UIKit.BodyFont,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = order,
			MaxTextSize = 22,
			Parent = panel.Body,
		})
		UIKit.Aspect(empty, 8)
		return
	end

	local me = Players.LocalPlayer.UserId
	for _, entry in entries do
		order += 1
		local mine = entry.UserId == me
		local card = UIKit.Card(
			panel.Body,
			UDim2.fromScale(1, 0),
			if mine then palette.UIAccent:Lerp(Color3.new(0, 0, 0), 0.5) else nil,
			order
		)
		UIKit.Aspect(card, 9)
		if mine then
			UIKit.Stroke(card, palette.UIAccent, 3)
		end
		UIKit.Label({
			Text = "#" .. tostring(entry.Rank),
			Size = UDim2.fromScale(0.14, 0.7),
			Position = UDim2.fromScale(0.02, 0.15),
			Color = RANK_COLORS[entry.Rank] or palette.UIText,
			MaxTextSize = 26,
			Parent = card,
		})
		UIKit.Label({
			Text = tostring(entry.Name) .. (if mine then "  (you)" else ""),
			Size = UDim2.fromScale(0.52, 0.7),
			Position = UDim2.fromScale(0.17, 0.15),
			Alignment = Enum.TextXAlignment.Left,
			MaxTextSize = 24,
			Parent = card,
		})
		UIKit.Label({
			Text = tostring(entry.Display),
			Size = UDim2.fromScale(0.27, 0.7),
			Position = UDim2.fromScale(0.71, 0.15),
			Alignment = Enum.TextXAlignment.Right,
			Color = palette.Cash,
			MaxTextSize = 24,
			Parent = card,
		})
	end
end

local function fetch()
	local res = Net.Request("GetLeaderboards")
	if res.Ok and type(res.Data) == "table" then
		boards = res.Data
		loaded = true
		if UIController.IsOpen(PANEL) then
			render()
		end
	elseif not res.Ok then
		NotificationController.Toast("Error", res.Error or "Could not load leaderboards")
	end
end

function LeaderboardController.Init()
	panel = UIKit.Panel(PANEL, "Leaderboards", UIController.GetLayer("Panels"), palette.UIAccent)

	local bar = UIKit.Create("Frame", {
		Name = "Tabs",
		Size = UDim2.fromScale(0.96, 0.08),
		Position = UDim2.fromScale(0.02, 0.135),
		BackgroundTransparency = 1,
		Parent = panel.Root,
	})
	UIKit.List(bar, 0.01, true)
	local count = #Config.Leaderboards.Boards
	for i, board in Config.Leaderboards.Boards do
		tabButtons[board.Key] = UIKit.Button({
			Text = board.Key,
			Size = UDim2.fromScale(1 / count - 0.01, 1),
			LayoutOrder = i,
			Parent = bar,
			OnClick = function()
				currentKey = board.Key
				render()
			end,
		})
	end
	panel.Body.Size = UDim2.fromScale(0.96, 0.75)
	panel.Body.Position = UDim2.fromScale(0.02, 0.23)
	UIKit.List(panel.Body, 0.015)

	UIController.RegisterPanel(PANEL, {
		Root = panel.Root,
		OnOpen = function()
			render()
			pollToken += 1
			local token = pollToken
			task.spawn(function()
				while pollToken == token and UIController.IsOpen(PANEL) do
					fetch()
					task.wait(REFRESH_SECONDS)
				end
			end)
		end,
		OnClose = function()
			pollToken += 1
		end,
	})
end

return LeaderboardController

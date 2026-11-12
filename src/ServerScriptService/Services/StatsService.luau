--!strict
--[[
	StatsService (L2): persistent counters plus the leaderstats shown on the player list.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local ServerSignals = require(script.Parent.Parent.Server.ServerSignals)
local DataService = require(script.Parent.DataService)

local StatsService = {}

function StatsService.Increment(player: Player, key: string, amount: number)
	local data = DataService.Get(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount == 0 then
		return
	end
	local stats = data.Stats :: { [string]: number }
	if stats[key] == nil then
		return
	end
	stats[key] = Formulas.Clamp(stats[key] + amount)
	DataService.MarkDirty(player, "Stats")
	ServerSignals.StatChanged:Fire(player, key, amount)
end

local function industryText(data: any): string
	local hall = Config.Halls[Formulas.HighestHall(data.Expansions)]
	local text = string.format("E%d · %s", data.Expansions, hall.Name)
	if data.Franchise > 0 then
		text = string.format("F%d %s", data.Franchise, text)
	end
	return text
end

local function stringValue(folder: Folder, name: string): StringValue
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("StringValue") then
		return existing
	end
	local value = Instance.new("StringValue")
	value.Name = name
	value.Parent = folder
	return value
end

local function refreshLeaderstats(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local folder = player:FindFirstChild("leaderstats")
	if not folder or not folder:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "leaderstats"
		created.Parent = player
		folder = created
	end
	stringValue(folder :: Folder, "Cash").Value = NumberFormat.Cash(data.Cash)
	stringValue(folder :: Folder, "Industry").Value = industryText(data)
end

function StatsService.Init() end

function StatsService.Start()
	DataService.Loaded:Connect(function(player: Player)
		refreshLeaderstats(player)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Data.LeaderstatsRefreshSeconds)
			for _, player in Players:GetPlayers() do
				pcall(refreshLeaderstats, player)
			end
		end
	end)
end

return StatsService

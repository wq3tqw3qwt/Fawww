--!strict
--[[
	LeaderboardService (L5): global leaderboards on OrderedDataStores.
	Huge idle numbers are stored as floor(log10(x + 1) * LogScale) so they fit in an integer
	(Formulas.EncodeLog / DecodeLog). The weekly board uses a store per ISO week.
	Results are cached, served through GetLeaderboards and drawn on the plaza boards.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Remote = require(script.Parent.Parent.Server.Remote)
local Retry = require(script.Parent.Parent.Server.Retry)
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

type PlayerData = Types.PlayerData
type BoardDef = {
	Key: string,
	Title: string,
	Store: string,
	Stat: string,
	Encoding: string,
	Weekly: boolean?,
}

export type Entry = {
	Rank: number,
	UserId: number,
	Name: string,
	Value: number,
	Display: string,
}
export type BoardView = { Title: string, Entries: { Entry } }

local cache: { [string]: BoardView } = {}
local nameCache: { [number]: string } = {}
local started = false

local function storeName(board: BoardDef): string
	if board.Weekly then
		return board.Store .. "_" .. Formulas.WeekKey(os.time())
	end
	return board.Store
end

-- Raw stat value for a board, or nil when this player has nothing to submit.
local function statValue(board: BoardDef, data: PlayerData): number?
	local value: number
	if board.Stat == "IndustryScore" then
		value = data.Franchise * Config.Leaderboards.IndustryFranchiseWeight + data.Expansions
	elseif board.Stat == "WeeklyEarnings" then
		if data.WeeklyKey ~= Formulas.WeekKey(os.time()) then
			return nil
		end
		value = data.WeeklyEarnings
	elseif board.Stat == "TotalEarnings" then
		value = data.TotalEarnings
	elseif board.Stat == "ProductsShipped" then
		value = data.Stats.ProductsShipped
	else
		return nil
	end
	if value ~= value or value <= 0 then
		return nil
	end
	return value
end

local function encode(board: BoardDef, value: number): number
	if board.Encoding == "Log" then
		return Formulas.EncodeLog(value)
	end
	return math.floor(value)
end

local function decode(board: BoardDef, stored: number): number
	if board.Encoding == "Log" then
		return Formulas.DecodeLog(stored)
	end
	return stored
end

local function display(board: BoardDef, value: number): string
	if board.Stat == "IndustryScore" then
		local weight = Config.Leaderboards.IndustryFranchiseWeight
		return string.format("F%d E%d", math.floor(value / weight), value % weight)
	end
	return NumberFormat.Short(value)
end

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------
local function writePlayer(player: Player, data: PlayerData)
	for _, board in Config.Leaderboards.Boards :: { BoardDef } do
		local value = statValue(board, data)
		if value then
			local encoded = encode(board, value)
			local store = DataStoreService:GetOrderedDataStore(storeName(board))
			-- Keep the best value so a stale or reset stat can never lower a rank.
			Retry.Call("LeaderboardWrite." .. board.Key, function()
				store:UpdateAsync(tostring(player.UserId), function(old: any): any
					if type(old) == "number" and old >= encoded then
						return nil
					end
					return encoded
				end)
			end)
		end
	end
end

local function writeAll()
	for _, player in DataService.GetLoadedPlayers() do
		local data = DataService.Get(player)
		if data and player.Parent == Players then
			writePlayer(player, data)
		end
	end
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------
local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		nameCache[userId] = inServer.Name
		return inServer.Name
	end
	local ok, name = Retry.Call("GetNameFromUserIdAsync", function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return "Player " .. tostring(userId)
end

local function readBoard(board: BoardDef): BoardView?
	local store = DataStoreService:GetOrderedDataStore(storeName(board))
	local ok, pages = Retry.Call("LeaderboardRead." .. board.Key, function(): any
		return store:GetSortedAsync(false, Config.Leaderboards.TopN)
	end)
	if not ok then
		return nil
	end
	local entries: { Entry } = {}
	for rank, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" then
			local value = decode(board, item.value)
			table.insert(entries, {
				Rank = rank,
				UserId = userId,
				Name = resolveName(userId),
				Value = value,
				Display = display(board, value),
			})
		end
	end
	return { Title = board.Title, Entries = entries }
end

--------------------------------------------------------------------------------
-- Physical plaza boards (built by the world builder; optional)
--------------------------------------------------------------------------------
local function findBoardGui(key: string): SurfaceGui?
	local plaza = workspace:FindFirstChild("Plaza")
	local folder = plaza and plaza:FindFirstChild("Leaderboards")
	local board = folder and folder:FindFirstChild("Board_" .. key)
	local gui = board and board:FindFirstChild("Board", true)
	if gui and gui:IsA("SurfaceGui") then
		return gui
	end
	return nil
end

local function makeLabel(parent: Instance, name: string, text: string, y: number, height: number, bold: boolean)
	local palette = Config.Visuals.Palette
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, y)
	label.Size = UDim2.fromScale(0.92, height)
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.TextColor3 = if bold then palette.UIAccent else palette.UIText
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
end

local function fillPhysicalBoard(key: string, view: BoardView)
	local gui = findBoardGui(key)
	if not gui then
		return
	end
	for _, child in gui:GetChildren() do
		if child:IsA("TextLabel") and child.Name:sub(1, 3) == "LB_" then
			child:Destroy()
		end
	end
	local rows = Config.Leaderboards.PhysicalRows
	local rowHeight = 1 / (rows + 1)
	makeLabel(gui, "LB_Title", view.Title, 0, rowHeight * 0.9, true)
	for i = 1, math.min(rows, #view.Entries) do
		local entry = view.Entries[i]
		makeLabel(
			gui,
			"LB_Row" .. i,
			string.format("#%d  %s  -  %s", entry.Rank, entry.Name, entry.Display),
			i * rowHeight,
			rowHeight * 0.9,
			false
		)
	end
end

local function refreshAll()
	for _, board in Config.Leaderboards.Boards :: { BoardDef } do
		local view = readBoard(board)
		if view then
			cache[board.Key] = view
		end
		local current = cache[board.Key]
		if current then
			fillPhysicalBoard(board.Key, current)
		end
	end
end

function LeaderboardService.GetBoards(): { [string]: BoardView }
	return cache
end

function LeaderboardService.Refresh()
	refreshAll()
end

function LeaderboardService.Init()
	Remote.Handle("GetLeaderboards", function(_player)
		return true, nil, cache
	end, { AllowBeforeLoad = true })
end

function LeaderboardService.Start()
	if started then
		return
	end
	started = true
	for _, board in Config.Leaderboards.Boards :: { BoardDef } do
		cache[board.Key] = { Title = board.Title, Entries = {} }
	end

	task.spawn(function()
		while true do
			refreshAll()
			task.wait(Config.Leaderboards.RefreshSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Leaderboards.WriteSeconds)
			writeAll()
		end
	end)
	-- Final write so short sessions and the last weekly progress count.
	DataService.Releasing:Connect(function(player: Player, data: PlayerData)
		task.spawn(writePlayer, player, data)
	end)
end

return LeaderboardService

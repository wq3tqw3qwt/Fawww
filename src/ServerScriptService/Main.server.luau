--!strict
--[[
	Main: boots the server. Order matters (it is the layer order in docs/03-architecture.md):
	remotes are created first, every service gets Init() (no yielding), then Start() in its own thread.
	A service that fails to load or initialize is reported but never stops the others.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local protect: (...any) -> (boolean, any) = pcall :: any

type Service = {
	Init: (() -> ())?,
	Start: (() -> ())?,
	[string]: any,
}

local SERVICE_ORDER = {
	"AntiExploitService",
	"DataService",
	"CurrencyService",
	"StatsService",
	"PassService",
	"EventService",
	"PlotService",
	"SocialBonusService",
	"MultiplierService",
	"FactoryService",
	"ExpansionService",
	"OfflineEarningsService",
	"TutorialService",
	"MachineService",
	"ContractService",
	"ResearchService",
	"QuestService",
	"DailyRewardService",
	"CodeService",
	"LeaderboardService",
	"TradeService",
	"ShopService",
	"AdminService",
}

Net.Setup()

local servicesFolder = script.Parent:WaitForChild("Services")
local loaded: { [string]: Service } = {}
local ordered: { string } = {}

for _, name in SERVICE_ORDER do
	local module = servicesFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(string.format("[Main] service %s is missing", name))
		continue
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		loaded[name] = result :: Service
		table.insert(ordered, name)
	else
		warn(string.format("[Main] service %s failed to load: %s", name, tostring(result)))
	end
end

local antiExploit = loaded.AntiExploitService
local dataService = loaded.DataService
local Remote = require(script.Parent.Server.Remote)
Remote.Configure(function(player: Player, remoteName: string): boolean
	if antiExploit and antiExploit.CheckRate then
		return antiExploit.CheckRate(player, remoteName)
	end
	return true
end, function(player: Player): boolean
	-- Fail closed: without DataService nothing can be authoritative.
	if dataService and dataService.IsLoaded then
		return dataService.IsLoaded(player)
	end
	return false
end)

for _, name in ordered do
	local init = loaded[name].Init
	if init then
		local ok, err = protect(init)
		if not ok then
			warn(string.format("[Main] %s.Init failed: %s", name, tostring(err)))
		end
	end
end

for _, name in ordered do
	local start = loaded[name].Start
	if start then
		task.spawn(function()
			local ok, err = protect(start)
			if not ok then
				warn(string.format("[Main] %s.Start failed: %s", name, tostring(err)))
			end
		end)
	end
end

print(string.format("[Main] %d/%d services running", #ordered, #SERVICE_ORDER))

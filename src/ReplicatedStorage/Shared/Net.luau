--!strict
--[[
	Net: the complete list of remotes. The server creates them under
	ReplicatedStorage.Remotes on startup (Net.Setup); clients wait for them.

	Client -> server calls are RemoteFunctions that always return a Types.Response
	({ Ok, Error?, Data? }). The server validates every argument (see docs/03-architecture.md).
	Server -> client pushes are RemoteEvents.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- Client -> server requests (RemoteFunction).
Net.Functions = {
	-- Factory
	"BuyLine",
	"UpgradeStage",
	"Overdrive",
	"CollectVault",
	"BuyPackaging",
	"BuyVault",
	"AssignRobot",
	-- Machines
	"BuyMachine",
	"EquipMachine",
	"UnequipMachine",
	"MergeChrome",
	"StartPlating",
	"ClaimPlating",
	"LockMachine",
	-- Contracts & R&D
	"ClaimContract",
	"MegaCreate",
	"MegaJoin",
	"StartResearch",
	"ClaimResearch",
	"TrySecretRecipe",
	-- Prestige
	"Expand",
	"Franchise",
	-- Retention
	"ClaimQuest",
	"ClaimDailyQuestBonus",
	"ClaimDaily",
	"ClaimSupplyDrop",
	"ClaimOffline",
	"ClaimGlobalGoal",
	"RedeemCode",
	"SetTitle",
	-- Trade
	"TradeRequest",
	"TradeRespond",
	"TradeSetOffer",
	"TradeReady",
	"TradeConfirm",
	"TradeCancel",
	-- Shop & ads
	"PromptPass",
	"PromptProduct",
	"WatchAd",
	"MarkOfferSeen",
	-- Social & misc
	"RequestSnapshot",
	"SetSetting",
	"TutorialAdvance",
	"GetLeaderboards",
	-- Admin (server checks admin rights on every call)
	"AdminCommand",
}

-- Server -> client pushes (RemoteEvent).
Net.Events = {
	"DataSync", -- (snapshot: PlayerData) full mirror on join
	"DataPatch", -- (key: string, value: any) top-level key replaced
	"Notify", -- (kind: string, text: string, payload: any?)
	"Effect", -- (kind: string, payload: any) visual/audio cue (Expansion, LevelMilestone, ContractStamp, Rocket...)
	"RuntimeState", -- (state) non-persisted per-player state: income/s, overdrive timers, operators, vault cap
	"EventState", -- (state) server-wide events: rush, weekend, global goal progress
	"TradeUpdate", -- (state) trade session view for this player
	"TradePrompt", -- (requestId, fromUserId, fromName)
	"Announce", -- (text, color) server/global announcement banner
	"AdminData", -- (metrics) admin panel refresh
}

local FOLDER_NAME = "Remotes"

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			local created = Instance.new("Folder")
			created.Name = FOLDER_NAME
			created.Parent = ReplicatedStorage
			folder = created
		end
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	local result = folder :: any
	return result
end

-- Server only: creates every remote. Safe to call more than once.
function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server-only")
	local root = getFolder()
	for _, name in Net.Functions do
		if not root:FindFirstChild(name) then
			local rf = Instance.new("RemoteFunction")
			rf.Name = name
			rf.Parent = root
		end
	end
	for _, name in Net.Events do
		if not root:FindFirstChild(name) then
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = root
		end
	end
end

function Net.Function(name: string): RemoteFunction
	assert(table.find(Net.Functions, name), "Unknown remote function " .. name)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Net.Event(name: string): RemoteEvent
	assert(table.find(Net.Events, name), "Unknown remote event " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

-- Client helper: invoke a request and always get a Response back (never throws).
function Net.Request(name: string, ...: any): { Ok: boolean, Error: string?, Data: any? }
	local rf = Net.Function(name)
	local ok, result = pcall(rf.InvokeServer, rf, ...)
	if not ok then
		return { Ok = false, Error = "Connection problem, try again" }
	end
	if type(result) ~= "table" then
		return { Ok = false, Error = "Unexpected response" }
	end
	return result
end

return Net

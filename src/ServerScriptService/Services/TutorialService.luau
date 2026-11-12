--!strict
--[[
	TutorialService (L5): the guided first three minutes. Steps live in Config.Tutorial.Steps and
	advance only from server-side TutorialAction signals, never from client claims.
	The tutorial contract itself is created by ContractService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local Server = script.Parent.Parent.Server
local Grants = require(Server.Grants)
local Guard = require(Server.Guard)
local Remote = require(Server.Remote)
local ServerSignals = require(Server.ServerSignals)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)

local TutorialService = {}

local STEPS = Config.Tutorial.Steps

-- Signal action -> the single step it completes (Upgrade is handled separately).
local ACTION_STEP: { [string]: string } = {
	VaultCollected = "CollectVault",
	ContractClaimed = "Contract",
	LineBought = "BuyLine2",
	Overdrive = "Overdrive",
	MachineEquipped = "EquipMachine",
}

local function hasMachine(data: Types.PlayerData, id: string): boolean
	for _, item in data.Machines.Inventory do
		if item.Id == id then
			return true
		end
	end
	return false
end

local function grantFreeMachine(player: Player, data: Types.PlayerData)
	if not hasMachine(data, Config.Tutorial.FreeMachineId) then
		Grants.GrantMachine(player, Config.Tutorial.FreeMachineId, "Tutorial")
	end
end

local function enterStep(player: Player, data: Types.PlayerData)
	local tutorial = data.Tutorial
	local name = STEPS[tutorial.Step]
	if name == "UpgradeFive" then
		tutorial.Upgrades = 0
		CurrencyService.AddCash(player, Config.Tutorial.WelcomeCrateCash, "TutorialCrate", false)
		Remote.Notify(player, "Reward", "Welcome crate! Use it to upgrade your machines.")
	elseif name == "EquipMachine" then
		grantFreeMachine(player, data)
	elseif name == "Done" then
		tutorial.Done = true
	end
	DataService.MarkDirty(player, "Tutorial")
end

local function advance(player: Player, data: Types.PlayerData)
	local tutorial = data.Tutorial
	if tutorial.Step >= #STEPS then
		return
	end
	tutorial.Step += 1
	enterStep(player, data)
end

local function complete(player: Player, data: Types.PlayerData)
	data.Tutorial.Step = #STEPS
	data.Tutorial.Done = true
	DataService.MarkDirty(player, "Tutorial")
end

local function onAction(player: Player, action: string)
	local data = DataService.Get(player)
	if not data or data.Tutorial.Done then
		return
	end
	local step = STEPS[data.Tutorial.Step]
	if action == "Upgrade" then
		local enoughUpgrades = data.Tutorial.Upgrades >= Config.Tutorial.UpgradeCount
		if step == "TapBottleneck" or (step == "UpgradeFive" and enoughUpgrades) then
			advance(player, data)
		end
	elseif ACTION_STEP[action] == step then
		advance(player, data)
	end
end

local function handleAdvance(player: Player, actionArg: any, stepArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded"
	end
	local action = Guard.String(actionArg, 8)
	local step = Guard.Integer(stepArg, 1, #STEPS)
	if action == nil or step == nil or step ~= data.Tutorial.Step then
		return false, "Out of date"
	end
	if action == "Skip" then
		complete(player, data)
		return true
	elseif action == "Ack" then
		-- Acknowledging the closing step is accepted; other steps advance only through gameplay.
		return STEPS[step] == "Done"
	end
	return false, "Unknown action"
end

function TutorialService.Init()
	Remote.Handle("TutorialAdvance", handleAdvance)
end

function TutorialService.Start()
	ServerSignals.TutorialAction:Connect(onAction)
	DataService.Loaded:Connect(function(player: Player, data: Types.PlayerData)
		-- Covers a player who disconnected between reaching the step and receiving the machine.
		if not data.Tutorial.Done and STEPS[data.Tutorial.Step] == "EquipMachine" then
			grantFreeMachine(player, data)
		end
	end)
end

return TutorialService

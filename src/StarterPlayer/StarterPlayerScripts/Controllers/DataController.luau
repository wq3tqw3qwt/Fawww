--!strict
--[[
	DataController: client mirror of PlayerData (DataSync/DataPatch), RuntimeState and EventState.
	Display-only: the server stays authoritative. Connections are made in Init so the one-shot
	DataSync is not missed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local DataController = {}

local maid = Maid.new()
local data: Types.PlayerData? = nil
local runtime: any = nil
local events: any = nil
local adminSeen = false
local adminMetrics: any = nil
local serverOffset = 0
local waiting: { thread } = {}

DataController.Changed = Signal.new() :: Signal.Signal<string, any>
DataController.RuntimeChanged = Signal.new() :: Signal.Signal<any>
DataController.EventsChanged = Signal.new() :: Signal.Signal<any>
DataController.AdminChanged = Signal.new() :: Signal.Signal<boolean>

function DataController.Get(): Types.PlayerData?
	return data
end

function DataController.GetKey(key: string): any
	if data == nil then
		return nil
	end
	return (data :: any)[key]
end

-- Yields until the first DataSync arrives.
function DataController.WaitForData(): Types.PlayerData
	if data == nil then
		table.insert(waiting, coroutine.running())
		coroutine.yield()
	end
	return data :: Types.PlayerData
end

function DataController.OnKey(key: string, fn: (value: any) -> ()): Signal.Connection
	local connection = DataController.Changed:Connect(function(changed: string, value: any)
		if changed == key then
			fn(value)
		end
	end)
	if data ~= nil then
		task.spawn(fn, (data :: any)[key])
	end
	return connection
end

function DataController.GetRuntime(): any?
	return runtime
end

function DataController.GetEvents(): any?
	return events
end

function DataController.IsAdmin(): boolean
	return adminSeen
end

function DataController.GetAdminMetrics(): any
	return adminMetrics
end

-- Server unix time estimate (os.time() corrected by the offset learned from EventState.ServerTime).
function DataController.ServerNow(): number
	return os.time() + serverOffset
end

local function onSync(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	data = snapshot :: Types.PlayerData
	for _, thread in waiting do
		task.spawn(thread)
	end
	table.clear(waiting)
	for key, value in snapshot do
		DataController.Changed:Fire(key, value)
	end
end

local function onPatch(key: any, value: any)
	if data == nil or type(key) ~= "string" then
		return
	end
	(data :: any)[key] = value
	DataController.Changed:Fire(key, value)
end

function DataController.Init()
	maid:Add(Net.Event("DataSync").OnClientEvent:Connect(onSync))
	maid:Add(Net.Event("DataPatch").OnClientEvent:Connect(onPatch))
	maid:Add(Net.Event("RuntimeState").OnClientEvent:Connect(function(state: any)
		if type(state) == "table" then
			runtime = state
			DataController.RuntimeChanged:Fire(state)
		end
	end))
	maid:Add(Net.Event("EventState").OnClientEvent:Connect(function(state: any)
		if type(state) == "table" then
			events = state
			if type(state.ServerTime) == "number" then
				serverOffset = state.ServerTime - os.time()
			end
			DataController.EventsChanged:Fire(state)
		end
	end))
	maid:Add(Net.Event("AdminData").OnClientEvent:Connect(function(metrics: any)
		adminMetrics = metrics
		if not adminSeen then
			adminSeen = true
			DataController.AdminChanged:Fire(true)
		end
	end))
end

function DataController.Start()
	-- Ask for the snapshot until it arrives, in case the server's DataSync fired before we connected.
	while DataController.Get() == nil do
		Net.Request("RequestSnapshot")
		task.wait(2)
	end
end

return DataController

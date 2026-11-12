--!strict
--[[
	ClientMain: boots every controller in StarterPlayerScripts/Controllers.
	Each controller is a ModuleScript returning a table with optional Init() and Start().
	Init runs for all controllers first (in Order, then alphabetical), then Start.
]]

local controllersFolder = script.Parent:WaitForChild("Controllers")

-- Controllers that others depend on boot first.
local ORDER = { "DataController", "UIController", "SoundController", "NotificationController", "InputController" }

type Controller = { Init: (() -> ())?, Start: (() -> ())?, [any]: any }

local modules: { ModuleScript } = {}
for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(modules, child)
	end
end
table.sort(modules, function(a, b)
	local ia, ib = table.find(ORDER, a.Name) or math.huge, table.find(ORDER, b.Name) or math.huge
	if ia ~= ib then
		return ia < ib
	end
	return a.Name < b.Name
end)

local loaded: { { name: string, controller: Controller } } = {}
for _, module in modules do
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		table.insert(loaded, { name = module.Name, controller = result })
	else
		warn("[ClientMain] failed to load " .. module.Name .. ": " .. tostring(result))
	end
end

for _, entry in loaded do
	local init = entry.controller.Init
	if init then
		local ok, err = pcall(init :: () -> any)
		if not ok then
			warn("[ClientMain] Init failed for " .. entry.name .. ": " .. tostring(err))
		end
	end
end

for _, entry in loaded do
	local start = entry.controller.Start
	if start then
		task.spawn(function()
			local ok, err = pcall(start :: () -> any)
			if not ok then
				warn("[ClientMain] Start failed for " .. entry.name .. ": " .. tostring(err))
			end
		end)
	end
end

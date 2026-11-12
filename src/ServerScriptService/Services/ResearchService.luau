--!strict
--[[
	ResearchService (L5): R&D Lab (permanent research on long timers, paid in Credits) and the
	deterministic Secret Recipe workbench. No randomness anywhere.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent.Server

local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Grants = require(Server.Grants)
local Guard = require(Server.Guard)
local Remote = require(Server.Remote)
local ServerSignals = require(Server.ServerSignals)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local MultiplierService = require(script.Parent.MultiplierService)

local ResearchService = {}

local researchById: { [string]: Config.ResearchDef } = {}
for _, def in Config.Research do
	researchById[def.Id] = def
end

local function startResearch(player: Player, idArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local id = Guard.Key(idArg, researchById)
	if not data or not id then
		return false, "Unknown research"
	end
	local def = researchById[id]
	local research = data.Research
	local level = research.Levels[id] or 0
	if level >= def.MaxLevel then
		return false, "Already at max level"
	end
	if research.ActiveId ~= "" then
		return false, "A project is already running"
	end
	if not CurrencyService.SpendCredits(player, Formulas.ResearchCost(def, level)) then
		return false, "Not enough Credits"
	end
	local labRat = MultiplierService.GetAbilities(player).LabRat or 0
	research.ActiveId = id
	research.EndsAt = os.time() + Formulas.ResearchDuration(def, labRat)
	DataService.MarkDirty(player, "Research")
	return true, nil, { EndsAt = research.EndsAt }
end

local function claimResearch(player: Player): (boolean, string?, any?)
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded"
	end
	local research = data.Research
	if research.ActiveId == "" then
		return false, "No research is running"
	end
	if os.time() < research.EndsAt then
		return false, "Research isn't finished yet"
	end
	local id = research.ActiveId
	research.Levels[id] = (research.Levels[id] or 0) + 1
	research.ActiveId = ""
	research.EndsAt = 0
	DataService.MarkDirty(player, "Research")
	ServerSignals.MultipliersDirty:Fire(player)
	return true, nil, { Id = id, Level = research.Levels[id] }
end

-- Finishes the running project's timer (used by the instant-research product).
function ResearchService.SkipResearch(player: Player): boolean
	local data = DataService.Get(player)
	if not data or data.Research.ActiveId == "" then
		return false
	end
	data.Research.EndsAt = os.time()
	DataService.MarkDirty(player, "Research")
	return true
end

local function sameSet(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for _, v in a do
		if not table.find(b, v) then
			return false
		end
	end
	return true
end

local function trySecretRecipe(player: Player, linesArg: any): (boolean, string?, any?)
	local data = DataService.Get(player)
	local lines = Guard.IntegerArray(linesArg, 3, 1, #Config.Lines)
	if not data or not lines or #lines ~= 3 then
		return false, "Pick exactly three different lines"
	end
	for i, line in lines do
		if table.find(lines, line) ~= i then
			return false, "Pick exactly three different lines"
		end
		if line > #data.Lines then
			return false, "You don't own that line yet"
		end
	end

	for _, recipe in Config.SecretRecipes do
		if sameSet(lines, recipe.Lines) then
			local tuned = true
			for _, line in lines do
				tuned = tuned and Formulas.LineMinLevel(data.Lines[line]) >= recipe.MinLevel
			end
			if tuned then
				if data.Catalog.Secrets[recipe.MachineId] then
					return false, "You already discovered this recipe"
				end
				if not Grants.GrantMachine(player, recipe.MachineId, "Secret") then
					return false, "Make room in your machine inventory first"
				end
				data.Catalog.Secrets[recipe.MachineId] = true
				DataService.MarkDirty(player, "Catalog")
				Remote.Fire("Effect", player, "SecretDiscovered", { Id = recipe.MachineId })
				local def = Formulas.GetMachine(recipe.MachineId)
				EventService.Announce(
					string.format(
						"%s cracked a secret recipe: %s!",
						player.DisplayName,
						if def then def.Name else "???"
					),
					Config.Rarities.Colors.Secret,
					true
				)
				return true, nil, { Id = recipe.MachineId }
			end
			break
		end
	end
	return false, "Nothing happened... yet. The machines hum quietly."
end

function ResearchService.Init()
	Remote.Handle("StartResearch", startResearch)
	Remote.Handle("ClaimResearch", claimResearch)
	Remote.Handle("TrySecretRecipe", trySecretRecipe)
end

function ResearchService.Start() end

return ResearchService

--!strict
--[[
	PlotService (L2): owns the player plots. Init builds the world and eight empty plot shells;
	Start claims a free plot when a player's data loads, builds the factory from their data and keeps it
	in sync on LinesChanged / Expanded / Franchised / MultipliersDirty. Everything is procedural (BuildKit).
	Naming contract: docs/03-architecture.md section 9.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Builders = ServerStorage.Builders
local BuildKit = require(Builders.BuildKit)
local MachineModelBuilder = require(Builders.MachineModelBuilder)
local WorldBuilder = require(Builders.WorldBuilder)

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Types = require(ReplicatedStorage.Shared.Types)

local ServerSignals = require(script.Parent.Parent.Server.ServerSignals)
local AntiExploitService = require(script.Parent.AntiExploitService)
local DataService = require(script.Parent.DataService)

local PlotService = {}

local World = Config.World
local Visuals = Config.Visuals
local Palette = Visuals.Palette
local P = Visuals.Plot

local SLAB = World.PlotSize.Y -- thickness of every floor slab
local HALF_X = World.PlotSize.X / 2
local HALF_Z = World.PlotSize.Z / 2

type PlotState = {
	Index: number,
	Model: Model,
	CFrame: CFrame,
	Owner: Player?,
	Highest: number,
	BayKeys: { [number]: string },
}

local plots: { PlotState } = {}
local byPlayer: { [Player]: PlotState } = {}
local waiting: { Player } = {}
local playerMaids: { [Player]: Maid.Maid } = {}
local plotsFolder: Folder? = nil

--------------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------------
local function floorTop(hall: number): number
	return (hall - 1) * World.FloorHeight + SLAB
end

local function lineZ(k: number): number
	local j = (k - 1) % Config.LinesPerHall + 1
	return (j - (Config.LinesPerHall + 1) / 2) * World.LineSpacing
end

local function localCFrame(state: PlotState, x: number, y: number, z: number): CFrame
	return state.CFrame * CFrame.new(x, y, z)
end

local function hallColor(hall: number): Color3
	local def = Config.Halls[hall] or Config.Halls[1]
	return def.Color
end

local function put(
	state: PlotState,
	parent: Instance,
	name: string,
	pos: Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	return BuildKit.Part({
		Name = name,
		Size = size,
		CFrame = state.CFrame * CFrame.new(pos),
		Color = color,
		Material = material,
		CanCollide = collide,
		Parent = parent,
	})
end

local function clearChildren(parent: Instance, predicate: (Instance) -> boolean)
	for _, child in parent:GetChildren() do
		if predicate(child) then
			child:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- Static shell (built once per plot)
--------------------------------------------------------------------------------
local function setSign(state: PlotState, title: string, subtitle: string, color: Color3)
	local sign = state.Model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	if not gui then
		return
	end
	local main = gui:FindFirstChild("Text") :: TextLabel?
	local sub = gui:FindFirstChild("Sub") :: TextLabel?
	if main then
		main.Text = title
		main.TextColor3 = color
	end
	if sub then
		sub.Text = subtitle
	end
	if sign and sign:IsA("BasePart") then
		sign.Color = BuildKit.Darken(color, 0.65)
	end
end

local function buildShell(index: number): PlotState
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	local state: PlotState = {
		Index = index,
		Model = model,
		CFrame = WorldBuilder.PlotCFrame(index),
		Owner = nil,
		Highest = 0,
		BayKeys = {},
	}
	local dark = Visuals.Stage.DarkColor
	local metal = Visuals.Stage.MetalColor

	local base = put(
		state,
		model,
		"Base",
		Vector3.new(0, SLAB / 2, 0),
		World.PlotSize,
		Palette.PlotBase:Lerp(hallColor(1), P.FloorTint),
		Enum.Material.SmoothPlastic,
		true
	)
	model.PrimaryPart = base
	put(
		state,
		model,
		"FrontEdge",
		Vector3.new(0, SLAB + 0.1, -HALF_Z + 0.4),
		Vector3.new(World.PlotSize.X, 0.2, 0.8),
		hallColor(1),
		Enum.Material.Neon
	).CastShadow =
		false

	-- Vault: collect zone pad with a safe on top.
	local vault = BuildKit.Model("Vault", model)
	local vaultPos = P.VaultOffset + Vector3.new(0, SLAB + P.VaultPadSize.Y / 2, 0)
	local pad = put(state, model, "VaultPad", vaultPos, P.VaultPadSize, Palette.Cash, Enum.Material.Neon)
	pad.Transparency = 0.35
	put(
		state,
		vault,
		"Safe",
		vaultPos + Vector3.new(0, 2.2, 1.5),
		Vector3.new(5, 4, 3),
		dark,
		Enum.Material.Metal,
		true
	)
	put(state, vault, "SafeDoor", vaultPos + Vector3.new(0, 2.2, 0), Vector3.new(3, 3, 0.2), metal, Enum.Material.Metal)
	BuildKit.Ball({
		Name = "SafeDial",
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = localCFrame(state, vaultPos.X, vaultPos.Y + 2.2, vaultPos.Z - 0.2),
		Color = Palette.Cash,
		Material = Enum.Material.Neon,
		Parent = vault,
	})
	BuildKit.Billboard(pad, "VAULT", { Offset = Vector3.new(0, 6, 0), Color = Palette.Cash, MaxDistance = 90 })

	-- Dock: road strip the trucks drive along.
	local dock = put(
		state,
		model,
		"Dock",
		Vector3.new(0, SLAB + P.DockSize.Y / 2, P.DockZ),
		P.DockSize,
		Palette.Road,
		Enum.Material.SmoothPlastic,
		true
	)
	local half = P.DockSize.X / 2 - 4
	BuildKit.Attachment(dock, "TruckStart", Vector3.new(half, P.DockSize.Y / 2, 0))
	BuildKit.Attachment(dock, "TruckEnd", Vector3.new(-half, P.DockSize.Y / 2, 0))
	put(
		state,
		model,
		"DockLine",
		Vector3.new(0, SLAB + P.DockSize.Y + 0.05, P.DockZ),
		Vector3.new(P.DockSize.X - 6, 0.1, 0.4),
		Palette.ConveyorStripe,
		Enum.Material.Neon
	).CastShadow =
		false

	BuildKit.Model("Bays", model)

	-- Contract board with two posts.
	local boardPos = P.ContractBoardOffset
	local board = put(
		state,
		model,
		"ContractBoard",
		Vector3.new(boardPos.X, SLAB + 2.5 + P.ContractBoardSize.Y / 2, boardPos.Z),
		P.ContractBoardSize,
		Palette.UIPanel,
		Enum.Material.SmoothPlastic
	)
	BuildKit.SurfaceText(board, Enum.NormalId.Front, "CONTRACTS", Palette.UIAccent)
	for _, side in { -1, 1 } do
		put(
			state,
			model,
			"ContractPost",
			Vector3.new(boardPos.X + side * (P.ContractBoardSize.X / 2 - 1), SLAB + 1.5, boardPos.Z),
			Vector3.new(0.7, 3, 0.7),
			dark,
			Enum.Material.Metal
		)
	end

	-- Sign with owner name and industry.
	local sign = put(state, model, "Sign", P.SignOffset, P.SignSize, dark, Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		put(
			state,
			model,
			"SignPost",
			Vector3.new(P.SignOffset.X + side * (P.SignSize.X / 2 - 2), P.SignOffset.Y / 2 + SLAB / 2, P.SignOffset.Z),
			Vector3.new(1, P.SignOffset.Y - P.SignSize.Y / 2, 1),
			metal,
			Enum.Material.Metal
		)
	end
	local gui, title = BuildKit.Billboard(sign, "", {
		Name = "SignGui",
		Size = UDim2.fromOffset(560, 150),
		MaxDistance = 400,
	})
	title.Size = UDim2.fromScale(1, 0.6)
	local sub = title:Clone()
	sub.Name = "Sub"
	sub.Size = UDim2.fromScale(1, 0.38)
	sub.Position = UDim2.fromScale(0, 0.62)
	sub.TextColor3 = Palette.UIText
	sub.Parent = gui
	setSign(state, P.FreeSignText, "Join to claim", Palette.UIText)

	-- Where the owner appears.
	put(
		state,
		model,
		"SpawnPoint",
		P.SpawnOffset + Vector3.new(0, SLAB + P.SpawnSize.Y / 2, 0),
		P.SpawnSize,
		hallColor(1),
		Enum.Material.Neon
	).Transparency =
		0.5

	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	model.Parent = plotsFolder
	return state
end

--------------------------------------------------------------------------------
-- Floors, roof, stairs
--------------------------------------------------------------------------------
-- Slab for a level (level 1 is the Base). Upper slabs stop at SlabBackZ so the stair well stays open.
local function buildSlab(state: PlotState, parent: Instance, level: number, color: Color3)
	local y0 = (level - 1) * World.FloorHeight
	local length = P.SlabBackZ + HALF_Z
	local centerZ = (P.SlabBackZ - HALF_Z) / 2
	put(
		state,
		parent,
		"Slab",
		Vector3.new(0, y0 + SLAB / 2, centerZ),
		Vector3.new(World.PlotSize.X, SLAB, length),
		color,
		Enum.Material.SmoothPlastic,
		true
	)
	-- Pillars from the level below.
	local ps = P.PillarSize
	local below = y0 - World.FloorHeight + SLAB
	for _, x in { -HALF_X + ps / 2, HALF_X - ps / 2 } do
		for _, z in { -HALF_Z + ps / 2, centerZ, P.SlabBackZ - ps / 2 } do
			put(
				state,
				parent,
				"Pillar",
				Vector3.new(x, (below + y0) / 2, z),
				Vector3.new(ps, y0 - below, ps),
				BuildKit.Darken(color, 0.15),
				Enum.Material.SmoothPlastic
			)
		end
	end
end

local function buildRails(state: PlotState, parent: Instance, level: number, accent: Color3, backGap: boolean)
	local top = (level - 1) * World.FloorHeight + SLAB
	local rh, rt = P.RailHeight, P.RailThickness
	local length = P.SlabBackZ + HALF_Z
	local centerZ = (P.SlabBackZ - HALF_Z) / 2
	local function rail(name: string, pos: Vector3, size: Vector3)
		local glass = put(
			state,
			parent,
			name .. "Glass",
			pos + Vector3.new(0, rh / 2, 0),
			size,
			Visuals.Stage.GlassColor,
			Enum.Material.Glass,
			level > 1
		)
		glass.Transparency = 0.65
		local bar = put(
			state,
			parent,
			name .. "Bar",
			pos + Vector3.new(0, rh, 0),
			Vector3.new(math.max(size.X, rt), rt, math.max(size.Z, rt)),
			accent,
			Enum.Material.Neon
		)
		bar.CastShadow = false
	end
	rail("RailFront", Vector3.new(0, top, -HALF_Z + 0.2), Vector3.new(World.PlotSize.X, rh, 0.2))
	for _, side in { -1, 1 } do
		rail("RailSide", Vector3.new(side * (HALF_X - 0.2), top, centerZ), Vector3.new(0.2, rh, length))
	end
	if backGap then
		local span = HALF_X - P.StairLandingDepth
		rail("RailBack", Vector3.new(0, top, P.SlabBackZ - 0.2), Vector3.new(span * 2, rh, 0.2))
	end
end

local function buildFloor(state: PlotState, hall: number, ghost: boolean)
	local def = Config.Halls[hall]
	local model = BuildKit.Model("Floor_" .. hall, state.Model)
	model:SetAttribute("Hall", hall)
	model:SetAttribute("Locked", ghost)
	local color = Palette.PlotBase:Lerp(def.Color, P.FloorTint)
	if ghost then
		local length = P.SlabBackZ + HALF_Z
		local y0 = (hall - 1) * World.FloorHeight
		local slab = put(
			state,
			model,
			"GhostSlab",
			Vector3.new(0, y0 + SLAB / 2, (P.SlabBackZ - HALF_Z) / 2),
			Vector3.new(World.PlotSize.X, SLAB, length),
			def.Color,
			Enum.Material.Neon
		)
		slab.Transparency = P.GhostAlpha
		slab.CastShadow = false
		BuildKit.Billboard(slab, string.format("%s: Expansion %d", def.Name, def.UnlockExpansions), {
			Offset = Vector3.new(0, 4, 0),
			Color = def.Color,
			MaxDistance = 220,
		})
		return
	end
	if hall > 1 then
		buildSlab(state, model, hall, color)
	end
	buildRails(state, model, hall, def.Color, true)
	local top = floorTop(hall)
	local nameplate = put(
		state,
		model,
		"Nameplate",
		Vector3.new(-HALF_X + 14, top + 1.5, -HALF_Z + 1.5),
		Vector3.new(24, 3, 0.6),
		BuildKit.Darken(def.Color, 0.5),
		Enum.Material.SmoothPlastic
	)
	BuildKit.SurfaceText(nameplate, Enum.NormalId.Front, string.upper(def.Name), def.Color)
end

local function buildStairs(state: PlotState, highest: number)
	local model = BuildKit.Model("Stairs", state.Model)
	local thickness = P.StairThickness
	local runHalf = HALF_X - P.StairLandingDepth
	local run = runHalf * 2
	local rise = World.FloorHeight
	local angle = math.atan2(rise, run)
	local length = math.sqrt(run * run + rise * rise)
	local landingWidth = HALF_Z - P.SlabBackZ
	local landingZ = (P.SlabBackZ + HALF_Z) / 2
	for h = 1, highest do
		local dir = if h % 2 == 1 then 1 else -1
		local y0 = floorTop(h)
		local y1 = floorTop(h + 1)
		local color = hallColor(math.min(h + 1, #Config.Halls))
		local mid = Vector3.new(0, (y0 + y1) / 2, P.StairZ)
		local rampCF = state.CFrame
			* CFrame.new(mid)
			* CFrame.Angles(0, 0, dir * angle)
			* CFrame.new(0, -thickness / 2, 0)
		BuildKit.Part({
			Name = "Ramp_" .. h,
			Size = Vector3.new(length, thickness, P.StairWidth),
			CFrame = rampCF,
			Color = Palette.PlotBase:Lerp(color, 0.3),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			Parent = model,
		})
		for _, side in { -1, 1 } do
			local railCF = rampCF * CFrame.new(0, thickness / 2 + P.RailHeight / 2, side * (P.StairWidth / 2 - 0.2))
			BuildKit.Part({
				Name = "RampGlass",
				Size = Vector3.new(length, P.RailHeight, 0.2),
				CFrame = railCF,
				Color = Visuals.Stage.GlassColor,
				Material = Enum.Material.Glass,
				Transparency = 0.65,
				CanCollide = true,
				Parent = model,
			})
			BuildKit.Part({
				Name = "RampBar",
				Size = Vector3.new(length, P.RailThickness, P.RailThickness),
				CFrame = railCF * CFrame.new(0, P.RailHeight / 2, 0),
				Color = color,
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = model,
			})
		end
		-- The landing is flush with the slab of the level above.
		put(
			state,
			model,
			"Landing_" .. h,
			Vector3.new(dir * (runHalf + P.StairLandingDepth / 2), y1 - thickness / 2, landingZ),
			Vector3.new(P.StairLandingDepth, thickness, landingWidth),
			Palette.PlotBase:Lerp(color, 0.3),
			Enum.Material.SmoothPlastic,
			true
		)
	end
end

local function buildRoof(state: PlotState, highest: number)
	local model = BuildKit.Model("Roof", state.Model)
	local level = highest + 1
	buildSlab(state, model, level, P.RoofColor)
	buildRails(state, model, level, hallColor(highest), true)
	if highest >= #Config.Halls then
		local top = floorTop(level)
		local padSize = P.RocketPadSize
		local pad = put(
			state,
			state.Model,
			"RocketPad",
			Vector3.new(P.RocketPadOffset.X, top + padSize.Y / 2, P.RocketPadOffset.Z),
			padSize,
			Visuals.Stage.DarkColor,
			Enum.Material.Metal,
			true
		)
		put(
			state,
			model,
			"RocketPadRing",
			Vector3.new(P.RocketPadOffset.X, top + padSize.Y + 0.03, P.RocketPadOffset.Z),
			Vector3.new(padSize.X - 2, 0.08, padSize.Z - 2),
			hallColor(#Config.Halls),
			Enum.Material.Neon
		).CastShadow =
			false
		BuildKit.Billboard(pad, "ROCKET PAD", { Offset = Vector3.new(0, 5, 0), Color = hallColor(#Config.Halls) })
	end
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------
local function addPrompt(
	parent: BasePart,
	name: string,
	action: string,
	objectText: string,
	lineIndex: number,
	ownerId: number,
	hold: number,
	distance: number
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = distance
	prompt:SetAttribute("LineIndex", lineIndex)
	prompt:SetAttribute("OwnerUserId", ownerId)
	prompt.Parent = parent
end

local function ownerIdOf(state: PlotState): number
	return if state.Owner then state.Owner.UserId else 0
end

local function recolorTier(line: Model, color: Color3)
	for _, inst in line:GetDescendants() do
		if inst:IsA("BasePart") and inst:GetAttribute("TierPart") == true then
			inst.Color = color
		end
	end
end

local function buildLine(state: PlotState, data: Types.PlayerData, k: number)
	local levels = data.Lines[k]
	local def = Config.Lines[k]
	if not levels or not def then
		return
	end
	local hall = Formulas.LineHall(k)
	local model = BuildKit.Model("Line_" .. k)
	local minLevel = Formulas.LineMinLevel(levels)
	local tierColor, tierIndex = BuildKit.TierColor(minLevel)
	model:SetAttribute("LineIndex", k)
	model:SetAttribute("Owned", true)
	model:SetAttribute("MinLevel", minLevel)
	model:SetAttribute("Tier", tierIndex)

	local y = floorTop(hall)
	local z = lineZ(k)
	local length = World.LineLength
	local startX = P.LineStartX
	local cx = startX + length / 2

	local belt = put(
		state,
		model,
		"Belt",
		Vector3.new(cx, y + P.BeltHeight, z),
		Vector3.new(length, P.BeltThickness, P.BeltWidth),
		Palette.Conveyor,
		Enum.Material.SmoothPlastic
	)
	local top = P.BeltThickness / 2
	BuildKit.Attachment(belt, "BeltStart", Vector3.new(-length / 2, top, 0))
	BuildKit.Attachment(belt, "BeltEnd", Vector3.new(length / 2, top, 0))
	for _, side in { -1, 1 } do
		put(
			state,
			model,
			"BeltStripe",
			Vector3.new(cx, y + P.BeltHeight + top + 0.05, z + side * (P.BeltWidth / 2 - 0.15)),
			Vector3.new(length, 0.1, 0.3),
			Palette.ConveyorStripe,
			Enum.Material.Neon
		).CastShadow =
			false
	end
	put(
		state,
		model,
		"BeltFrame",
		Vector3.new(cx, y + 0.5, z),
		Vector3.new(length - 2, 0.6, 1.2),
		Visuals.Stage.DarkColor,
		Enum.Material.Metal
	).CastShadow =
		false
	model.PrimaryPart = belt

	local quarter = length / 4
	for s = 1, 4 do
		local stage = MachineModelBuilder.BuildStage(hall, s, tierColor)
		stage:SetAttribute("Level", levels[s] or 1)
		stage:PivotTo(state.CFrame * CFrame.new(startX + (s - 0.5) * quarter, y, z))
		stage.Parent = model
	end

	-- Overdrive lever beside the belt start.
	local leverX = startX + P.LeverOffsetX
	local lever = put(
		state,
		model,
		"Lever",
		Vector3.new(leverX, y + 1.1, z),
		Vector3.new(1.6, 2.2, 1.6),
		Visuals.Stage.DarkColor,
		Enum.Material.Metal
	)
	BuildKit.Part({
		Name = "LeverHandle",
		Size = Vector3.new(0.3, 1.8, 0.3),
		CFrame = localCFrame(state, leverX, y + 2.6, z) * CFrame.Angles(0, 0, math.rad(25)),
		Color = Palette.UIAccent,
		Material = Enum.Material.Metal,
		CastShadow = false,
		Parent = model,
	})
	BuildKit.Ball({
		Name = "LeverKnob",
		Size = Vector3.new(0.8, 0.8, 0.8),
		CFrame = localCFrame(state, leverX - 0.4, y + 3.45, z),
		Color = Palette.Bottleneck,
		Material = Enum.Material.Neon,
		CastShadow = false,
		Parent = model,
	})
	addPrompt(lever, "OverdrivePrompt", "Overdrive!", def.Name, k, ownerIdOf(state), 0.3, P.LeverPromptDistance)
	BuildKit.Billboard(lever, def.Name, {
		Name = "LineTag",
		Size = UDim2.fromOffset(200, 44),
		Offset = Vector3.new(0, 3.4, 0),
		Color = hallColor(hall),
		MaxDistance = 60,
	})

	model.Parent = state.Model
end

local function buildBuildPad(state: PlotState, k: number)
	local def = Config.Lines[k]
	if not def then
		return
	end
	local hall = Formulas.LineHall(k)
	local model = BuildKit.Model("Line_" .. k)
	model:SetAttribute("LineIndex", k)
	model:SetAttribute("Owned", false)
	model:SetAttribute("MinLevel", 0)
	local pad = put(
		state,
		model,
		"BuildPad",
		Vector3.new(P.LineStartX + World.LineLength / 2, floorTop(hall) + 0.2, lineZ(k)),
		Vector3.new(World.LineLength * 0.9, 0.3, P.BuildPadWidth),
		hallColor(hall),
		Enum.Material.Neon
	)
	pad.Transparency = P.BuildPadAlpha
	pad.CastShadow = false
	local cost = Formulas.LineUnlockCost(k)
	BuildKit.Billboard(pad, string.format("BUILD %s  %s", def.Name, NumberFormat.Cash(cost)), {
		Name = "BuildLabel",
		Size = UDim2.fromOffset(340, 60),
		Offset = Vector3.new(0, 3, 0),
		Color = hallColor(hall),
		MaxDistance = 120,
	})
	addPrompt(pad, "BuildPrompt", "Build", def.Name, k, ownerIdOf(state), 0, P.BuildPromptDistance)
	model.Parent = state.Model
end

local function updateBuildPad(state: PlotState, data: Types.PlayerData)
	local nextK = #data.Lines + 1
	local wanted = nextK <= Formulas.MaxLineForExpansions(data.Expansions) and Config.Lines[nextK] ~= nil
	local found = false
	for _, child in state.Model:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Owned") == false then
			if wanted and child:GetAttribute("LineIndex") == nextK and not found then
				found = true
			else
				child:Destroy()
			end
		end
	end
	if wanted and not found then
		buildBuildPad(state, nextK)
	end
end

local function updateLine(state: PlotState, data: Types.PlayerData, k: number)
	local levels = data.Lines[k]
	if not levels then
		return
	end
	local existing = state.Model:FindFirstChild("Line_" .. k)
	if existing and existing:GetAttribute("Owned") ~= true then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		buildLine(state, data, k)
		updateBuildPad(state, data)
		return
	end
	local line = existing :: Model
	local minLevel = Formulas.LineMinLevel(levels)
	local tierColor, tierIndex = BuildKit.TierColor(minLevel)
	line:SetAttribute("MinLevel", minLevel)
	for s = 1, 4 do
		local stage = line:FindFirstChild("Stage_" .. s)
		if stage then
			stage:SetAttribute("Level", levels[s] or 1)
		end
	end
	if line:GetAttribute("Tier") ~= tierIndex then
		line:SetAttribute("Tier", tierIndex)
		recolorTier(line, tierColor)
	end
end

--------------------------------------------------------------------------------
-- Bays and sign
--------------------------------------------------------------------------------
local function updateBays(state: PlotState, data: Types.PlayerData)
	local bays = state.Model:FindFirstChild("Bays")
	if not bays then
		return
	end
	local list = data.Machines.Bays
	local count = #list
	local padSize = P.BayPadSize
	for i = 1, count do
		local uid = list[i]
		local item = if uid ~= "" then data.Machines.Inventory[uid] else nil
		local key = if item then item.Id .. "|" .. item.Grade else ""
		local existing = bays:FindFirstChild("Bay_" .. i)
		local bay: BasePart
		if existing and existing:IsA("BasePart") then
			bay = existing
		else
			local col = (i - 1) % #P.BaysX + 1
			local row = (i - 1) // #P.BaysX
			bay = put(
				state,
				bays,
				"Bay_" .. i,
				Vector3.new(P.BaysX[col], SLAB + padSize.Y / 2, P.BaysZStart + row * P.BaysZStep),
				padSize,
				Palette.PlotBase,
				Enum.Material.SmoothPlastic,
				true
			)
			bay:SetAttribute("BayIndex", i)
			state.BayKeys[i] = "?"
		end
		if state.BayKeys[i] ~= key then
			state.BayKeys[i] = key
			local old = bays:FindFirstChild("Machine_" .. i)
			if old then
				old:Destroy()
			end
			local def = if item then Formulas.GetMachine(item.Id) else nil
			if item and def then
				bay.Color = Config.Rarities.Colors[def.Rarity] or Palette.PlotBase
				local machine = MachineModelBuilder.Build(def, item.Grade)
				machine.Name = "Machine_" .. i
				machine:PivotTo(bay.CFrame * CFrame.new(0, padSize.Y / 2, 0))
				machine.Parent = bays
			else
				bay.Color = Palette.PlotBase
			end
		end
	end
	-- Remove pads beyond the current bay count (e.g. after a Franchise reset).
	for _, child in bays:GetChildren() do
		local index = tonumber(string.match(child.Name, "^%a+_(%d+)$"))
		if index and index > count then
			child:Destroy()
			state.BayKeys[index] = nil
		end
	end
end

local function updateSign(state: PlotState, data: Types.PlayerData)
	local owner = state.Owner
	if not owner then
		return
	end
	local hall = Formulas.HighestHall(data.Expansions)
	local def = Config.Halls[hall]
	local sub = def.Name
	if data.Franchise > 0 then
		sub = string.format("%s  -  %s %d", sub, Config.Franchise.TitlePrefix, data.Franchise)
	end
	setSign(state, owner.DisplayName .. "'s Factory", sub, def.Color)
end

--------------------------------------------------------------------------------
-- Full refresh
--------------------------------------------------------------------------------
local function refresh(state: PlotState, data: Types.PlayerData)
	local model = state.Model
	clearChildren(model, function(child)
		local name = child.Name
		return string.match(name, "^Floor_%d+$") ~= nil
			or string.match(name, "^Line_%d+$") ~= nil
			or name == "Roof"
			or name == "Stairs"
			or name == "RocketPad"
	end)
	local bays = model:FindFirstChild("Bays")
	if bays then
		bays:ClearAllChildren()
	end
	table.clear(state.BayKeys)

	local ownedHall = if #data.Lines > 0 then Formulas.LineHall(#data.Lines) else 1
	local highest = math.max(Formulas.HighestHall(data.Expansions), ownedHall)
	state.Highest = highest
	for h = 1, highest do
		buildFloor(state, h, false)
	end
	if highest < #Config.Halls then
		buildFloor(state, highest + 1, true)
	end
	buildStairs(state, highest)
	buildRoof(state, highest)
	for k = 1, #data.Lines do
		buildLine(state, data, k)
	end
	updateBuildPad(state, data)
	updateBays(state, data)
	updateSign(state, data)
end

--------------------------------------------------------------------------------
-- Ownership
--------------------------------------------------------------------------------
local function spawnCFrame(state: PlotState): CFrame
	local pos = state.CFrame:PointToWorldSpace(P.SpawnOffset + Vector3.new(0, SLAB + World.SpawnHeight, 0))
	-- Face into the plot (away from the plaza).
	return CFrame.lookAt(pos, pos + state.CFrame.LookVector * -1)
end

local function teleportHome(player: Player): boolean
	local state = byPlayer[player]
	local character = player.Character
	if not state or not character then
		return false
	end
	AntiExploitService.AllowTeleport(player, 3)
	character:PivotTo(spawnCFrame(state))
	return true
end

local function claim(player: Player, data: Types.PlayerData): boolean
	if byPlayer[player] then
		return true
	end
	for _, state in plots do
		if state.Owner == nil then
			state.Owner = player
			byPlayer[player] = state
			state.Model:SetAttribute("OwnerUserId", player.UserId)
			pcall(function()
				state.Model:AddPersistentPlayer(player)
			end)
			refresh(state, data)
			task.defer(teleportHome, player)
			return true
		end
	end
	return false
end

local function release(player: Player)
	local index = table.find(waiting, player)
	if index then
		table.remove(waiting, index)
	end
	local maid = playerMaids[player]
	if maid then
		maid:Destroy()
		playerMaids[player] = nil
	end
	local state = byPlayer[player]
	if not state then
		return
	end
	byPlayer[player] = nil
	pcall(function()
		state.Model:RemovePersistentPlayer(player)
	end)
	state.Owner = nil
	state.Model:SetAttribute("OwnerUserId", 0)
	clearChildren(state.Model, function(child)
		local name = child.Name
		return string.match(name, "^Floor_%d+$") ~= nil
			or string.match(name, "^Line_%d+$") ~= nil
			or name == "Roof"
			or name == "Stairs"
			or name == "RocketPad"
	end)
	local bays = state.Model:FindFirstChild("Bays")
	if bays then
		bays:ClearAllChildren()
	end
	table.clear(state.BayKeys)
	setSign(state, P.FreeSignText, "Join to claim", Palette.UIText)

	-- Hand the freed plot to anyone still waiting for one.
	for i = #waiting, 1, -1 do
		local candidate = waiting[i]
		local data = DataService.Get(candidate)
		if candidate.Parent == Players and data and claim(candidate, data) then
			table.remove(waiting, i)
			break
		end
	end
end

local function onLoaded(player: Player, data: Types.PlayerData)
	if not claim(player, data) then
		warn(
			string.format("[PlotService] no free plot for %s (server larger than Config.World.PlotCount?)", player.Name)
		)
		table.insert(waiting, player)
	end
end

local function watchCharacter(player: Player)
	if playerMaids[player] then
		return
	end
	local maid = Maid.new()
	playerMaids[player] = maid
	maid:Add(player.CharacterAdded:Connect(function(character)
		if not byPlayer[player] then
			return
		end
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			if player.Character == character then
				teleportHome(player)
			end
		end)
	end))
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function PlotService.GetPlot(player: Player): Model?
	local state = byPlayer[player]
	return if state then state.Model else nil
end

function PlotService.GetPlotOwner(model: Model): Player?
	local userId = model:GetAttribute("OwnerUserId")
	if type(userId) ~= "number" or userId == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

function PlotService.GetVaultPosition(player: Player): Vector3?
	local state = byPlayer[player]
	local pad = state and state.Model:FindFirstChild("VaultPad")
	if pad and pad:IsA("BasePart") then
		return pad.Position
	end
	return nil
end

function PlotService.GetLeverPosition(player: Player, line: number): Vector3?
	local state = byPlayer[player]
	local model = state and state.Model:FindFirstChild("Line_" .. line)
	local lever = model and model:FindFirstChild("Lever")
	if lever and lever:IsA("BasePart") then
		return lever.Position
	end
	return nil
end

function PlotService.GetSpawnCFrame(player: Player): CFrame?
	local state = byPlayer[player]
	return if state then spawnCFrame(state) else nil
end

function PlotService.TeleportHome(player: Player)
	teleportHome(player)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function PlotService.Init()
	local built = WorldBuilder.Build()
	plotsFolder = built.Plots
	for i = 1, World.PlotCount do
		table.insert(plots, buildShell(i))
	end
end

function PlotService.Start()
	local function withData(player: Player, fn: (PlotState, Types.PlayerData) -> ())
		local state = byPlayer[player]
		local data = DataService.Get(player)
		if state and data then
			fn(state, data)
		end
	end

	DataService.Loaded:Connect(onLoaded)

	ServerSignals.LinesChanged:Connect(function(player, line)
		withData(player, function(state, data)
			updateLine(state, data, line)
			updateSign(state, data)
		end)
	end)
	local function fullRefresh(player: Player)
		withData(player, function(state, data)
			refresh(state, data)
			teleportHome(player)
		end)
	end
	ServerSignals.Expanded:Connect(fullRefresh)
	ServerSignals.Franchised:Connect(fullRefresh)
	ServerSignals.MultipliersDirty:Connect(function(player)
		withData(player, updateBays)
	end)

	Players.PlayerAdded:Connect(watchCharacter)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
		local data = DataService.Get(player)
		if data and DataService.IsLoaded(player) then
			onLoaded(player, data)
		end
	end
end

return PlotService

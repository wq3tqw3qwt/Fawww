--!strict
--[[
	VisualsController: everything that moves in the world, client-side only.
	- Pooled conveyor items (one RenderStepped connection animates every visible line).
	- Delivery trucks, the bottleneck ring, floating "+$" text.
	- Overdrive lever / build pad prompts.
	- Effect events: milestones, line drop-in, vault coins, rockets, expansion shockwave.
	- VIP door opens locally when the VIP pass is owned.
	The server never creates per-item parts; this controller only reads the plot naming contract
	(docs/03-architecture.md section 9) and tolerates parts streaming in and out.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local VisualsController = {}

local LocalPlayer = Players.LocalPlayer
local Visuals = Config.Visuals
local ConveyorCfg = Visuals.Conveyor
local TruckCfg = Visuals.Truck
local RocketCfg = Visuals.Rocket
local EffectsCfg = Visuals.Effects
local BottleneckCfg = Visuals.Bottleneck
local Palette = Visuals.Palette

local FIND_TIMEOUT = 30

type LineVis = {
	Index: number,
	Model: Model,
	Belt: BasePart,
	Start: Attachment,
	Finish: Attachment,
	Items: { Part },
	Cframes: { CFrame },
	Phase: number,
}

type TruckVis = {
	Model: Model,
	Label: TextLabel,
	Progress: number, -- 0..1 while driving
	Running: boolean,
}

type PlotVis = {
	Model: Model,
	Maid: any,
	Lines: { [number]: LineVis },
	Truck: TruckVis?,
	TruckClock: number,
}

local plotVis: { [Model]: PlotVis } = {}
local rings: { [number]: Part } = {}
local visualsFolder: Folder? = nil
local plotsFolder: Folder? = nil
local rootMaid = Maid.new()
local rng = Random.new()
local clock = 0
local scanTimer = 0
local lastLowGraphics = false

--------------------------------------------------------------------------------
-- Lazy access to other controllers (written separately; never hard-fail)
--------------------------------------------------------------------------------
local dataController: any = nil
local dataTriedAt = -math.huge

local function getData(): any
	if dataController then
		return dataController
	end
	if os.clock() - dataTriedAt < 2 then
		return nil
	end
	dataTriedAt = os.clock()
	local module = script.Parent:FindFirstChild("DataController")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			dataController = result
		end
	end
	return dataController
end

local function playerData(): any
	local dc = getData()
	if dc and type(dc.Get) == "function" then
		local ok, result = pcall(dc.Get)
		if ok then
			return result
		end
	end
	return nil
end

local function runtimeState(): any
	local dc = getData()
	if dc and type(dc.GetRuntime) == "function" then
		local ok, result = pcall(dc.GetRuntime)
		if ok then
			return result
		end
	end
	return nil
end

local function isLowGraphics(): boolean
	local data = playerData()
	return data ~= nil and data.Settings ~= nil and data.Settings.LowGraphics == true
end

local function toast(kind: string, text: string)
	local module = script.Parent:FindFirstChild("NotificationController")
	if module and module:IsA("ModuleScript") then
		local ok, controller = pcall(require, module)
		if ok and type(controller) == "table" then
			for _, name in { "Toast", "Notify", "Show" } do
				local fn = (controller :: any)[name]
				if type(fn) == "function" then
					if pcall(fn, kind, text) then
						return
					end
				end
			end
		end
	end
	print(string.format("[Visuals] %s: %s", kind, text))
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local function getFolder(): Folder
	if visualsFolder and visualsFolder.Parent then
		return visualsFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientVisuals"
	folder.Parent = Workspace
	visualsFolder = folder
	return folder
end

local function addEmitter(
	parent: Instance,
	preset: string,
	color: Color3?,
	face: Enum.NormalId?,
	rateScale: number?
): ParticleEmitter?
	local def = Visuals.Particles[preset]
	if not def then
		return nil
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FX_" .. preset
	emitter.Texture = def.Texture
	emitter.Rate = def.Rate * (rateScale or 1)
	emitter.Lifetime = NumberRange.new(def.LifetimeMin, def.LifetimeMax)
	emitter.Speed = NumberRange.new(def.SpeedMin, def.SpeedMax)
	emitter.SpreadAngle = Vector2.new(def.Spread, def.Spread)
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, def.Size), NumberSequenceKeypoint.new(1, def.SizeEnd) })
	emitter.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, def.Transparency), NumberSequenceKeypoint.new(1, 1) })
	emitter.Color = ColorSequence.new(color or def.Color)
	emitter.LightEmission = def.LightEmission
	emitter.Acceleration = def.Acceleration
	emitter.EmissionDirection = face or Enum.NormalId.Top
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = parent
	return emitter
end

local function newAnchor(position: Vector3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = "FxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Position = position
	part.Parent = getFolder()
	Debris:AddItem(part, lifetime)
	return part
end

-- One-shot particle burst at a position (skipped on low graphics).
local function burst(position: Vector3, preset: string, color: Color3?, count: number?)
	if isLowGraphics() then
		return
	end
	local anchor = newAnchor(position, 3)
	local emitter = addEmitter(anchor, preset, color, nil, 0)
	if emitter then
		emitter:Emit(count or EffectsCfg.BurstCount)
	end
end

local function floatText(position: Vector3, text: string, color: Color3, rise: number?)
	local seconds = EffectsCfg.TextSeconds
	local anchor = newAnchor(position, seconds + 0.3)
	local labels = Visuals.Labels
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 64)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.StudsOffsetWorldSpace = Vector3.zero
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = labels.Font
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = labels.StrokeColor
	label.TextStrokeTransparency = labels.StrokeTransparency
	label.Parent = gui
	gui.Parent = anchor
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, rise or EffectsCfg.TextRise, 0) }):Play()
	TweenService:Create(
		label,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
end

local function ownerIdOf(plot: Instance): number
	local id = plot:GetAttribute("OwnerUserId")
	return if type(id) == "number" then id else 0
end

local function findPlotOf(userId: number): Model?
	local folder = plotsFolder
	if not folder then
		return nil
	end
	for _, plot in folder:GetChildren() do
		if plot:IsA("Model") and ownerIdOf(plot) == userId then
			return plot
		end
	end
	return nil
end

local function cameraPosition(): Vector3?
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function focusPosition(): Vector3?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return cameraPosition()
end

--------------------------------------------------------------------------------
-- Conveyor items
--------------------------------------------------------------------------------
local function destroyLine(vis: PlotVis, k: number)
	local line = vis.Lines[k]
	if not line then
		return
	end
	for _, item in line.Items do
		item:Destroy()
	end
	vis.Lines[k] = nil
end

local function makeItem(index: number, color: Color3): Part
	local item = Instance.new("Part")
	item.Name = "Item"
	item.Anchored = true
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	item.Massless = true
	item.Material = Enum.Material.SmoothPlastic
	item.Shape = if index % 2 == 0 then Enum.PartType.Ball else Enum.PartType.Block
	item.Size = ConveyorCfg.ItemSize
	item.Color = color
	item.Parent = getFolder()
	return item
end

local function hallOfLine(k: number): number
	local def = Config.Lines[k]
	return if def then def.Hall else 1
end

local function lineItemTarget(length: number, low: boolean): number
	local count = math.clamp(math.floor(length / ConveyorCfg.ItemSpacing), 1, ConveyorCfg.MaxItemsPerLine)
	if low then
		count = math.max(1, math.floor(count * ConveyorCfg.LowGraphicsScale))
	end
	return count
end

local function ensureLine(vis: PlotVis, k: number, model: Model, low: boolean): LineVis?
	local belt = model:FindFirstChild("Belt")
	if not belt or not belt:IsA("BasePart") then
		return nil
	end
	local start = belt:FindFirstChild("BeltStart")
	local finish = belt:FindFirstChild("BeltEnd")
	if not start or not start:IsA("Attachment") or not finish or not finish:IsA("Attachment") then
		return nil
	end
	local existing: LineVis? = vis.Lines[k]
	if existing and (existing.Model ~= model or existing.Belt ~= belt) then
		destroyLine(vis, k)
		existing = nil
	end
	local length = (finish.WorldPosition - start.WorldPosition).Magnitude
	local want = lineItemTarget(length, low)
	local state: LineVis
	if existing then
		state = existing
	else
		state = {
			Index = k,
			Model = model,
			Belt = belt,
			Start = start,
			Finish = finish,
			Items = {},
			Cframes = {},
			Phase = rng:NextNumber(),
		}
		vis.Lines[k] = state
	end
	local color = Config.Halls[hallOfLine(k)].Color
	while #state.Items < want do
		table.insert(state.Items, makeItem(#state.Items + 1, color))
	end
	while #state.Items > want do
		local item = table.remove(state.Items) :: Part
		item:Destroy()
	end
	state.Cframes = table.create(#state.Items, CFrame.identity)
	return state
end

local function lineSpeed(plot: Model, k: number, runtime: any): number
	if ownerIdOf(plot) ~= LocalPlayer.UserId then
		return ConveyorCfg.OtherPlayerSpeed
	end
	local entry = runtime and runtime.Lines and runtime.Lines[k]
	if type(entry) ~= "table" then
		return ConveyorCfg.BaseItemSpeed
	end
	local output = tonumber(entry.Output) or 0
	local speed = ConveyorCfg.BaseItemSpeed + ConveyorCfg.SpeedPerDecade * math.log10(1 + math.max(output, 0))
	if (tonumber(entry.OverdriveLeft) or 0) > 0 then
		speed = ConveyorCfg.MaxItemSpeed
	end
	return math.clamp(speed, ConveyorCfg.BaseItemSpeed, ConveyorCfg.MaxItemSpeed)
end

local function stepLines(dt: number)
	local runtime = runtimeState()
	local up = Vector3.new(0, ConveyorCfg.ItemSize.Y / 2, 0)
	for plot, vis in plotVis do
		for k, line in vis.Lines do
			local a = line.Start.WorldPosition
			local b = line.Finish.WorldPosition
			local length = (b - a).Magnitude
			local count = #line.Items
			if length > 0 and count > 0 then
				line.Phase = (line.Phase + dt * lineSpeed(plot, k, runtime) / length) % 1
				local rotation = CFrame.lookAt(a, b).Rotation
				local cfs = line.Cframes
				for i = 1, count do
					local t = (line.Phase + (i - 1) / count) % 1
					cfs[i] = CFrame.new(a:Lerp(b, t) + up) * rotation
				end
				Workspace:BulkMoveTo(line.Items, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Trucks
--------------------------------------------------------------------------------
local function buildTruck(): TruckVis
	local size = TruckCfg.Size
	local length, height, width = size.X, size.Y, size.Z
	local model = Instance.new("Model")
	model.Name = "Truck"
	local wheelD = height * 0.45

	local function part(name: string, partSize: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = material or Enum.Material.SmoothPlastic
		p.Color = color
		p.Size = partSize
		p.CFrame = CFrame.new(offset)
		p.Parent = model
		return p
	end

	-- Front of the truck is -Z; origin sits on the road surface.
	local cargo = part(
		"Cargo",
		Vector3.new(width, height, length * 0.65),
		Vector3.new(0, wheelD * 0.6 + height / 2, length * 0.17),
		Palette.Truck
	)
	part(
		"Cab",
		Vector3.new(width, height * 0.8, length * 0.28),
		Vector3.new(0, wheelD * 0.6 + height * 0.4, -length * 0.36),
		TruckCfg.CabColor
	)
	part(
		"Window",
		Vector3.new(width * 0.8, height * 0.3, 0.1),
		Vector3.new(0, wheelD * 0.6 + height * 0.55, -length * 0.5 - 0.05),
		Visuals.Stage.GlassColor,
		Enum.Material.Glass
	)
	part(
		"Stripe",
		Vector3.new(width + 0.1, 0.4, length * 0.65),
		cargo.Position + Vector3.new(0, 0.2, 0),
		Palette.Cash,
		Enum.Material.Neon
	)
	for _, z in { -length * 0.36, length * 0.38 } do
		for _, x in { -width / 2, width / 2 } do
			local wheel = Instance.new("Part")
			wheel.Name = "Wheel"
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Anchored = true
			wheel.CanCollide = false
			wheel.CanQuery = false
			wheel.CanTouch = false
			wheel.CastShadow = false
			wheel.Color = TruckCfg.WheelColor
			wheel.Size = Vector3.new(0.5, wheelD, wheelD)
			wheel.CFrame = CFrame.new(x, wheelD / 2, z)
			wheel.Parent = model
		end
	end
	model.PrimaryPart = cargo
	cargo.PivotOffset = CFrame.new(0, -(wheelD * 0.6 + height / 2), -length * 0.17)

	local gui = Instance.new("BillboardGui")
	gui.Name = "CashText"
	gui.Size = UDim2.fromOffset(240, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + TruckCfg.TextRise / 2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Visuals.Labels.Font
	label.TextScaled = true
	label.TextColor3 = Palette.Cash
	label.TextStrokeColor3 = Visuals.Labels.StrokeColor
	label.TextStrokeTransparency = Visuals.Labels.StrokeTransparency
	label.Text = ""
	label.Parent = gui
	gui.Parent = cargo
	return { Model = model, Label = label, Progress = 0, Running = false }
end

local function startTruck(plot: Model, vis: PlotVis)
	local state: TruckVis
	if vis.Truck then
		state = vis.Truck
	else
		state = buildTruck()
		vis.Truck = state
		vis.Maid:Add(state.Model)
	end
	local local_ = ownerIdOf(plot) == LocalPlayer.UserId
	local gui = state.Label.Parent :: BillboardGui
	if local_ then
		local runtime = runtimeState()
		local income = runtime and tonumber(runtime.Income) or 0
		state.Label.Text = "+" .. NumberFormat.Cash(income * Visuals.TruckIntervalSeconds)
		gui.Enabled = true
	else
		gui.Enabled = false
	end
	state.Progress = 0
	state.Running = true
	state.Model.Parent = getFolder()
end

local function stepTruck(plot: Model, vis: PlotVis, dt: number, near: boolean)
	vis.TruckClock += dt
	local truck = vis.Truck
	if truck and truck.Running then
		local dock = plot:FindFirstChild("Dock")
		local a = dock and dock:FindFirstChild("TruckStart")
		local b = dock and dock:FindFirstChild("TruckEnd")
		if a and b and a:IsA("Attachment") and b:IsA("Attachment") then
			truck.Progress += dt / TruckCfg.DriveSeconds
			if truck.Progress >= 1 then
				truck.Running = false
				truck.Model.Parent = nil
			else
				local from, to = a.WorldPosition, b.WorldPosition
				local pos = from:Lerp(to, truck.Progress)
				truck.Model:PivotTo(CFrame.lookAt(pos, pos + (to - from)))
			end
		else
			truck.Running = false
			truck.Model.Parent = nil
		end
	elseif near and vis.TruckClock >= Visuals.TruckIntervalSeconds then
		vis.TruckClock = 0
		startTruck(plot, vis)
	end
end

--------------------------------------------------------------------------------
-- Bottleneck rings (local plot only)
--------------------------------------------------------------------------------
local function ringFor(k: number): Part
	local ring = rings[k]
	if ring then
		return ring
	end
	local part = Instance.new("Part")
	part.Name = "BottleneckRing"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Palette.Bottleneck
	part.Size = Vector3.new(BottleneckCfg.Thickness, BottleneckCfg.Diameter, BottleneckCfg.Diameter)
	rings[k] = part
	return part
end

local function hideRing(k: number)
	local ring = rings[k]
	if ring then
		ring.Parent = nil
	end
end

local function updateRings(plot: Model, focus: Vector3?)
	local runtime = runtimeState()
	local lines = runtime and runtime.Lines
	for k = 1, #Config.Lines do
		local entry = if type(lines) == "table" then lines[k] else nil
		local stageIndex = if type(entry) == "table" then tonumber(entry.Bottleneck) or 0 else 0
		local line = plot:FindFirstChild("Line_" .. k)
		local stage = if line and stageIndex > 0 then line:FindFirstChild("Stage_" .. stageIndex) else nil
		local root = if stage and stage:IsA("Model") then stage.PrimaryPart else nil
		if root and focus and (root.Position - focus).Magnitude <= BottleneckCfg.Radius then
			local ring = ringFor(k)
			ring.CFrame = CFrame.new(root.Position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			if ring.Parent ~= getFolder() then
				ring.Parent = getFolder()
			end
		else
			hideRing(k)
		end
	end
end

local function stepRings()
	local phase = (math.sin(clock * 2 * math.pi / BottleneckCfg.PulseSeconds) + 1) / 2
	local transparency = BottleneckCfg.MinTransparency
		+ (BottleneckCfg.MaxTransparency - BottleneckCfg.MinTransparency) * phase
	for _, ring in rings do
		if ring.Parent then
			ring.Transparency = transparency
		end
	end
end

--------------------------------------------------------------------------------
-- Scanning: which plots/lines are close enough to animate
--------------------------------------------------------------------------------
local function setEmitters(root: Instance, enabled: boolean)
	for _, inst in root:GetDescendants() do
		if inst:IsA("ParticleEmitter") and string.sub(inst.Name, 1, 3) == "FX_" then
			inst.Enabled = enabled
		end
	end
end

local function scan()
	local camera = cameraPosition()
	local focus = focusPosition()
	if not camera then
		return
	end
	local low = isLowGraphics()
	local radius = ConveyorCfg.VisibleRadius
	local plotReach = radius + Config.World.PlotSize.Z / 2
	local localPlot: Model? = nil

	for plot, vis in plotVis do
		local base = plot:FindFirstChild("Base")
		local near = base ~= nil and base:IsA("BasePart") and (base.Position - camera).Magnitude <= plotReach
		local isLocal = ownerIdOf(plot) == LocalPlayer.UserId
		if isLocal then
			localPlot = plot
		end

		local seen: { [number]: boolean } = {}
		if near then
			for _, child in plot:GetChildren() do
				local index = tonumber(string.match(child.Name, "^Line_(%d+)$"))
				if index and child:IsA("Model") and child:GetAttribute("Owned") == true then
					local belt = child:FindFirstChild("Belt")
					if belt and belt:IsA("BasePart") and (belt.Position - camera).Magnitude <= radius then
						local before = vis.Lines[index]
						local line = ensureLine(vis, index, child, low)
						if line then
							seen[index] = true
							if not before and low then
								setEmitters(child, false)
							end
						end
					end
				end
			end
		end
		for k in vis.Lines do
			if not seen[k] then
				destroyLine(vis, k)
			end
		end
		if not near and vis.Truck and vis.Truck.Running then
			vis.Truck.Running = false
			vis.Truck.Model.Parent = nil
		end
	end

	if localPlot then
		updateRings(localPlot, focus)
	else
		for k in rings do
			hideRing(k)
		end
	end

	if low ~= lastLowGraphics then
		lastLowGraphics = low
		for plot in plotVis do
			setEmitters(plot, not low)
		end
	end
end

local function step(dt: number)
	clock += dt
	scanTimer += dt
	if scanTimer >= ConveyorCfg.ScanSeconds then
		scanTimer = 0
		scan()
	end
	stepLines(dt)
	local camera = cameraPosition()
	for plot, vis in plotVis do
		local base = plot:FindFirstChild("Base")
		local near = camera ~= nil
			and base ~= nil
			and base:IsA("BasePart")
			and (base.Position - camera).Magnitude <= ConveyorCfg.VisibleRadius + Config.World.PlotSize.Z / 2
		stepTruck(plot, vis, dt, near)
	end
	stepRings()
end

--------------------------------------------------------------------------------
-- Plot registration
--------------------------------------------------------------------------------
local function addPlot(plot: Instance)
	if not plot:IsA("Model") or plotVis[plot] or not string.match(plot.Name, "^Plot_%d+$") then
		return
	end
	local vis: PlotVis = {
		Model = plot,
		Maid = Maid.new(),
		Lines = {},
		Truck = nil,
		TruckClock = rng:NextNumber() * Visuals.TruckIntervalSeconds,
	}
	plotVis[plot] = vis
end

local function removePlot(plot: Instance)
	local vis = plotVis[plot :: Model]
	if not vis then
		return
	end
	for k in vis.Lines do
		destroyLine(vis, k)
	end
	vis.Maid:Destroy()
	plotVis[plot :: Model] = nil
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------
local lastPrompt = 0

local function onPrompt(prompt: ProximityPrompt)
	if prompt.Name ~= "OverdrivePrompt" and prompt.Name ~= "BuildPrompt" then
		return
	end
	local now = os.clock()
	if now - lastPrompt < 0.3 then
		return
	end
	lastPrompt = now
	local lineIndex = prompt:GetAttribute("LineIndex")
	local ownerId = prompt:GetAttribute("OwnerUserId")
	if type(lineIndex) ~= "number" or type(ownerId) ~= "number" then
		return
	end
	task.spawn(function()
		if prompt.Name == "OverdrivePrompt" then
			local host = if ownerId ~= LocalPlayer.UserId then ownerId else nil
			local response = Net.Request("Overdrive", lineIndex, host)
			if not response.Ok then
				toast("Error", response.Error or "Overdrive failed")
			end
		elseif ownerId == LocalPlayer.UserId then
			local response = Net.Request("BuyLine")
			if not response.Ok then
				toast("Error", response.Error or "Cannot build yet")
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------
local function waitForLine(plot: Model, k: number, timeout: number): Model?
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local line = plot:FindFirstChild("Line_" .. k)
		if line and line:IsA("Model") and line:GetAttribute("Owned") == true and line:FindFirstChild("Stage_4") then
			return line
		end
		task.wait(0.1)
	end
	return nil
end

local function lineMilestone(payload: any)
	local plot = findPlotOf(LocalPlayer.UserId)
	local k: any = if type(payload) == "table" then payload.Line else nil
	local line = if plot and type(k) == "number" then plot:FindFirstChild("Line_" .. k) else nil
	local belt = if line then line:FindFirstChild("Belt") else nil
	if belt and belt:IsA("BasePart") then
		local pos = belt.Position + Vector3.new(0, 4, 0)
		burst(pos, "Sparkles", EffectsCfg.MilestoneColor)
		floatText(pos, EffectsCfg.MilestoneText, EffectsCfg.MilestoneColor)
	end
end

local function lineBuilt(payload: any)
	local k = type(payload) == "table" and payload.Line
	if type(k) ~= "number" then
		return
	end
	task.spawn(function()
		local plot = findPlotOf(LocalPlayer.UserId)
		local line = plot and waitForLine(plot, k, 5)
		if not line then
			return
		end
		local drop = EffectsCfg.LineDropHeight
		for s = 1, 4 do
			local stage = line:FindFirstChild("Stage_" .. s)
			if stage and stage:IsA("Model") then
				local target = stage:GetPivot()
				stage:PivotTo(target + Vector3.new(0, drop, 0))
				local value = Instance.new("CFrameValue")
				value.Value = target + Vector3.new(0, drop, 0)
				local connection = value.Changed:Connect(function(cf)
					if stage.Parent then
						stage:PivotTo(cf)
					end
				end)
				local tween = TweenService:Create(
					value,
					TweenInfo.new(
						EffectsCfg.LineDropSeconds,
						Enum.EasingStyle.Bounce,
						Enum.EasingDirection.Out,
						0,
						false,
						(s - 1) * 0.12
					),
					{ Value = target }
				)
				tween.Completed:Once(function()
					connection:Disconnect()
					value:Destroy()
					if stage.Parent then
						stage:PivotTo(target)
						burst(target.Position + Vector3.new(0, 1, 0), "Sparks", nil, 14)
					end
				end)
				tween:Play()
			end
		end
	end)
end

local function vaultCollected(payload: any)
	local plot = findPlotOf(LocalPlayer.UserId)
	local pad = plot and plot:FindFirstChild("VaultPad")
	if pad and pad:IsA("BasePart") then
		local pos = pad.Position + Vector3.new(0, 2, 0)
		burst(pos, "Coins", nil, 60)
		local amount = type(payload) == "table" and tonumber(payload.Amount) or nil
		if amount then
			floatText(pos + Vector3.new(0, 3, 0), "+" .. NumberFormat.Cash(amount), Palette.Cash)
		end
	end
end

local function buildRocket(origin: Vector3): (Model, Part)
	local d, h = RocketCfg.BodyDiameter, RocketCfg.BodyHeight
	local model = Instance.new("Model")
	model.Name = "Rocket"
	local function make(
		name: string,
		shape: Enum.PartType,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = material or Enum.Material.SmoothPlastic
		p.Color = color
		p.Size = size
		p.CFrame = cf
		p.Parent = model
		return p
	end
	local base = CFrame.new(origin + Vector3.new(0, h / 2, 0))
	local body = make(
		"Body",
		Enum.PartType.Cylinder,
		Vector3.new(h, d, d),
		base * CFrame.Angles(0, 0, math.pi / 2),
		RocketCfg.BodyColor
	)
	make("Nose", Enum.PartType.Ball, Vector3.new(d, d, d), base * CFrame.new(0, h / 2, 0), RocketCfg.NoseColor)
	make(
		"Window",
		Enum.PartType.Ball,
		Vector3.new(d * 0.5, d * 0.5, d * 0.5),
		base * CFrame.new(0, h * 0.25, -d / 2 + 0.05),
		RocketCfg.WindowColor,
		Enum.Material.Glass
	)
	for i = 0, 3 do
		local rotation = CFrame.Angles(0, math.rad(i * 90), 0)
		make(
			"Fin",
			Enum.PartType.Block,
			Vector3.new(0.3, h * 0.28, d * 0.9),
			base * rotation * CFrame.new(d / 2 + 0.2, -h * 0.34, 0),
			RocketCfg.FinColor
		)
	end
	local flame = make(
		"Flame",
		Enum.PartType.Cylinder,
		Vector3.new(RocketCfg.FlameSize.Y, RocketCfg.FlameSize.X, RocketCfg.FlameSize.Z),
		base * CFrame.new(0, -h / 2 - RocketCfg.FlameSize.Y / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		RocketCfg.FlameColor,
		Enum.Material.Neon
	)
	flame.Transparency = 0.15
	model.PrimaryPart = body
	body.PivotOffset = CFrame.identity
	return model, flame
end

local function launchRocket(payload: any)
	local userId: any = if type(payload) == "table" then payload.UserId else nil
	local plot = if type(userId) == "number" then findPlotOf(userId) else nil
	local pad = if plot then plot:FindFirstChild("RocketPad") else nil
	if not pad or not pad:IsA("BasePart") then
		return
	end
	local origin = pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)
	local model, flame = buildRocket(origin)
	local low = isLowGraphics()
	if not low then
		addEmitter(flame, "Fire", nil, Enum.NormalId.Bottom)
		addEmitter(flame, "Clouds", nil, Enum.NormalId.Bottom, 8)
	end
	model.Parent = getFolder()
	local start = model:GetPivot()
	local value = Instance.new("CFrameValue")
	value.Value = start
	local connection = value.Changed:Connect(function(cf)
		if model.Parent then
			model:PivotTo(cf)
		end
	end)
	local tween = TweenService:Create(
		value,
		TweenInfo.new(RocketCfg.FlightSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Value = start + Vector3.new(0, RocketCfg.FlightHeight, 0) }
	)
	tween.Completed:Once(function()
		connection:Disconnect()
		value:Destroy()
		model:Destroy()
	end)
	tween:Play()
end

local function shockwave(color: Color3)
	local plot = findPlotOf(LocalPlayer.UserId)
	local base = plot and plot:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	local pos = base.Position + Vector3.new(0, 2, 0)
	burst(pos + Vector3.new(0, 4, 0), "Sparkles", color, EffectsCfg.BurstCount * 2)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.6, 2, 2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = getFolder()
	local diameter = EffectsCfg.ShockwaveRadius * 2
	local info = TweenInfo.new(EffectsCfg.ShockwaveSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(ring, info, { Size = Vector3.new(0.6, diameter, diameter), Transparency = 1 })
	tween.Completed:Once(function()
		ring:Destroy()
	end)
	tween:Play()
end

local function onEffect(kind: string, payload: any)
	if kind == "LevelMilestone" then
		lineMilestone(payload)
	elseif kind == "LineBuilt" then
		lineBuilt(payload)
	elseif kind == "VaultCollected" then
		vaultCollected(payload)
	elseif kind == "Rocket" then
		launchRocket(payload)
	elseif kind == "Expansion" then
		shockwave(EffectsCfg.ExpansionColor)
	elseif kind == "Franchise" then
		shockwave(EffectsCfg.FranchiseColor)
	end
end

--------------------------------------------------------------------------------
-- VIP door
--------------------------------------------------------------------------------
local function updateVipDoor()
	local plaza = Workspace:FindFirstChild("Plaza")
	local lounge = plaza and plaza:FindFirstChild("VIPLounge")
	local door = lounge and lounge:FindFirstChild("VIPDoor")
	if not door or not door:IsA("BasePart") then
		return
	end
	local data = playerData()
	local vip = data ~= nil and data.Passes ~= nil and data.Passes.VIP == true
	door.CanCollide = not vip
	door.Transparency = if vip then Visuals.VIPDoor.OpenTransparency else 0.3
end

local function watchVip()
	local plaza = Workspace:WaitForChild("Plaza", FIND_TIMEOUT)
	local lounge = plaza and plaza:WaitForChild("VIPLounge", FIND_TIMEOUT)
	if lounge then
		lounge:WaitForChild("VIPDoor", FIND_TIMEOUT)
	end
	updateVipDoor()
	local deadline = os.clock() + FIND_TIMEOUT
	while not getData() and os.clock() < deadline do
		task.wait(1)
	end
	local dc = getData()
	if dc and dc.Changed and type(dc.Changed.Connect) == "function" then
		rootMaid:Add(dc.Changed:Connect(function(key: string)
			if key == "Passes" or key == "Settings" then
				updateVipDoor()
			end
		end))
	end
	-- The data mirror may arrive after the door streams in; retry for a few seconds.
	for _ = 1, 10 do
		if playerData() then
			break
		end
		task.wait(2)
	end
	updateVipDoor()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function VisualsController.Init()
	getFolder()
end

function VisualsController.Start()
	rootMaid:Add(RunService.RenderStepped:Connect(step))
	rootMaid:Add(ProximityPromptService.PromptTriggered:Connect(onPrompt))
	rootMaid:Add(Net.Event("Effect").OnClientEvent:Connect(onEffect))

	task.spawn(watchVip)

	local folder = Workspace:WaitForChild("Plots", FIND_TIMEOUT)
	if not folder or not folder:IsA("Folder") then
		warn("[VisualsController] Workspace.Plots not found")
		return
	end
	plotsFolder = folder
	for _, plot in folder:GetChildren() do
		addPlot(plot)
	end
	rootMaid:Add(folder.ChildAdded:Connect(addPlot))
	rootMaid:Add(folder.ChildRemoved:Connect(removePlot))
end

return VisualsController

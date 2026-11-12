--!strict
--[[
	WorldBuilder: builds everything that is not a player plot: lighting, ground, roads, the central
	plaza (spawn, leaderboards, trade plaza, VIP lounge, mega board) and decorative props.
	Everything is made of simple Parts; all numbers live in Config.World / Config.Visuals.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BuildKit = require(script.Parent.BuildKit)
local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local World = Config.World
local Visuals = Config.Visuals
local Palette = Visuals.Palette
local PlazaCfg = Visuals.Plaza
local Props = Visuals.Props

local PLAZA_TOP = PlazaCfg.Thickness

--------------------------------------------------------------------------------
-- Plot placement (shared with PlotService)
--------------------------------------------------------------------------------
-- Plots sit on a ring; indices start at an offset so the plaza axes stay free for landmarks.
function WorldBuilder.PlotAngle(index: number): number
	return (index - 0.5) * 2 * math.pi / World.PlotCount
end

-- Plot-local axes: -Z points at the plaza, +Y up.
function WorldBuilder.PlotCFrame(index: number): CFrame
	local a = WorldBuilder.PlotAngle(index)
	local pos = Vector3.new(math.cos(a) * World.PlotRingRadius, 0, math.sin(a) * World.PlotRingRadius)
	return CFrame.lookAt(pos, Vector3.zero)
end

local function polar(radius: number, angle: number, y: number?): Vector3
	return Vector3.new(math.cos(angle) * radius, y or 0, math.sin(angle) * radius)
end

--------------------------------------------------------------------------------
-- Lighting
--------------------------------------------------------------------------------
local function replaceEffect(className: string, name: string): Instance
	local old = Lighting:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local function buildLighting()
	local cfg = Visuals.Lighting
	Lighting.ClockTime = cfg.ClockTime
	Lighting.Brightness = cfg.Brightness
	Lighting.Ambient = cfg.Ambient
	Lighting.OutdoorAmbient = cfg.OutdoorAmbient
	Lighting.GlobalShadows = true

	local atmosphere = replaceEffect("Atmosphere", "FactoryAtmosphere") :: Atmosphere
	atmosphere.Density = cfg.AtmosphereDensity
	atmosphere.Haze = cfg.AtmosphereHaze
	atmosphere.Color = cfg.AtmosphereColor

	local bloom = replaceEffect("BloomEffect", "FactoryBloom") :: BloomEffect
	bloom.Intensity = cfg.BloomIntensity
	bloom.Size = cfg.BloomSize
	bloom.Threshold = cfg.BloomThreshold

	local color = replaceEffect("ColorCorrectionEffect", "FactoryColor") :: ColorCorrectionEffect
	color.Saturation = cfg.Saturation
	color.Contrast = cfg.Contrast
	color.TintColor = cfg.TintColor

	replaceEffect("SunRaysEffect", "FactorySunRays")
	replaceEffect("Sky", "FactorySky")
end

--------------------------------------------------------------------------------
-- Small builders
--------------------------------------------------------------------------------
local function box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	return BuildKit.Part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		CanCollide = collide,
		Parent = parent,
	})
end

local function disc(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	pos: Vector3,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	return BuildKit.Cylinder({
		Name = name,
		Size = Vector3.new(diameter, height, diameter),
		Position = pos,
		Color = color,
		Material = material,
		CanCollide = collide,
		Parent = parent,
	}, "Y")
end

local function road(parent: Instance, name: string, a: Vector3, b: Vector3, width: number)
	local mid = (a + b) / 2
	local thickness = PlazaCfg.RoadThickness
	box(
		parent,
		name,
		Vector3.new(width, thickness, (b - a).Magnitude),
		CFrame.lookAt(mid + Vector3.new(0, thickness / 2, 0), b + Vector3.new(0, thickness / 2, 0)),
		Palette.Road,
		Enum.Material.SmoothPlastic,
		true
	)
end

local function lamp(parent: Instance, pos: Vector3, withLight: boolean)
	local color = Props.LampColor
	BuildKit.Cylinder({
		Name = "LampPole",
		Size = Vector3.new(0.5, 9, 0.5),
		Position = pos + Vector3.new(0, 4.5, 0),
		Color = Visuals.Stage.DarkColor,
		Material = Enum.Material.Metal,
		CastShadow = false,
		Parent = parent,
	}, "Y")
	local head = BuildKit.Ball({
		Name = "LampHead",
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = pos + Vector3.new(0, 9.4, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CastShadow = false,
		Parent = parent,
	})
	if withLight then
		BuildKit.Light(head, color, 1, 28)
	end
end

local function tree(parent: Instance, pos: Vector3, rng: Random)
	local scale = 0.8 + rng:NextNumber() * 0.7
	local leaves = Props.LeafColors[rng:NextInteger(1, #Props.LeafColors)]
	BuildKit.Cylinder({
		Name = "Trunk",
		Size = Vector3.new(1.3 * scale, 5 * scale, 1.3 * scale),
		Position = pos + Vector3.new(0, 2.5 * scale, 0),
		Color = Props.TrunkColor,
		CastShadow = false,
		Parent = parent,
	}, "Y")
	for i, d in { 6.5, 5, 3.4 } do
		BuildKit.Ball({
			Name = "Leaves",
			Size = Vector3.new(d * scale, d * scale, d * scale),
			Position = pos + Vector3.new(0, (4.4 + (i - 1) * 2.2) * scale, 0),
			Color = leaves,
			CastShadow = i == 1,
			Parent = parent,
		})
	end
end

local function boardGui(part: Part, guiName: string, title: string, canvas: Vector2, leaderboard: boolean): SurfaceGui
	local labels = Visuals.Labels
	local gui = Instance.new("SurfaceGui")
	gui.Name = guiName
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = true
	gui.Parent = part

	-- Leaderboard boards: LeaderboardService replaces every "LB_*" label; the part itself is the dark background.
	local label = Instance.new("TextLabel")
	label.Name = if leaderboard then "LB_Title" else "Title"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.92, if leaderboard then 0.08 else 0.5)
	label.Position = UDim2.fromScale(0.04, if leaderboard then 0 else 0.25)
	label.Font = labels.Font
	label.TextScaled = true
	label.TextXAlignment = if leaderboard then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.Text = title
	label.TextColor3 = Palette.UIAccent
	label.Parent = gui
	return gui
end

--------------------------------------------------------------------------------
-- Ground and roads
--------------------------------------------------------------------------------
local function buildGround(world: Instance)
	local extent = 2 * (World.PlotRingRadius + World.PlotSize.Z / 2 + PlazaCfg.GroundMargin)
	box(
		world,
		"Ground",
		Vector3.new(extent, 1, extent),
		CFrame.new(0, -0.5, 0),
		Palette.Ground,
		Enum.Material.SmoothPlastic,
		true
	)
end

local function ringRoadRadius(): number
	return World.PlotRingRadius - World.PlotSize.Z / 2 - PlazaCfg.RingRoadMargin
end

local function buildRoads(parent: Instance)
	local roads = BuildKit.Folder("Roads", parent)
	local width = PlazaCfg.RoadWidth
	local front = World.PlotRingRadius - World.PlotSize.Z / 2
	local ringR = ringRoadRadius()
	for i = 1, World.PlotCount do
		local a = WorldBuilder.PlotAngle(i)
		local b = WorldBuilder.PlotAngle(i % World.PlotCount + 1)
		if i == World.PlotCount then
			b += 2 * math.pi
		end
		road(roads, "Spoke_" .. i, polar(World.PlazaRadius - 2, a), polar(front, a), width)
		road(roads, "Ring_" .. i, polar(ringR, a), polar(ringR, b), width * 0.7)
	end
end

--------------------------------------------------------------------------------
-- Plaza pieces
--------------------------------------------------------------------------------
local function buildMonument(plaza: Instance)
	local folder = BuildKit.Folder("Monument", plaza)
	local dark = Visuals.Stage.DarkColor
	local metal = Visuals.Stage.MetalColor
	local gold = PlazaCfg.InnerRingColor
	local h = PlazaCfg.StatueHeight
	disc(folder, "Pedestal", 12, 1.2, Vector3.new(0, PLAZA_TOP + 0.6, 0), dark, Enum.Material.Metal, true)
	disc(folder, "PedestalTop", 9, 0.6, Vector3.new(0, PLAZA_TOP + 1.5, 0), metal, Enum.Material.Metal, true)
	-- Big gear with teeth, a column and a glowing globe on top.
	local gearY = PLAZA_TOP + 2.2
	BuildKit.Cylinder({
		Name = "Gear",
		Size = Vector3.new(7, 1, 7),
		Position = Vector3.new(0, gearY, 0),
		Color = gold,
		Material = Enum.Material.Metal,
		CastShadow = false,
		Parent = folder,
	}, "Y")
	for i = 0, 11 do
		local a = i * math.pi / 6
		box(
			folder,
			"Tooth",
			Vector3.new(1.2, 1, 1.6),
			CFrame.new(polar(3.8, a, gearY)) * CFrame.Angles(0, -a, 0),
			gold,
			Enum.Material.Metal
		).CastShadow =
			false
	end
	BuildKit.Cylinder({
		Name = "Column",
		Size = Vector3.new(1.4, h - 6, 1.4),
		Position = Vector3.new(0, gearY + (h - 6) / 2, 0),
		Color = metal,
		Material = Enum.Material.Metal,
		Parent = folder,
	}, "Y")
	local globe = BuildKit.Ball({
		Name = "Globe",
		Size = Vector3.new(5, 5, 5),
		Position = Vector3.new(0, gearY + h - 6 + 2.5, 0),
		Color = Palette.Cash,
		Material = Enum.Material.Neon,
		CastShadow = false,
		Parent = folder,
	})
	BuildKit.AddParticles(globe, "Sparkles")
	BuildKit.Light(globe, Palette.Cash, 1.5, 40)
end

local function buildSpawn(plaza: Instance)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.AllowTeamChangeOnTouch = false
	BuildKit.Apply(spawn, {
		Size = PlazaCfg.SpawnSize,
		Position = PlazaCfg.SpawnOffset + Vector3.new(0, PLAZA_TOP + PlazaCfg.SpawnSize.Y / 2, 0),
		Color = Palette.UIAccent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		Transparency = 0.4,
		Parent = plaza,
	})
	-- Reapply because SpawnLocation sets a decal texture on its top face by default.
	for _, child in spawn:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
end

local function buildLeaderboards(plaza: Instance)
	local folder = BuildKit.Folder("Leaderboards", plaza)
	local boards = Config.Leaderboards.Boards
	local size = PlazaCfg.BoardSize
	local centerAngle = math.rad(PlazaCfg.BoardCenterAngleDegrees)
	local step = math.rad(PlazaCfg.BoardAngleStepDegrees)
	local dark = Visuals.Stage.DarkColor
	for i, def in boards do
		local a = centerAngle + (i - (#boards + 1) / 2) * step
		local base = polar(PlazaCfg.BoardRadius, a, PLAZA_TOP)
		local facing = CFrame.lookAt(base, Vector3.new(0, PLAZA_TOP, 0))
		local board = box(
			folder,
			"Board_" .. def.Key,
			size,
			facing * CFrame.new(0, size.Y / 2 + 1.5, 0),
			dark,
			Enum.Material.SmoothPlastic,
			true
		)
		board:SetAttribute("BoardKey", def.Key)
		boardGui(board, "Board", def.Title, PlazaCfg.BoardCanvas, true)
		-- Neon frame and two posts.
		local frameColor = Palette.UIAccent
		local half = size / 2
		local mid = facing * CFrame.new(0, size.Y / 2 + 1.5, 0.05)
		for _, side in { -1, 1 } do
			box(
				folder,
				"FrameV",
				Vector3.new(0.4, size.Y + 0.4, 0.3),
				mid * CFrame.new(side * (half.X + 0.2), 0, -0.4),
				frameColor,
				Enum.Material.Neon
			).CastShadow =
				false
			box(
				folder,
				"Post",
				Vector3.new(0.8, 1.5, 0.8),
				facing * CFrame.new(side * (half.X - 1), 0.75, 0),
				dark,
				Enum.Material.Metal
			).CastShadow =
				false
		end
		for _, side in { -1, 1 } do
			box(
				folder,
				"FrameH",
				Vector3.new(size.X + 0.8, 0.4, 0.3),
				mid * CFrame.new(0, side * (half.Y + 0.2), -0.4),
				frameColor,
				Enum.Material.Neon
			).CastShadow =
				false
		end
	end
end

local function buildMegaBoard(plaza: Instance)
	local model = BuildKit.Model("MegaBoard", plaza)
	local angle = math.rad(PlazaCfg.MegaBoardAngleDegrees)
	local size = PlazaCfg.MegaBoardSize
	local base = polar(World.PlazaRadius - 6, angle, PLAZA_TOP)
	local facing = CFrame.lookAt(base, Vector3.new(0, PLAZA_TOP, 0))
	local dark = Visuals.Stage.DarkColor
	local board =
		box(model, "Board", size, facing * CFrame.new(0, size.Y / 2 + 3, 0), dark, Enum.Material.SmoothPlastic, true)
	boardGui(board, "MegaBoard", "MEGA CONTRACT", Vector2.new(size.X * 24, size.Y * 24), false)
	for _, side in { -1, 1 } do
		box(
			model,
			"Post",
			Vector3.new(1, 3.4, 1),
			facing * CFrame.new(side * (size.X / 2 - 2), 1.7, 0),
			Visuals.Stage.MetalColor,
			Enum.Material.Metal
		)
	end
	box(
		model,
		"Frame",
		size + Vector3.new(1, 1, -0.4),
		facing * CFrame.new(0, size.Y / 2 + 3, 0.25),
		Palette.UIAccent,
		Enum.Material.Neon
	).CastShadow =
		false
	model.PrimaryPart = board
end

local function buildTradePlaza(plaza: Instance)
	local model = BuildKit.Model("TradePlaza", plaza)
	local angle = math.rad(PlazaCfg.TradeAngleDegrees)
	local center = polar(PlazaCfg.TradeRadius, angle)
	local r = PlazaCfg.TradePadRadius
	local ring = disc(
		model,
		"TradePad",
		r * 2,
		0.3,
		center + Vector3.new(0, PLAZA_TOP + 0.2, 0),
		Palette.UIAccent,
		Enum.Material.Neon,
		true
	)
	disc(
		model,
		"TradePadInner",
		r * 2 - 1.6,
		0.34,
		center + Vector3.new(0, PLAZA_TOP + 0.2, 0),
		Palette.Plaza,
		Enum.Material.SmoothPlastic,
		true
	)
	local facing = CFrame.lookAt(center, Vector3.zero)
	-- Two stalls and an overhead banner.
	for _, side in { -1, 1 } do
		box(
			model,
			"Post",
			Vector3.new(0.8, 9, 0.8),
			facing * CFrame.new(side * (r - 1), PLAZA_TOP + 4.5, 0),
			Visuals.Stage.DarkColor,
			Enum.Material.Metal
		)
		box(
			model,
			"Stall",
			Vector3.new(3, 1, 2),
			facing * CFrame.new(side * (r * 0.45), PLAZA_TOP + 0.5, r * 0.55),
			Palette.UIPanel,
			Enum.Material.SmoothPlastic,
			true
		)
	end
	local banner = box(
		model,
		"Banner",
		Vector3.new(r * 2, 3, 0.6),
		facing * CFrame.new(0, PLAZA_TOP + 9.5, 0),
		Palette.UIPanel,
		Enum.Material.SmoothPlastic
	)
	BuildKit.SurfaceText(banner, Enum.NormalId.Front, "TRADE PLAZA", Palette.UIAccent)
	BuildKit.SurfaceText(banner, Enum.NormalId.Back, "TRADE PLAZA", Palette.UIAccent)
	BuildKit.AddParticles(ring, "Sparkles", Palette.UIAccent, nil, 0.6)
	model.PrimaryPart = ring
end

local function buildVIPLounge(plaza: Instance)
	local model = BuildKit.Model("VIPLounge", plaza)
	local center = polar(PlazaCfg.VIPRadius, math.rad(PlazaCfg.VIPAngleDegrees))
	local frame = CFrame.lookAt(center, Vector3.zero) -- -Z is the entrance side
	local size = PlazaCfg.VIPSize
	local gold = PlazaCfg.VIPColor
	local dark = Visuals.Stage.DarkColor
	local doorSize = PlazaCfg.VIPDoorSize
	local base = PLAZA_TOP

	local function put(
		name: string,
		localPos: Vector3,
		partSize: Vector3,
		color: Color3,
		material: Enum.Material?,
		collide: boolean?
	)
		return box(model, name, partSize, frame * CFrame.new(localPos), color, material, collide)
	end

	local floor = put(
		"Floor",
		Vector3.new(0, base + 0.2, 0),
		Vector3.new(size.X, 0.4, size.Z),
		BuildKit.Darken(gold, 0.55),
		Enum.Material.SmoothPlastic,
		true
	)
	put(
		"Carpet",
		Vector3.new(0, base + 0.45, 0),
		Vector3.new(size.X * 0.6, 0.1, size.Z * 0.6),
		Color3.fromRGB(150, 30, 50),
		nil
	)
	local wallY = base + size.Y / 2
	put(
		"WallBack",
		Vector3.new(0, wallY, size.Z / 2),
		Vector3.new(size.X, size.Y, 1),
		dark,
		Enum.Material.SmoothPlastic,
		true
	)
	for _, side in { -1, 1 } do
		put(
			"WallSide",
			Vector3.new(side * size.X / 2, wallY, 0),
			Vector3.new(1, size.Y, size.Z),
			dark,
			Enum.Material.SmoothPlastic,
			true
		)
		local sideWidth = (size.X - doorSize.X) / 2
		put(
			"WallFront",
			Vector3.new(side * (doorSize.X / 2 + sideWidth / 2), wallY, -size.Z / 2),
			Vector3.new(sideWidth, size.Y, 1),
			dark,
			Enum.Material.SmoothPlastic,
			true
		)
		put(
			"Pillar",
			Vector3.new(side * (doorSize.X / 2 + 0.3), wallY, -size.Z / 2 - 0.6),
			Vector3.new(0.6, size.Y, 0.6),
			gold,
			Enum.Material.Neon
		).CastShadow =
			false
	end
	local lintelHeight = size.Y - doorSize.Y
	put(
		"Lintel",
		Vector3.new(0, base + doorSize.Y + lintelHeight / 2, -size.Z / 2),
		Vector3.new(doorSize.X, lintelHeight, 1),
		dark,
		Enum.Material.SmoothPlastic,
		true
	)
	put(
		"Roof",
		Vector3.new(0, base + size.Y + 0.3, 0),
		Vector3.new(size.X + 2, 0.6, size.Z + 2),
		gold,
		Enum.Material.Metal,
		false
	)

	local door = put(
		"VIPDoor",
		Vector3.new(0, base + doorSize.Y / 2, -size.Z / 2),
		doorSize,
		gold,
		Enum.Material.SmoothPlastic,
		true
	)
	door.Transparency = 0.3
	door:SetAttribute("VIPOnly", true)
	BuildKit.Billboard(door, "VIP ONLY", { Offset = Vector3.new(0, doorSize.Y / 2 + 1.5, 0), Color = gold })

	-- Furniture: sofas, table, plants and a chandelier.
	for _, x in { -6, 6 } do
		put("Sofa", Vector3.new(x, base + 1, 6), Vector3.new(7, 1.2, 2.6), gold, Enum.Material.SmoothPlastic, true)
		put("SofaBack", Vector3.new(x, base + 2, 7.1), Vector3.new(7, 1.6, 0.5), BuildKit.Darken(gold, 0.2))
	end
	put("Table", Vector3.new(0, base + 0.9, 1), Vector3.new(5, 0.4, 3), dark, Enum.Material.Metal, true)
	put("TableLegs", Vector3.new(0, base + 0.5, 1), Vector3.new(1, 0.8, 1), dark, Enum.Material.Metal)
	put("TableGlow", Vector3.new(0, base + 1.15, 1), Vector3.new(4, 0.1, 2), gold, Enum.Material.Neon)
	for _, x in { -11, 11 } do
		BuildKit.Cylinder({
			Name = "PlantPot",
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = frame * CFrame.new(x, base + 0.8, -8),
			Color = dark,
			Parent = model,
		}, "Y")
		BuildKit.Ball({
			Name = "Plant",
			Size = Vector3.new(3, 3, 3),
			CFrame = frame * CFrame.new(x, base + 2.8, -8),
			Color = Props.LeafColors[1],
			Parent = model,
		})
	end
	local chandelier = BuildKit.Ball({
		Name = "Chandelier",
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = frame * CFrame.new(0, base + size.Y - 1.5, 0),
		Color = gold,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	BuildKit.Light(chandelier, gold, 1.5, 28)
	BuildKit.AddParticles(chandelier, "Sparkles", gold, nil, 0.5)
	BuildKit.Billboard(floor, "VIP LOUNGE", { Offset = Vector3.new(0, size.Y + 3.5, -size.Z / 2), Color = gold })
	model.PrimaryPart = floor
end

local function buildFence(plaza: Instance)
	local folder = BuildKit.Folder("Fence", plaza)
	local radius = World.PlazaRadius + 1.5
	local segments = PlazaCfg.FenceSegments
	local gap = math.asin(math.min(1, (PlazaCfg.RoadWidth / 2 + 3) / radius))
	local chord = 2 * radius * math.sin(math.pi / segments)
	for s = 0, segments - 1 do
		local a = (s + 0.5) * 2 * math.pi / segments
		local blocked = false
		for i = 1, World.PlotCount do
			local d = math.abs((a - WorldBuilder.PlotAngle(i) + math.pi) % (2 * math.pi) - math.pi)
			if d < gap then
				blocked = true
				break
			end
		end
		if not blocked then
			local pos = polar(radius, a, PLAZA_TOP + PlazaCfg.FenceHeight / 2)
			box(
				folder,
				"Rail",
				Vector3.new(0.3, 0.3, chord),
				CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))),
				Palette.UIAccent,
				Enum.Material.Metal
			).CastShadow =
				false
			BuildKit.Cylinder({
				Name = "Post",
				Size = Vector3.new(0.5, PlazaCfg.FenceHeight, 0.5),
				Position = pos,
				Color = Visuals.Stage.DarkColor,
				Material = Enum.Material.Metal,
				CastShadow = false,
				Parent = folder,
			}, "Y")
		end
	end
end

local function buildScenery(parent: Instance)
	local scenery = BuildKit.Folder("Scenery", parent)
	local rng = Random.new(Props.Seed)
	local plotFront = World.PlotRingRadius - World.PlotSize.Z / 2
	local ringR = ringRoadRadius()
	local outerStart = World.PlotRingRadius + World.PlotSize.Z / 2 + 10
	local planted = 0
	local attempts = 0
	while planted < Props.TreeCount and attempts < Props.TreeCount * 20 do
		attempts += 1
		local inner = rng:NextNumber() < 0.6
		local r = if inner
			then rng:NextNumber(Props.TreeMinRadius, plotFront - PlazaCfg.RingRoadMargin - 22)
			else rng:NextNumber(outerStart, outerStart + 50)
		local a = rng:NextNumber(0, 2 * math.pi)
		local ok = true
		-- Keep trees off the radial roads and the ring road.
		for i = 1, World.PlotCount do
			local d = math.abs((a - WorldBuilder.PlotAngle(i) + math.pi) % (2 * math.pi) - math.pi)
			if d * r < PlazaCfg.RoadWidth + 4 then
				ok = false
				break
			end
		end
		if inner and r > ringR * math.cos(math.pi / World.PlotCount) - 14 then
			ok = false
		end
		if ok then
			tree(scenery, polar(r, a), rng)
			planted += 1
		end
	end

	-- Lamp posts along each spoke road and around the plaza.
	local front = plotFront - 6
	for i = 1, World.PlotCount do
		local a = WorldBuilder.PlotAngle(i)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		for n = 1, Props.LampsPerRoad do
			local r = World.PlazaRadius + (front - World.PlazaRadius) * n / (Props.LampsPerRoad + 1)
			for _, side in { -1, 1 } do
				lamp(scenery, polar(r, a) + tangent * side * (PlazaCfg.RoadWidth / 2 + 1.5), false)
			end
		end
		lamp(scenery, polar(World.PlazaRadius - 3, a + math.pi / World.PlotCount), true)
	end
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------
function WorldBuilder.Build(): { Plots: Folder, Plaza: Model }
	local root = Workspace
	for _, name in { "WorldBase", "Plaza", "Plots" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	buildLighting()

	local base = BuildKit.Folder("WorldBase", root)
	buildGround(base)
	buildRoads(base)
	buildScenery(base)

	local plaza = BuildKit.Model("Plaza", root)
	local plazaDisc = disc(
		plaza,
		"PlazaGround",
		World.PlazaRadius * 2,
		PLAZA_TOP,
		Vector3.new(0, PLAZA_TOP / 2, 0),
		PlazaCfg.InnerRingColor,
		Enum.Material.Neon,
		true
	)
	disc(
		plaza,
		"PlazaInner",
		World.PlazaRadius * 2 - 3,
		PLAZA_TOP + 0.04,
		Vector3.new(0, PLAZA_TOP / 2 + 0.02, 0),
		Palette.Plaza,
		Enum.Material.SmoothPlastic,
		true
	)
	buildMonument(plaza)
	buildSpawn(plaza)
	buildLeaderboards(plaza)
	buildMegaBoard(plaza)
	buildTradePlaza(plaza)
	buildVIPLounge(plaza)
	buildFence(plaza)
	plaza.PrimaryPart = plazaDisc
	pcall(function()
		plaza.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	local plots = BuildKit.Folder("Plots", root)
	return { Plots = plots, Plaza = plaza }
end

return WorldBuilder

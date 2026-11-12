--!strict
--[[
	BuildKit: small helpers for building the world procedurally from Parts.
	Every part is anchored and non-colliding unless CanCollide = true is passed
	(walkable surfaces only). No MeshParts and no external assets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local BuildKit = {}

export type PartProps = {
	Name: string?,
	Size: Vector3?,
	CFrame: CFrame?,
	Position: Vector3?,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CastShadow: boolean?,
	Shape: Enum.PartType?,
	Parent: Instance?,
	Attributes: { [string]: any }?,
}

-- A build context places parts relative to an origin so shapes can be authored around (0,0,0).
export type Context = {
	Model: Model,
	Origin: CFrame,
	Scale: number,
}

local DEFAULT_COLOR = Color3.fromRGB(163, 162, 165)

local function apply(part: BasePart, props: PartProps)
	part.Anchored = true
	part.CanCollide = props.CanCollide == true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Color = props.Color or DEFAULT_COLOR
	part.Size = props.Size or Vector3.new(1, 1, 1)
	part.CFrame = props.CFrame or CFrame.new(props.Position or Vector3.zero)
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	part.CastShadow = props.CastShadow ~= false
	if props.Name then
		part.Name = props.Name
	end
	if props.Attributes then
		for key, value in props.Attributes do
			part:SetAttribute(key, value)
		end
	end
	if props.Parent then
		part.Parent = props.Parent
	end
end

-- Applies the common props to a part you created yourself (e.g. a SpawnLocation).
BuildKit.Apply = apply

function BuildKit.Part(props: PartProps): Part
	local part = Instance.new("Part")
	part.Shape = props.Shape or Enum.PartType.Block
	apply(part, props)
	return part
end

function BuildKit.Wedge(props: PartProps): WedgePart
	local part = Instance.new("WedgePart")
	apply(part, props)
	return part
end

function BuildKit.CornerWedge(props: PartProps): CornerWedgePart
	local part = Instance.new("CornerWedgePart")
	apply(part, props)
	return part
end

-- Sphere; Size.X is the diameter.
function BuildKit.Ball(props: PartProps): Part
	local copy = table.clone(props)
	local d = (props.Size or Vector3.new(1, 1, 1)).X
	copy.Size = Vector3.new(d, d, d)
	copy.Shape = Enum.PartType.Ball
	return BuildKit.Part(copy)
end

-- Cylinder described by its world-space envelope: axis "Y" (default) expects Size = (diameter, height, diameter),
-- "X" = (length, d, d), "Z" = (d, d, length). Roblox cylinders natively run along X.
function BuildKit.Cylinder(props: PartProps, axis: string?): Part
	local copy = table.clone(props)
	local s = props.Size or Vector3.new(1, 1, 1)
	local base = props.CFrame or CFrame.new(props.Position or Vector3.zero)
	local a = axis or "Y"
	if a == "X" then
		copy.Size = Vector3.new(s.X, math.max(s.Y, s.Z), math.max(s.Y, s.Z))
		copy.CFrame = base
	elseif a == "Z" then
		copy.Size = Vector3.new(s.Z, math.max(s.X, s.Y), math.max(s.X, s.Y))
		copy.CFrame = base * CFrame.Angles(0, math.pi / 2, 0)
	else
		copy.Size = Vector3.new(s.Y, math.max(s.X, s.Z), math.max(s.X, s.Z))
		copy.CFrame = base * CFrame.Angles(0, 0, math.pi / 2)
	end
	copy.Shape = Enum.PartType.Cylinder
	return BuildKit.Part(copy)
end

-- Built-in SpecialMesh (Sphere, Cylinder, Wedge, Brick only; no asset ids).
function BuildKit.Mesh(part: BasePart, meshType: Enum.MeshType, scale: Vector3?): SpecialMesh
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = meshType
	mesh.Scale = scale or Vector3.new(1, 1, 1)
	mesh.Parent = part
	return mesh
end

function BuildKit.Weld(a: BasePart, b: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	return weld
end

function BuildKit.Model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	if parent then
		model.Parent = parent
	end
	return model
end

function BuildKit.Folder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	if parent then
		folder.Parent = parent
	end
	return folder
end

function BuildKit.SetPrimary(model: Model, part: BasePart)
	model.PrimaryPart = part
end

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------
function BuildKit.Lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), math.clamp(amount, 0, 1))
end

function BuildKit.Darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), math.clamp(amount, 0, 1))
end

-- Colour of the highest LevelTiers entry whose MinLevel <= level; also returns its index.
function BuildKit.TierColor(level: number): (Color3, number)
	local tiers = Config.Visuals.LevelTiers
	local best = 1
	for i, tier in tiers do
		if level >= tier.MinLevel then
			best = i
		end
	end
	return tiers[best].Color, best
end

--------------------------------------------------------------------------------
-- Context placement
--------------------------------------------------------------------------------
function BuildKit.NewContext(model: Model, origin: CFrame?, scale: number?): Context
	return { Model = model, Origin = origin or CFrame.identity, Scale = scale or 1 }
end

local function place(ctx: Context, at: CFrame | Vector3): CFrame
	local s = ctx.Scale
	if typeof(at) == "Vector3" then
		return ctx.Origin * CFrame.new(at * s)
	end
	local cf = at :: CFrame
	return ctx.Origin * (cf.Rotation + cf.Position * s)
end

function BuildKit.Box(
	ctx: Context,
	at: CFrame | Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: PartProps?
): Part
	local props: PartProps = if extra then table.clone(extra) else {}
	props.Color = props.Color or color
	props.Material = props.Material or material
	props.CFrame = place(ctx, at)
	props.Size = size * ctx.Scale
	props.Parent = ctx.Model
	if props.CastShadow == nil and size.Magnitude * ctx.Scale < 2.5 then
		props.CastShadow = false
	end
	return BuildKit.Part(props)
end

function BuildKit.Cyl(
	ctx: Context,
	at: CFrame | Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	axis: string?,
	extra: PartProps?
): Part
	local props: PartProps = if extra then table.clone(extra) else {}
	props.Color = props.Color or color
	props.Material = props.Material or material
	props.CFrame = place(ctx, at)
	props.Size = size * ctx.Scale
	props.Parent = ctx.Model
	if props.CastShadow == nil and size.Magnitude * ctx.Scale < 2.5 then
		props.CastShadow = false
	end
	return BuildKit.Cylinder(props, axis)
end

function BuildKit.Sphere(
	ctx: Context,
	at: CFrame | Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	extra: PartProps?
): Part
	local props: PartProps = if extra then table.clone(extra) else {}
	props.Color = props.Color or color
	props.Material = props.Material or material
	props.CFrame = place(ctx, at)
	props.Size = Vector3.new(diameter, diameter, diameter) * ctx.Scale
	props.Parent = ctx.Model
	if props.CastShadow == nil and diameter * ctx.Scale < 1.6 then
		props.CastShadow = false
	end
	return BuildKit.Ball(props)
end

-- WedgePart (slope direction follows the part CFrame; check orientation in Studio).
function BuildKit.WedgeAt(
	ctx: Context,
	at: CFrame | Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: PartProps?
): WedgePart
	local props: PartProps = if extra then table.clone(extra) else {}
	props.Color = props.Color or color
	props.Material = props.Material or material
	props.CFrame = place(ctx, at)
	props.Size = size * ctx.Scale
	props.Parent = ctx.Model
	return BuildKit.Wedge(props)
end

--------------------------------------------------------------------------------
-- Particles, lights, labels
--------------------------------------------------------------------------------
-- Adds an emitter from Config.Visuals.Particles[preset]. Direction defaults to the parent's top face.
function BuildKit.AddParticles(
	parent: Instance,
	preset: string,
	color: Color3?,
	direction: Enum.NormalId?,
	rateScale: number?
): ParticleEmitter?
	local def = Config.Visuals.Particles[preset]
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
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, def.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(color or def.Color)
	emitter.LightEmission = def.LightEmission
	emitter.Acceleration = def.Acceleration
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.EmissionDirection = direction or Enum.NormalId.Top
	emitter.Parent = parent
	return emitter
end

function BuildKit.Light(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

function BuildKit.Attachment(parent: BasePart, name: string, offset: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = offset
	attachment.Parent = parent
	return attachment
end

export type LabelProps = {
	Size: UDim2?,
	Offset: Vector3?,
	Color: Color3?,
	MaxDistance: number?,
	AlwaysOnTop: boolean?,
	Name: string?,
}

function BuildKit.Billboard(parent: BasePart, text: string, props: LabelProps?): (BillboardGui, TextLabel)
	local labels = Config.Visuals.Labels
	local p: LabelProps = props or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = p.Name or "Label"
	gui.Adornee = parent
	gui.Size = p.Size or labels.BillboardSize
	gui.StudsOffset = p.Offset or Vector3.zero
	gui.MaxDistance = p.MaxDistance or labels.MaxDistance
	gui.AlwaysOnTop = p.AlwaysOnTop == true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = labels.Font
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = p.Color or labels.TextColor
	label.TextStrokeColor3 = labels.StrokeColor
	label.TextStrokeTransparency = labels.StrokeTransparency
	label.RichText = true
	label.Parent = gui
	gui.Parent = parent
	return gui, label
end

-- Text printed on one face of a part; Size is the part's face in studs.
function BuildKit.SurfaceText(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3?,
	name: string?
): (SurfaceGui, TextLabel)
	local labels = Config.Visuals.Labels
	local gui = Instance.new("SurfaceGui")
	gui.Name = name or "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = labels.PixelsPerStud
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = labels.Font
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or labels.TextColor
	label.TextStrokeTransparency = 1
	label.Parent = gui
	gui.Parent = part
	return gui, label
end

-- Instance:Clone of ServerStorage/ModelOverrides/<name> when it exists.
function BuildKit.Override(name: string?): Model?
	if not name or name == "" then
		return nil
	end
	local folder = game:GetService("ServerStorage"):FindFirstChild("ModelOverrides")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return nil
end

-- Looks keys up in Config.Visuals.ModelOverrides in order and clones the first model found.
function BuildKit.OverrideFor(keys: { string }): Model?
	for _, key in keys do
		local clone = BuildKit.Override(Config.Visuals.ModelOverrides[key])
		if clone then
			return clone
		end
	end
	return nil
end

return BuildKit

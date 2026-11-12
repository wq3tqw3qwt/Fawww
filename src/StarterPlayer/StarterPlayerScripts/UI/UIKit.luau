--!strict
--[[
	UIKit: procedural, mobile-first UI building blocks.
	- Every size/position uses Scale (no Offset layouts).
	- Buttons are large, rounded, gamepad-selectable and give press feedback.
	- Text uses TextScaled with UITextSizeConstraint so it stays readable on phones.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local UIKit = {}

local Palette = Config.Visuals.Palette
UIKit.Palette = Palette
UIKit.Font = Enum.Font.FredokaOne
UIKit.BodyFont = Enum.Font.GothamBold

export type Props = { [string]: any }

-- Generic constructor: UIKit.Create("Frame", { Size = ..., Parent = ... }, { children })
function UIKit.Create(className: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.Corner(parent: Instance, scale: number?): UICorner
	return UIKit.Create("UICorner", { CornerRadius = UDim.new(scale or 0.2, 0), Parent = parent })
end

function UIKit.Stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	return UIKit.Create("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = 0.2,
		Parent = parent,
	})
end

function UIKit.Padding(parent: Instance, scale: number?): UIPadding
	local s = UDim.new(scale or 0.04, 0)
	return UIKit.Create(
		"UIPadding",
		{ PaddingTop = s, PaddingBottom = s, PaddingLeft = s, PaddingRight = s, Parent = parent }
	)
end

function UIKit.List(
	parent: Instance,
	paddingScale: number?,
	horizontal: boolean?,
	align: Enum.HorizontalAlignment?
): UIListLayout
	return UIKit.Create("UIListLayout", {
		Padding = UDim.new(paddingScale or 0.02, 0),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

function UIKit.Grid(parent: Instance, cellScale: Vector2, paddingScale: number?): UIGridLayout
	local p = paddingScale or 0.02
	return UIKit.Create("UIGridLayout", {
		CellSize = UDim2.fromScale(cellScale.X, cellScale.Y),
		CellPadding = UDim2.fromScale(p, p),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = parent,
	})
end

-- Locks width:height. An element sized with zero height (e.g. UDim2.fromScale(1, 0)) means
-- "height follows width": FitWithinMaxSize would collapse a zero-height box to 0 px, so the box
-- is made very tall and the constraint then fits it by width (height = width / ratio).
local WIDTH_DRIVEN_BOX = 100000

function UIKit.Aspect(parent: Instance, ratio: number): UIAspectRatioConstraint
	if parent:IsA("GuiObject") and parent.Size.Y.Scale == 0 and parent.Size.Y.Offset == 0 then
		local gui = parent :: GuiObject
		gui.Size = UDim2.new(gui.Size.X, UDim.new(0, WIDTH_DRIVEN_BOX))
	end
	return UIKit.Create("UIAspectRatioConstraint", { AspectRatio = ratio, Parent = parent })
end

-- Gamepad focus: only move the selection when a gamepad is in use and the target can be selected,
-- otherwise Roblox warns "Setting GuiService.SelectedObject to invalid GuiObject".
function UIKit.Select(target: GuiObject?)
	local lastInput = UserInputService:GetLastInputType()
	local usingGamepad = lastInput.Name:sub(1, 7) == "Gamepad"
	if not usingGamepad or target == nil then
		return
	end
	if not target.Selectable or not target:IsDescendantOf(game) then
		return
	end
	local node: Instance? = target
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return
		end
		node = node.Parent
	end
	GuiService.SelectedObject = target
end

function UIKit.Tween(
	inst: Instance,
	props: Props,
	seconds: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(seconds or 0.2, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Quick "pop" using a UIScale child (created on demand).
function UIKit.Pop(inst: GuiObject, amount: number?)
	local scale = inst:FindFirstChildOfClass("UIScale") or UIKit.Create("UIScale", { Parent = inst })
	scale.Scale = 1 + (amount or 0.12)
	UIKit.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
end

local soundCache: { [string]: Sound } = {}
function UIKit.PlaySound(key: string, volume: number?)
	local id = Config.Visuals.Sounds[key]
	if not id or id == "" then
		return
	end
	local sound = soundCache[key]
	if not sound then
		sound = UIKit.Create("Sound", { SoundId = id, Volume = volume or 0.5, Parent = SoundService })
		soundCache[key] = sound
	end
	SoundService:PlayLocalSound(sound)
end

-- Sound toggle hook, set by the settings controller.
UIKit.SfxEnabled = true

export type LabelProps = {
	Text: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Font: Enum.Font?,
	MaxTextSize: number?,
	Alignment: Enum.TextXAlignment?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
	ZIndex: number?,
}

function UIKit.Label(p: LabelProps): TextLabel
	local label = UIKit.Create("TextLabel", {
		Name = p.Name or "Label",
		Text = p.Text or "",
		Size = p.Size or UDim2.fromScale(1, 0.1),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		TextColor3 = p.Color or Palette.UIText,
		Font = p.Font or UIKit.Font,
		TextScaled = true,
		TextXAlignment = p.Alignment or Enum.TextXAlignment.Center,
		LayoutOrder = p.LayoutOrder or 0,
		ZIndex = p.ZIndex or 1,
		RichText = true,
	})
	UIKit.Create("UITextSizeConstraint", { MaxTextSize = p.MaxTextSize or 36, MinTextSize = 8, Parent = label })
	UIKit.Create("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), Transparency = 0.3, Parent = label })
	if p.Parent then
		label.Parent = p.Parent
	end
	return label
end

export type ButtonProps = {
	Text: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	TextColor: Color3?,
	OnClick: (() -> ())?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
	MaxTextSize: number?,
	ZIndex: number?,
}

function UIKit.Button(p: ButtonProps): TextButton
	local color = p.Color or Palette.UIAccent
	local button = UIKit.Create("TextButton", {
		Name = p.Name or "Button",
		Text = p.Text or "",
		Size = p.Size or UDim2.fromScale(0.3, 0.12),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		TextColor3 = p.TextColor or Palette.UIText,
		Font = UIKit.Font,
		TextScaled = true,
		AutoButtonColor = true,
		Selectable = true,
		LayoutOrder = p.LayoutOrder or 0,
		ZIndex = p.ZIndex or 1,
		RichText = true,
	})
	UIKit.Corner(button, 0.25)
	UIKit.Create("UIStroke", {
		Color = color:Lerp(Color3.new(0, 0, 0), 0.45),
		Thickness = 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	})
	UIKit.Create("UITextSizeConstraint", { MaxTextSize = p.MaxTextSize or 30, MinTextSize = 8, Parent = button })
	UIKit.Create("UIPadding", {
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
		PaddingTop = UDim.new(0.12, 0),
		PaddingBottom = UDim.new(0.12, 0),
		Parent = button,
	})
	button.Activated:Connect(function()
		UIKit.Pop(button, 0.08)
		if UIKit.SfxEnabled then
			UIKit.PlaySound("Click", 0.4)
		end
		if p.OnClick then
			p.OnClick()
		end
	end)
	if p.Parent then
		button.Parent = p.Parent
	end
	return button
end

-- Rounded container card.
function UIKit.Card(parent: Instance?, size: UDim2?, color: Color3?, layoutOrder: number?): Frame
	local card = UIKit.Create("Frame", {
		Size = size or UDim2.fromScale(1, 0.2),
		BackgroundColor3 = color or Palette.UIPanel,
		LayoutOrder = layoutOrder or 0,
	})
	UIKit.Corner(card, 0.12)
	UIKit.Stroke(card, Color3.new(0, 0, 0), 2)
	if parent then
		card.Parent = parent
	end
	return card
end

function UIKit.Scroll(parent: Instance, size: UDim2?, position: UDim2?): ScrollingFrame
	return UIKit.Create("ScrollingFrame", {
		Size = size or UDim2.fromScale(1, 1),
		Position = position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		Parent = parent,
	})
end

export type ProgressBar = {
	Root: Frame,
	Set: (fraction: number, text: string?) -> (),
}

function UIKit.ProgressBar(parent: Instance, size: UDim2?, fillColor: Color3?, layoutOrder: number?): ProgressBar
	local root = UIKit.Create("Frame", {
		Size = size or UDim2.fromScale(1, 0.08),
		BackgroundColor3 = Color3.fromRGB(20, 20, 26),
		LayoutOrder = layoutOrder or 0,
		Parent = parent,
	})
	UIKit.Corner(root, 0.5)
	local fill = UIKit.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor or Palette.UIGood,
		Parent = root,
	})
	UIKit.Corner(fill, 0.5)
	local label = UIKit.Label({ Text = "", Size = UDim2.fromScale(1, 1), Parent = root, ZIndex = 2, MaxTextSize = 20 })
	return {
		Root = root,
		Set = function(fraction: number, text: string?)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			label.Text = text or ""
		end,
	}
end

export type Panel = {
	Root: Frame,
	Body: ScrollingFrame,
	Title: TextLabel,
	Close: TextButton,
}

-- Centered modal panel sized for phones first; caps its size on large screens.
function UIKit.Panel(name: string, title: string, parent: Instance, accent: Color3?): Panel
	local root = UIKit.Create("Frame", {
		Name = name,
		Size = UDim2.fromScale(0.92, 0.82),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Palette.UIBackground,
		Visible = false,
		Parent = parent,
	})
	UIKit.Corner(root, 0.04)
	UIKit.Stroke(root, accent or Palette.UIAccent, 3)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(1100, 760), Parent = root })

	local header = UIKit.Create("Frame", {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.12),
		BackgroundColor3 = accent or Palette.UIAccent,
		Parent = root,
	})
	UIKit.Corner(header, 0.3)
	local titleLabel = UIKit.Label({
		Text = title,
		Size = UDim2.fromScale(0.75, 0.8),
		Position = UDim2.fromScale(0.04, 0.1),
		Alignment = Enum.TextXAlignment.Left,
		MaxTextSize = 40,
		Parent = header,
	})
	local close = UIKit.Button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromScale(0.1, 0.9),
		Position = UDim2.fromScale(0.985, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = Palette.UIBad,
		Parent = header,
	})
	UIKit.Aspect(close, 1)

	local body = UIKit.Scroll(root, UDim2.fromScale(0.96, 0.84), UDim2.fromScale(0.02, 0.14))
	body.Name = "Body"
	return { Root = root, Body = body, Title = titleLabel, Close = close }
end

return UIKit

--!strict
--[[
	UIController: owns the FactoryUI ScreenGui layers and modal panel stack.

	Layers (ZIndex order): HUD < Panels < Overlay < Toasts.
	Feature controllers create a panel with UIKit.Panel(..., UIController.GetLayer("Panels"))
	and register it here; HUD buttons call UIController.Open(name).
	Gamepad: opening a panel selects its first button; ButtonB closes the top panel.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local UIController = {}

export type PanelEntry = {
	Root: GuiObject,
	OnOpen: (() -> ())?,
	OnClose: (() -> ())?,
}

local screen: ScreenGui
local layers: { [string]: Frame } = {}
local panels: { [string]: PanelEntry } = {}
local stack: { string } = {}

UIController.Opened = Signal.new() :: Signal.Signal<string>
UIController.Closed = Signal.new() :: Signal.Signal<string>

local function firstSelectable(root: Instance): GuiObject?
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Visible and d.Selectable and d.Name ~= "Close" then
			return d
		end
	end
	return nil
end

function UIController.Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:WaitForChild("FactoryUI", 10)
	if existing and existing:IsA("ScreenGui") then
		screen = existing
	else
		screen = UIKit.Create(
			"ScreenGui",
			{ Name = "FactoryUI", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = playerGui }
		)
	end
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	for index, name in { "HUD", "Panels", "Overlay", "Toasts" } do
		layers[name] = UIKit.Create("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = index * 10,
			Parent = screen,
		})
	end
end

function UIController.Start()
	ContextActionService:BindAction("FE_ClosePanel", function(_, state)
		if state == Enum.UserInputState.Begin and #stack > 0 then
			UIController.Close(stack[#stack])
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonB)
end

function UIController.GetScreen(): ScreenGui
	return screen
end

function UIController.GetLayer(name: "HUD" | "Panels" | "Overlay" | "Toasts"): Frame
	return layers[name]
end

function UIController.RegisterPanel(name: string, entry: PanelEntry)
	panels[name] = entry
	entry.Root.Visible = false
	local close = entry.Root:FindFirstChild("Close", true)
	if close and close:IsA("GuiButton") then
		close.Activated:Connect(function()
			UIController.Close(name)
		end)
	end
end

function UIController.IsOpen(name: string): boolean
	return table.find(stack, name) ~= nil
end

function UIController.Open(name: string)
	local entry = panels[name]
	if not entry then
		warn("[UIController] unknown panel " .. name)
		return
	end
	-- One modal at a time keeps phones readable.
	for i = #stack, 1, -1 do
		if stack[i] ~= name then
			UIController.Close(stack[i])
		end
	end
	if not UIController.IsOpen(name) then
		table.insert(stack, name)
	end
	entry.Root.Visible = true
	UIKit.Pop(entry.Root, 0.06)
	if entry.OnOpen then
		task.spawn(entry.OnOpen)
	end
	GuiService.SelectedObject = firstSelectable(entry.Root)
	UIController.Opened:Fire(name)
end

function UIController.Close(name: string)
	local entry = panels[name]
	local index = table.find(stack, name)
	if index then
		table.remove(stack, index)
	end
	if entry and entry.Root.Visible then
		entry.Root.Visible = false
		if entry.OnClose then
			task.spawn(entry.OnClose)
		end
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(entry.Root) then
			GuiService.SelectedObject = nil
		end
		UIController.Closed:Fire(name)
	end
end

function UIController.Toggle(name: string)
	if UIController.IsOpen(name) then
		UIController.Close(name)
	else
		UIController.Open(name)
	end
end

function UIController.CloseAll()
	for i = #stack, 1, -1 do
		UIController.Close(stack[i])
	end
end

-- Simple yes/no confirmation dialog on the Overlay layer.
function UIController.Confirm(text: string, onYes: () -> (), yesText: string?)
	local overlay = layers.Overlay
	local shade = UIKit.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Parent = overlay,
	})
	local card = UIKit.Card(shade, UDim2.fromScale(0.8, 0.4), nil)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(620, 320), Parent = card })
	UIKit.Label({ Text = text, Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.06), Parent = card })
	local no = UIKit.Button({
		Text = "Cancel",
		Size = UDim2.fromScale(0.4, 0.28),
		Position = UDim2.fromScale(0.06, 0.66),
		Color = UIKit.Palette.UIBad,
		Parent = card,
		OnClick = function()
			shade:Destroy()
		end,
	})
	UIKit.Button({
		Text = yesText or "Yes",
		Size = UDim2.fromScale(0.4, 0.28),
		Position = UDim2.fromScale(0.54, 0.66),
		Color = UIKit.Palette.UIGood,
		Parent = card,
		OnClick = function()
			shade:Destroy()
			onYes()
		end,
	})
	GuiService.SelectedObject = no
end

return UIController

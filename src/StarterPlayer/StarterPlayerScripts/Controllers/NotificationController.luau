--!strict
--[[
	NotificationController: stacked toasts and a centre banner on the Toasts layer.
	Also hosts Request(): a Net.Request wrapper that toasts server errors, used by all controllers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Types = require(ReplicatedStorage.Shared.Types)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local NotificationController = {}

export type Kind = "Info" | "Success" | "Error" | "Reward"

local MAX_TOASTS = 4
local Palette = UIKit.Palette

local maid = Maid.new()
local stack: Frame? = nil
local active: { Frame } = {}
local banner: Frame? = nil
local bannerToken = 0
local toastOrder = 0

local KIND_COLORS: { [string]: Color3 } = {
	Info = Color3.fromRGB(70, 110, 200),
	Success = Palette.UIGood,
	Error = Palette.UIBad,
	Reward = Palette.UIAccent,
}
local KIND_SOUNDS: { [string]: string } = { Error = "Error", Reward = "Coins", Success = "Upgrade" }

local function fadeOut(frame: Frame)
	local index = table.find(active, frame)
	if index then
		table.remove(active, index)
	end
	if not frame.Parent then
		return
	end
	UIKit.Tween(frame, { BackgroundTransparency = 1 }, 0.3)
	for _, d in frame:GetDescendants() do
		if d:IsA("TextLabel") then
			UIKit.Tween(d, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.3)
		elseif d:IsA("UIStroke") then
			UIKit.Tween(d, { Transparency = 1 }, 0.3)
		end
	end
	task.delay(0.35, function()
		frame:Destroy()
	end)
end

function NotificationController.Toast(kind: Kind, text: string)
	local container = stack
	if container == nil then
		return
	end
	local color = KIND_COLORS[kind] or KIND_COLORS.Info
	toastOrder += 1
	local toast = UIKit.Card(container, UDim2.fromScale(1, 0), color:Lerp(Color3.new(0, 0, 0), 0.35), toastOrder)
	UIKit.Aspect(toast, 8)
	UIKit.Label({
		Text = text,
		Size = UDim2.fromScale(0.94, 0.8),
		Position = UDim2.fromScale(0.03, 0.1),
		MaxTextSize = 26,
		Parent = toast,
	})
	UIKit.Pop(toast, 0.06)
	table.insert(active, toast)
	while #active > MAX_TOASTS do
		fadeOut(active[1])
	end
	local sound = KIND_SOUNDS[kind]
	if sound then
		SoundController.Play(sound)
	end
	task.delay(Config.UI.ToastSeconds, fadeOut, toast)
end

function NotificationController.Banner(text: string, color: Color3?)
	local layer = UIController.GetLayer("Toasts")
	if banner then
		banner:Destroy()
	end
	bannerToken += 1
	local token = bannerToken
	local tint = color or Palette.UIAccent
	local frame = UIKit.Card(layer, UDim2.fromScale(0.8, 0), tint:Lerp(Color3.new(0, 0, 0), 0.4))
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, -0.1)
	UIKit.Aspect(frame, 6)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(900, 160), Parent = frame })
	UIKit.Label({
		Text = text,
		Size = UDim2.fromScale(0.94, 0.8),
		Position = UDim2.fromScale(0.03, 0.1),
		MaxTextSize = 44,
		Parent = frame,
	})
	banner = frame
	UIKit.Tween(frame, { Position = UDim2.fromScale(0.5, 0.3) }, 0.45, Enum.EasingStyle.Back)
	task.delay(Config.UI.ToastSeconds + 1.5, function()
		if token ~= bannerToken or frame.Parent == nil then
			return
		end
		local tween = TweenService:Create(frame, TweenInfo.new(0.4), { Position = UDim2.fromScale(0.5, -0.15) })
		tween.Completed:Once(function()
			frame:Destroy()
		end)
		tween:Play()
	end)
end

-- Net.Request that shows the server's error text as a toast. Returns the Response.
function NotificationController.Request(name: string, ...: any): Types.Response
	local response = Net.Request(name, ...)
	if not response.Ok then
		NotificationController.Toast("Error", response.Error or "Something went wrong")
	end
	return response
end

local function onNotify(kind: any, text: any)
	if type(text) ~= "string" then
		return
	end
	local k: Kind = "Info"
	if kind == "Success" or kind == "Error" or kind == "Reward" then
		k = kind
	end
	NotificationController.Toast(k, text)
end

local function onEffect(kind: any, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if kind == "ContractStamp" then
		local parts: { string } = {}
		if type(payload.Cash) == "number" and payload.Cash > 0 then
			table.insert(parts, NumberFormat.Cash(payload.Cash))
		end
		if type(payload.Credits) == "number" and payload.Credits > 0 then
			table.insert(parts, NumberFormat.Short(payload.Credits) .. " Credits")
		end
		local tier = if type(payload.Tier) == "string" then payload.Tier else "Contract"
		NotificationController.Toast("Reward", `{tier} contract done! {table.concat(parts, "  ")}`)
	elseif kind == "MachineGranted" then
		-- The server already toasts the grant; high rarities also get a banner.
		local def = if type(payload.Id) == "string" then Formulas.GetMachine(payload.Id) else nil
		if def and table.find(Config.Events.AnnounceRarities, def.Rarity) then
			NotificationController.Banner(`{def.Rarity}: {def.Name}!`, nil)
		end
	elseif kind == "SecretDiscovered" then
		local def = if type(payload.Id) == "string" then Formulas.GetMachine(payload.Id) else nil
		local name = if def then def.Name else "a secret machine"
		NotificationController.Banner(`SECRET DISCOVERED: {name}`, Color3.fromRGB(150, 90, 255))
		NotificationController.Toast("Reward", `Secret recipe unlocked: {name}`)
	end
end

function NotificationController.Init()
	maid:Add(Net.Event("Notify").OnClientEvent:Connect(onNotify))
	maid:Add(Net.Event("Effect").OnClientEvent:Connect(onEffect))
	maid:Add(Net.Event("Announce").OnClientEvent:Connect(function(text: any, color: any)
		if type(text) == "string" then
			NotificationController.Banner(text, if typeof(color) == "Color3" then color else nil)
		end
	end))
end

function NotificationController.Start()
	local container = UIKit.Create("Frame", {
		Name = "ToastStack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.5, 0.4),
		BackgroundTransparency = 1,
		Parent = UIController.GetLayer("Toasts"),
	})
	UIKit.List(container, 0.015)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(560, 400), Parent = container })
	stack = container
	maid:Add(container)
end

return NotificationController

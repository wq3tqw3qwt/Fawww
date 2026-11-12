--!strict
--[[
	InputController: keyboard and gamepad shortcuts for the main panels (ContextActionService).
	Mobile uses the HUD buttons. A small hint strip appears while a gamepad is the active input.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Maid = require(game:GetService("ReplicatedStorage").Shared.Maid)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local InputController = {}

local maid = Maid.new()
local hints: Frame? = nil
local hintsForced: boolean? = nil

local BINDINGS: { { panel: string, keys: { Enum.KeyCode } } } = {
	{ panel = "Factory", keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonX } },
	{ panel = "Contracts", keys = { Enum.KeyCode.C, Enum.KeyCode.ButtonY } },
	{ panel = "Machines", keys = { Enum.KeyCode.M } },
	{ panel = "Quests", keys = { Enum.KeyCode.Q } },
	{ panel = "Shop", keys = { Enum.KeyCode.B } },
}

local function refreshHints()
	if hints == nil then
		return
	end
	local show = hintsForced
	if show == nil then
		show = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	end
	hints.Visible = show == true
end

-- nil restores automatic detection (visible only while a gamepad is the last input).
function InputController.SetGamepadHintsVisible(visible: boolean?)
	hintsForced = visible
	refreshHints()
end

local function buildHints()
	local frame = UIKit.Create("Frame", {
		Name = "GamepadHints",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.99),
		Size = UDim2.fromScale(0.5, 0.05),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = UIController.GetLayer("HUD"),
	})
	UIKit.Label({
		Text = "(X) Factory   (Y) Contracts   (B) Close",
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 20,
		Parent = frame,
	})
	hints = frame
	maid:Add(frame)
end

function InputController.Start()
	for _, binding in BINDINGS do
		local actionName = "FE_Toggle_" .. binding.panel
		ContextActionService:BindAction(actionName, function(_, state)
			if state == Enum.UserInputState.Begin then
				UIController.Toggle(binding.panel)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(binding.keys))
		maid:Add(function()
			ContextActionService:UnbindAction(actionName)
		end)
	end
	buildHints()
	maid:Add(UserInputService.LastInputTypeChanged:Connect(refreshHints))
	refreshHints()
end

return InputController

--!strict
--[[
	TutorialController: the guided first three minutes (Config.Tutorial.Steps / data.Tutorial.Step).
	Each step shows one word, an arrow Beam from the character to the world target, a pulsing
	billboard and/or pulsing UI buttons. The server advances steps; this only guides.
	Resources are polled every POLL_SECONDS because StreamingEnabled may not have streamed the
	plot parts yet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Maid = require(ReplicatedStorage.Shared.Maid)
local DataController = require(script.Parent.DataController)
local FactoryController = require(script.Parent.FactoryController)
local HUDController = require(script.Parent.HUDController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local TutorialController = {}

local Palette = UIKit.Palette
local STEPS = Config.Tutorial.Steps
local DONE_INDEX = #STEPS
local POLL_SECONDS = 0.5
local FRIENDS_TOAST_SECONDS = 12
local localPlayer = Players.LocalPlayer

local HINTS: { [string]: string } = {
	TapBottleneck = "TAP!",
	UpgradeFive = "UPGRADE",
	CollectVault = "COLLECT",
	Contract = "CONTRACT",
	BuyLine2 = "BUILD",
	Overdrive = "HOLD",
	EquipMachine = "EQUIP",
}

type Guide = {
	World: ((plot: Instance) -> Instance?)?,
	Gui: { () -> GuiObject? },
	Billboard: string?, -- "Tap" makes the billboard an upgrade button; otherwise a plain label
	BillboardText: string?,
}

local maid = Maid.new()
local stepMaid = Maid.new()
local toastMaid = Maid.new()
local hintLabel: TextLabel? = nil
local skipButton: TextButton? = nil
local currentStep = 0
local sawActiveStep = false
local skipped = false
local toastShown = false

--------------------------------------------------------------------------------
-- World lookups
--------------------------------------------------------------------------------
local function findPlot(): Instance?
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == localPlayer.UserId then
			return plot
		end
	end
	return nil
end

local function partOf(instance: Instance?): BasePart?
	if instance == nil then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function bottleneckStage(): number
	local runtime: any = DataController.GetRuntime()
	local fromRuntime = if runtime and runtime.Lines and runtime.Lines[1] then runtime.Lines[1].Bottleneck else nil
	if type(fromRuntime) == "number" then
		return fromRuntime
	end
	local data = DataController.Get()
	local levels = if data then data.Lines[1] else nil
	return if levels then Formulas.BottleneckStage(levels) else 1
end

local function hudButton(name: string): () -> GuiObject?
	return function()
		if UIController.IsOpen(name) then
			return nil
		end
		return HUDController.GetButton(name)
	end
end

local GUIDES: { [string]: Guide } = {
	TapBottleneck = {
		World = function(plot)
			local line = plot:FindFirstChild("Line_1")
			return if line then line:FindFirstChild("Stage_" .. bottleneckStage()) else nil
		end,
		Gui = {
			hudButton("Factory"),
			function()
				return FactoryController.GetUpgradeButton(1, bottleneckStage())
			end,
		},
		Billboard = "Tap",
		BillboardText = "TAP",
	},
	UpgradeFive = {
		World = function(plot)
			local line = plot:FindFirstChild("Line_1")
			return if line then line:FindFirstChild("Stage_" .. bottleneckStage()) else nil
		end,
		Gui = {
			hudButton("Factory"),
			function()
				return FactoryController.GetUpgradeButton(1, bottleneckStage())
			end,
		},
		Billboard = "Tap",
	},
	CollectVault = {
		World = function(plot)
			return plot:FindFirstChild("VaultPad")
		end,
		Gui = {
			function()
				return HUDController.GetCollectButton()
			end,
		},
		BillboardText = "COLLECT",
	},
	Contract = { Gui = { hudButton("Contracts") } },
	BuyLine2 = {
		World = function(plot)
			local line = plot:FindFirstChild("Line_2")
			return if line then line:FindFirstChild("BuildPad") else nil
		end,
		Gui = {
			hudButton("Factory"),
			function()
				return FactoryController.GetBuildButton()
			end,
		},
		BillboardText = "BUILD",
	},
	Overdrive = {
		World = function(plot)
			local line = plot:FindFirstChild("Line_1")
			return if line then line:FindFirstChild("Lever") else nil
		end,
		Gui = {},
		BillboardText = "HOLD",
	},
	EquipMachine = { Gui = { hudButton("Machines") } },
}

--------------------------------------------------------------------------------
-- Guidance visuals
--------------------------------------------------------------------------------
-- Beam from the character's root part to `target`. Returns a cleanup function, or nil if no character yet.
local function makeArrow(target: BasePart): (() -> ())?
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local from = UIKit.Create("Attachment", { Name = "TutorialArrowStart", Parent = root })
	local to = UIKit.Create("Attachment", { Name = "TutorialArrowEnd", Parent = target })
	local beam = UIKit.Create("Beam", {
		Name = "TutorialArrow",
		Attachment0 = from,
		Attachment1 = to,
		Color = ColorSequence.new(Palette.UIAccent),
		Width0 = 0.5,
		Width1 = 0.5,
		FaceCamera = true,
		LightEmission = 1,
		Transparency = NumberSequence.new(0.1),
		Parent = from,
	})
	local tween = TweenService:Create(
		beam,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Width0 = 1.2, Width1 = 1.2 }
	)
	tween:Play()
	return function()
		tween:Cancel()
		beam:Destroy()
		from:Destroy()
		to:Destroy()
	end
end

-- Pulsing label (or tap button) floating over `target`. Returns cleanup and the text label.
local function makeBillboard(target: BasePart, text: string, onTap: (() -> ())?): (() -> (), TextButton)
	local gui = UIKit.Create("BillboardGui", {
		Name = "TutorialBillboard",
		Adornee = target,
		AlwaysOnTop = true,
		Size = UDim2.fromScale(7, 3.2),
		StudsOffset = Vector3.new(0, 5, 0),
		MaxDistance = 250,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	local button = UIKit.Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIAccent,
		Text = text,
		TextColor3 = Palette.UIText,
		Font = UIKit.Font,
		TextScaled = true,
		AutoButtonColor = onTap ~= nil,
		Active = onTap ~= nil,
		Parent = gui,
	})
	UIKit.Corner(button, 0.3)
	UIKit.Stroke(button, Color3.new(0, 0, 0), 3)
	local scale = UIKit.Create("UIScale", { Parent = button })
	local tween = TweenService:Create(
		scale,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.15 }
	)
	tween:Play()
	if onTap then
		button.Activated:Connect(onTap)
	end
	return function()
		tween:Cancel()
		gui:Destroy()
	end, button
end

local function setHint(text: string)
	if hintLabel then
		hintLabel.Text = text
		hintLabel.Visible = text ~= ""
	end
	if skipButton then
		skipButton.Visible = text ~= ""
	end
end

local function tapBottleneck()
	task.spawn(function()
		local response = NotificationController.Request("UpgradeStage", 1, bottleneckStage(), 1)
		if response.Ok then
			SoundController.Play("Upgrade")
		end
	end)
end

local function upgradeProgress(): string
	local data = DataController.Get()
	local done = if data then data.Tutorial.Upgrades else 0
	return `{math.min(done, Config.Tutorial.UpgradeCount)}/{Config.Tutorial.UpgradeCount}`
end

local function runStep(index: number)
	stepMaid:Clean()
	currentStep = index
	local name = STEPS[index]
	if name == nil or index >= DONE_INDEX then
		setHint("")
		return
	end
	sawActiveStep = true
	local guide = GUIDES[name]
	local base = HINTS[name] or ""
	setHint(base)
	if guide == nil then
		return
	end

	local pulses: { [GuiObject]: () -> () } = {}
	stepMaid:Add(function()
		for _, stop in pulses do
			stop()
		end
	end)
	local arrowTarget: BasePart? = nil
	local arrowRoot: Instance? = nil
	local stopArrow: (() -> ())? = nil
	local stopBillboard: (() -> ())? = nil
	local billboardButton: TextButton? = nil
	stepMaid:Add(function()
		if stopArrow then
			stopArrow()
		end
		if stopBillboard then
			stopBillboard()
		end
	end)

	stepMaid:Add(task.spawn(function()
		while true do
			local plot = if guide.World then findPlot() else nil
			local target: BasePart? = if plot and guide.World then partOf(guide.World(plot)) else nil
			local character = localPlayer.Character
			local rootNow = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if target ~= arrowTarget or (target ~= nil and (stopArrow == nil or rootNow ~= arrowRoot)) then
				arrowRoot = rootNow
				if stopArrow then
					stopArrow()
					stopArrow = nil
				end
				if stopBillboard then
					stopBillboard()
					stopBillboard = nil
					billboardButton = nil
				end
				arrowTarget = target
				if target then
					stopArrow = makeArrow(target)
					local text = guide.BillboardText or ""
					if text ~= "" or guide.Billboard == "Tap" then
						local onTap = if guide.Billboard == "Tap" then tapBottleneck else nil
						stopBillboard, billboardButton = makeBillboard(target, text, onTap)
					end
				end
			end
			if name == "UpgradeFive" then
				local progress = upgradeProgress()
				setHint(`{base} {progress}`)
				if billboardButton then
					billboardButton.Text = progress
				end
			end

			local wanted: { [GuiObject]: boolean } = {}
			for _, resolve in guide.Gui do
				local gui = resolve()
				if gui and gui.Parent then
					wanted[gui] = true
					if pulses[gui] == nil then
						pulses[gui] = HUDController.Pulse(gui)
					end
				end
			end
			for gui, stop in pulses do
				if not wanted[gui] then
					stop()
					pulses[gui] = nil
				end
			end
			task.wait(POLL_SECONDS)
		end
	end))
end

--------------------------------------------------------------------------------
-- "Done" toast
--------------------------------------------------------------------------------
local function showFriendsToast()
	if toastShown then
		return
	end
	toastShown = true
	toastMaid:Clean()
	local card = UIKit.Card(UIController.GetLayer("Overlay"), UDim2.fromScale(0.6, 0), Palette.UIPanel)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.62)
	UIKit.Aspect(card, 3.4)
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(720, 220), Parent = card })
	toastMaid:Add(card)
	local percent = math.floor(Config.Social.OperatorBonusPerOperator * 100 + 0.5)
	UIKit.Label({
		Text = `Friends = +{percent}% 👥`,
		Size = UDim2.fromScale(0.94, 0.4),
		Position = UDim2.fromScale(0.03, 0.08),
		MaxTextSize = 40,
		Parent = card,
	})
	UIKit.Button({
		Name = "Invite",
		Text = "INVITE",
		Size = UDim2.fromScale(0.44, 0.38),
		Position = UDim2.fromScale(0.04, 0.54),
		Color = Palette.UIGood,
		Parent = card,
		OnClick = function()
			-- VERIFY: SocialService invite prompts need the feature enabled for the experience.
			pcall(function()
				if SocialService:CanSendGameInviteAsync(localPlayer) then
					SocialService:PromptGameInvite(localPlayer)
				end
			end)
		end,
	})
	UIKit.Button({
		Name = "Dismiss",
		Text = "OK",
		Size = UDim2.fromScale(0.44, 0.38),
		Position = UDim2.fromScale(0.52, 0.54),
		Parent = card,
		OnClick = function()
			toastMaid:Clean()
		end,
	})
	toastMaid:Add(task.delay(FRIENDS_TOAST_SECONDS, function()
		toastMaid:Clean()
	end))
	task.spawn(function()
		NotificationController.Request("TutorialAdvance", "Ack", DONE_INDEX)
	end)
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
local function onTutorial(value: any)
	if type(value) ~= "table" then
		return
	end
	local step: number = value.Step or 1
	if step >= DONE_INDEX or value.Done == true then
		stepMaid:Clean()
		currentStep = DONE_INDEX
		setHint("")
		if sawActiveStep and not skipped and step >= DONE_INDEX then
			showFriendsToast()
		end
		return
	end
	if step ~= currentStep then
		runStep(step)
	end
end

local function buildHud()
	local overlay = UIController.GetLayer("Overlay")
	local hint = UIKit.Label({
		Name = "TutorialHint",
		Size = UDim2.fromScale(0.34, 0.09),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Color = Palette.UIAccent,
		MaxTextSize = 56,
		Parent = overlay,
	})
	hint.Visible = false
	hintLabel = hint
	maid:Add(hint)
	local skip = UIKit.Button({
		Name = "TutorialSkip",
		Text = "Skip",
		Size = UDim2.fromScale(0.12, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.8),
		Color = Color3.fromRGB(80, 84, 100),
		Parent = overlay,
		OnClick = function()
			skipped = true
			task.spawn(function()
				local response = NotificationController.Request("TutorialAdvance", "Skip", currentStep)
				if not response.Ok then
					skipped = false
				end
			end)
		end,
	})
	UIKit.Aspect(skip, 3)
	skip.Visible = false
	skipButton = skip
	maid:Add(skip)
end

function TutorialController.Start()
	buildHud()
	maid:Add(DataController.OnKey("Tutorial", onTutorial))
end

return TutorialController

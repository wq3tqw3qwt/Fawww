--!strict
--[[
	SoundController: plays UI/effect sounds from Config.Visuals.Sounds, honouring Settings.Sfx,
	and runs the optional looping music track (Settings.Music).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Maid = require(ReplicatedStorage.Shared.Maid)
local Net = require(ReplicatedStorage.Shared.Net)
local DataController = require(script.Parent.DataController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SoundController = {}

local maid = Maid.new()
local music: Sound? = nil

-- Effect kind -> sound key.
local EFFECT_SOUNDS: { [string]: string } = {
	LevelMilestone = "Upgrade",
	LineBuilt = "Whoosh",
	VaultCollected = "Coins",
	ContractStamp = "Coins",
	Expansion = "Fanfare",
	Franchise = "Fanfare",
	MachineGranted = "Fanfare",
	SecretDiscovered = "Fanfare",
}

local function setting(key: string): boolean
	local settings = DataController.GetKey("Settings")
	if type(settings) ~= "table" then
		return true
	end
	return settings[key] ~= false
end

function SoundController.Play(key: string, volume: number?)
	if not setting("Sfx") then
		return
	end
	UIKit.PlaySound(key, volume)
end

local function applyMusic()
	local id = Config.Visuals.Sounds.Music
	if id == nil or id == "" then
		return
	end
	if setting("Music") then
		if music == nil then
			local created = UIKit.Create(
				"Sound",
				{ Name = "FE_Music", SoundId = id, Looped = true, Volume = 0.3, Parent = SoundService }
			)
			music = created
			maid:Add(created)
		end
		if music and not music.Playing then
			music:Play()
		end
	elseif music then
		music:Pause()
	end
end

function SoundController.Init()
	maid:Add(DataController.OnKey("Settings", function()
		UIKit.SfxEnabled = setting("Sfx")
		applyMusic()
	end))
	maid:Add(Net.Event("Effect").OnClientEvent:Connect(function(kind: any)
		local key = if type(kind) == "string" then EFFECT_SOUNDS[kind] else nil
		if key then
			SoundController.Play(key)
		end
	end))
end

return SoundController

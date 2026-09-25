--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Weapon and hit sounds, played on this client only.
--
-- Sounds come from the game's assets: a Folder named Sounds in
-- Assets/Weapons/<Name>, holding a Sound for each cue, named after it (see
-- Sounds.Cues). A cue can instead be a Folder of Sounds, and one is picked at
-- random each time, so repeated shots don't sound identical. Missing cues are
-- simply silent, so the "systems only" download, which has no assets, works
-- without any sound at all.
--
-- Everything plays through the OpenSRS SoundGroup in SoundService, so a game
-- can turn all of it up or down in one place.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Assets = require(script.Parent.Assets)

local PITCH_VARIATION = 0.03 -- each play is up to this much higher or lower, so repeats don't sound identical
local MAX_LIFETIME = 10 -- seconds a played sound is kept, in case it never reports finishing

local Sounds = {}

Sounds.Cues = table.freeze({
	Fire = "Fire", -- your own shot, and others' up close
	FireDistant = "FireDistant", -- others' shots from far away; Fire is used if there isn't one
	DryFire = "DryFire", -- pulling the trigger with no ammo left at all
	Casing = "Casing", -- a spent case landing, just after each of your shots
	Draw = "Draw",
	MagazineOut = "MagazineOut",
	MagazineFloor = "MagazineFloor",
	MagazineIn = "MagazineIn",
	SlideBack = "SlideBack",
	SlideForward = "SlideForward",
	ImpactWorld = "ImpactWorld",
	ImpactBody = "ImpactBody",
	NearMiss = "NearMiss", -- a bullet passing close by
	HitMarker = "HitMarker", -- your shot hit someone
	Headshot = "Headshot", -- your shot hit someone's head; HitMarker is used if there isn't one
})

local group = SoundService:FindFirstChild("OpenSRS")
if not (group and group:IsA("SoundGroup")) then
	local created = Instance.new("SoundGroup")
	created.Name = "OpenSRS"
	created.Volume = 1 -- SoundGroups start at half volume
	created.Parent = SoundService
	group = created
end
local soundGroup = group :: SoundGroup

local random = Random.new()

local function pick(weapon: string, cue: string): Sound?
	local folder = Assets.weaponPart(weapon, "Sounds")
	local entry = folder and folder:FindFirstChild(cue)
	if entry and entry:IsA("Sound") then
		return entry
	elseif entry and entry:IsA("Folder") then
		local options = {}
		for _, child in entry:GetChildren() do
			if child:IsA("Sound") then
				table.insert(options, child)
			end
		end
		if #options > 0 then
			return options[random:NextInteger(1, #options)]
		end
	end
	return nil
end

local function start(source: Sound, parent: Instance, cleanup: Instance)
	local sound = source:Clone()
	sound.SoundGroup = soundGroup
	sound.PlaybackSpeed *= 1 + random:NextNumber(-PITCH_VARIATION, PITCH_VARIATION)
	sound.Parent = parent
	sound.Ended:Once(function()
		cleanup:Destroy()
	end)
	Debris:AddItem(cleanup, MAX_LIFETIME)
	sound:Play()
end

-- Plays a cue as the player hears their own weapon: not placed in the world.
-- Returns whether there was a sound to play.
function Sounds.play(weapon: string, cue: string): boolean
	local source = pick(weapon, cue)
	if not source then
		return false
	end
	local holder = Instance.new("Folder")
	holder.Name = cue
	holder.Parent = soundGroup
	start(source, holder, holder)
	return true
end

-- Plays a cue at a point in the world, fainter with distance (set by the
-- Sound's own roll-off). Returns whether there was a sound to play.
function Sounds.at(weapon: string, cue: string, position: Vector3): boolean
	local source = pick(weapon, cue)
	if not source then
		return false
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = cue
	attachment.Position = position -- attachments on Terrain are in world space
	attachment.Parent = workspace.Terrain
	start(source, attachment, attachment)
	return true
end

return table.freeze(Sounds)

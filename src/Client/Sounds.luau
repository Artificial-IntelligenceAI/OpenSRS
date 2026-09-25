--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Weapon and hit sounds, played on this client only.
--
-- Sounds play through Roblox's audio API with acoustic simulation on, so
-- sounds in the world are muffled by walls, bend around corners and echo off
-- their surroundings, all worked out from the map. That includes the player's
-- own gun: firing in a concrete room sounds like it. Only interface sounds,
-- like the hit marker, play straight to the player's ears.
--
-- Sounds come from the game's assets: a Folder named Sounds in
-- Assets/Weapons/<Name>, holding a Sound for each cue, named after it (see
-- Sounds.Cues). A cue can instead be a Folder of Sounds, and one is picked at
-- random each time, so repeated shots don't sound identical. Each Sound sets
-- SoundId, Volume and PlaybackSpeed, and for sounds in the world,
-- RollOffMinDistance (full volume within it) and RollOffMaxDistance (silent
-- beyond it). Missing cues are simply silent, so the "systems only" download,
-- which has no assets, works without any sound at all.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Assets = require(script.Parent.Assets)

local PITCH_VARIATION = 0.03 -- each play is up to this much higher or lower, so repeats don't sound identical
local MAX_LIFETIME = 10 -- seconds a played sound is kept, in case it never reports finishing
local FALLOFF_STEP = 1.5 -- distance ratio between points on a sound's volume-over-distance curve

local Sounds = {}

Sounds.Cues = table.freeze({
	Fire = "Fire", -- a shot, yours or someone else's up close
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

SoundService.AcousticSimulationEnabled = true

-- Interface sounds skip the world and go straight to the speakers.
local output = Instance.new("AudioDeviceOutput")
output.Name = "OpenSRS"
output.Parent = SoundService

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

-- Full volume within the Sound's RollOffMinDistance, then falling off like
-- sound does in the open (half as loud at twice the distance), easing to
-- silence at its RollOffMaxDistance.
local function falloff(source: Sound): { [number]: number }
	local near = math.max(source.RollOffMinDistance, 0.1)
	local far = math.max(source.RollOffMaxDistance, near + 1)
	local curve = { [0] = 1, [near] = 1 }
	local distance = near * FALLOFF_STEP
	while distance < far do
		local taper = 1 - ((distance - near) / (far - near)) ^ 2
		curve[distance] = near / distance * taper
		distance *= FALLOFF_STEP
	end
	curve[far] = 0
	return curve
end

-- Plays `source` into `target`, then cleans up `holder` (which contains both).
local function start(source: Sound, target: Instance, holder: Instance)
	local player = Instance.new("AudioPlayer")
	player.Asset = source.SoundId
	player.Volume = source.Volume
	player.PlaybackSpeed = source.PlaybackSpeed * (1 + random:NextNumber(-PITCH_VARIATION, PITCH_VARIATION))
	player.Parent = holder
	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = target
	wire.Parent = holder
	player.Ended:Once(function()
		holder:Destroy()
	end)
	Debris:AddItem(holder, MAX_LIFETIME)
	player:Play()
end

-- Plays an interface cue straight to the player's ears, not placed in the
-- world. Returns whether there was a sound to play.
function Sounds.play(weapon: string, cue: string): boolean
	local source = pick(weapon, cue)
	if not source then
		return false
	end
	local holder = Instance.new("Folder")
	holder.Name = cue
	holder.Parent = output
	start(source, output, holder)
	return true
end

-- Plays a cue at a point in the world. Returns whether there was a sound to play.
function Sounds.at(weapon: string, cue: string, position: Vector3): boolean
	local source = pick(weapon, cue)
	if not source then
		return false
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = cue
	attachment.Position = position -- attachments on Terrain are in world space
	local emitter = Instance.new("AudioEmitter")
	emitter:SetDistanceAttenuation(falloff(source))
	emitter.Parent = attachment
	attachment.Parent = workspace.Terrain
	start(source, emitter, attachment)
	return true
end

-- Plays a cue close to the player, `offset` from their view (in the view's
-- space: +X right, +Y up, -Z ahead). Used for their own gun's handling sounds.
function Sounds.near(weapon: string, cue: string, offset: Vector3): boolean
	local view = workspace.CurrentCamera.CFrame
	return Sounds.at(weapon, cue, view:PointToWorldSpace(offset))
end

-- Starts loading every sound a weapon has, so the first shot isn't silent
-- while its sound downloads.
function Sounds.preload(weapon: string)
	local folder = Assets.weaponPart(weapon, "Sounds")
	if not folder then
		return
	end
	local players = {}
	for _, sound in folder:GetDescendants() do
		if sound:IsA("Sound") then
			local player = Instance.new("AudioPlayer")
			player.Asset = sound.SoundId
			table.insert(players, player)
		end
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(players)
		for _, player in players do
			player:Destroy()
		end
	end)
end

return table.freeze(Sounds)

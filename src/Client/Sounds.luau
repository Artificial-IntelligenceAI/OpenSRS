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
--
-- A cue can also be shaped with Roblox's audio effects (AudioCompressor,
-- AudioDistortion, AudioEqualizer, AudioReverb and the like): put them in the
-- Sound, or in the cue's Folder to shape every variation. The sound passes
-- through them in order of their names, so name them "1 Compress",
-- "2 Distort" and so on.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Assets = require(script.Parent.Assets)

local PITCH_VARIATION = 0.03 -- each play is up to this much higher or lower, so repeats don't sound identical
local MAX_LIFETIME = 10 -- seconds a played sound is kept, in case it never reports finishing
local FALLOFF_STEP = 1.5 -- distance ratio between points on a sound's volume-over-distance curve
local ENCLOSURE_RANGE = 60 -- studs: walls and roofs further away than this don't count as being indoors
local SETTLE_TIME = 1 -- seconds after the player jumps (see Sounds.jumped) before acoustic simulation is trusted again
local REMIX_EVERY = 0.1 -- seconds between re-judging a moving shot's surroundings
local REMIX_SPEED = 12 -- how quickly a moving shot's tails cross-fade to fit where it is now

local Sounds = {}

Sounds.Cues = table.freeze({
	Fire = "Fire", -- a shot, yours or someone else's up close: the blast itself
	FireTailIndoor = "FireTailIndoor", -- what follows the blast in a room: played with Fire, by how enclosed the shot is
	FireTailOutdoor = "FireTailOutdoor", -- what follows the blast in the open
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
local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude
probe.IgnoreWater = true
local ignored: { Instance } = {}
-- Sounds that move with something (your own gun, your view) while they play.
local following: { { attachment: Attachment, follow: () -> Vector3 } } = {}
local settledAt = 0 -- os.clock() when acoustic simulation has caught up with the last jump
-- Moving shots whose indoor and outdoor tails are re-mixed as they go.
type Mix = {
	indoor: AudioPlayer?,
	outdoor: AudioPlayer?,
	indoorVolume: number,
	outdoorVolume: number,
	follow: () -> Vector3,
	inside: number,
	target: number,
	sinceJudged: number,
}
local mixes: { Mix } = {}

local EFFECTS = table.freeze({
	AudioChorus = true,
	AudioCompressor = true,
	AudioDistortion = true,
	AudioEcho = true,
	AudioEqualizer = true,
	AudioFader = true,
	AudioFilter = true,
	AudioFlanger = true,
	AudioLimiter = true,
	AudioPitchShifter = true,
	AudioReverb = true,
	AudioTremolo = true,
})

-- The effects a sound passes through, in order: its own and its cue Folder's.
local function effectsOf(source: Sound): { Instance }
	local found = {}
	for _, container in { source.Parent, source } do
		if container and (container == source or container:IsA("Folder")) then
			for _, child in container:GetChildren() do
				if EFFECTS[child.ClassName] then
					table.insert(found, child)
				end
			end
		end
	end
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found
end

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

local function connect(from: Instance, to: Instance, holder: Instance)
	local wire = Instance.new("Wire")
	wire.SourceInstance = from
	wire.TargetInstance = to
	wire.Parent = holder
end

-- Plays `source` through its effects into `target`, then cleans up `holder`
-- (which contains all of it). `gain` scales the Sound's own volume.
local function start(source: Sound, target: Instance, holder: Instance, gain: number?): AudioPlayer
	local player = Instance.new("AudioPlayer")
	player.Asset = source.SoundId
	player.Volume = source.Volume * (gain or 1)
	player.PlaybackSpeed = source.PlaybackSpeed * (1 + random:NextNumber(-PITCH_VARIATION, PITCH_VARIATION))
	player.Parent = holder
	local last: Instance = player
	local tail = 0 -- how long effects keep sounding after the recording ends
	for _, effect in effectsOf(source) do
		local copy = effect:Clone()
		copy.Parent = holder
		connect(last, copy, holder)
		last = copy
		if copy:IsA("AudioReverb") then
			tail = math.max(tail, copy.DecayTime)
		elseif copy:IsA("AudioEcho") then
			tail = math.max(tail, copy.DelayTime * 4)
		end
	end
	connect(last, target, holder)
	player.Ended:Once(function()
		Debris:AddItem(holder, tail)
	end)
	Debris:AddItem(holder, MAX_LIFETIME + tail)
	player:Play()
	return player
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

-- Plays a cue at a point in the world, `gain` times as loud as its Sound says.
-- If `follow` is given, the sound moves to where it says each frame while it
-- plays (see Sounds.update), so it stays with something that moves.
-- Returns whether there was a sound to play.
local function playAt(
	weapon: string,
	cue: string,
	position: Vector3,
	gain: number?,
	follow: (() -> Vector3)?
): AudioPlayer?
	local source = pick(weapon, cue)
	if not source then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = cue
	attachment.Position = position -- attachments on Terrain are in world space
	local emitter = Instance.new("AudioEmitter")
	emitter:SetDistanceAttenuation(falloff(source))
	emitter.Parent = attachment
	attachment.Parent = workspace.Terrain
	-- The player's own sounds skip acoustic simulation until it has caught up
	-- with a jump (see Sounds.jumped).
	local settling = follow ~= nil and os.clock() < settledAt
	local player = start(source, if settling then output else emitter, attachment, gain)
	if follow and not settling then
		table.insert(following, { attachment = attachment, follow = follow })
	end
	return player
end

function Sounds.at(weapon: string, cue: string, position: Vector3, gain: number?, follow: (() -> Vector3)?): boolean
	return playAt(weapon, cue, position, gain, follow) ~= nil
end

-- Things that don't count as walls when judging how enclosed a spot is: the
-- player's own view model, other players, effects.
function Sounds.ignore(instances: { Instance })
	for _, instance in instances do
		table.insert(ignored, instance)
	end
	probe.FilterDescendantsInstances = ignored
end

-- Straight up, up at 45 degrees all around, and level all around.
local UP = { Vector3.yAxis }
local AROUND = {}
for index = 0, 7 do
	local angle = index * math.pi / 4
	local level = Vector3.new(math.cos(angle), 0, math.sin(angle))
	table.insert(AROUND, level)
	if index % 2 == 0 then
		table.insert(UP, (level + Vector3.yAxis).Unit)
	end
end

-- How enclosed a spot is, from 0 (in the open) to 1 (in a room): half from
-- how much roof is over it, half from how many walls are around it.
local function enclosure(position: Vector3): number
	local function blocked(directions: { Vector3 }): number
		local count = 0
		for _, direction in directions do
			if workspace:Raycast(position, direction * ENCLOSURE_RANGE, probe) then
				count += 1
			end
		end
		return count / #directions
	end
	return (blocked(UP) + blocked(AROUND)) / 2
end

-- A gunshot at `position`: the blast, then the tail a room or the open air
-- gives it, mixed by how enclosed the spot is. (Acoustic simulation adds the
-- actual map's echoes on top of either.) Weapons without tails just play Fire.
-- `follow` keeps it with the gun (your own shots), as for Sounds.at.
-- Returns whether there was a sound to play.
function Sounds.shot(weapon: string, position: Vector3, follow: (() -> Vector3)?): boolean
	if not Sounds.at(weapon, Sounds.Cues.Fire, position, nil, follow) then
		return false
	end
	local inside = enclosure(position)
	if follow then
		-- Both tails play, re-mixed as the shooter moves (see Sounds.update), so
		-- a shot fired just before going outside doesn't ring like a room out
		-- there.
		local indoor = playAt(weapon, Sounds.Cues.FireTailIndoor, position, nil, follow)
		local outdoor = playAt(weapon, Sounds.Cues.FireTailOutdoor, position, nil, follow)
		local mix: Mix = {
			indoor = indoor,
			outdoor = outdoor,
			indoorVolume = if indoor then indoor.Volume else 0,
			outdoorVolume = if outdoor then outdoor.Volume else 0,
			follow = follow,
			inside = inside,
			target = inside,
			sinceJudged = 0,
		}
		table.insert(mixes, mix)
		-- Equal power, so a half-enclosed spot isn't quieter than either extreme.
		if indoor then
			indoor.Volume = mix.indoorVolume * math.sqrt(inside)
		end
		if outdoor then
			outdoor.Volume = mix.outdoorVolume * math.sqrt(1 - inside)
		end
		return true
	end
	if inside > 0 then
		Sounds.at(weapon, Sounds.Cues.FireTailIndoor, position, math.sqrt(inside))
	end
	if inside < 1 then
		Sounds.at(weapon, Sounds.Cues.FireTailOutdoor, position, math.sqrt(1 - inside))
	end
	return true
end

-- Call when the player has just been moved in an instant (a teleport or a
-- respawn). Acoustic simulation takes a moment to catch up with the listener
-- jumping: their own sounds playing or started meanwhile can come out
-- muffled, and a shot's weak blast lets the echo in its tail sound like a
-- second shot. So until it has caught up, their own sounds go straight to
-- their ears instead, as they'd sound right next to them, just without the
-- room.
function Sounds.jumped()
	settledAt = os.clock() + SETTLE_TIME
	for _, sound in following do
		local attachment = sound.attachment
		if attachment.Parent then
			for _, wire in attachment:GetChildren() do
				if wire:IsA("Wire") and wire.TargetInstance and wire.TargetInstance:IsA("AudioEmitter") then
					wire.TargetInstance = output
				end
			end
		end
	end
	table.clear(following)
end

-- Moves the sounds that follow something, and re-mixes moving shots' tails
-- for where they are now; call once a frame.
function Sounds.update(frameTime: number)
	for index = #following, 1, -1 do
		local sound = following[index]
		if sound.attachment.Parent then
			sound.attachment.Position = sound.follow()
		else
			table.remove(following, index)
		end
	end
	for index = #mixes, 1, -1 do
		local mix = mixes[index]
		local indoor, outdoor = mix.indoor, mix.outdoor
		local playing = (indoor and indoor.Parent) or (outdoor and outdoor.Parent)
		if not playing then
			table.remove(mixes, index)
			continue
		end
		mix.sinceJudged += frameTime
		if mix.sinceJudged >= REMIX_EVERY then
			mix.sinceJudged = 0
			mix.target = enclosure(mix.follow())
		end
		mix.inside += (mix.target - mix.inside) * (1 - math.exp(-REMIX_SPEED * frameTime))
		if indoor and indoor.Parent then
			indoor.Volume = mix.indoorVolume * math.sqrt(mix.inside)
		end
		if outdoor and outdoor.Parent then
			outdoor.Volume = mix.outdoorVolume * math.sqrt(1 - mix.inside)
		end
	end
end

-- Plays a cue close to the player, `offset` from their view (in the view's
-- space: +X right, +Y up, -Z ahead), and keeps it there while it plays unless
-- `stays` (for something left behind, like a dropped magazine). Used for their
-- own gun's handling sounds.
function Sounds.near(weapon: string, cue: string, offset: Vector3, stays: boolean?): boolean
	local function place(): Vector3
		return workspace.CurrentCamera.CFrame:PointToWorldSpace(offset)
	end
	return Sounds.at(weapon, cue, place(), nil, if stays then nil else place)
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

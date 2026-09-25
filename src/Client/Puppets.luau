--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Draws other players. The server only sends the players this client is
-- allowed to know about, so anyone missing from the latest update is hidden.
-- Positions are shown slightly in the past and blended between updates so
-- movement looks smooth.

local Shared = script.Parent.Parent.Shared
local Body = require(Shared.Body)
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
local Avatar = require(script.Parent.Avatar)

type Snapshot = Protocol.Snapshot
type Remote = Protocol.Remote

local INTERPOLATION_TICKS = Config.snapshotInterval * 2 + 1
local MAX_SNAPSHOTS = 30
local CLOCK_SMOOTHING = 0.02

local Puppets = {}

local folder = Instance.new("Folder")
folder.Name = "OpenSRSPuppets"
folder.Parent = workspace
Puppets.folder = folder

local snapshots: { Snapshot } = {}
local avatars: { [number]: Avatar.Avatar } = {}
local clockOffset: number? = nil -- server tick minus local tick

local function localTick(): number
	return os.clock() * Config.tickRate
end

local function lerpAngle(a: number, b: number, t: number): number
	local difference = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + difference * t
end

local function blend(a: Remote, b: Remote, t: number): Remote
	return {
		position = a.position:Lerp(b.position, t),
		yaw = lerpAngle(a.yaw, b.yaw, t),
		pitch = a.pitch + (b.pitch - a.pitch) * t,
		stance = b.stance,
		leanOffset = a.leanOffset + (b.leanOffset - a.leanOffset) * t,
	}
end

function Puppets.receive(data: unknown)
	local snapshot = Protocol.decodeSnapshot(data)
	if not snapshot then
		return
	end
	local latest = snapshots[#snapshots]
	if latest and snapshot.tick <= latest.tick then
		return -- arrived out of order
	end
	table.insert(snapshots, snapshot)
	if #snapshots > MAX_SNAPSHOTS then
		table.remove(snapshots, 1)
	end

	-- Track the server clock. A snapshot that arrives unusually fast moves the
	-- estimate forward right away; slow ones only nudge it back.
	local offset = snapshot.tick - localTick()
	local current = clockOffset
	if current == nil or offset > current then
		clockOffset = offset
	else
		clockOffset = current + (offset - current) * CLOCK_SMOOTHING
	end
end

-- The server tick other players are being drawn at right now, or 0 before
-- the first snapshot. Shots tell the server this so it can rewind to it.
function Puppets.renderTick(): number
	local offset = clockOffset
	if offset == nil then
		return 0
	end
	return math.max(localTick() + offset - INTERPOLATION_TICKS, 0)
end

function Puppets.render()
	if clockOffset == nil or #snapshots == 0 then
		return
	end
	local renderTick = Puppets.renderTick()

	local before: Snapshot? = nil
	local after: Snapshot? = nil
	for _, snapshot in snapshots do
		if snapshot.tick <= renderTick then
			before = snapshot
		else
			after = snapshot
			break
		end
	end

	local shown: { [number]: Remote } = {}
	if before and after then
		local t = (renderTick - before.tick) / (after.tick - before.tick)
		for slot, remote in after.players do
			local previous = before.players[slot]
			shown[slot] = if previous then blend(previous, remote, t) else remote
		end
	else
		local only = before or after
		if only then
			shown = only.players
		end
	end

	for slot, remote in shown do
		local avatar = avatars[slot]
		if not avatar then
			avatar = Avatar.new(`Player{slot}`)
			avatars[slot] = avatar
		end
		Avatar.apply(avatar, Body.pose(remote.position, remote.yaw, remote.pitch, remote.stance, remote.leanOffset))
		avatar.model.Parent = folder
	end
	for slot, avatar in avatars do
		if not shown[slot] then
			avatar.model.Parent = nil
		end
	end
end

return table.freeze(Puppets)

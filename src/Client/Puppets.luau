--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Draws other players. The server only sends the players this client is
-- allowed to know about, so anyone missing from the latest update is hidden.
-- Positions are shown slightly in the past and blended between updates so
-- movement looks smooth. With the TeammateHighlights setting on, teammates are
-- outlined in their team's color, even through walls.

local Players = game:GetService("Players")

local Shared = script.Parent.Parent.Shared
local Body = require(Shared.Body)
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
local Teammates = require(Shared.Teammates)
local Avatar = require(script.Parent.Avatar)
local GunModel = require(script.Parent.GunModel)

type Snapshot = Protocol.Snapshot
type Remote = Protocol.Remote

local INTERPOLATION_TICKS = Config.snapshotInterval * 2 + 1
local MAX_SNAPSHOTS = 30
local CLOCK_SMOOTHING = 0.02
local HIGHLIGHT = "OpenSRSTeammate"
local HIGHLIGHT_FILL = 0.75 -- how see-through the fill is; the outline is solid

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
-- Where the ejection port of the gun held by the player in `slot` is, if that
-- player is being shown.
function Puppets.ejectionPort(slot: number): CFrame?
	local avatar = avatars[slot]
	if not avatar or not avatar.model.Parent then
		return nil
	end
	local port = GunModel.point(avatar.gun, "EjectionPort")
	return if port then port.WorldCFrame else nil
end

-- The player in each slot, from the attribute the server sets on them.
local function playersBySlot(): { [number]: Player }
	local found = {}
	for _, player in Players:GetPlayers() do
		local slot = player:GetAttribute(Teammates.SLOT_ATTRIBUTE)
		if typeof(slot) == "number" then
			found[slot] = player
		end
	end
	return found
end

-- Outlines a teammate in their team's color, through walls; anyone else has
-- no outline.
local function outline(avatar: Avatar.Avatar, player: Player?)
	local existing = avatar.model:FindFirstChild(HIGHLIGHT)
	if not (player and Teammates.are(Players.LocalPlayer, player)) then
		if existing then
			existing:Destroy()
		end
		return
	end
	local highlight: Highlight
	if existing and existing:IsA("Highlight") then
		highlight = existing
	else
		highlight = Instance.new("Highlight")
		highlight.Name = HIGHLIGHT
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = HIGHLIGHT_FILL
		highlight.OutlineTransparency = 0
		highlight.Parent = avatar.model
	end
	local color = player.TeamColor.Color
	highlight.FillColor = color
	highlight.OutlineColor = color
end

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

	local owners = if Config.teammateHighlights then playersBySlot() else nil
	for slot, remote in shown do
		local avatar = avatars[slot]
		if not avatar then
			avatar = Avatar.new(`Player{slot}`)
			avatars[slot] = avatar
		end
		Avatar.apply(avatar, Body.pose(remote.position, remote.yaw, remote.pitch, remote.stance, remote.leanOffset))
		if owners then
			outline(avatar, owners[slot])
		end
		avatar.model.Parent = folder
	end
	for slot, avatar in avatars do
		if not shown[slot] and avatar.model.Parent then
			-- Holes from Impacts don't outlast a player being shown: they'd
			-- still be there after a respawn.
			for _, descendant in avatar.model:GetDescendants() do
				if descendant:GetAttribute("OpenSRSHole") then
					descendant:Destroy()
				end
			end
			avatar.model.Parent = nil
		end
	end
end

return table.freeze(Puppets)

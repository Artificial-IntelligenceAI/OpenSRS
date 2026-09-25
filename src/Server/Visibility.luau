--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Anti-wallhack. Decides which players each player may know about. The server
-- only sends a client the characters on this list, so a wallhack has nothing
-- to draw.
--
-- A target counts as visible if any line from one of the viewer's possible eye
-- positions reaches one of the target's body parts. To avoid pop-in, eyes and
-- bodies are pushed a little ahead in time along their velocity, and eyes
-- include where the viewer could lean to. Nothing is ever pushed through a
-- wall. Once seen, a target stays known for a short grace period.

local Shared = script.Parent.Parent.Shared
local Body = require(Shared.Body)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

type State = Types.State

export type Subject = {
	slot: number,
	state: State,
	leanOffset: number,
}

export type Stats = {
	pairs: number,
	rays: number,
	seconds: number,
}

local LOOKAHEAD = 0.25 -- seconds of movement to look ahead
local GRACE = 0.4 -- seconds a target stays known after it was last visible
local SEE_THROUGH = 0.25 -- parts at least this transparent don't block sight
local EYE_RADIUS = Config.movement.eyeRadius
local MAX_HOPS = 4 -- see-through parts a single line may pass
local HOP_EPSILON = 0.01

local Visibility = {}

local vision = RaycastParams.new()
vision.FilterType = Enum.RaycastFilterType.Exclude
vision.IgnoreWater = true
-- Unlike movement, scenery that can be walked through (like bushes) still blocks sight.
vision.RespectCanCollide = false

local lastSeen: { [number]: { [number]: number } } = {}
local hints: { [number]: { [number]: number? } } = {} -- which line worked last time

-- Moves a point along `displacement`, stopping short of any wall.
local function advance(point: Vector3, displacement: Vector3): Vector3
	if displacement.Magnitude < 1e-3 then
		return point
	end
	local result = workspace:Spherecast(point, EYE_RADIUS, displacement, vision)
	if result then
		return point + displacement.Unit * result.Distance
	end
	return point + displacement
end

local function rightVector(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

local function eyesOf(subject: Subject): { Vector3 }
	local state = subject.state
	local stance = Config.stance(state.stance)
	local current = state.position + Vector3.new(0, stance.eyeHeight, 0) + rightVector(state.yaw) * subject.leanOffset
	local center = state.position + Vector3.new(0, stance.eyeHeight, 0)
	local ahead = advance(center, state.velocity * LOOKAHEAD)
	local eyes = { current, ahead }
	if state.stance ~= Types.Stance.Prone then
		local right = rightVector(state.yaw) * Config.movement.leanDistance
		table.insert(eyes, advance(ahead, right))
		table.insert(eyes, advance(ahead, -right))
	end
	return eyes
end

local function pointsOf(subject: Subject): { Vector3 }
	local state = subject.state
	local torsoHeight = Config.stance(state.stance).height / 2
	local torso = state.position + Vector3.new(0, torsoHeight, 0)
	local shift = advance(torso, state.velocity * LOOKAHEAD) - torso
	local pose = Body.pose(state.position + shift, state.yaw, state.pitch, state.stance, subject.leanOffset)
	return {
		pose.Torso.Position,
		pose.Head.Position,
		pose["Left Arm"].Position,
		pose["Right Arm"].Position,
		pose["Left Leg"].Position:Lerp(pose["Right Leg"].Position, 0.5),
	}
end

-- True if nothing solid is between the two points.
local function clear(from: Vector3, to: Vector3): (boolean, number)
	local rays = 0
	for _ = 1, MAX_HOPS do
		local offset = to - from
		rays += 1
		local result = workspace:Raycast(from, offset, vision)
		if not result then
			return true, rays
		end
		local part = result.Instance
		if not (part:IsA("BasePart") and part.Transparency >= SEE_THROUGH) then
			return false, rays
		end
		from = result.Position + offset.Unit * HOP_EPSILON
	end
	return false, rays
end

-- Recomputes what the subjects in one group can see. Viewers are split into
-- `groups` groups by slot, so the work is spread over several ticks instead of
-- landing in one frame.
function Visibility.update(subjects: { Subject }, now: number, group: number, groups: number): Stats
	local started = os.clock()
	local rays = 0
	local pairCount = 0

	local eyes: { { Vector3 } } = {}
	local points: { { Vector3 } } = {}
	for index, subject in subjects do
		eyes[index] = eyesOf(subject)
		points[index] = pointsOf(subject)
	end

	for viewerIndex, viewer in subjects do
		if viewer.slot % groups ~= group then
			continue
		end
		local seen = lastSeen[viewer.slot]
		if not seen then
			seen = {}
			lastSeen[viewer.slot] = seen
		end
		local hinted = hints[viewer.slot]
		if not hinted then
			hinted = {}
			hints[viewer.slot] = hinted
		end

		for targetIndex, target in subjects do
			if targetIndex == viewerIndex then
				continue
			end
			pairCount += 1
			local viewerEyes = eyes[viewerIndex]
			local targetPoints = points[targetIndex]
			local pointCount = #targetPoints

			-- Try the line that worked last time first; it usually still does.
			local hint = hinted[target.slot]
			local found: number? = nil
			if hint then
				local eye = viewerEyes[(hint - 1) // pointCount + 1]
				local point = targetPoints[(hint - 1) % pointCount + 1]
				if eye and point then
					local visible, used = clear(eye, point)
					rays += used
					if visible then
						found = hint
					end
				end
			end

			if not found then
				for eyeIndex, eye in viewerEyes do
					for pointIndex, point in targetPoints do
						local visible, used = clear(eye, point)
						rays += used
						if visible then
							found = (eyeIndex - 1) * pointCount + pointIndex
							break
						end
					end
					if found then
						break
					end
				end
			end

			hinted[target.slot] = found
			if found then
				seen[target.slot] = now
			end
		end
	end

	return { pairs = pairCount, rays = rays, seconds = os.clock() - started }
end

function Visibility.canSee(viewer: number, target: number, now: number): boolean
	local seen = lastSeen[viewer]
	local at = seen and seen[target]
	return at ~= nil and now - at <= GRACE
end

-- Call when a slot is freed, so a new player in it starts with a clean slate.
function Visibility.forget(slot: number)
	lastSeen[slot] = nil
	hints[slot] = nil
	for _, seen in lastSeen do
		seen[slot] = nil
	end
	for _, hinted in hints do
		hinted[slot] = nil
	end
end

return table.freeze(Visibility)

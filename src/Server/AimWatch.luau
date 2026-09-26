--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Aimbot detection. Watches where each player aims, tick by tick, against
-- where the enemies they could see really were (rewound to what they saw),
-- and raises a flag (see Flags) when their aim keeps doing what no hand does:
--
--   SnapAim      Flicks that land dead on a target and stop there. A person
--                flicking overshoots or undershoots, then corrects.
--   Reaction     Aim reaching an enemy within a blink of them coming into view,
--                again and again. People take roughly 150 to 250 ms.
--   LockOn       Aim that follows a moving enemy's head with almost no wobble:
--                the aim's offset from them stays frozen, where a hand's drifts
--                back and forth around them. (The offset itself isn't judged:
--                what a player sees always lags their target a little.)
--
-- One suspicious moment never flags anyone: each detector keeps a record of
-- recent chances and raises a flag only when enough of them look inhuman.
-- After a flag the record starts over, so another needs fresh evidence. The
-- AimFlagSensitivity setting scales how much evidence it takes; 0 turns this
-- off. OpenSRS never punishes anyone itself: the game decides what a flag means.

local Shared = script.Parent.Parent.Shared
local Body = require(Shared.Body)
local Config = require(Shared.Config)
local Flags = require(script.Parent.Flags)

-- What a person can't do (in degrees and seconds), at sensitivity 1.
local ON_TARGET = 1.5 -- degrees from a target's head or body that count as on it
local SNAP_MIN_TRAVEL = 15 -- degrees the aim must move in the flick window to count as a flick
local SNAP_WINDOW_TICKS = 8 -- how far back a flick is looked for
local SNAP_DEAD_ON = 0.35 -- degrees: a flick ending this close to a target's center is suspiciously exact
local REACTION_MIN_TURN = 10 -- degrees the aim had to move for a reaction to count
local REACTION_LIMIT = 0.12 -- seconds: reaching a target faster than this is suspicious
local LOCK_TARGET_SPEED = 15 -- degrees a second: a target moving across the view at least this fast
local LOCK_WINDOW_TICKS = 30 -- how long one tracking sample lasts
local LOCK_NEAR = 1.5 -- degrees: tracking closer than this on average counts as tracking
local LOCK_WOBBLE = 0.1 -- degrees: the aim's offset from them moving around less than this is suspicious
-- Evidence: of the last RECORD_SIZE chances, at least FLAG_COUNT suspicious
-- ones, making up at least FLAG_SHARE of them.
local RECORD_SIZE = 20
local FLAG_COUNT = 6
local FLAG_SHARE = 0.5

type Record = { results: { boolean } }

type Seen = {
	since: number, -- the server tick they came into view (they reach the player's screen when it's viewing that tick)
	startError: number, -- degrees off them when they did
	reacted: boolean,
	lastDirection: Vector3?, -- from the eye to them, last tick
	lockOffsets: { Vector2 }, -- this tracking sample so far: the aim's offset from their head, in degrees
}

type Watcher = {
	aims: { Vector3 }, -- the last SNAP_WINDOW_TICKS + 1 aim directions, oldest first
	seen: { [number]: Seen }, -- enemies currently in view, by slot
	records: { [string]: Record },
}

export type Target = {
	slot: number,
	visible: boolean,
}

local AimWatch = {}

local watchers: { [number]: Watcher } = {}

local function angle(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

-- How far `aim` is to the side of and above `toward`, in degrees.
local function offset(aim: Vector3, toward: Vector3): Vector2
	local pitch = math.asin(math.clamp(toward.Y, -1, 1))
	local yawDifference = math.atan2(-aim.X, -aim.Z) - math.atan2(-toward.X, -toward.Z)
	yawDifference = (yawDifference + math.pi) % (2 * math.pi) - math.pi
	return Vector2.new(math.deg(yawDifference * math.cos(pitch)), math.deg(math.asin(math.clamp(aim.Y, -1, 1)) - pitch))
end

local function watcherFor(slot: number): Watcher
	local watcher = watchers[slot]
	if not watcher then
		watcher = { aims = {}, seen = {}, records = {} }
		watchers[slot] = watcher
	end
	return watcher
end

-- Adds one chance to a detector's record, and raises a flag when the record
-- holds enough evidence.
local function note(player: Player, watcher: Watcher, detector: string, suspicious: boolean, details: string)
	local sensitivity = Config.aimFlagSensitivity
	if sensitivity <= 0 then
		return
	end
	local record = watcher.records[detector]
	if not record then
		record = { results = {} }
		watcher.records[detector] = record
	end
	table.insert(record.results, suspicious)
	if #record.results > RECORD_SIZE then
		table.remove(record.results, 1)
	end
	local count = 0
	for _, result in record.results do
		if result then
			count += 1
		end
	end
	local needed = math.max(math.ceil(FLAG_COUNT / sensitivity), 2)
	local share = math.clamp(FLAG_SHARE / sensitivity, 0.2, 1)
	if suspicious and count >= needed and count / #record.results >= share then
		Flags.raise(player, detector, `{count} of the last {#record.results} {details}`)
		table.clear(record.results)
	end
end

-- Where the target's head and torso were at `tick`, if known.
local function aimPoints(poseAt: (slot: number, tick: number) -> any, slot: number, tick: number): (Vector3?, Vector3?)
	local remote = poseAt(slot, tick)
	if not remote then
		return nil, nil
	end
	local pose = Body.pose(remote.position, remote.yaw, remote.pitch, remote.stance, remote.leanOffset)
	return pose.Head.Position, pose.Torso.Position
end

-- Called for every input the server processes from `player` (in `slot`):
-- their eye, where they aim (recoil included, since that's where bullets go),
-- the tick they were seeing others at, whether they fired, and the other
-- players with whether each is in their view.
function AimWatch.observe(
	player: Player,
	slot: number,
	eye: Vector3,
	aim: Vector3,
	viewedTick: number,
	serverTick: number,
	fired: boolean,
	targets: { Target },
	poseAt: (slot: number, tick: number) -> any
)
	if Config.aimFlagSensitivity <= 0 then
		return
	end
	local watcher = watcherFor(slot)
	local aims = watcher.aims
	table.insert(aims, aim)
	if #aims > SNAP_WINDOW_TICKS + 1 then
		table.remove(aims, 1)
	end

	local nearestError, nearestSlot = math.huge, nil
	local inView: { [number]: boolean } = {}
	for _, target in targets do
		if not target.visible then
			continue
		end
		local head, torso = aimPoints(poseAt, target.slot, viewedTick)
		if not (head and torso) then
			continue
		end
		inView[target.slot] = true
		local toHead = (head - eye).Unit
		local headError = angle(aim, toHead)
		local offTarget = math.min(headError, angle(aim, (torso - eye).Unit))
		if offTarget < nearestError then
			nearestError, nearestSlot = offTarget, target.slot
		end

		local seen = watcher.seen[target.slot]
		if not seen then
			seen = { since = serverTick, startError = offTarget, reacted = false, lockOffsets = {} }
			watcher.seen[target.slot] = seen
		end

		-- Reaction: how soon after coming into view the aim reached them.
		if not seen.reacted and offTarget < ON_TARGET then
			seen.reacted = true
			if seen.startError >= REACTION_MIN_TURN then
				-- From when they appeared on the player's screen, not when the
				-- server let them be seen: getting there takes a while. The
				-- first snapshot with them in is drawn straight away, up to a
				-- snapshot early, so count from the earliest they could have
				-- shown: a real reaction can only measure a little longer.
				local shown = seen.since - Config.snapshotInterval
				local reaction = math.max(viewedTick - shown, 0) / Config.tickRate
				note(
					player,
					watcher,
					"Reaction",
					reaction < REACTION_LIMIT,
					`enemies coming into view were aimed at within {REACTION_LIMIT * 1000} ms (last: {math.round(
						reaction * 1000
					)} ms after they appeared, {math.round(seen.startError)} degrees away)`
				)
			end
		end

		-- Lock-on: tracking a target that moves across the view.
		local lastDirection = seen.lastDirection
		seen.lastDirection = toHead
		if lastDirection then
			local targetSpeed = angle(lastDirection, toHead) * Config.tickRate
			if targetSpeed >= LOCK_TARGET_SPEED and headError < ON_TARGET * 2 then
				local offsets = seen.lockOffsets
				table.insert(offsets, offset(aim, toHead))
				if #offsets >= LOCK_WINDOW_TICKS then
					local mean = Vector2.zero
					for _, value in offsets do
						mean += value
					end
					mean /= #offsets
					local spread = 0
					for _, value in offsets do
						spread += (value - mean).Magnitude ^ 2
					end
					local wobble = math.sqrt(spread / #offsets)
					if mean.Magnitude < LOCK_NEAR then
						note(
							player,
							watcher,
							"LockOn",
							wobble < LOCK_WOBBLE,
							`half-second stretches tracking a moving enemy wobbled less than {LOCK_WOBBLE} degrees (last: {string.format(
								"%.3f",
								wobble
							)} degrees wobble, {string.format("%.2f", mean.Magnitude)} degrees off)`
						)
					end
					table.clear(offsets)
				end
			else
				table.clear(seen.lockOffsets)
			end
		end
	end
	-- Anyone out of view counts as new when they come back.
	for targetSlot in watcher.seen do
		if not inView[targetSlot] then
			watcher.seen[targetSlot] = nil
		end
	end

	-- Snap: a shot at the end of a flick.
	if fired and nearestSlot and nearestError < ON_TARGET and #aims >= SNAP_WINDOW_TICKS + 1 then
		local travel = angle(aims[1], aim)
		if travel >= SNAP_MIN_TRAVEL then
			-- Did the flick overshoot? A person's usually does: the aim passes the
			-- target (or falls short) and comes back. Look for the aim being closer
			-- to its final direction earlier in the flick than just before the end.
			local approach = {}
			for index = 1, #aims do
				table.insert(approach, angle(aims[index], aim))
			end
			local corrected = false
			for index = 2, #approach - 1 do
				if approach[index] < approach[#approach - 1] - 0.05 then
					corrected = true
				end
			end
			note(
				player,
				watcher,
				"SnapAim",
				nearestError < SNAP_DEAD_ON and not corrected,
				`flicks of {SNAP_MIN_TRAVEL}+ degrees ended within {SNAP_DEAD_ON} degrees of an enemy without overshooting (last: {math.round(
					travel
				)} degree flick, {string.format("%.2f", nearestError)} degrees off)`
			)
		end
	end
end

-- Forgets a player's aim when they respawn or leave.
function AimWatch.forget(slot: number)
	watchers[slot] = nil
end

-- Clears what `slot` knows about seeing others, without losing their evidence
-- (after a teleport or respawn their view starts over).
function AimWatch.reset(slot: number)
	local watcher = watchers[slot]
	if watcher then
		table.clear(watcher.aims)
		table.clear(watcher.seen)
	end
end

return table.freeze(AimWatch)

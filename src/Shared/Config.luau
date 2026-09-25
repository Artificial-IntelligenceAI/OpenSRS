--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Default gameplay values. Distances are in studs, times in seconds unless a
-- name says ticks.

export type StanceConfig = {
	height: number, -- collision height
	stepUp: number, -- ledges up to this height are climbed automatically
	eyeHeight: number,
	speed: number,
	leanPivot: number, -- height the upper body rotates around when leaning
}

local stand: StanceConfig = table.freeze({ height = 5, stepUp = 1.1, eyeHeight = 4.5, speed = 12, leanPivot = 2 })
local crouch: StanceConfig = table.freeze({ height = 4, stepUp = 1.1, eyeHeight = 3.4, speed = 6, leanPivot = 1.1 })
local prone: StanceConfig = table.freeze({ height = 1.5, stepUp = 0.5, eyeHeight = 0.8, speed = 2.5, leanPivot = 0 })

local Config = {
	tickRate = 60,
	snapshotInterval = 3, -- ticks between updates about other players

	movement = table.freeze({
		width = 2,
		skin = 0.05,
		gravity = 196.2,
		terminalVelocity = 150,
		groundAcceleration = 60,
		groundDeceleration = 80,
		airAcceleration = 6,
		jumpVelocity = 38,
		jumpCooldownTicks = 24,
		groundSnap = 0.6,
		minGroundNormal = 0.5,
		backwardMultiplier = 0.8,
		slowWalkSpeed = 6,
		sprintSpeed = 19,
		sprintMinForward = 0.5,
		leanDistance = 1,
		leanTicks = 10, -- ticks to go from upright to a full lean
		eyeRadius = 0.4, -- how close the eye may get to a wall
		maxPitch = math.rad(80),
	}),
}

-- Stance numbers match Types.Stance.
local stances: { [number]: StanceConfig } = { [0] = stand, [1] = crouch, [2] = prone }

function Config.stance(stance: number): StanceConfig
	return stances[stance] or stand
end

return table.freeze(Config)

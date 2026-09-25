--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Gameplay values used by the simulation. Distances are in studs, times in
-- seconds unless a name says ticks.
--
-- Values games can change come from Settings (see SettingsSchema.luau), which
-- fills these in once at startup, before anything else reads them. The rest
-- are fixed by the R6 body and aren't meant to be tuned per game.

export type StanceConfig = {
	height: number, -- collision height
	stepUp: number, -- ledges up to this height are climbed automatically
	eyeHeight: number,
	speed: number,
	leanPivot: number, -- height the upper body rotates around when leaning
}

local stand: StanceConfig = { height = 5, stepUp = 1.1, eyeHeight = 4.5, speed = 12, leanPivot = 2 }
local crouch: StanceConfig = { height = 4, stepUp = 1.1, eyeHeight = 3.4, speed = 6, leanPivot = 1.1 }
local prone: StanceConfig = { height = 1.5, stepUp = 0.5, eyeHeight = 0.8, speed = 2.5, leanPivot = 0 }

local Config = {
	tickRate = 60,
	snapshotInterval = 3, -- ticks between updates about other players
	respawnTime = 3,
	maxHealth = 100,

	movement = {
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
		aimSpeedMultiplier = 0.6,
		slowWalkSpeed = 6,
		sprintSpeed = 19,
		sprintMinForward = 0.5,
		leanDistance = 1,
		leanTicks = 10, -- ticks to go from upright to a full lean
		eyeRadius = 0.4, -- how close the eye may get to a wall
		maxPitch = math.rad(80),
	},
}

-- Stance numbers match Types.Stance.
local stances: { [number]: StanceConfig } = { [0] = stand, [1] = crouch, [2] = prone }

function Config.stance(stance: number): StanceConfig
	return stances[stance] or stand
end

return Config

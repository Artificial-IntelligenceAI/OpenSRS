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
	-- Lying down, the body is much longer than it is wide, so its collision
	-- box covers the whole body and turns with it: `bodyLength` along it,
	-- centered `bodyBack` behind the feet point, `bodyWidth` across. Upright
	-- stances leave these out and use a square box of movement.width.
	bodyLength: number?,
	bodyBack: number?,
	bodyWidth: number?,
}

local stand: StanceConfig = { height = 5, stepUp = 1.1, eyeHeight = 4.5, speed = 12, leanPivot = 2 }
local crouch: StanceConfig = { height = 4, stepUp = 1.1, eyeHeight = 3.4, speed = 6, leanPivot = 1.1 }
-- The prone box spans the body in Body.luau: arms reaching 1.6 ahead, feet
-- 4.6 behind, elbows 1.7 to each side.
local prone: StanceConfig = {
	height = 1.5,
	stepUp = 0.5,
	eyeHeight = 0.8,
	speed = 2.5,
	leanPivot = 0,
	bodyLength = 6.2,
	bodyBack = 1.5,
	bodyWidth = 3.4,
}

local Config = {
	tickRate = 60,
	snapshotInterval = 3, -- ticks between updates about other players
	catchUpTicks = 4, -- ticks of input a stalled player may catch up on at once (CatchUpTime)
	respawnTime = 3,
	maxHealth = 100,
	bulletHoleTime = 30, -- seconds; cosmetic, on each client
	maxBulletHoles = 60,
	teammateHighlights = false, -- teammates are outlined, and sent even behind walls
	unseenShotPrecision = 5, -- studs: how exactly shots from someone out of sight are placed
	friendlyFire = false, -- bullets hurt teammates
	allowReset = true, -- Roblox's menu Reset button works
	killCreditTime = 0, -- seconds: a reset or fall credits whoever last hurt them if within this; 0 is no limit
	aimFlagSensitivity = 1, -- 0 turns aimbot flags off; higher flags on less evidence
	aimToggle = false, -- right click toggles aiming rather than holding it
	leanToggle = true, -- Q and E toggle leaning rather than holding it

	movement = {
		width = 2,
		skin = 0.05,
		gravity = 196.2,
		terminalVelocity = 150,
		groundAcceleration = 1000,
		groundDeceleration = 1000,
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

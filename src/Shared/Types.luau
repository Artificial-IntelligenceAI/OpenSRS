--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Data shapes shared by the server and the client.

-- One tick of player input. The client sends these; the server never trusts
-- anything else from it about movement or shooting.
export type Input = {
	seq: number, -- increases by one every tick
	moveX: number, -- -1 (left) to 1 (right)
	moveZ: number, -- -1 (back) to 1 (forward)
	yaw: number, -- radians, -pi to pi
	pitch: number, -- radians, positive looks up
	buttons: number, -- bit flags, see Types.Buttons
	stance: number, -- the stance the player wants, see Types.Stance
	viewTick: number, -- the server tick the player was seeing others at, in eighths of a tick
}

-- Everything the simulation needs to continue from one tick to the next.
export type State = {
	position: Vector3, -- feet, center of the body
	velocity: Vector3,
	grounded: boolean,
	stance: number,
	sprinting: boolean,
	aiming: boolean,
	leanTicks: number, -- negative leans left, positive leans right
	jumpCooldown: number, -- ticks until the next jump is allowed
	yaw: number,
	pitch: number,

	-- Weapon
	ammo: number, -- rounds in the magazine
	reserve: number, -- rounds left outside the magazine
	fireCooldown: number, -- ticks until the next shot is allowed
	reloadTicks: number, -- ticks left in the current reload; 0 when not reloading
	drawTicks: number, -- ticks until the gun is drawn after spawning
	raiseTicks: number, -- ticks until the gun is raised after sprinting
	triggerHeld: boolean, -- the trigger was held last tick (semi-automatic needs a fresh press)
	canShoot: boolean, -- false while the game has stopped this player shooting (see API.setCanShoot)
	recoilPitch: number, -- radians added to the aim by recoil
	recoilYaw: number,
	bloom: number, -- degrees of extra spread from recent shots
}

local Types = {}

Types.Buttons = table.freeze({
	Jump = 1,
	Sprint = 2,
	SlowWalk = 4,
	LeanLeft = 8,
	LeanRight = 16,
	Fire = 32,
	Aim = 64,
	Reload = 128,
})

Types.ALL_BUTTONS = 255

Types.Stance = table.freeze({
	Stand = 0,
	Crouch = 1,
	Prone = 2,
})

return table.freeze(Types)

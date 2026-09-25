--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Data shapes shared by the server and the client.

-- One tick of player input. The client sends these; the server never trusts
-- anything else from it about movement.
export type Input = {
	seq: number, -- increases by one every tick
	moveX: number, -- -1 (left) to 1 (right)
	moveZ: number, -- -1 (back) to 1 (forward)
	yaw: number, -- radians, -pi to pi
	pitch: number, -- radians, positive looks up
	buttons: number, -- bit flags, see Types.Buttons
	stance: number, -- the stance the player wants, see Types.Stance
}

-- Everything the movement simulation needs to continue from one tick to the next.
export type State = {
	position: Vector3, -- feet, center of the body
	velocity: Vector3,
	grounded: boolean,
	stance: number,
	leanTicks: number, -- negative leans left, positive leans right
	jumpCooldown: number, -- ticks until the next jump is allowed
	yaw: number,
	pitch: number,
}

local Types = {}

Types.Buttons = table.freeze({
	Jump = 1,
	Sprint = 2,
	SlowWalk = 4,
	LeanLeft = 8,
	LeanRight = 16,
})

Types.ALL_BUTTONS = 31

Types.Stance = table.freeze({
	Stand = 0,
	Crouch = 1,
	Prone = 2,
})

return table.freeze(Types)

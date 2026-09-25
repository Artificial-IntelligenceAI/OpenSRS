--!strict
-- SPDX-License-Identifier: Apache-2.0

-- One tick of a player: movement, then the weapon. Server and client both run
-- exactly this.

local Firearm = require(script.Parent.Firearm)
local Movement = require(script.Parent.Movement)
local Types = require(script.Parent.Types)
local Weapons = require(script.Parent.Weapons)

type Input = Types.Input
type State = Types.State
type Weapon = Weapons.Weapon
type World = Movement.World

-- A shot fired this tick. The aim includes recoil from earlier shots, not this one.
export type Shot = {
	state: State, -- the shooter, after this tick's movement
	yaw: number,
	pitch: number,
	spread: number, -- degrees
}

local Simulation = {}

function Simulation.newState(position: Vector3, yaw: number, weapon: Weapon): State
	return {
		position = position,
		velocity = Vector3.zero,
		grounded = false,
		stance = Types.Stance.Stand,
		sprinting = false,
		aiming = false,
		leanTicks = 0,
		jumpCooldown = 0,
		yaw = yaw,
		pitch = 0,

		ammo = weapon.magazine,
		reserve = weapon.reserve,
		fireCooldown = 0,
		reloadTicks = 0,
		drawTicks = weapon.drawTicks, -- a fresh spawn starts by drawing the gun
		raiseTicks = 0,
		triggerHeld = false,
		recoilPitch = 0,
		recoilYaw = 0,
		bloom = 0,
	}
end

function Simulation.step(state: State, input: Input, world: World, weapon: Weapon): (State, Shot?)
	local nextState = Movement.step(state, input, world)
	local yaw = input.yaw + nextState.recoilYaw
	local pitch = input.pitch + nextState.recoilPitch
	local spread = Firearm.spread(nextState, weapon)
	if Firearm.step(nextState, input, weapon) then
		-- Firing doesn't change where the shooter stands, so the moved state is the origin.
		return nextState, { state = nextState, yaw = yaw, pitch = pitch, spread = spread }
	end
	return nextState, nil
end

return table.freeze(Simulation)

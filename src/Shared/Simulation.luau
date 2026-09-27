--!strict
-- SPDX-License-Identifier: Apache-2.0

-- One tick of a player: movement, then switching weapons, then the weapon.
-- Server and client both run exactly this.

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
	weapon: Weapon, -- what fired it
	state: State, -- the shooter, after this tick's movement
	yaw: number,
	pitch: number,
	spread: number, -- degrees
}

local Simulation = {}

-- The weapon in `state`'s hands.
function Simulation.weapon(state: State): Weapon
	return Weapons.at(state.weapon) or Weapons.loadout[1]
end

-- A fresh spawn, holding the first weapon in the loadout, every magazine full.
function Simulation.newState(position: Vector3, yaw: number): State
	local stowed = {}
	for _, carried in Weapons.loadout do
		table.insert(stowed, carried.magazine)
		table.insert(stowed, carried.reserve)
	end
	local weapon = Weapons.loadout[1]
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

		weapon = 1,
		ammo = weapon.magazine,
		reserve = weapon.reserve,
		stowed = table.freeze(stowed),
		fireCooldown = 0,
		reloadTicks = 0,
		drawTicks = weapon.drawTicks, -- a fresh spawn starts by drawing the gun
		raiseTicks = 0,
		triggerHeld = false,
		canShoot = true,
		recoilPitch = 0,
		recoilYaw = 0,
		bloom = 0,
	}
end

-- Puts the weapon in hand away (keeping its ammo) and takes out the one at
-- `index`, which then has to be drawn. A reload in progress is lost. The time
-- until the next shot and the bloom carry on as they were, so switching back
-- and forth can't be used to fire faster or more accurately.
local function switch(state: State, index: number)
	local stowed = table.clone(state.stowed)
	stowed[state.weapon * 2 - 1] = state.ammo
	stowed[state.weapon * 2] = state.reserve
	local weapon = Weapons.loadout[index]
	state.weapon = index
	state.ammo = stowed[index * 2 - 1]
	state.reserve = stowed[index * 2]
	state.stowed = table.freeze(stowed)
	state.drawTicks = weapon.drawTicks
	state.reloadTicks = 0
	state.triggerHeld = true -- a held trigger doesn't carry over into the new gun
end

function Simulation.step(state: State, input: Input, world: World): (State, Shot?)
	local nextState = Movement.step(state, input, world)
	if input.weapon ~= nextState.weapon and Weapons.at(input.weapon) then
		switch(nextState, input.weapon)
	end
	local weapon = Simulation.weapon(nextState)
	local yaw = input.yaw + nextState.recoilYaw
	local pitch = input.pitch + nextState.recoilPitch
	local spread = Firearm.spread(nextState, weapon)
	if Firearm.step(nextState, input, weapon) then
		-- Firing doesn't change where the shooter stands, so the moved state is the origin.
		return nextState, { weapon = weapon, state = nextState, yaw = yaw, pitch = pitch, spread = spread }
	end
	return nextState, nil
end

return table.freeze(Simulation)

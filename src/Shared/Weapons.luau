--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Weapon stats. Distances are in studs, angles in degrees, times in ticks
-- (60 a second) unless a name says otherwise.

local Config = require(script.Parent.Config)

export type Spread = {
	stand: number, -- standing still, from the hip
	crouch: number,
	prone: number,
	moving: number, -- added at full walking speed, less when slower
	airborne: number, -- added while in the air
	aimMultiplier: number, -- everything above is multiplied by this while aiming
}

export type Weapon = {
	name: string,
	automatic: boolean,
	fireInterval: number, -- ticks between shots
	magazine: number,
	reserve: number,
	reloadTicks: number,
	reloadEmptyTicks: number, -- reloading from empty also has to rack the slide
	raiseTicks: number, -- after sprinting, before the gun can fire

	damage: number,
	headMultiplier: number,
	limbMultiplier: number,
	fullDamageRange: number,
	minDamageRange: number,
	minDamageMultiplier: number, -- damage at and beyond minDamageRange
	bulletSpeed: number, -- studs a second; damage lands after the bullet's travel time
	instantDamage: boolean, -- true skips the travel time
	range: number,

	spread: Spread,
	bloomPerShot: number,
	bloomMax: number,
	bloomRecovery: number, -- degrees a tick

	recoilPitch: number, -- degrees kicked up per shot
	recoilYaw: number, -- degrees kicked sideways per shot, alternating
	recoilRecovery: number, -- fraction of the kick that settles back each tick
}

local TICKS = Config.tickRate

local X16: Weapon = table.freeze({
	name = "X16",
	automatic = false,
	fireInterval = math.round(TICKS * 60 / 400), -- 400 rounds a minute
	magazine = 17,
	reserve = 51,
	reloadTicks = math.round(TICKS * 1.6),
	reloadEmptyTicks = math.round(TICKS * 2.1),
	raiseTicks = math.round(TICKS * 0.25),

	damage = 25,
	headMultiplier = 2,
	limbMultiplier = 0.8,
	fullDamageRange = 30,
	minDamageRange = 100,
	minDamageMultiplier = 0.6,
	bulletSpeed = 1340, -- about 375 m/s
	instantDamage = false,
	range = 1000,

	spread = table.freeze({
		stand = 1,
		crouch = 0.8,
		prone = 0.6,
		moving = 1.2,
		airborne = 4,
		aimMultiplier = 0.3,
	}),
	bloomPerShot = 0.6,
	bloomMax = 3,
	bloomRecovery = 0.05,

	recoilPitch = 1.6,
	recoilYaw = 0.4,
	recoilRecovery = 0.1,
})

local Weapons = {}

Weapons.X16 = X16

-- The weapon every player carries for now.
Weapons.default = X16

return table.freeze(Weapons)

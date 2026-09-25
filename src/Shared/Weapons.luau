--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Weapon stats as the simulation uses them. Distances are in studs, angles in
-- degrees, and times in ticks unless a name says otherwise. They're built from
-- Settings (in friendlier units, like rounds a minute and seconds) at startup.

local Config = require(script.Parent.Config)
local SettingsSchema = require(script.Parent.SettingsSchema)

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
	drawTicks: number, -- after spawning, before the gun can fire or reload
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

-- Settings values for one weapon, keyed by field name (see SettingsSchema).
export type Values = { [string]: number | boolean }

local Weapons = {}

local byName: { [string]: Weapon } = {}

local function ticks(seconds: number): number
	return math.max(math.round(seconds * Config.tickRate), 1)
end

-- Fills in (or creates) a weapon's stats from its settings.
function Weapons.configure(name: string, values: Values): Weapon
	local function number(field: string): number
		return values[field] :: number
	end
	local weapon = byName[name] or ({ name = name } :: any)
	weapon.automatic = values.Automatic == true
	weapon.fireInterval = ticks(60 / number("FireRate"))
	weapon.magazine = math.round(number("MagazineSize"))
	weapon.reserve = math.round(number("ReserveAmmo"))
	weapon.reloadTicks = ticks(number("ReloadTime"))
	weapon.drawTicks = math.round(number("DrawTime") * Config.tickRate)
	weapon.raiseTicks = math.round(number("RaiseTime") * Config.tickRate)
	weapon.damage = number("Damage")
	weapon.headMultiplier = number("HeadshotMultiplier")
	weapon.limbMultiplier = number("LimbMultiplier")
	weapon.fullDamageRange = number("FullDamageRange")
	weapon.minDamageRange = math.max(number("MinDamageRange"), number("FullDamageRange") + 0.01)
	weapon.minDamageMultiplier = number("MinDamageMultiplier")
	weapon.bulletSpeed = number("BulletSpeed")
	weapon.instantDamage = values.InstantDamage == true
	weapon.range = number("Range")
	weapon.spread = {
		stand = number("SpreadStanding"),
		crouch = number("SpreadCrouching"),
		prone = number("SpreadProne"),
		moving = number("SpreadMoving"),
		airborne = number("SpreadAirborne"),
		aimMultiplier = number("AimSpreadMultiplier"),
	}
	weapon.bloomPerShot = number("BloomPerShot")
	weapon.bloomMax = number("BloomMax")
	weapon.bloomRecovery = number("BloomRecovery") / Config.tickRate
	weapon.recoilPitch = number("RecoilUp")
	weapon.recoilYaw = number("RecoilSide")
	weapon.recoilRecovery = 1 - math.exp(-number("RecoilRecovery") / Config.tickRate)
	byName[name] = weapon
	return weapon
end

function Weapons.get(name: string): Weapon?
	return byName[name]
end

-- Start from the defaults, so weapons exist even before Settings are applied.
for _, entry in SettingsSchema.weapons do
	local values: Values = {}
	for _, field in SettingsSchema.weaponFields do
		local default = entry.defaults[field.name]
		values[field.name] = if default ~= nil then default else field.default
	end
	Weapons.configure(entry.name, values)
end

-- The weapon every player carries for now.
Weapons.default = byName.X16

return Weapons

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Every setting a game can change, with its default, allowed range and a short
-- description. The Settings folder shipped with OpenSRS, and docs/SETTINGS.md,
-- are generated from this file (scripts/generate-settings.luau), so it is the
-- one place defaults live.
--
-- This module is plain data so tools outside Roblox can read it too.

export type Field = {
	name: string, -- attribute name
	default: number | boolean,
	min: number?,
	max: number?,
	description: string,
}

export type Section = {
	name: string, -- Configuration name; weapons live under Weapons/<name>
	fields: { Field },
}

local game: Section = {
	name = "Game",
	fields = {
		{
			name = "TickRate",
			default = 60,
			min = 20,
			max = 120,
			description = "Simulation updates a second. Higher is more precise and costs more server time.",
		},
		{
			name = "SnapshotRate",
			default = 20,
			min = 5,
			max = 60,
			description = "How many times a second each player is told about the others.",
		},
		{
			name = "RespawnTime",
			default = 3,
			min = 0,
			max = 60,
			description = "Seconds between dying and respawning.",
		},
		{ name = "MaxHealth", default = 100, min = 1, max = 10000, description = "Health each player spawns with." },
		{
			name = "BulletHoleTime",
			default = 30,
			min = 0,
			max = 600,
			description = "Seconds bullet holes stay on walls and players. 0 turns them off.",
		},
		{
			name = "MaxBulletHoles",
			default = 60,
			min = 0,
			max = 1000,
			description = "Most bullet holes shown at once; the oldest disappear first.",
		},
	},
}

local movement: Section = {
	name = "Movement",
	fields = {
		{ name = "WalkSpeed", default = 12, min = 0, max = 100, description = "Studs a second when walking." },
		{ name = "SlowWalkSpeed", default = 6, min = 0, max = 100, description = "Studs a second when slow-walking." },
		{ name = "SprintSpeed", default = 19, min = 0, max = 100, description = "Studs a second when sprinting." },
		{ name = "CrouchSpeed", default = 6, min = 0, max = 100, description = "Studs a second when crouched." },
		{ name = "ProneSpeed", default = 2.5, min = 0, max = 100, description = "Studs a second when prone." },
		{
			name = "AimSpeedMultiplier",
			default = 0.6,
			min = 0,
			max = 1,
			description = "Movement speed while aiming down sights, as a fraction.",
		},
		{
			name = "BackwardSpeedMultiplier",
			default = 0.8,
			min = 0,
			max = 1,
			description = "Movement speed when walking backwards, as a fraction.",
		},
		{
			name = "Acceleration",
			default = 60,
			min = 1,
			max = 1000,
			description = "How quickly players speed up on the ground (studs a second, per second).",
		},
		{
			name = "Deceleration",
			default = 80,
			min = 1,
			max = 1000,
			description = "How quickly players stop on the ground (studs a second, per second).",
		},
		{
			name = "AirAcceleration",
			default = 6,
			min = 0,
			max = 1000,
			description = "How much players can steer in the air. Low stops bunny-hopping and air strafing.",
		},
		{ name = "JumpHeight", default = 3.7, min = 0, max = 50, description = "Studs a jump reaches." },
		{
			name = "JumpCooldown",
			default = 0.4,
			min = 0,
			max = 2,
			description = "Seconds before a player can jump again.",
		},
		{
			name = "Gravity",
			default = 196.2,
			min = 1,
			max = 1000,
			description = "Downward pull, in studs a second squared.",
		},
		{
			name = "LeanDistance",
			default = 1,
			min = 0,
			max = 2,
			description = "Studs the eye moves sideways when leaning.",
		},
		{
			name = "LeanTime",
			default = 0.17,
			min = 0.02,
			max = 1,
			description = "Seconds to go from upright to a full lean.",
		},
	},
}

-- Each weapon in Weapons.luau gets a section with these fields.
local weaponFields: { Field } = {
	{ name = "Damage", default = 25, min = 0, max = 10000, description = "Damage of a body shot at close range." },
	{ name = "HeadshotMultiplier", default = 2, min = 0, max = 100, description = "Damage multiplier for headshots." },
	{
		name = "LimbMultiplier",
		default = 0.8,
		min = 0,
		max = 100,
		description = "Damage multiplier for arms and legs.",
	},
	{ name = "FireRate", default = 400, min = 30, max = 3600, description = "Rounds a minute." },
	{ name = "Automatic", default = false, description = "Keeps firing while the trigger is held." },
	{ name = "MagazineSize", default = 17, min = 1, max = 255, description = "Rounds in a full magazine." },
	{ name = "ReserveAmmo", default = 51, min = 0, max = 65535, description = "Spare rounds a player spawns with." },
	{
		name = "ReloadTime",
		default = 1.3,
		min = 0.02,
		max = 4,
		description = "Seconds to reload. The reload animation stretches to fit.",
	},
	{
		name = "DrawTime",
		default = 0.5,
		min = 0,
		max = 2,
		description = "Seconds after spawning before the gun can fire or reload. The draw animation stretches to fit.",
	},
	{
		name = "RaiseTime",
		default = 0.25,
		min = 0,
		max = 2,
		description = "Seconds after sprinting before the gun can fire.",
	},
	{ name = "BulletSpeed", default = 1340, min = 1, max = 100000, description = "Studs a second a bullet travels." },
	{
		name = "InstantDamage",
		default = false,
		description = "Damage lands the moment the gun fires instead of when the bullet would arrive.",
	},
	{ name = "Range", default = 1000, min = 1, max = 10000, description = "Studs a bullet can reach." },
	{
		name = "FullDamageRange",
		default = 30,
		min = 0,
		max = 10000,
		description = "Studs before damage starts to drop off.",
	},
	{
		name = "MinDamageRange",
		default = 100,
		min = 0,
		max = 10000,
		description = "Studs where damage stops dropping.",
	},
	{
		name = "MinDamageMultiplier",
		default = 0.6,
		min = 0,
		max = 1,
		description = "Fraction of damage left at and beyond MinDamageRange.",
	},
	{
		name = "SpreadStanding",
		default = 1,
		min = 0,
		max = 45,
		description = "Degrees of spread standing still, from the hip.",
	},
	{ name = "SpreadCrouching", default = 0.8, min = 0, max = 45, description = "Degrees of spread crouched." },
	{ name = "SpreadProne", default = 0.6, min = 0, max = 45, description = "Degrees of spread prone." },
	{ name = "SpreadMoving", default = 1.2, min = 0, max = 45, description = "Degrees added at full walking speed." },
	{ name = "SpreadAirborne", default = 4, min = 0, max = 45, description = "Degrees added while in the air." },
	{
		name = "AimSpreadMultiplier",
		default = 0.3,
		min = 0,
		max = 1,
		description = "All spread is multiplied by this while aiming down sights.",
	},
	{ name = "BloomPerShot", default = 0.6, min = 0, max = 45, description = "Degrees of spread each shot adds." },
	{ name = "BloomMax", default = 3, min = 0, max = 45, description = "Most spread shots can add." },
	{
		name = "BloomRecovery",
		default = 3,
		min = 0,
		max = 1000,
		description = "Degrees of added spread that fade a second.",
	},
	{ name = "RecoilUp", default = 1.6, min = 0, max = 45, description = "Degrees each shot kicks the aim up." },
	{
		name = "RecoilSide",
		default = 0.4,
		min = 0,
		max = 45,
		description = "Degrees each shot kicks the aim sideways.",
	},
	{
		name = "RecoilRecovery",
		default = 6.3,
		min = 0,
		max = 100,
		description = "How fast the aim settles back after a kick. Higher settles faster.",
	},
}

-- Weapons shipped with OpenSRS, in order. Each gets a Weapons/<name> section
-- with the fields above; `defaults` replaces field defaults for that weapon.
export type WeaponEntry = {
	name: string,
	defaults: { [string]: number | boolean },
}

local weapons: { WeaponEntry } = {
	{ name = "X16", defaults = {} }, -- the field defaults above are the X16's
}

local SettingsSchema = {}

SettingsSchema.sections = { game, movement }
SettingsSchema.weaponFields = weaponFields
SettingsSchema.weapons = weapons

return SettingsSchema

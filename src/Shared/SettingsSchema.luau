--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Every setting a game can change, with its default, allowed range and a short
-- description. The Settings folder shipped with SecureRGS, and docs/SETTINGS.md,
-- are generated from this file (scripts/generate-settings.luau), so it is the
-- one place defaults live.
--
-- This module is plain data so tools outside Roblox can read it too.

-- A color, as red, green and blue from 0 to 255. In Studio it's a Color3
-- attribute; in Overrides, a Color3.
export type Color = { r: number, g: number, b: number }

export type Field = {
	name: string, -- attribute name
	default: number | boolean | Color,
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
			name = "CatchUpTime",
			default = 0.07,
			min = 0.02,
			max = 0.25,
			description = "Seconds of movement a player whose connection stalled may catch up on at once. "
				.. "Longer is kinder to unstable connections; shorter limits lag-switch peeking, where a "
				.. "player stalls their connection to move and shoot before others see them.",
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
		{
			name = "AimFlagSensitivity",
			default = 1,
			min = 0,
			max = 3,
			description = "How readily aim that looks like an aimbot is flagged (see Flags). "
				.. "0 turns it off; above 1 flags on less evidence, and risks flagging very good players.",
		},
		{
			name = "UnseenShotPrecision",
			default = 5,
			min = 0,
			max = 50,
			description = "How exactly players hear shots from someone they can't see, in studs. The sound comes from "
				.. "the middle of the grid square of this size the shooter is in, and they aren't told who fired or "
				.. "where an unseen victim was hit. Smaller is easier to locate by ear, and by wallhacks; 0 is exact.",
		},
		{
			name = "FriendlyFire",
			default = false,
			description = "Whether players' bullets hurt their own teammates. Teams come from Roblox's Teams service.",
		},
		{
			name = "AllowReset",
			default = true,
			description = "Whether Roblox's menu Reset button works. Off, the button is greyed out.",
		},
		{
			name = "KillCreditTime",
			default = 0,
			min = 0,
			max = 600,
			description = "When a player resets or falls out of the map, whoever last hurt them in that life gets "
				.. "the kill, if it was within this many seconds. 0 means no time limit.",
		},
		{
			name = "TeammateHighlights",
			default = false,
			description = "Outlines teammates, even through walls. Teams come from Roblox's Teams service. "
				.. "While on, players are also sent where their teammates are behind walls (never their enemies), "
				.. "so a cheat could show teammates too.",
		},
	},
}

local controls: Section = {
	name = "Controls",
	fields = {
		{
			name = "AimToggle",
			default = false,
			description = "Right click toggles aiming down sights instead of aiming only while held. "
				.. "Starting a sprint stops aiming.",
		},
		{
			name = "LeanToggle",
			default = true,
			description = "Q and E toggle leaning left and right instead of leaning only while held.",
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
			name = "BackwardSpeedMultiplier",
			default = 0.8,
			min = 0,
			max = 1,
			description = "Movement speed when walking backwards, as a fraction.",
		},
		{
			name = "Acceleration",
			default = 1000,
			min = 1,
			max = 1000,
			description = "How quickly players speed up on the ground (studs a second, per second). "
				.. "The default is near-instant, like a standard Roblox character; lower it for a sense of weight.",
		},
		{
			name = "Deceleration",
			default = 1000,
			min = 1,
			max = 1000,
			description = "How quickly players stop on the ground (studs a second, per second). "
				.. "The default is near-instant; lower it and players slide a little before stopping.",
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
	{
		name = "SpeedMultiplier",
		default = 1,
		min = 0.1,
		max = 3,
		description = "Movement speed while holding this weapon, as a multiple of the Movement settings' speeds.",
	},
	{
		name = "AimSpeedMultiplier",
		default = 0.6,
		min = 0,
		max = 1,
		description = "Movement speed while aiming down this weapon's sights, as a fraction.",
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
	{
		name = "RecoilUp",
		default = 1.6,
		min = -45,
		max = 45,
		description = "Degrees each shot kicks the aim up. Negative kicks it down.",
	},
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

-- Weapons shipped with SecureRGS, in order: every player carries all of them,
-- in this order (the first is what they spawn holding, on key 1). Each gets a
-- Weapons/<name> section with the fields above; `defaults` replaces field
-- defaults for that weapon.
export type WeaponEntry = {
	name: string,
	defaults: { [string]: number | boolean },
}

local weapons: { WeaponEntry } = {
	{
		-- A submachine gun for moving, spraying and praying: easy to do well
		-- with, but it eats through ammo. Light and quick to handle, low damage
		-- that falls off fast, a very high fire rate, recoil that pushes down,
		-- and little penalty for shooting on the move.
		name = "XS-120",
		defaults = {
			Automatic = true,
			FireRate = 1200,
			MagazineSize = 40,
			ReserveAmmo = 180,
			ReloadTime = 2,
			DrawTime = 0.4,
			RaiseTime = 0.15,
			SpeedMultiplier = 1.1,
			AimSpeedMultiplier = 0.8,
			Damage = 16,
			FullDamageRange = 15,
			MinDamageRange = 40,
			MinDamageMultiplier = 0.25,
			SpreadMoving = 0.3,
			SpreadAirborne = 2,
			RecoilUp = -0.2,
			RecoilSide = 0.15,
			BloomPerShot = 0.2,
		},
	},
	{ name = "X16", defaults = {} }, -- the field defaults above are the X16's
}

local SettingsSchema = {}

local damageNumbers: Section = {
	name = "DamageNumbers",
	fields = {
		{
			name = "Enabled",
			default = true,
			description = "Shows each hit's damage popping up beside the spot hit, to the player who fired it.",
		},
		{
			name = "Offset",
			default = 35,
			min = -400,
			max = 400,
			description = "Pixels to the right of the hit where a number appears (negative is to the left).",
		},
		{ name = "Size", default = 26, min = 8, max = 100, description = "Text size, in pixels." },
		{
			name = "Lifetime",
			default = 0.8,
			min = 0.1,
			max = 5,
			description = "Seconds a number stays up; it fades over the second half.",
		},
		{ name = "Rise", default = 2.2, min = 0, max = 20, description = "Studs a number drifts up." },
		{
			name = "Drift",
			default = 0.9,
			min = 0,
			max = 20,
			description = "Studs a number may drift further sideways, away from the hit (each a random amount).",
		},
		{ name = "BodyColor", default = { r = 255, g = 255, b = 255 }, description = "Color for body hits." },
		{ name = "HeadshotColor", default = { r = 255, g = 214, b = 64 }, description = "Color for headshots." },
		{ name = "KillColor", default = { r = 255, g = 70, b = 70 }, description = "Color for the hit that kills." },
	},
}

SettingsSchema.sections = { game, controls, movement, damageNumbers }
SettingsSchema.weaponFields = weaponFields
SettingsSchema.weapons = weapons

return SettingsSchema

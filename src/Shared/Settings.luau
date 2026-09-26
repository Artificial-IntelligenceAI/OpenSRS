--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Reads a game's settings and applies them before anything else runs.
--
-- On the server, settings come from the Settings folder inside OpenSRS
-- (attributes, editable in Studio's Properties panel), then from an optional
-- ModuleScript named Overrides in that folder. Anything missing, of the wrong
-- type or out of range falls back to the default or is clamped, with a warning.
--
-- The server then publishes the final values to clients, which apply exactly
-- the same numbers so their predictions match. The server only ever uses its
-- own copy.

local Config = require(script.Parent.Config)
local SettingsSchema = require(script.Parent.SettingsSchema)
local Weapons = require(script.Parent.Weapons)

type Field = SettingsSchema.Field
export type Values = { [string]: number | boolean }
export type Resolved = {
	sections: { [string]: Values },
	weapons: { [string]: Values },
}

local Settings = {}

local function read(
	field: Field,
	default: number | boolean,
	source: Instance?,
	override: unknown,
	path: string
): number | boolean
	local value: unknown = default
	if source then
		local attribute = source:GetAttribute(field.name)
		if attribute ~= nil then
			value = attribute
		end
	end
	if override ~= nil then
		value = override
	end

	if typeof(value) ~= typeof(default) then
		warn(`OpenSRS: setting {path}.{field.name} should be a {typeof(default)}; using the default, {default}.`)
		return default
	end
	if type(value) == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			warn(`OpenSRS: setting {path}.{field.name} isn't a real number; using the default, {default}.`)
			return default
		end
		local clamped = math.clamp(value, field.min or -math.huge, field.max or math.huge)
		if clamped ~= value then
			warn(
				`OpenSRS: setting {path}.{field.name} is {value}, outside {field.min} to {field.max}; using {clamped}.`
			)
		end
		return clamped
	end
	return value :: boolean
end

local function section(value: unknown): { [string]: unknown }
	return if type(value) == "table" then value :: { [string]: unknown } else {}
end

-- `folder` holds the settings (it may be missing); `overrides` is the table an
-- Overrides module returned, shaped like { Movement = { WalkSpeed = 14 }, Weapons = { X16 = { Damage = 30 } } }.
function Settings.resolve(folder: Instance?, overrides: unknown): Resolved
	local extra = section(overrides)
	local resolved: Resolved = { sections = {}, weapons = {} }

	for _, schema in SettingsSchema.sections do
		local source = folder and folder:FindFirstChild(schema.name)
		local changes = section(extra[schema.name])
		local values: Values = {}
		for _, field in schema.fields do
			values[field.name] = read(field, field.default, source, changes[field.name], schema.name)
		end
		resolved.sections[schema.name] = values
	end

	local weaponFolder = folder and folder:FindFirstChild("Weapons")
	local weaponChanges = section(extra.Weapons)
	for _, entry in SettingsSchema.weapons do
		local source = weaponFolder and weaponFolder:FindFirstChild(entry.name)
		local changes = section(weaponChanges[entry.name])
		local values: Values = {}
		for _, field in SettingsSchema.weaponFields do
			local default = entry.defaults[field.name]
			local path = `Weapons.{entry.name}`
			values[field.name] =
				read(field, if default ~= nil then default else field.default, source, changes[field.name], path)
		end
		resolved.weapons[entry.name] = values
	end
	return resolved
end

-- Writes resolved settings as attributes, in the same layout they're read
-- from, so clients can resolve the identical values.
function Settings.write(resolved: Resolved, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Settings"

	local function configuration(name: string, values: Values, into: Instance)
		local config = Instance.new("Configuration")
		config.Name = name
		for key, value in values do
			config:SetAttribute(key, value)
		end
		config.Parent = into
	end

	for name, values in resolved.sections do
		configuration(name, values, folder)
	end
	local weapons = Instance.new("Folder")
	weapons.Name = "Weapons"
	weapons.Parent = folder
	for name, values in resolved.weapons do
		configuration(name, values, weapons)
	end
	folder.Parent = parent
	return folder
end

-- Puts resolved settings into Config and Weapons. Call once, before requiring
-- anything that reads them.
function Settings.apply(resolved: Resolved)
	local gameValues = resolved.sections.Game
	local movement = resolved.sections.Movement
	local function number(values: Values, field: string): number
		return values[field] :: number
	end

	local tickRate = math.round(number(gameValues, "TickRate"))
	Config.tickRate = tickRate
	Config.snapshotInterval = math.max(math.round(tickRate / number(gameValues, "SnapshotRate")), 1)
	Config.respawnTime = number(gameValues, "RespawnTime")
	Config.maxHealth = number(gameValues, "MaxHealth")
	Config.bulletHoleTime = number(gameValues, "BulletHoleTime")
	Config.maxBulletHoles = math.round(number(gameValues, "MaxBulletHoles"))
	Config.teammateHighlights = gameValues.TeammateHighlights == true
	local controls = resolved.sections.Controls
	Config.aimToggle = controls.AimToggle == true
	Config.leanToggle = controls.LeanToggle == true

	local M = Config.movement
	M.slowWalkSpeed = number(movement, "SlowWalkSpeed")
	M.sprintSpeed = number(movement, "SprintSpeed")
	M.aimSpeedMultiplier = number(movement, "AimSpeedMultiplier")
	M.backwardMultiplier = number(movement, "BackwardSpeedMultiplier")
	M.groundAcceleration = number(movement, "Acceleration")
	M.groundDeceleration = number(movement, "Deceleration")
	M.airAcceleration = number(movement, "AirAcceleration")
	M.gravity = number(movement, "Gravity")
	M.jumpVelocity = math.sqrt(2 * M.gravity * number(movement, "JumpHeight"))
	M.jumpCooldownTicks = math.round(number(movement, "JumpCooldown") * tickRate)
	M.leanDistance = number(movement, "LeanDistance")
	M.leanTicks = math.max(math.round(number(movement, "LeanTime") * tickRate), 1)
	Config.stance(0).speed = number(movement, "WalkSpeed")
	Config.stance(1).speed = number(movement, "CrouchSpeed")
	Config.stance(2).speed = number(movement, "ProneSpeed")

	for name, values in resolved.weapons do
		Weapons.configure(name, values)
	end
end

return table.freeze(Settings)

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Generates the Settings folder shipped with OpenSRS (src/Settings) and
-- docs/SETTINGS.md from src/Shared/SettingsSchema.luau.
--
--     lune run scripts/generate-settings          write the files
--     lune run scripts/generate-settings --check  fail if they're out of date

local fs = require("@lune/fs")
local process = require("@lune/process")

local Schema = require("../src/Shared/SettingsSchema")

type Field = Schema.Field

local check = table.find(process.args, "--check") ~= nil
local outOfDate: { string } = {}

local function emit(path: string, contents: string)
	local current = if fs.isFile(path) then fs.readFile(path) else nil
	if current == contents then
		return
	end
	if check then
		table.insert(outOfDate, path)
	else
		fs.writeFile(path, contents)
		print(`wrote {path}`)
	end
end

local function value(v: number | boolean): string
	return tostring(v)
end

-- Rojo model file for a Configuration holding one attribute per field.
local function model(fields: { Field }, defaults: { [string]: number | boolean }?): string
	local lines = { "{", '\t"className": "Configuration",', '\t"attributes": {' }
	for index, field in fields do
		local default = if defaults and defaults[field.name] ~= nil then defaults[field.name] else field.default
		local comma = if index < #fields then "," else ""
		table.insert(lines, `\t\t"{field.name}": {value(default)}{comma}`)
	end
	table.insert(lines, "\t}")
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n"
end

local function range(field: Field): string
	if field.min == nil and field.max == nil then
		return "true or false"
	end
	return `{field.min} to {field.max}`
end

local function table_(fields: { Field }, defaults: { [string]: number | boolean }?): string
	local lines = { "| Setting | Default | Allowed | What it does |", "| --- | --- | --- | --- |" }
	for _, field in fields do
		local default = if defaults and defaults[field.name] ~= nil then defaults[field.name] else field.default
		table.insert(lines, `| \`{field.name}\` | {value(default)} | {range(field)} | {field.description} |`)
	end
	return table.concat(lines, "\n")
end

-- Settings folder
if not check then
	fs.writeDir("src/Settings/Weapons")
end
for _, section in Schema.sections do
	emit(`src/Settings/{section.name}.model.json`, model(section.fields))
end
for _, weapon in Schema.weapons do
	emit(`src/Settings/Weapons/{weapon.name}.model.json`, model(Schema.weaponFields, weapon.defaults))
end

-- Docs
local doc = {
	"# OpenSRS Settings",
	"",
	"<!-- Generated from src/Shared/SettingsSchema.luau by scripts/generate-settings.luau. Don't edit by hand. -->",
	"",
	"Every value here can be changed in Roblox Studio without code: select a Configuration inside `ServerScriptService > OpenSRS > Settings` and edit its attributes in the Properties panel.",
	"",
	"Values of the wrong type fall back to the default, and values outside the allowed range are clamped. Both print a warning in the Output window.",
	"",
	"## Changing settings in code",
	"",
	"For anything more advanced, add a ModuleScript named `Overrides` to the Settings folder. It returns a table shaped like the folder, and its values win over the attributes:",
	"",
	"```lua",
	"return {",
	"\tMovement = { WalkSpeed = 14 },",
	"\tWeapons = { X16 = { Damage = 30, Automatic = true } },",
	"}",
	"```",
	"",
	"The server only uses its own copy of the settings. It sends the final values to players so their games predict with exactly the same numbers, but changing them on a player's computer does nothing.",
	"",
}
for _, section in Schema.sections do
	table.insert(doc, `## {section.name}`)
	table.insert(doc, "")
	table.insert(doc, table_(section.fields))
	table.insert(doc, "")
end
for _, weapon in Schema.weapons do
	table.insert(doc, `## Weapons / {weapon.name}`)
	table.insert(doc, "")
	table.insert(doc, table_(Schema.weaponFields, weapon.defaults))
	table.insert(doc, "")
end
emit("docs/SETTINGS.md", table.concat(doc, "\n"))

if check and #outOfDate > 0 then
	print("These generated files are out of date; run `lune run scripts/generate-settings`:")
	for _, path in outOfDate do
		print(`  {path}`)
	end
	process.exit(1)
end

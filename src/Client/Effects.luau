--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Visual effects for shots: tracers and muzzle flashes (impacts are in
-- Impacts). Purely cosmetic and client-side.
--
-- A muzzle flash comes from a template like the impacts do: a Folder of
-- ParticleEmitters fired once from an attachment at the muzzle, which faces
-- the way the gun fires (so an emitter's Front direction is out of the
-- barrel), each with a Burst attribute for how many particles, and
-- optionally a PointLight named Light, lit for a moment. A game can supply
-- its own in Assets/Effects/Muzzle, named after the weapon, or Default for
-- every weapon.

local Debris = game:GetService("Debris")

local Assets = require(script.Parent.Assets)

type Tracer = {
	part: Part,
	from: Vector3,
	direction: Vector3,
	distance: number,
	speed: number,
	travelled: number,
}

local TRACER_LENGTH = 4
local TRACER_COLOR = Color3.fromRGB(255, 220, 150)
local FLASH_TIME = 0.05 -- seconds the muzzle light stays on

local Effects = {}

local folder = Instance.new("Folder")
folder.Name = "OpenSRSEffects"
folder.Parent = workspace
Effects.folder = folder

local tracers: { Tracer } = {}

local function effectPart(size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- A streak that flies from `from` to `to` at the bullet's speed.
function Effects.tracer(from: Vector3, to: Vector3, speed: number)
	local offset = to - from
	local distance = offset.Magnitude
	if distance < 1 then
		return
	end
	local part = effectPart(Vector3.new(0.06, 0.06, TRACER_LENGTH), TRACER_COLOR, Enum.Material.Neon)
	part.Parent = folder
	table.insert(tracers, {
		part = part,
		from = from,
		direction = offset / distance,
		distance = distance,
		speed = speed,
		travelled = 0,
	})
end

-- The built-in muzzle flash ------------------------------------------------

local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- A value changing evenly through each of `...` over a particle's life.
local function sequence(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local keys = {}
	for index, value in values do
		table.insert(keys, NumberSequenceKeypoint.new((index - 1) / (#values - 1), value))
	end
	return NumberSequence.new(keys)
end

local function emitter(
	parent: Instance,
	name: string,
	props: {
		texture: string,
		color: Color3,
		count: number,
		size: NumberSequence,
		transparency: NumberSequence,
		lifetime: NumberRange,
		speed: NumberRange,
		spread: number,
		drag: number,
		rise: number, -- studs a second squared upward (negative falls)
		glow: boolean, -- gives off light and ignores the scene's lighting
	}
): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Name = name
	particles.Enabled = false
	particles.EmissionDirection = Enum.NormalId.Front
	particles.Texture = props.texture
	particles.Color = ColorSequence.new(props.color)
	particles.Size = props.size
	particles.Transparency = props.transparency
	particles.Lifetime = props.lifetime
	particles.Speed = props.speed
	particles.SpreadAngle = Vector2.new(props.spread, props.spread)
	particles.Drag = props.drag
	particles.Acceleration = Vector3.new(0, props.rise, 0)
	particles.Rotation = NumberRange.new(0, 360)
	particles.LightEmission = if props.glow then 1 else 0
	particles.LightInfluence = if props.glow then 0 else 1
	particles.Brightness = if props.glow then 3 else 1
	particles:SetAttribute("Burst", props.count)
	particles.Parent = parent
	return particles
end

local BUILT_IN_MUZZLE = Instance.new("Folder")
BUILT_IN_MUZZLE.Name = "Default"
do
	-- The flash itself: a hot core, gone almost as soon as it appears.
	emitter(BUILT_IN_MUZZLE, "Flash", {
		texture = FIRE,
		color = Color3.fromRGB(255, 160, 60),
		count = 4,
		size = sequence(0.3, 0.5),
		transparency = sequence(0, 1),
		lifetime = NumberRange.new(0.03, 0.06),
		speed = NumberRange.new(1, 4),
		spread = 12,
		drag = 0,
		rise = 0,
		glow = true,
	})
	-- A star of light around it.
	emitter(BUILT_IN_MUZZLE, "Star", {
		texture = SPARKLE,
		color = Color3.fromRGB(255, 205, 130),
		count = 2,
		size = sequence(0.35, 0.1),
		transparency = sequence(0.1, 1),
		lifetime = NumberRange.new(0.03, 0.05),
		speed = NumberRange.new(0, 0.5),
		spread = 0,
		drag = 0,
		rise = 0,
		glow = true,
	})
	-- Burning powder thrown out ahead.
	emitter(BUILT_IN_MUZZLE, "Sparks", {
		texture = SPARKLE,
		color = Color3.fromRGB(255, 200, 110),
		count = 5,
		size = sequence(0.08, 0),
		transparency = sequence(0),
		lifetime = NumberRange.new(0.05, 0.12),
		speed = NumberRange.new(15, 30),
		spread = 10,
		drag = 3,
		rise = -10,
		glow = true,
	})
	-- A small puff of smoke that hangs and drifts up.
	emitter(BUILT_IN_MUZZLE, "Smoke", {
		texture = SMOKE,
		color = Color3.fromRGB(95, 95, 100),
		count = 3,
		size = sequence(0.1, 0.55), -- small: your own gun is only a couple of studs from your eye
		transparency = sequence(0.45, 0.75, 1),
		lifetime = NumberRange.new(0.4, 0.8),
		speed = NumberRange.new(1, 3),
		spread = 15,
		drag = 5,
		rise = 1.5,
		glow = false,
	})
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = TRACER_COLOR
	light.Range = 10
	light.Brightness = 3
	light.Parent = BUILT_IN_MUZZLE
end

-- A flash at `muzzle` (facing the way the gun fires) from `weapon`.
function Effects.muzzleFlash(weapon: string, muzzle: CFrame)
	local template = Assets.effect("Muzzle", weapon) or Assets.effect("Muzzle", "Default") or BUILT_IN_MUZZLE
	local attachment = Instance.new("Attachment")
	attachment.Name = "MuzzleFlash"
	attachment.WorldCFrame = muzzle -- attachments on Terrain are in world space
	attachment.Parent = workspace.Terrain
	local longest = FLASH_TIME
	for _, child in template:GetChildren() do
		if child:IsA("ParticleEmitter") then
			local particles = child:Clone()
			particles.Enabled = false
			particles.Parent = attachment
			particles:Emit(tonumber(particles:GetAttribute("Burst")) or 5)
			longest = math.max(longest, particles.Lifetime.Max)
		elseif child:IsA("PointLight") and child.Name == "Light" then
			local light = child:Clone()
			light.Parent = attachment
			Debris:AddItem(light, FLASH_TIME)
		end
	end
	Debris:AddItem(attachment, longest + 0.1)
end

-- Moves tracers; call once a frame.
function Effects.update(frameTime: number)
	for index = #tracers, 1, -1 do
		local tracer = tracers[index]
		tracer.travelled += tracer.speed * frameTime
		if tracer.travelled >= tracer.distance then
			tracer.part:Destroy()
			table.remove(tracers, index)
		else
			local head = tracer.from + tracer.direction * tracer.travelled
			local tail = tracer.from + tracer.direction * math.max(tracer.travelled - TRACER_LENGTH, 0)
			tracer.part.Size = Vector3.new(0.06, 0.06, math.max((head - tail).Magnitude, 0.1))
			tracer.part.CFrame = CFrame.lookAt((head + tail) / 2, head)
		end
	end
end

return table.freeze(Effects)

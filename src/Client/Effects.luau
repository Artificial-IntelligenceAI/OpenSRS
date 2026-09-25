--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Visual effects for shots: tracers and muzzle flashes (impacts are in
-- Impacts). Purely cosmetic and client-side.

local Debris = game:GetService("Debris")

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
local FLASH_TIME = 0.05

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

function Effects.muzzleFlash(position: Vector3)
	local flash = effectPart(Vector3.new(0.3, 0.3, 0.3), TRACER_COLOR, Enum.Material.Neon)
	flash.Shape = Enum.PartType.Ball
	flash.Position = position
	local light = Instance.new("PointLight")
	light.Color = TRACER_COLOR
	light.Range = 10
	light.Brightness = 3
	light.Parent = flash
	flash.Parent = folder
	Debris:AddItem(flash, FLASH_TIME)
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

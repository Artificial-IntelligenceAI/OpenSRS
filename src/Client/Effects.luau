--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Visual effects for shots: tracers and muzzle flashes (impacts are in
-- Impacts). Purely cosmetic and client-side.
--
-- A muzzle flash comes from a template like the impacts do: a Folder of
-- ParticleEmitters fired once from an attachment at the muzzle, which faces
-- the way the gun fires (so an emitter's Front direction is out of the
-- barrel), each with a Burst attribute for how many particles, and
-- optionally a PointLight named Light, lit for a moment (the built-in flash
-- has none, so it doesn't light up its surroundings), and BillboardGuis
-- (with ImageLabels), which fade out over their Lifetime attribute in seconds
-- while growing by their Grow attribute. Your own gun's flash moves with the
-- gun while it lasts; emitters with a LeaveBehind attribute set to true (like
-- sparks) stay where they were made instead.
--
-- No two flashes are the same: each is scaled at random between the
-- template's SmallestSize and LargestSize attributes (fractions of its
-- authored size), emitters give off a varying number of particles at varying
-- brightness, anything with a Chance attribute (0 to 1) only appears that
-- often, and billboards with a Stretch attribute vary in width by up to that
-- fraction. A game can supply its own in
-- Assets/Effects/Muzzle, named after the weapon, or Default for every weapon.

local AssetService = game:GetService("AssetService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

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
local FLASH_TIME = 0.06 -- seconds a muzzle light stays on, and a billboard lasts unless it says

local Effects = {}

local folder = Instance.new("Folder")
folder.Name = "OpenSRSEffects"
folder.Parent = workspace
Effects.folder = folder

local tracers: { Tracer } = {}
local random = Random.new()
-- Flashes that move with a gun, until they're gone.
local following: { { attachment: Attachment, follow: () -> CFrame } } = {}

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

local FIREBALL = "rbxasset://textures/particles/explosion01_core_main.dds" -- already orange
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Pictures for the flash, drawn by the game (see HoleImages for when that's
-- possible); where they can't be, the flash is just its fire. `paint` gets
-- x and y from -1 to 1 and returns red, green, blue (0-255) and alpha (0-1).
local function drawPicture(
	width: number,
	height: number,
	paint: (number, number) -> (number, number, number, number)
): Content?
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(width, height) })
	end)
	if not ok or not image then
		return nil
	end
	local pixels = buffer.create(width * height * 4)
	for row = 0, height - 1 do
		for column = 0, width - 1 do
			local r, g, b, a = paint((column + 0.5) / width * 2 - 1, (row + 0.5) / height * 2 - 1)
			local offset = (row * width + column) * 4
			buffer.writeu8(pixels, offset, math.clamp(math.round(r), 0, 255))
			buffer.writeu8(pixels, offset + 1, math.clamp(math.round(g), 0, 255))
			buffer.writeu8(pixels, offset + 2, math.clamp(math.round(b), 0, 255))
			buffer.writeu8(pixels, offset + 3, math.clamp(math.round(a * 255), 0, 255))
		end
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)
	return Content.fromObject(image)
end

-- A soft round glow: pale cream in the middle, orange at the edge.
local GLOW = drawPicture(64, 64, function(x, y)
	local heat = 1 - math.min(math.sqrt(x * x + y * y), 1)
	return 255, 150 + 100 * math.min(heat * 1.5, 1), 60 + 170 * math.max(heat * 2 - 1, 0), heat ^ 2
end)

-- A lens streak: a thin orange line across the flash, brightest in the middle.
local STREAK = drawPicture(128, 16, function(x, y)
	local along = 1 - math.abs(x)
	local across = 1 - math.abs(y)
	return 255, 150 + 80 * along ^ 3, 60 + 100 * along ^ 4, along ^ 2 * across ^ 3
end)

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
		glow: number, -- above 0, gives off light and ignores the scene's lighting; 1 adds fully onto what's behind
		brightness: number?,
		leaveBehind: boolean?, -- stays where it was made rather than moving with the gun
		chance: number?, -- how often it appears at all, 0 to 1
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
	particles.LightEmission = props.glow
	particles.LightInfluence = if props.glow > 0 then 0 else 1
	particles.Brightness = props.brightness or 1
	particles:SetAttribute("Burst", props.count)
	if props.leaveBehind then
		particles:SetAttribute("LeaveBehind", true)
	end
	if props.chance then
		particles:SetAttribute("Chance", props.chance)
	end
	particles.Parent = parent
	return particles
end

local BUILT_IN_MUZZLE = Instance.new("Folder")
BUILT_IN_MUZZLE.Name = "Default"
BUILT_IN_MUZZLE:SetAttribute("SmallestSize", 0.45)
BUILT_IN_MUZZLE:SetAttribute("LargestSize", 1)
do
	-- The flash: a ragged cloud of fire so bright its middle burns out to pale
	-- cream, orange only at the edges, wider than it is tall and gone almost
	-- as soon as it appears.
	emitter(BUILT_IN_MUZZLE, "Fire", {
		texture = FIREBALL,
		color = Color3.fromRGB(255, 240, 215),
		count = 5,
		size = sequence(0.7, 1.2),
		transparency = sequence(0, 0.15, 1),
		lifetime = NumberRange.new(0.05, 0.07),
		speed = NumberRange.new(1, 5),
		spread = 35,
		drag = 0,
		rise = 0,
		glow = 1,
		brightness = 3,
	})
	-- Drawn pictures can't be a particle's texture, so these are billboards.
	local function billboard(
		name: string,
		picture: Content,
		width: number,
		height: number,
		brightness: number,
		grow: number,
		chance: number,
		stretch: number
	)
		local gui = Instance.new("BillboardGui")
		gui.Name = name
		gui.Size = UDim2.fromScale(width, height) -- studs
		gui.LightInfluence = 0
		gui.Brightness = brightness
		gui:SetAttribute("Lifetime", 0.06)
		gui:SetAttribute("Grow", grow)
		gui:SetAttribute("Chance", chance)
		gui:SetAttribute("Stretch", stretch)
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ImageContent = picture
		image.Parent = gui
		gui.Parent = BUILT_IN_MUZZLE
	end
	-- A soft glow behind the fire.
	if GLOW then
		billboard("Glow", GLOW, 1.4, 1.1, 2, 1.2, 1, 0.15)
	end
	-- A lens streak across it, like a camera looking straight into the flash.
	if STREAK then
		billboard("Streak", STREAK, 3, 0.3, 3, 1.1, 0.65, 0.4) -- only on some shots
	end
	-- Burning powder thrown out ahead.
	emitter(BUILT_IN_MUZZLE, "Sparks", {
		leaveBehind = true,
		chance = 0.75,
		texture = SPARKLE,
		color = Color3.fromRGB(255, 185, 70),
		count = 5,
		size = sequence(0.08, 0),
		transparency = sequence(0),
		lifetime = NumberRange.new(0.05, 0.12),
		speed = NumberRange.new(15, 30),
		spread = 10,
		drag = 3,
		rise = -10,
		glow = 1,
		brightness = 2,
	})
end

-- A flash at `muzzle` (facing the way the gun fires) from `weapon`. If
-- `follow` is given, the flash moves to where it says the muzzle is each
-- frame while it lasts, so it stays on a gun that's moving.
function Effects.muzzleFlash(weapon: string, muzzle: CFrame, follow: (() -> CFrame)?)
	local template = Assets.effect("Muzzle", weapon) or Assets.effect("Muzzle", "Default") or BUILT_IN_MUZZLE
	local attachment = Instance.new("Attachment")
	attachment.Name = "MuzzleFlash"
	attachment.WorldCFrame = muzzle -- attachments on Terrain are in world space
	attachment.Parent = workspace.Terrain
	local longest = FLASH_TIME
	local smallest = tonumber(template:GetAttribute("SmallestSize")) or 1
	local largest = tonumber(template:GetAttribute("LargestSize")) or 1
	local scale = random:NextNumber(math.min(smallest, largest), math.max(smallest, largest))
	for _, child in template:GetChildren() do
		local chance = tonumber(child:GetAttribute("Chance"))
		if chance and random:NextNumber() >= chance then
			continue
		end
		if child:IsA("ParticleEmitter") then
			local particles = child:Clone()
			particles.Enabled = false
			particles.LockedToPart = follow ~= nil and particles:GetAttribute("LeaveBehind") ~= true
			local keys = {}
			for _, key in particles.Size.Keypoints do
				table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale))
			end
			particles.Size = NumberSequence.new(keys)
			particles.Brightness *= random:NextNumber(0.8, 1.05)
			particles.Parent = attachment
			local burst = tonumber(particles:GetAttribute("Burst")) or 5
			particles:Emit(math.max(math.round(burst * random:NextNumber(0.6, 1.1)), 1))
			longest = math.max(longest, particles.Lifetime.Max)
		elseif child:IsA("PointLight") and child.Name == "Light" then
			local light = child:Clone()
			light.Parent = attachment
			Debris:AddItem(light, FLASH_TIME)
		elseif child:IsA("BillboardGui") then
			local billboard = child:Clone()
			local stretch = tonumber(billboard:GetAttribute("Stretch")) or 0
			local wide = 1 + random:NextNumber(-stretch, stretch)
			billboard.Size = UDim2.new(
				billboard.Size.X.Scale * scale * wide,
				billboard.Size.X.Offset,
				billboard.Size.Y.Scale * scale,
				billboard.Size.Y.Offset
			)
			billboard.Adornee = attachment
			billboard.Parent = attachment
			local lifetime = tonumber(billboard:GetAttribute("Lifetime")) or FLASH_TIME
			local grow = tonumber(billboard:GetAttribute("Grow")) or 1
			local fade = TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(billboard, fade, {
				Size = UDim2.new(
					billboard.Size.X.Scale * grow,
					billboard.Size.X.Offset,
					billboard.Size.Y.Scale * grow,
					billboard.Size.Y.Offset
				),
			}):Play()
			for _, image in billboard:GetDescendants() do
				if image:IsA("ImageLabel") then
					TweenService:Create(image, fade, { ImageTransparency = 1 }):Play()
				end
			end
			longest = math.max(longest, lifetime)
		end
	end
	Debris:AddItem(attachment, longest + 0.1)
	if follow then
		table.insert(following, { attachment = attachment, follow = follow })
	end
end

-- Moves tracers; call once a frame.
function Effects.update(frameTime: number)
	for index = #following, 1, -1 do
		local flash = following[index]
		if flash.attachment.Parent then
			flash.attachment.WorldCFrame = flash.follow()
		else
			table.remove(following, index)
		end
	end
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

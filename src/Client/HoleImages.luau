--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Bullet hole pictures, drawn by the game rather than uploaded. A few
-- versions of each kind are drawn, each a little different, and holes pick
-- one at random. They're drawn a few rows a frame after the game starts
-- (prepare), so drawing never causes a hitch; a hole needed before its kind is
-- ready has one drawn on the spot.
--
--   World: a dark hole with a ragged, chipped rim, a few fine cracks running
--          out from it and a faint ring of soot.
--   Body:  a dark wound with a torn red rim, a stain around it and a few
--          drops.
--
-- Drawing uses Roblox's EditableImage, which only works in games whose owner
-- is ID-verified (and on devices with memory to spare). Where it can't be
-- used, pick returns nil and holes are plain discs instead.

local AssetService = game:GetService("AssetService")

local SIZE = 128 -- pixels across
local ROWS_PER_FRAME = 16 -- while preparing
local VARIANTS: { [string]: number } = { World = 6, Body = 4 }

local HoleImages = {}

local random = Random.new()
local pools: { [string]: { Content } } = {}
local unavailable = false

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- A radius that wobbles around the circle by up to `amount`.
local function wobble(amount: number): (number) -> number
	local waves = {}
	local total = 0
	for _ = 1, 4 do
		local weight = random:NextNumber(0.3, 1)
		total += weight
		table.insert(waves, {
			frequency = random:NextInteger(2, 9),
			phase = random:NextNumber(0, 2 * math.pi),
			weight = weight,
		})
	end
	return function(angle: number): number
		local sum = 0
		for _, wave in waves do
			sum += wave.weight * math.sin(wave.frequency * angle + wave.phase)
		end
		return sum / total * amount
	end
end

-- One pixel being built up from layers painted over each other.
type Pixel = { r: number, g: number, b: number, a: number }

local function over(pixel: Pixel, r: number, g: number, b: number, a: number)
	if a <= 0 then
		return
	end
	local out = a + pixel.a * (1 - a)
	pixel.r = (r * a + pixel.r * pixel.a * (1 - a)) / out
	pixel.g = (g * a + pixel.g * pixel.a * (1 - a)) / out
	pixel.b = (b * a + pixel.b * pixel.a * (1 - a)) / out
	pixel.a = out
end

type Painter = (pixel: Pixel, x: number, y: number, radius: number, angle: number) -> ()

local function worldPainter(): Painter
	local holeEdge = wobble(0.03)
	local rimEdge = wobble(0.08)
	local sootEdge = wobble(0.12)
	local cracks = {}
	for _ = 1, random:NextInteger(3, 5) do
		table.insert(cracks, {
			angle = random:NextNumber(0, 2 * math.pi),
			length = random:NextNumber(0.5, 0.95),
			width = random:NextNumber(0.012, 0.022),
			bend = random:NextNumber(0, 2 * math.pi),
		})
	end
	return function(pixel, x, y, radius, angle)
		local hole = 0.22 + holeEdge(angle)
		local rim = 0.4 + rimEdge(angle)
		local soot = 0.75 + sootEdge(angle)
		local grain = random:NextNumber(0.75, 1)

		-- Soot, fading out from the rim.
		if radius > hole then
			over(pixel, 18, 17, 16, 0.35 * grain * (1 - smoothstep(rim, soot, radius)))
		end
		-- Cracks: thin dark lines that wander a little and taper away.
		for _, crack in cracks do
			if radius > hole and radius < crack.length then
				local direction = crack.angle + 0.12 * math.sin(radius * 14 + crack.bend)
				local across = math.abs(-math.sin(direction) * x + math.cos(direction) * y)
				local along = math.cos(direction) * x + math.sin(direction) * y
				if along > 0 then
					local width = crack.width * (1 - radius / crack.length * 0.6)
					local line = 1 - smoothstep(width * 0.5, width, across)
					over(pixel, 22, 21, 20, 0.75 * line * (1 - smoothstep(crack.length * 0.7, crack.length, radius)))
				end
			end
		end
		-- The chipped rim: broken surface, rough and patchy.
		if radius < rim then
			local chip = if random:NextNumber() < 0.15 then 20 else 0
			over(pixel, 58 + chip, 55 + chip, 52 + chip, 0.9 * grain * (1 - smoothstep(rim - 0.06, rim, radius)))
		end
		-- The hole itself, darkest in the middle.
		local depth = 1 - smoothstep(hole - 0.03, hole, radius)
		local shade = 4 + 14 * (radius / hole)
		over(pixel, shade, shade, shade, depth)
	end
end

local function bodyPainter(): Painter
	local woundEdge = wobble(0.04)
	local rimEdge = wobble(0.07)
	local stainEdge = wobble(0.15)
	local drops = {}
	for _ = 1, random:NextInteger(5, 9) do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = random:NextNumber(0.45, 0.85)
		table.insert(drops, {
			x = math.cos(angle) * distance,
			y = math.sin(angle) * distance,
			size = random:NextNumber(0.025, 0.065),
		})
	end
	return function(pixel, x, y, radius, angle)
		local wound = 0.24 + woundEdge(angle)
		local rim = 0.42 + rimEdge(angle)
		local stain = 0.6 + stainEdge(angle)
		local grain = random:NextNumber(0.85, 1)

		for _, drop in drops do
			local distance = math.sqrt((x - drop.x) ^ 2 + (y - drop.y) ^ 2)
			over(pixel, 110, 0, 0, 0.85 * (1 - smoothstep(drop.size * 0.7, drop.size, distance)))
		end
		over(pixel, 120, 5, 5, 0.5 * grain * (1 - smoothstep(rim, stain, radius)))
		if radius < rim then
			over(pixel, 150 * grain, 12, 12, 1 - smoothstep(rim - 0.05, rim, radius))
		end
		local depth = 1 - smoothstep(wound - 0.03, wound, radius)
		over(pixel, 30 + 40 * (radius / wound), 0, 0, depth)
	end
end

-- Draws a picture; if `patient`, spread over several frames.
local function draw(painter: Painter, patient: boolean): Content?
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(SIZE, SIZE) })
	end)
	if not ok or not image then
		return nil
	end
	local pixels = buffer.create(SIZE * SIZE * 4)
	local pixel: Pixel = { r = 0, g = 0, b = 0, a = 0 }
	for row = 0, SIZE - 1 do
		for column = 0, SIZE - 1 do
			local x = (column + 0.5) / SIZE * 2 - 1
			local y = (row + 0.5) / SIZE * 2 - 1
			pixel.r, pixel.g, pixel.b, pixel.a = 0, 0, 0, 0
			painter(pixel, x, y, math.sqrt(x * x + y * y), math.atan2(y, x))
			local offset = (row * SIZE + column) * 4
			buffer.writeu8(pixels, offset, math.clamp(math.round(pixel.r), 0, 255))
			buffer.writeu8(pixels, offset + 1, math.clamp(math.round(pixel.g), 0, 255))
			buffer.writeu8(pixels, offset + 2, math.clamp(math.round(pixel.b), 0, 255))
			buffer.writeu8(pixels, offset + 3, math.clamp(math.round(pixel.a * 255), 0, 255))
		end
		if patient and row % ROWS_PER_FRAME == ROWS_PER_FRAME - 1 then
			task.wait()
		end
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(SIZE, SIZE), pixels)
	return Content.fromObject(image)
end

local function add(kind: string, patient: boolean): Content?
	if unavailable then
		return nil
	end
	local picture = draw(if kind == "Body" then bodyPainter() else worldPainter(), patient)
	if not picture then
		unavailable = true
		return nil
	end
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	table.insert(pool, picture)
	return picture
end

-- Starts drawing every picture in the background. Call once.
function HoleImages.prepare()
	task.spawn(function()
		for _, kind in { "World", "Body" } do
			while not unavailable and #(pools[kind] or {}) < VARIANTS[kind] do
				add(kind, true)
			end
		end
	end)
end

-- A picture for a hole of `kind` ("World" or "Body"), or nil if the game can't
-- draw them.
function HoleImages.pick(kind: string): Content?
	if unavailable or not VARIANTS[kind] then
		return nil
	end
	local pool = pools[kind]
	if not pool or #pool == 0 then
		return add(kind, false)
	end
	return pool[random:NextInteger(1, #pool)]
end

return table.freeze(HoleImages)

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- What a bullet does where it lands: a small hole and a burst of particles.
-- Purely cosmetic and client-side; the server has already decided the hit.
--
-- The server only says where a bullet landed and whether it hit the world, a
-- body or a head. The map is the same for everyone, so each client casts the
-- same line again to find the surface, which way it faces and what it's made
-- of. Holes in players stick to the body part that was hit and move with it;
-- they're cleared when that player stops being shown.
--
-- Every effect comes from a template: a Folder holding ParticleEmitters to
-- fire once (each with a Burst attribute, the number of particles; a
-- SurfaceColor attribute set to true colors them like the surface, and a
-- SurfaceShade number lightens that color above 1 or darkens it below), and
-- optionally a part named Hole, placed with its X axis pointing out of the
-- surface. A game can replace any of them with its own in
-- Assets/Effects/Impacts, named after the surface family (Stone, Wood, Metal,
-- Soft, Glass, Default) or Body for players. How long holes last and how many
-- there can be are the BulletHoleTime and MaxBulletHoles settings.

local Debris = game:GetService("Debris")

local Config = require(script.Parent.Parent.Shared.Config)
local Assets = require(script.Parent.Assets)
local Casings = require(script.Parent.Casings)
local Effects = require(script.Parent.Effects)
local Puppets = require(script.Parent.Puppets)

local HOLE_ATTRIBUTE = "OpenSRSHole" -- Puppets clears parts with this when it hides a player
local REACH = 0.5 -- studs past the reported hit point the line is cast, in case of rounding

local Impacts = {}

-- Which template each material uses.
local FAMILIES: { [Enum.Material]: string } = {}
for family, materials in
	{
		Stone = {
			"Concrete",
			"Brick",
			"Cobblestone",
			"Granite",
			"Marble",
			"Slate",
			"Pebble",
			"Rock",
			"Basalt",
			"Limestone",
			"Pavement",
			"Asphalt",
			"Sandstone",
			"CrackedLava",
			"Salt",
		},
		Wood = { "Wood", "WoodPlanks" },
		Metal = { "Metal", "DiamondPlate", "CorrodedMetal", "Foil" },
		Soft = { "Grass", "LeafyGrass", "Ground", "Mud", "Sand", "Snow", "Fabric" },
		Glass = { "Glass", "Ice", "Glacier" },
	} :: { [string]: { string } }
do
	for _, name in materials do
		local ok, material = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and material then
			FAMILIES[material] = family
		end
	end
end

local holes = Instance.new("Folder")
holes.Name = "OpenSRSHoles"
holes.Parent = workspace
Impacts.folder = holes

local placed: { Instance } = {} -- every hole, oldest first
local random = Random.new()

local world = RaycastParams.new()
world.FilterType = Enum.RaycastFilterType.Exclude
world.IgnoreWater = true
local bodies = RaycastParams.new()
bodies.FilterType = Enum.RaycastFilterType.Include
bodies.FilterDescendantsInstances = { Puppets.folder }

-- Built-in templates -------------------------------------------------------

type Burst = {
	texture: string,
	color: Color3?, -- nil takes the surface's color, shaded by `shade`
	shade: number?, -- above 1 lightens the surface's color (dust), below 1 darkens it (chips)
	count: number,
	size: NumberSequence,
	transparency: NumberSequence,
	lifetime: NumberRange,
	speed: NumberRange,
	spread: number,
	drag: number,
	gravity: number, -- studs a second squared, downward
	glow: number, -- above 0, the particles give off light and ignore the scene's lighting, like sparks
}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- Crushed material is lighter than the surface it came from, which also keeps
-- it from vanishing against that surface.
local function dust(color: Color3?, count: number, size: number): Burst
	return {
		texture = SMOKE,
		color = color,
		shade = 1.5,
		count = count,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.45),
			NumberSequenceKeypoint.new(1, size * 1.3),
		}),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.35, 0.7),
		speed = NumberRange.new(2, 5),
		spread = 35,
		drag = 6,
		gravity = 2,
		glow = 0,
	}
end

-- Small solid flecks, darker than the surface.
local function specks(color: Color3?, count: number): Burst
	return {
		texture = SMOKE,
		color = color,
		shade = 0.55,
		count = count,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0.06) }),
		transparency = NumberSequence.new(0),
		lifetime = NumberRange.new(0.3, 0.6),
		speed = NumberRange.new(7, 13),
		spread = 50,
		drag = 1,
		gravity = 60,
		glow = 0,
	}
end

local function sparks(count: number): Burst
	return {
		texture = SPARK,
		color = Color3.fromRGB(255, 205, 120),
		count = count,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new(0),
		lifetime = NumberRange.new(0.15, 0.35),
		speed = NumberRange.new(10, 20),
		spread = 60,
		drag = 2,
		gravity = 40,
		glow = 1,
	}
end

local function template(bursts: { Burst }, hole: { size: number, color: Color3 }?): Folder
	local folder = Instance.new("Folder")
	for index, burst in bursts do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = `Burst{index}`
		emitter.Enabled = false
		emitter.Texture = burst.texture
		emitter.Color = ColorSequence.new(burst.color or Color3.new(1, 1, 1))
		emitter.Size = burst.size
		emitter.Transparency = burst.transparency
		emitter.Lifetime = burst.lifetime
		emitter.Speed = burst.speed
		emitter.SpreadAngle = Vector2.new(burst.spread, burst.spread)
		emitter.Drag = burst.drag
		emitter.Acceleration = Vector3.new(0, -burst.gravity, 0)
		emitter.LightEmission = burst.glow
		emitter.LightInfluence = if burst.glow > 0 then 0 else 1
		emitter.Brightness = if burst.glow > 0 then 4 else 1
		emitter.Rotation = NumberRange.new(0, 360)
		emitter:SetAttribute("Burst", burst.count)
		emitter:SetAttribute("SurfaceColor", burst.color == nil)
		emitter:SetAttribute("SurfaceShade", burst.shade or 1)
		emitter.Parent = folder
	end
	if hole then
		local part = Instance.new("Part")
		part.Name = "Hole"
		part.Shape = Enum.PartType.Cylinder -- a round disc, its axis along X
		part.Size = Vector3.new(0.02, hole.size, hole.size)
		part.Color = hole.color
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = folder
	end
	return folder
end

local BUILT_IN: { [string]: Folder } = {
	Stone = template({ dust(nil, 5, 1.1), specks(nil, 7) }, { size = 0.13, color = Color3.fromRGB(35, 35, 35) }),
	Wood = template(
		{ dust(Color3.fromRGB(215, 185, 140), 5, 1), specks(Color3.fromRGB(90, 60, 30), 9) }, -- sawdust and splinters
		{ size = 0.13, color = Color3.fromRGB(45, 30, 20) }
	),
	Metal = template({ sparks(14), dust(Color3.fromRGB(150, 150, 150), 2, 0.6) }, {
		size = 0.11,
		color = Color3.fromRGB(55, 55, 58),
	}),
	Soft = template({ dust(nil, 6, 1.3), specks(nil, 5) }, { size = 0.16, color = Color3.fromRGB(40, 32, 25) }),
	Glass = template(
		{ specks(Color3.fromRGB(220, 235, 245), 10), dust(Color3.fromRGB(230, 240, 250), 2, 0.6) },
		{ size = 0.14, color = Color3.fromRGB(200, 210, 215) }
	),
	Default = template({ dust(nil, 4, 0.9), specks(nil, 5) }, { size = 0.12, color = Color3.fromRGB(35, 35, 35) }),
	-- A small red burst and a small dark hole.
	Body = template({
		{
			texture = SMOKE,
			color = Color3.fromRGB(125, 5, 5),
			count = 6,
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.5) }),
			transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			lifetime = NumberRange.new(0.15, 0.3),
			speed = NumberRange.new(3, 7),
			spread = 25,
			drag = 8,
			gravity = 10,
			glow = 0,
		},
		specks(Color3.fromRGB(110, 0, 0), 5),
	}, { size = 0.1, color = Color3.fromRGB(60, 8, 8) }),
}

local function templateFor(family: string): Instance
	local custom = Assets.effect("Impacts", family)
	if custom then
		return custom
	end
	if family ~= "Body" then
		local fallback = Assets.effect("Impacts", "Default")
		if fallback and not BUILT_IN[family] then
			return fallback
		end
	end
	return BUILT_IN[family] or BUILT_IN.Default
end

-- Placing effects ----------------------------------------------------------

-- A frame at `point` whose Y axis is `normal`, turned a random way around it.
local function facing(point: Vector3, normal: Vector3): CFrame
	local across = if math.abs(normal.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local tangent = normal:Cross(across).Unit
	return CFrame.fromMatrix(point, tangent, normal) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0)
end

local function burst(from: Instance, point: Vector3, normal: Vector3, surface: Color3)
	local emitters = {}
	for _, child in from:GetChildren() do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
		end
	end
	if #emitters == 0 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Impact"
	attachment.WorldCFrame = facing(point, normal) -- particles fly out along Y, off the surface
	attachment.Parent = workspace.Terrain
	local longest = 0
	for _, source in emitters do
		local emitter = source:Clone()
		if emitter:GetAttribute("SurfaceColor") == true then
			local shade = tonumber(emitter:GetAttribute("SurfaceShade")) or 1
			local shaded = if shade >= 1
				then surface:Lerp(Color3.new(1, 1, 1), math.min(shade - 1, 1))
				else surface:Lerp(Color3.new(0, 0, 0), 1 - math.max(shade, 0))
			emitter.Color = ColorSequence.new(shaded)
		end
		emitter.Enabled = false
		emitter.Parent = attachment
		emitter:Emit(tonumber(emitter:GetAttribute("Burst")) or 8)
		longest = math.max(longest, emitter.Lifetime.Max)
	end
	Debris:AddItem(attachment, longest + 0.1)
end

local function hole(from: Instance, point: Vector3, normal: Vector3, stuckTo: BasePart?)
	local source = from:FindFirstChild("Hole")
	if not (source and source:IsA("BasePart")) or Config.bulletHoleTime <= 0 or Config.maxBulletHoles <= 0 then
		return
	end
	while #placed >= Config.maxBulletHoles do
		local oldest = table.remove(placed, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local part = source:Clone()
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	-- X out of the surface, sitting just proud of it so it doesn't flicker.
	local frame = facing(point, normal) * CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis)
	part.CFrame = frame + normal * (part.Size.X / 2 + 0.003)
	part:SetAttribute(HOLE_ATTRIBUTE, true)
	if stuckTo then
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = stuckTo
		weld.Part1 = part
		weld.Parent = part
		part.Parent = stuckTo
	else
		part.Anchored = true
		part.Parent = holes
	end
	table.insert(placed, part)
	Debris:AddItem(part, Config.bulletHoleTime)
end

local function ignoring(): { Instance }
	return { workspace.CurrentCamera, Puppets.folder, Effects.folder, Casings.folder, holes }
end

-- A bullet from `origin` hit the world at `hit`.
function Impacts.world(origin: Vector3, hit: Vector3)
	local line = hit - origin
	if line.Magnitude < 1e-3 then
		return
	end
	world.FilterDescendantsInstances = ignoring()
	local result = workspace:Raycast(origin, line + line.Unit * REACH, world)
	if not result then
		burst(templateFor("Default"), hit, -line.Unit, Color3.fromRGB(150, 150, 150))
		return
	end
	local instance = result.Instance
	local surface = if instance:IsA("BasePart") and not instance:IsA("Terrain")
		then instance.Color
		else Color3.fromRGB(120, 110, 95)
	local from = templateFor(FAMILIES[result.Material] or "Default")
	burst(from, result.Position, result.Normal, surface)
	hole(from, result.Position, result.Normal, nil)
end

-- A bullet from `origin` hit a player at `hit`. The shown player is where the
-- server says it hit, give or take a little, so the line is cast against
-- the players shown to find the part.
function Impacts.body(origin: Vector3, hit: Vector3)
	local line = hit - origin
	if line.Magnitude < 1e-3 then
		return
	end
	local from = templateFor("Body")
	local result = workspace:Raycast(origin, line + line.Unit * (REACH * 3), bodies)
	if result and result.Instance:IsA("BasePart") then
		burst(from, result.Position, result.Normal, Color3.new(1, 1, 1))
		hole(from, result.Position, result.Normal, result.Instance)
	else
		burst(from, hit, -line.Unit, Color3.new(1, 1, 1))
	end
end

return table.freeze(Impacts)

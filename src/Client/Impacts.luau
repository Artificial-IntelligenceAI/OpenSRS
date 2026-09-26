--!strict
-- SPDX-License-Identifier: Apache-2.0

-- What a bullet does where it lands. Anything alive (players, and anything a
-- game gives a Humanoid) gets a red hole and blood: a red mist where the bullet
-- goes in and droplets sprayed out along its path, falling as they fly.
-- Anything else gets a black hole and a puff of smoke. Purely cosmetic and
-- client-side; the server has already decided the hit.
--
-- The server only says where a bullet landed and whether it hit the world, a
-- body or a head. The map is the same for everyone, so each client casts the
-- same line again to find the surface, which way it faces and what it's made
-- of. Holes in players stick to the body part that was hit and move with it;
-- they're cleared when that player stops being shown.
--
-- Every effect comes from a template: a Folder holding ParticleEmitters to
-- fire once (each with a Burst attribute, the number of particles; they fly
-- out of the surface, or along the bullet's path if a Through attribute is
-- true; a SurfaceColor attribute set to true colors them like the surface, and
-- a SurfaceShade number lightens that color above 1 or darkens it below), and
-- optionally a part named Hole, placed with its X axis pointing out of the
-- surface. A Hole with a Drawn attribute ("World" or "Body") gets a picture
-- drawn by the game (see HoleImages) on its outward face, DrawnSize studs
-- across, turned and sized a little differently each time; without one it's
-- used as it is. A game can replace any of them with its own in
-- Assets/Effects/Impacts, named after the surface family (Stone, Wood, Metal,
-- Soft, Glass, Default) or Body for anything alive. How long holes last and
-- how many there can be are the BulletHoleTime and MaxBulletHoles settings.

local Debris = game:GetService("Debris")

local Config = require(script.Parent.Parent.Shared.Config)
local Living = require(script.Parent.Parent.Shared.Living)
local Assets = require(script.Parent.Assets)
local Casings = require(script.Parent.Casings)
local Effects = require(script.Parent.Effects)
local HoleImages = require(script.Parent.HoleImages)
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

HoleImages.prepare()

local holes = Instance.new("Folder")
holes.Name = "OpenSRSHoles"
holes.Parent = workspace
Impacts.folder = holes

local placed: { Instance } = {} -- every hole, oldest first
local random = Random.new()

local world = RaycastParams.new()
world.FilterType = Enum.RaycastFilterType.Exclude
world.IgnoreWater = true
local NEAREST_BODY = 3 -- studs: if the line misses the players shown, the closest part this near is used

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
	through: boolean?, -- fly along the bullet's path instead of out of the surface
}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

type HoleLook = {
	size: number, -- across, as a plain disc
	color: Color3,
	drawn: string, -- the kind of picture drawn for it (see HoleImages)
	drawnSize: number, -- across, as a picture, rim and all
}

local function template(bursts: { Burst }, hole: HoleLook?): Folder
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
		emitter:SetAttribute("Through", burst.through == true)
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
		part:SetAttribute("Drawn", hole.drawn)
		part:SetAttribute("DrawnSize", hole.drawnSize)
		part.Parent = folder
	end
	return folder
end

-- Anything that isn't alive: a black hole and a quick puff of smoke. Dark enough to show on pale walls, light enough to show on dark ones.
local WORLD = template({
	{
		texture = SMOKE,
		color = Color3.fromRGB(80, 80, 82),
		count = 8,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.9) }),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		lifetime = NumberRange.new(0.25, 0.5),
		speed = NumberRange.new(2, 5),
		spread = 30,
		drag = 5,
		gravity = -1, -- drifts up
		glow = 0,
	},
}, { size = 0.13, color = Color3.fromRGB(12, 12, 12), drawn = "World", drawnSize = 0.45 })

-- Anything alive: a red hole, a red mist where the bullet goes in, droplets
-- sprayed out along its path that fall as they fly, and a few thrown back.
local BODY = template({
	{
		texture = SMOKE,
		color = Color3.fromRGB(150, 8, 8),
		count = 7,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.8) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		lifetime = NumberRange.new(0.2, 0.4),
		speed = NumberRange.new(3, 8),
		spread = 30,
		drag = 6,
		gravity = 5,
		glow = 0,
	},
	{
		texture = SMOKE,
		color = Color3.fromRGB(120, 0, 0),
		count = 16,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.05) }),
		transparency = NumberSequence.new(0),
		lifetime = NumberRange.new(0.4, 0.7),
		speed = NumberRange.new(8, 16),
		spread = 25,
		drag = 1,
		gravity = 60,
		glow = 0,
		through = true,
	},
	{
		-- A little back spatter toward the shooter, so they see it land.
		texture = SMOKE,
		color = Color3.fromRGB(120, 0, 0),
		count = 6,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.04) }),
		transparency = NumberSequence.new(0),
		lifetime = NumberRange.new(0.3, 0.5),
		speed = NumberRange.new(4, 8),
		spread = 45,
		drag = 1,
		gravity = 60,
		glow = 0,
	},
}, { size = 0.12, color = Color3.fromRGB(135, 5, 5), drawn = "Body", drawnSize = 0.36 })

local BUILT_IN: { [string]: Folder } = {
	Stone = WORLD,
	Wood = WORLD,
	Metal = WORLD,
	Soft = WORLD,
	Glass = WORLD,
	Default = WORLD,
	Body = BODY,
}

local function templateFor(family: string): Instance
	local custom = Assets.effect("Impacts", family)
	if custom then
		return custom
	end
	if family ~= "Body" then
		local fallback = Assets.effect("Impacts", "Default")
		if fallback then
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

-- `along` is the way the bullet was going, for emitters marked Through.
local function burst(from: Instance, point: Vector3, normal: Vector3, surface: Color3, along: Vector3)
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
	local onward: Attachment? = nil
	local longest = 0
	for _, source in emitters do
		local emitter = source:Clone()
		local parent: Attachment = attachment
		if emitter:GetAttribute("Through") == true then
			if not onward then
				-- Its own attachment: an attachment can only be placed on a part (or Terrain).
				local created = Instance.new("Attachment")
				created.Name = "ImpactThrough"
				created.WorldCFrame = facing(point, along)
				created.Parent = workspace.Terrain
				onward = created
			end
			parent = onward :: Attachment
		end
		if emitter:GetAttribute("SurfaceColor") == true then
			local shade = tonumber(emitter:GetAttribute("SurfaceShade")) or 1
			local shaded = if shade >= 1
				then surface:Lerp(Color3.new(1, 1, 1), math.min(shade - 1, 1))
				else surface:Lerp(Color3.new(0, 0, 0), 1 - math.max(shade, 0))
			emitter.Color = ColorSequence.new(shaded)
		end
		emitter.Enabled = false
		emitter.Parent = parent
		emitter:Emit(tonumber(emitter:GetAttribute("Burst")) or 8)
		longest = math.max(longest, emitter.Lifetime.Max)
	end
	Debris:AddItem(attachment, longest + 0.1)
	if onward then
		Debris:AddItem(onward, longest + 0.1)
	end
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
	local drawn = part:GetAttribute("Drawn")
	local picture = if typeof(drawn) == "string" then HoleImages.pick(drawn) else nil
	if picture then
		local across = (tonumber(part:GetAttribute("DrawnSize")) or 0.4) * random:NextNumber(0.85, 1.15)
		if part:IsA("Part") then
			part.Shape = Enum.PartType.Block
		end
		part.Size = Vector3.new(0.02, across, across)
		part.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Right -- +X, out of the surface
		decal.TextureContent = picture
		decal.Parent = part
	end
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

-- A bullet from `origin` hit the world at `hit`. Returns true if what it hit
-- was alive (something in the game with a Humanoid), which bleeds like a player.
function Impacts.world(origin: Vector3, hit: Vector3): boolean
	local line = hit - origin
	if line.Magnitude < 1e-3 then
		return false
	end
	world.FilterDescendantsInstances = ignoring()
	local result = workspace:Raycast(origin, line + line.Unit * REACH, world)
	if not result then
		burst(templateFor("Default"), hit, -line.Unit, Color3.fromRGB(150, 150, 150), line.Unit)
		return false
	end
	local instance = result.Instance
	if instance:IsA("BasePart") and Living.humanoidOf(instance) then
		local from = templateFor("Body")
		burst(from, result.Position, result.Normal, Color3.new(1, 1, 1), line.Unit)
		hole(from, result.Position, result.Normal, instance)
		return true
	end
	local surface = if instance:IsA("BasePart") and not instance:IsA("Terrain")
		then instance.Color
		else Color3.fromRGB(120, 110, 95)
	local from = templateFor(FAMILIES[result.Material] or "Default")
	burst(from, result.Position, result.Normal, surface, line.Unit)
	hole(from, result.Position, result.Normal, nil)
	return false
end

-- Where a line from `origin` along `direction` first enters `part` (treated
-- as a box), and the normal of the face it enters through.
local function enterBox(part: BasePart, origin: Vector3, direction: Vector3): (number?, Vector3?)
	local from = part.CFrame:PointToObjectSpace(origin)
	local way = part.CFrame:VectorToObjectSpace(direction)
	local half = part.Size / 2
	local near, far = -math.huge, math.huge
	local enteredAxis, enteredSign = 1, 1
	for axis = 1, 3 do
		local start = if axis == 1 then from.X elseif axis == 2 then from.Y else from.Z
		local step = if axis == 1 then way.X elseif axis == 2 then way.Y else way.Z
		local extent = if axis == 1 then half.X elseif axis == 2 then half.Y else half.Z
		if math.abs(step) < 1e-9 then
			if math.abs(start) > extent then
				return nil, nil
			end
		else
			local t1 = (-extent - start) / step
			local t2 = (extent - start) / step
			if math.min(t1, t2) > near then
				near = math.min(t1, t2)
				enteredAxis = axis
				enteredSign = if t1 < t2 then -1 else 1
			end
			far = math.min(far, math.max(t1, t2))
			if near > far then
				return nil, nil
			end
		end
	end
	if near < 0 then
		return nil, nil
	end
	local normal = if enteredAxis == 1 then Vector3.xAxis elseif enteredAxis == 2 then Vector3.yAxis else Vector3.zAxis
	return near, part.CFrame:VectorToWorldSpace(normal * enteredSign)
end

-- The closest point on `part`'s surface to `point`, and that face's normal.
local function nearestOnBox(part: BasePart, point: Vector3): (Vector3, Vector3)
	local at = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(at.X, -half.X, half.X),
		math.clamp(at.Y, -half.Y, half.Y),
		math.clamp(at.Z, -half.Z, half.Z)
	)
	-- Snap to whichever face is nearest.
	local gaps = { half.X - math.abs(clamped.X), half.Y - math.abs(clamped.Y), half.Z - math.abs(clamped.Z) }
	local axis = if gaps[1] <= gaps[2] and gaps[1] <= gaps[3] then 1 elseif gaps[2] <= gaps[3] then 2 else 3
	local normal
	if axis == 1 then
		normal = Vector3.xAxis * (if clamped.X >= 0 then 1 else -1)
		clamped = Vector3.new(half.X * normal.X, clamped.Y, clamped.Z)
	elseif axis == 2 then
		normal = Vector3.yAxis * (if clamped.Y >= 0 then 1 else -1)
		clamped = Vector3.new(clamped.X, half.Y * normal.Y, clamped.Z)
	else
		normal = Vector3.zAxis * (if clamped.Z >= 0 then 1 else -1)
		clamped = Vector3.new(clamped.X, clamped.Y, half.Z * normal.Z)
	end
	return part.CFrame:PointToWorldSpace(clamped), part.CFrame:VectorToWorldSpace(normal)
end

-- A bullet from `origin` hit something alive at `hit`: a player, or anything
-- a game gave a Humanoid. The players shown are where the server says the
-- bullet hit, give or take a little, so the line is traced against their parts
-- to find which one and where (their parts are left out of raycasts, so this
-- is worked out here); failing that, it's cast against the world for anything
-- alive; failing that, the player part closest to `hit` is used.
function Impacts.body(origin: Vector3, hit: Vector3)
	local line = hit - origin
	if line.Magnitude < 1e-3 then
		return
	end
	local from = templateFor("Body")
	local direction = line.Unit
	local struck: BasePart? = nil
	local point, normal = hit, -direction
	local nearest = math.huge
	for _, part in Puppets.folder:GetDescendants() do
		if part:IsA("BasePart") and not part:GetAttribute(HOLE_ATTRIBUTE) and part.Transparency < 1 then
			local distance, face = enterBox(part, origin, direction)
			if distance and face and distance < nearest then
				nearest = distance
				struck = part
				point, normal = origin + direction * distance, face
			end
		end
	end
	if not struck then
		world.FilterDescendantsInstances = ignoring()
		local result = workspace:Raycast(origin, line + direction * REACH, world)
		if result and result.Instance:IsA("BasePart") and Living.humanoidOf(result.Instance) then
			struck = result.Instance
			point, normal = result.Position, result.Normal
		end
	end
	if not struck then
		local closest = NEAREST_BODY
		for _, part in Puppets.folder:GetDescendants() do
			if part:IsA("BasePart") and not part:GetAttribute(HOLE_ATTRIBUTE) and part.Transparency < 1 then
				local surface, face = nearestOnBox(part, hit)
				local distance = (surface - hit).Magnitude
				if distance < closest then
					closest = distance
					struck = part
					point, normal = surface, face
				end
			end
		end
	end
	burst(from, point, normal, Color3.new(1, 1, 1), direction)
	if struck then
		hole(from, point, normal, struck)
	end
end

return table.freeze(Impacts)

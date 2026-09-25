--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Spent cases thrown from guns as they fire. Purely cosmetic and client-side.
--
-- A case flies out of the ejection port to the right and up, spinning, falls,
-- bounces off whatever it hits and comes to rest on its side. Its sound plays
-- where it first lands. They're simulated here with raycasts rather than
-- Roblox physics, which lets tiny parts pass through floors.
--
-- A game can give a weapon its own case by adding a part named Casing to it
-- in Assets (Assets/Weapons/<Name>/Casing); otherwise a small brass cylinder
-- is used.

local Assets = require(script.Parent.Assets)
local Sounds = require(script.Parent.Sounds)

type Casing = {
	part: BasePart,
	weapon: string,
	velocity: Vector3,
	spin: Vector3, -- radians a second
	resting: boolean,
	landed: boolean,
	age: number,
}

local SIZE = Vector3.new(0.12, 0.064, 0.064) -- a 9mm case at the gun's scale, lying along X
local BRASS = Color3.fromRGB(196, 156, 72)
local EJECT = Vector3.new(8, 6, 1.5) -- studs a second in the gun's space: right, up, and back toward the shooter
local EJECT_VARIATION = 0.2 -- each case flies up to this much faster or slower
local SPIN = 30 -- radians a second, at most
local GRAVITY = 60 -- studs a second squared: real gravity at the gun's scale, gentler than the game's
local BOUNCE = 0.35 -- how much speed a bounce keeps, straight off the surface
local SLIDE = 0.6 -- how much speed a bounce keeps along the surface
local REST_SPEED = 1.5 -- below this after a bounce on flat ground, it settles
local LIFETIME = 10 -- seconds before a case disappears
local MAX_CASINGS = 40 -- the oldest cases go first beyond this
local MAX_STEP = 1 / 30 -- longer frames are simulated in steps no longer than this

local Casings = {}

local folder = Instance.new("Folder")
folder.Name = "OpenSRSCasings"
folder.Parent = workspace
Casings.folder = folder

local casings: { Casing } = {}
local random = Random.new()
local ignored: { Instance } = { folder }
local raycast = RaycastParams.new()
raycast.FilterType = Enum.RaycastFilterType.Exclude
raycast.IgnoreWater = true

-- Things a case should fly through rather than bounce off: the player's own
-- view model, other players, effects.
function Casings.ignore(instances: { Instance })
	for _, instance in instances do
		table.insert(ignored, instance)
	end
	raycast.FilterDescendantsInstances = ignored
end
raycast.FilterDescendantsInstances = ignored

local function newPart(weapon: string): BasePart
	local custom = Assets.weaponPart(weapon, "Casing")
	if custom and custom:IsA("BasePart") then
		local part = custom:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		return part
	end
	local part = Instance.new("Part")
	part.Name = "Casing"
	part.Shape = Enum.PartType.Cylinder
	part.Size = SIZE
	part.Color = BRASS
	part.Material = Enum.Material.SmoothPlastic -- Metal's diamond-plate texture makes a case look like a block
	part.Reflectance = 0.25
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Throws a case out of `port` (the ejection port, facing the gun's way, so its
-- +X is the gun's right). `carried` is how fast the gun itself was moving.
function Casings.eject(weapon: string, port: CFrame, carried: Vector3?)
	if #casings >= MAX_CASINGS then
		local oldest = table.remove(casings, 1)
		if oldest then
			oldest.part:Destroy()
		end
	end
	local speed = 1 + random:NextNumber(-EJECT_VARIATION, EJECT_VARIATION)
	local part = newPart(weapon)
	part.CFrame = port
	part.Parent = folder
	table.insert(casings, {
		part = part,
		weapon = weapon,
		velocity = port:VectorToWorldSpace(EJECT * speed) + (carried or Vector3.zero),
		spin = Vector3.new(
			random:NextNumber(-SPIN, SPIN),
			random:NextNumber(-SPIN, SPIN),
			random:NextNumber(-SPIN, SPIN)
		),
		resting = false,
		landed = false,
		age = 0,
	})
end

local function step(casing: Casing, dt: number)
	local part = casing.part
	local from = part.Position
	casing.velocity -= Vector3.new(0, GRAVITY * dt, 0)
	local move = casing.velocity * dt
	local hit = workspace:Raycast(from, move, raycast)
	if not hit then
		part.CFrame = (part.CFrame + move) * CFrame.Angles(casing.spin.X * dt, casing.spin.Y * dt, casing.spin.Z * dt)
		return
	end

	-- Bounce: lose most of the speed into the surface, some along it.
	local normal = hit.Normal
	local into = casing.velocity:Dot(normal)
	local along = casing.velocity - normal * into
	casing.velocity = along * SLIDE - normal * into * BOUNCE
	casing.spin *= SLIDE
	local at = hit.Position + normal * (part.Size.Y / 2)
	if not casing.landed then
		casing.landed = true
		Sounds.at(casing.weapon, Sounds.Cues.Casing, hit.Position)
	end
	if casing.velocity.Magnitude < REST_SPEED and normal.Y > 0.7 then
		-- Settle on its side, lying across the surface.
		casing.resting = true
		local lying = part.CFrame.RightVector - normal * part.CFrame.RightVector:Dot(normal)
		if lying.Magnitude < 1e-3 then
			lying = normal:Cross(Vector3.new(0, 0, 1))
		end
		part.CFrame = CFrame.fromMatrix(at, lying.Unit, normal)
	else
		part.CFrame = part.CFrame - part.Position + at
	end
end

function Casings.update(frameTime: number)
	for index = #casings, 1, -1 do
		local casing = casings[index]
		casing.age += frameTime
		if casing.age > LIFETIME then
			casing.part:Destroy()
			table.remove(casings, index)
		elseif not casing.resting then
			local remaining = frameTime
			while remaining > 0 and not casing.resting do
				local dt = math.min(remaining, MAX_STEP)
				remaining -= dt
				step(casing, dt)
			end
		end
	end
end

return table.freeze(Casings)

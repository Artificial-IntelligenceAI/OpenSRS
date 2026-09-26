--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Tools for the OpenSRS test place. Only dev.project.json syncs this; it's
-- never part of OpenSRS itself. It also shows a game using OpenSRS's API.
--
-- Teleports: players ask (see DevTools.client) to go inside the spawn box,
-- outside it, or to the zombie arena. They can also switch their own shooting
-- off and on, to try OpenSRS.setCanShoot.
--
-- The zombie arena: a walled yard away from the spawn with some cover. While
-- anyone is in it, zombies keep coming: plain R6 figures with a Humanoid, so
-- bullets hurt them and they bleed with nothing else needed. They walk at the
-- nearest player and hit anyone they reach. When the arena empties they're
-- cleared away, so nobody arrives into a crowd left waiting at the entrance.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local OpenSRS = require(ServerScriptService:WaitForChild("OpenSRS"):WaitForChild("Server"):WaitForChild("API")) :: any

local ARENA_CENTER = Vector3.new(0, 0, 250)
local ARENA_SIZE = 100 -- studs across
local WALL_HEIGHT = 14

-- Where each teleport puts a player's feet.
local PLACES: { [string]: Vector3 } = {
	Inside = Vector3.new(0, 0.1, 8),
	Outside = Vector3.new(0, 0.1, 40),
	Arena = ARENA_CENTER + Vector3.new(0, 0.2, -ARENA_SIZE / 2 + 8),
}

local MAX_ZOMBIES = 6
local SPAWN_EVERY = 3 -- seconds between new zombies
local ZOMBIE_SPEED = 11 -- a little slower than walking (12), much slower than sprinting (19)
local ZOMBIE_HEALTH = 100
local ZOMBIE_DAMAGE = 15
local ZOMBIE_REACH = 3.5 -- studs
local ZOMBIE_HIT_EVERY = 1 -- seconds between a zombie's hits
local THINK_EVERY = 0.2 -- seconds between zombies picking where to go

-- Teleports -------------------------------------------------------------------

local teleport = Instance.new("RemoteEvent")
teleport.Name = "OpenSRSDevTeleport"
teleport.Parent = ReplicatedStorage
local shootingOff: { [Player]: boolean } = {}
teleport.OnServerEvent:Connect(function(player: Player, where: unknown)
	if where == "ToggleShooting" then
		shootingOff[player] = not shootingOff[player]
		OpenSRS.setCanShoot(player, not shootingOff[player])
		return
	end
	local place = if typeof(where) == "string" then PLACES[where] else nil
	if place then
		OpenSRS.teleport(player, place)
	end
end)
Players.PlayerRemoving:Connect(function(player)
	shootingOff[player] = nil
end)

-- The arena ---------------------------------------------------------------------

local arena = Instance.new("Model")
arena.Name = "DevArena"

local function block(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = arena
	return part
end

local half = ARENA_SIZE / 2
local concrete = Color3.fromRGB(120, 116, 110)
block(
	"Floor",
	Vector3.new(ARENA_SIZE, 0.2, ARENA_SIZE),
	ARENA_CENTER + Vector3.new(0, 0.1, 0),
	Color3.fromRGB(70, 66, 60),
	Enum.Material.Asphalt
)
for _, side in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
	local along = if side.X ~= 0
		then Vector3.new(2, WALL_HEIGHT, ARENA_SIZE + 4)
		else Vector3.new(ARENA_SIZE + 4, WALL_HEIGHT, 2)
	block(
		"Wall",
		along,
		ARENA_CENTER + side * (half + 1) + Vector3.new(0, WALL_HEIGHT / 2, 0),
		concrete,
		Enum.Material.Concrete
	)
end
-- Cover: low walls and crates to fight around.
for _, cover in
	{
		{ Vector3.new(12, 4, 2), Vector3.new(-18, 2, -15) },
		{ Vector3.new(12, 4, 2), Vector3.new(18, 2, -15) },
		{ Vector3.new(2, 4, 14), Vector3.new(0, 2, 0) },
		{ Vector3.new(6, 6, 6), Vector3.new(-25, 3, 18) },
		{ Vector3.new(6, 6, 6), Vector3.new(25, 3, 18) },
		{ Vector3.new(16, 4, 2), Vector3.new(0, 2, 28) },
	}
do
	block("Cover", cover[1], ARENA_CENTER + cover[2], concrete, Enum.Material.Concrete)
end
arena.Parent = workspace

local function inArena(position: Vector3): boolean
	local offset = position - ARENA_CENTER
	return math.abs(offset.X) < half and math.abs(offset.Z) < half and offset.Y < WALL_HEIGHT
end

-- Zombies -----------------------------------------------------------------------

type Zombie = { model: Model, humanoid: Humanoid, root: BasePart, lastHit: number }

local zombies: { Zombie } = {}
local SPAWNS = {
	ARENA_CENTER + Vector3.new(-half + 5, 3, half - 5),
	ARENA_CENTER + Vector3.new(half - 5, 3, half - 5),
	ARENA_CENTER + Vector3.new(-half + 5, 3, 5),
	ARENA_CENTER + Vector3.new(half - 5, 3, 5),
}

local function newZombie(position: Vector3)
	local look = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(95, 135, 75)
	look.HeadColor = skin
	look.LeftArmColor = skin
	look.RightArmColor = skin
	look.TorsoColor = Color3.fromRGB(70, 60, 50)
	look.LeftLegColor = Color3.fromRGB(45, 45, 60)
	look.RightLegColor = Color3.fromRGB(45, 45, 60)
	local model = Players:CreateHumanoidModelFromDescription(look, Enum.HumanoidRigType.R6)
	model.Name = "Zombie"
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = ZOMBIE_HEALTH
	humanoid.Health = ZOMBIE_HEALTH
	humanoid.WalkSpeed = ZOMBIE_SPEED
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model:PivotTo(CFrame.new(position))
	model.Parent = workspace
	root:SetNetworkOwner(nil) -- the server moves them, so everyone sees the same zombie
	local zombie: Zombie = { model = model, humanoid = humanoid, root = root, lastHit = 0 }
	table.insert(zombies, zombie)
	humanoid.Died:Once(function()
		Debris:AddItem(model, 4)
	end)
end

-- The nearest living player in the arena to `position`.
local function nearestPlayer(position: Vector3): (Player?, Vector3?)
	local best, bestPosition, bestDistance = nil, nil, math.huge
	for _, player in Players:GetPlayers() do
		local at = OpenSRS.position(player)
		if at and inArena(at) then
			local distance = (at - position).Magnitude
			if distance < bestDistance then
				best, bestPosition, bestDistance = player, at, distance
			end
		end
	end
	return best, bestPosition
end

local sinceSpawn = 0
local sinceThink = 0
RunService.Heartbeat:Connect(function(frameTime)
	for index = #zombies, 1, -1 do
		if zombies[index].humanoid.Health <= 0 or not zombies[index].model.Parent then
			table.remove(zombies, index)
		end
	end

	local anyoneInArena = false
	for _, player in Players:GetPlayers() do
		local at = OpenSRS.position(player)
		if at and inArena(at) then
			anyoneInArena = true
		end
	end
	if not anyoneInArena then
		for _, zombie in zombies do
			zombie.model:Destroy()
		end
		table.clear(zombies)
	end
	sinceSpawn += frameTime
	if anyoneInArena and #zombies < MAX_ZOMBIES and sinceSpawn >= SPAWN_EVERY then
		sinceSpawn = 0
		newZombie(SPAWNS[math.random(#SPAWNS)])
	end

	sinceThink += frameTime
	if sinceThink < THINK_EVERY then
		return
	end
	sinceThink = 0
	local now = os.clock()
	for _, zombie in zombies do
		local target, at = nearestPlayer(zombie.root.Position)
		if target and at then
			zombie.humanoid:MoveTo(at)
			local offset = at - zombie.root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flat <= ZOMBIE_REACH and math.abs(offset.Y + 3) < 4 and now - zombie.lastHit >= ZOMBIE_HIT_EVERY then
				zombie.lastHit = now
				OpenSRS.damage(target, ZOMBIE_DAMAGE)
			end
		else
			zombie.humanoid:MoveTo(zombie.root.Position)
		end
	end
end)

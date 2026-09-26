--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Shooting on the server: lag-compensated hit detection, damage and health.
--
-- The client only says when it fired and where it aimed (as part of its
-- inputs). The server rewinds every other player to what the shooter was
-- seeing, casts the bullet itself with spread only the server knows, and
-- decides the damage. Nothing about a hit is ever taken from the client.
--
-- Bullets also hurt anything else alive: anything a game gives a Humanoid
-- (see Living). Those are hit where the server has them now (they're the
-- server's own, so there's nothing to rewind), and take damage through their
-- Humanoid, head shots included, so a game handles their death itself.

local Shared = script.Parent.Parent.Shared
local Body = require(Shared.Body)
local Config = require(Shared.Config)
local Eye = require(Shared.Eye)
local Firearm = require(Shared.Firearm)
local Living = require(Shared.Living)
local Movement = require(Shared.Movement)
local Protocol = require(Shared.Protocol)
local Simulation = require(Shared.Simulation)
local Types = require(Shared.Types)
local Weapons = require(Shared.Weapons)
local Remotes = require(script.Parent.Remotes)

type Input = Types.Input
type Pose = Protocol.Remote
type Shot = Simulation.Shot

-- What Combat needs to know about the player in a slot.
export type Target = {
	player: Player,
	epoch: number, -- changes on every respawn
	alive: boolean,
}

type Entry = { tick: number, pose: Pose }

local HISTORY_TICKS = Config.tickRate -- one second of rewind history
local MAX_REWIND_TICKS = math.round(Config.tickRate * 0.4)
-- A shot's rewind may only differ this much (in ticks) from the player's usual
-- delay. Jumping further back is how "backtrack" cheats pick a moment when the
-- target was exposed.
local REWIND_TOLERANCE = 3
local REWIND_SMOOTHING = 0.05
local HEARING_RANGE = 400
local HEAD = "Head"
local TORSO = "Torso"

local Combat = {}

local damaged = Instance.new("BindableEvent")
local died = Instance.new("BindableEvent")

-- (victim: Player, attacker: Player?, amount: number, part: string)
Combat.Damaged = damaged.Event
-- (victim: Player, killer: Player?)
Combat.Died = died.Event

local history: { [number]: { Entry } } = {}
local health: { [number]: number } = {}
local usualRewind: { [number]: number } = {}
local random = Random.new() -- never shared: this is what makes spread unpredictable
local world = Movement.newWorld({})
local bullets = RaycastParams.new()
bullets.FilterType = Enum.RaycastFilterType.Exclude
bullets.RespectCanCollide = true
bullets.IgnoreWater = true

local remotes: Remotes.Remotes
local lookup: (slot: number) -> Target?

function Combat.start(created: Remotes.Remotes, find: (slot: number) -> Target?)
	remotes = created
	lookup = find
end

function Combat.spawned(slot: number)
	health[slot] = Config.maxHealth
	history[slot] = {}
end

function Combat.forget(slot: number)
	health[slot] = nil
	history[slot] = nil
	usualRewind[slot] = nil
end

function Combat.health(slot: number): number
	return health[slot] or 0
end

-- Stores where a player was at a snapshot tick, for rewinding later. Uses the
-- same snapshots clients see, so rewinds match what shooters saw.
function Combat.record(tick: number, slot: number, pose: Pose)
	local entries = history[slot]
	if not entries then
		return
	end
	table.insert(entries, { tick = tick, pose = pose })
	while entries[1] and entries[1].tick < tick - HISTORY_TICKS do
		table.remove(entries, 1)
	end
end

-- Tracks how far behind the server each player normally sees others.
function Combat.observe(slot: number, input: Input, serverTick: number)
	local rewind = math.clamp(serverTick - input.viewTick / Protocol.VIEW_TICK_SCALE, 0, MAX_REWIND_TICKS)
	local usual = usualRewind[slot]
	usualRewind[slot] = if usual then usual + (rewind - usual) * REWIND_SMOOTHING else rewind
end

local function lerpAngle(a: number, b: number, t: number): number
	return a + ((b - a + math.pi) % (2 * math.pi) - math.pi) * t
end

local function poseAt(slot: number, tick: number): Pose?
	local entries = history[slot]
	if not entries or #entries == 0 then
		return nil
	end
	if tick <= entries[1].tick then
		return entries[1].pose
	end
	for index = 2, #entries do
		local after = entries[index]
		if after.tick >= tick then
			local before = entries[index - 1]
			local t = (tick - before.tick) / (after.tick - before.tick)
			local a, b = before.pose, after.pose
			return {
				position = a.position:Lerp(b.position, t),
				yaw = lerpAngle(a.yaw, b.yaw, t),
				pitch = a.pitch + (b.pitch - a.pitch) * t,
				stance = b.stance,
				leanOffset = a.leanOffset + (b.leanOffset - a.leanOffset) * t,
			}
		end
	end
	return entries[#entries].pose
end

-- Where the player in `slot` was at `tick`, as others saw them (for AimWatch).
function Combat.poseAt(slot: number, tick: number): Pose?
	return poseAt(slot, tick)
end

-- The server tick the player in `slot` was seeing others at when sending
-- `input`, kept close to their usual delay (so it can't be used to backtrack).
local function viewedTick(slot: number, input: Input, serverTick: number): number
	local rewind = math.clamp(serverTick - input.viewTick / Protocol.VIEW_TICK_SCALE, 0, MAX_REWIND_TICKS)
	local usual = usualRewind[slot] or rewind
	rewind =
		math.clamp(rewind, math.max(usual - REWIND_TOLERANCE, 0), math.min(usual + REWIND_TOLERANCE, MAX_REWIND_TICKS))
	return serverTick - rewind
end
Combat.viewedTick = viewedTick

-- Distance along a ray (with a unit direction) to an oriented box, if it hits.
local function rayBox(origin: Vector3, direction: Vector3, cframe: CFrame, size: Vector3): number?
	local o = cframe:PointToObjectSpace(origin)
	local d = cframe:VectorToObjectSpace(direction)
	local near, far = -math.huge, math.huge

	-- Narrows [near, far] to where the ray is between one pair of box faces.
	local function slab(start: number, step: number, half: number): boolean
		if math.abs(step) < 1e-9 then
			return math.abs(start) <= half
		end
		local t1 = (-half - start) / step
		local t2 = (half - start) / step
		near = math.max(near, math.min(t1, t2))
		far = math.min(far, math.max(t1, t2))
		return near <= far
	end

	if
		not slab(o.X, d.X, size.X / 2)
		or not slab(o.Y, d.Y, size.Y / 2)
		or not slab(o.Z, d.Z, size.Z / 2)
		or far < 0
	then
		return nil
	end
	return math.max(near, 0)
end

local function damageFor(weapon: Weapons.Weapon, distance: number, part: string): number
	local falloff =
		math.clamp((distance - weapon.fullDamageRange) / (weapon.minDamageRange - weapon.fullDamageRange), 0, 1)
	local damage = weapon.damage * (1 + (weapon.minDamageMultiplier - 1) * falloff)
	if part == HEAD then
		damage *= weapon.headMultiplier
	elseif part ~= TORSO then
		damage *= weapon.limbMultiplier
	end
	return damage
end

local function applyDamage(victimSlot: number, epoch: number, attackerSlot: number, amount: number, part: string)
	local victim = lookup(victimSlot)
	local current = health[victimSlot]
	if not victim or not victim.alive or victim.epoch ~= epoch or not current or current <= 0 then
		return -- respawned or already dead while the bullet was in flight
	end
	local attacker = lookup(attackerSlot)
	local attackerPlayer = if attacker then attacker.player else nil
	local remaining = math.max(current - amount, 0)
	health[victimSlot] = remaining
	damaged:Fire(victim.player, attackerPlayer, amount, part)
	if remaining <= 0 then
		died:Fire(victim.player, attackerPlayer)
	end
end

-- Kills a player outright, as if by no one (a reset).
function Combat.kill(victimSlot: number)
	local victim = lookup(victimSlot)
	local current = health[victimSlot]
	if victim and current and current > 0 then
		applyDamage(victimSlot, victim.epoch, 0, current, TORSO)
	end
end

-- Damage to a player from something other than a bullet (see API.damage).
function Combat.hurt(victimSlot: number, amount: number)
	local victim = lookup(victimSlot)
	if victim and amount > 0 then
		applyDamage(victimSlot, victim.epoch, 0, amount, TORSO)
	end
end

local function hurtLiving(humanoid: Humanoid, amount: number)
	if humanoid.Parent and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
	end
end

local function latestPosition(slot: number): Vector3?
	local entries = history[slot]
	local last = entries and entries[#entries]
	return if last then last.pose.position else nil
end

-- Resolves a shot fired during `serverTick`.
function Combat.fire(shooterSlot: number, shot: Shot, input: Input, serverTick: number)
	local shooter = lookup(shooterSlot)
	if not shooter or not shooter.alive then
		return
	end
	local weapon = Weapons.default

	-- How far to rewind: what the shooter was seeing, kept close to their usual delay.
	local rewoundTick = viewedTick(shooterSlot, input, serverTick)

	local origin = Eye.position(shot.state, Eye.leanOffset(shot.state, world))
	local direction = Firearm.scatter(Firearm.direction(shot.yaw, shot.pitch), shot.spread, random)

	local worldHit = workspace:Raycast(origin, direction * weapon.range, bullets)
	local distance = if worldHit then worldHit.Distance else weapon.range
	local kind = if worldHit then Protocol.HitKind.World else Protocol.HitKind.Nothing
	local victimSlot: number? = nil
	local victimPart = ""

	for slot in health do
		local target = if slot ~= shooterSlot then lookup(slot) else nil
		local pose = if target and target.alive then poseAt(slot, rewoundTick) else nil
		if pose then
			-- Skip anyone the bullet passes nowhere near.
			local toBody = pose.position + Vector3.new(0, 2.5, 0) - origin
			local along = toBody:Dot(direction)
			if along > -4 and along < distance + 4 and (toBody - direction * along).Magnitude < 6 then
				for name, cframe in Body.pose(pose.position, pose.yaw, pose.pitch, pose.stance, pose.leanOffset) do
					local hit = rayBox(origin, direction, cframe, Body.SIZES[name])
					if hit and hit < distance then
						distance = hit
						victimSlot = slot
						victimPart = name
						kind = if name == HEAD then Protocol.HitKind.Head else Protocol.HitKind.Body
					end
				end
			end
		end
	end

	-- Nobody was in the way, but the bullet may have hit something else alive.
	local living: Humanoid? = nil
	if not victimSlot and worldHit then
		living = Living.humanoidOf(worldHit.Instance)
		if living then
			victimPart = worldHit.Instance.Name
			kind = if victimPart == HEAD then Protocol.HitKind.Head else Protocol.HitKind.Body
		end
	end

	local hitPoint = origin + direction * distance
	local effect = Protocol.encodeShot({ slot = shooterSlot, origin = origin, hit = hitPoint, kind = kind })
	remotes.shotResult:FireClient(shooter.player, effect)
	for slot in health do
		local listener = if slot ~= shooterSlot then lookup(slot) else nil
		local position = latestPosition(slot)
		if listener and position and (position - origin).Magnitude <= HEARING_RANGE then
			remotes.shots:FireClient(listener.player, effect)
		end
	end

	if living then
		local amount = damageFor(weapon, distance, victimPart)
		if weapon.instantDamage then
			hurtLiving(living, amount)
		else
			task.delay(distance / weapon.bulletSpeed, hurtLiving, living, amount)
		end
	elseif victimSlot then
		local victim = lookup(victimSlot)
		if victim then
			local amount = damageFor(weapon, distance, victimPart)
			local slot, epoch, part = victimSlot, victim.epoch, victimPart
			if weapon.instantDamage then
				applyDamage(slot, epoch, shooterSlot, amount, part)
			else
				-- The hit is decided now; the damage lands when the bullet would arrive.
				task.delay(distance / weapon.bulletSpeed, applyDamage, slot, epoch, shooterSlot, amount, part)
			end
		end
	end
end

return table.freeze(Combat)

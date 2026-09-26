--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The wire format between client and server. Messages are packed into buffers.
-- Everything coming from a client is checked field by field, and anything
-- malformed is rejected as a whole.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type Input = Types.Input
type State = Types.State

-- Another player as seen by the client.
export type Remote = {
	position: Vector3,
	yaw: number,
	pitch: number,
	stance: number,
	leanOffset: number,
}

export type Snapshot = {
	tick: number,
	players: { [number]: Remote }, -- keyed by slot
}

export type StateMessage = {
	epoch: number, -- changes whenever the server moves the player on its own (spawns, teleports)
	ack: number, -- the last input the server has processed
	state: State,
	health: number,
}

-- What a shot hit. Shooters get their own; nearby players get everyone's.
export type ShotEffect = {
	slot: number, -- who fired
	origin: Vector3,
	hit: Vector3,
	kind: number, -- see Protocol.HitKind
}

local M = Config.movement

local Protocol = {}

Protocol.Remotes = table.freeze({
	Input = "Input",
	State = "State",
	Snapshot = "Snapshot",
	ShotResult = "ShotResult",
	Shots = "Shots",
	Life = "Life",
})

Protocol.HitKind = table.freeze({
	Nothing = 0, -- flew out of range
	World = 1,
	Body = 2,
	Head = 3,
})

-- Inputs carry the view tick in eighths of a tick.
Protocol.VIEW_TICK_SCALE = 8

-- Each input packet repeats the last few inputs, so one lost packet costs nothing.
Protocol.MAX_INPUTS_PER_PACKET = 3

local INPUT_SIZE = 16
local STATE_SIZE = 66
local SHOT_SIZE = 26
local SNAPSHOT_HEADER_SIZE = 5
local SNAPSHOT_ENTRY_SIZE = 19
local ANGLE_SCALE = 32767 / math.pi
local UNIT_SCALE = 127
local TWO_PI = 2 * math.pi

local function packUnit(value: number): number
	return math.clamp(math.round(value * UNIT_SCALE), -UNIT_SCALE, UNIT_SCALE)
end

local function packYaw(yaw: number): number
	return math.round(((yaw + math.pi) % TWO_PI - math.pi) * ANGLE_SCALE)
end

local function packPitch(pitch: number): number
	return math.round(math.clamp(pitch, -M.maxPitch, M.maxPitch) * ANGLE_SCALE)
end

-- Rounds an input exactly the way the wire does. The client predicts with the
-- rounded input, so its prediction matches what the server computes.
function Protocol.quantizeInput(input: Input): Input
	return {
		seq = input.seq,
		moveX = packUnit(input.moveX) / UNIT_SCALE,
		moveZ = packUnit(input.moveZ) / UNIT_SCALE,
		yaw = packYaw(input.yaw) / ANGLE_SCALE,
		pitch = packPitch(input.pitch) / ANGLE_SCALE,
		buttons = input.buttons,
		stance = input.stance,
		viewTick = math.clamp(math.floor(input.viewTick), 0, 0xFFFFFFFF),
	}
end

function Protocol.encodeInputs(inputs: { Input }): buffer
	local count = #inputs
	local data = buffer.create(1 + count * INPUT_SIZE)
	buffer.writeu8(data, 0, count)
	for index, input in inputs do
		local offset = 1 + (index - 1) * INPUT_SIZE
		buffer.writeu32(data, offset, input.seq)
		buffer.writei8(data, offset + 4, packUnit(input.moveX))
		buffer.writei8(data, offset + 5, packUnit(input.moveZ))
		buffer.writei16(data, offset + 6, packYaw(input.yaw))
		buffer.writei16(data, offset + 8, packPitch(input.pitch))
		buffer.writeu8(data, offset + 10, input.buttons)
		buffer.writeu8(data, offset + 11, input.stance)
		buffer.writeu32(data, offset + 12, math.clamp(math.floor(input.viewTick), 0, 0xFFFFFFFF))
	end
	return data
end

-- Runs on the server with data straight from a client, so it trusts nothing.
function Protocol.decodeInputs(data: unknown): { Input }?
	if typeof(data) ~= "buffer" then
		return nil
	end
	local length = buffer.len(data)
	if length < 1 then
		return nil
	end
	local count = buffer.readu8(data, 0)
	if count < 1 or count > Protocol.MAX_INPUTS_PER_PACKET or length ~= 1 + count * INPUT_SIZE then
		return nil
	end

	local maxPitch = packPitch(M.maxPitch)
	local inputs = table.create(count)
	for index = 1, count do
		local offset = 1 + (index - 1) * INPUT_SIZE
		local moveX = buffer.readi8(data, offset + 4)
		local moveZ = buffer.readi8(data, offset + 5)
		local yaw = buffer.readi16(data, offset + 6)
		local pitch = buffer.readi16(data, offset + 8)
		local buttons = buffer.readu8(data, offset + 10)
		local stance = buffer.readu8(data, offset + 11)
		if
			moveX < -UNIT_SCALE
			or moveZ < -UNIT_SCALE
			or yaw < -32767
			or math.abs(pitch) > maxPitch
			or bit32.band(buttons, bit32.bnot(Types.ALL_BUTTONS)) ~= 0
			or stance > Types.Stance.Prone
		then
			return nil
		end
		inputs[index] = {
			seq = buffer.readu32(data, offset),
			moveX = moveX / UNIT_SCALE,
			moveZ = moveZ / UNIT_SCALE,
			yaw = yaw / ANGLE_SCALE,
			pitch = pitch / ANGLE_SCALE,
			buttons = buttons,
			stance = stance,
			viewTick = buffer.readu32(data, offset + 12),
		}
	end
	return inputs
end

local function writeVector(data: buffer, offset: number, vector: Vector3)
	buffer.writef32(data, offset, vector.X)
	buffer.writef32(data, offset + 4, vector.Y)
	buffer.writef32(data, offset + 8, vector.Z)
end

local function readVector(data: buffer, offset: number): Vector3
	return Vector3.new(buffer.readf32(data, offset), buffer.readf32(data, offset + 4), buffer.readf32(data, offset + 8))
end

-- The player's own authoritative state, sent back so the client can check its
-- prediction. Recoil and bloom are sent at full precision because the client
-- must reproduce them exactly.
function Protocol.encodeState(epoch: number, ack: number, state: State, health: number): buffer
	local data = buffer.create(STATE_SIZE)
	buffer.writeu8(data, 0, epoch)
	buffer.writeu32(data, 1, ack)
	writeVector(data, 5, state.position)
	writeVector(data, 17, state.velocity)
	local flags = state.stance * 2
		+ (if state.grounded then 1 else 0)
		+ (if state.sprinting then 8 else 0)
		+ (if state.aiming then 16 else 0)
		+ (if state.triggerHeld then 32 else 0)
		+ (if state.canShoot then 0 else 64)
	buffer.writeu8(data, 29, flags)
	buffer.writei8(data, 30, state.leanTicks)
	buffer.writeu8(data, 31, state.jumpCooldown)
	buffer.writeu8(data, 32, state.ammo)
	buffer.writeu16(data, 33, state.reserve)
	buffer.writeu8(data, 35, state.fireCooldown)
	buffer.writeu16(data, 36, state.reloadTicks)
	buffer.writeu8(data, 38, state.raiseTicks)
	buffer.writef64(data, 39, state.recoilPitch)
	buffer.writef64(data, 47, state.recoilYaw)
	buffer.writef64(data, 55, state.bloom)
	buffer.writeu16(data, 63, math.clamp(math.ceil(health), 0, 0xFFFF))
	buffer.writeu8(data, 65, state.drawTicks)
	return data
end

function Protocol.decodeState(data: unknown): StateMessage?
	if typeof(data) ~= "buffer" or buffer.len(data) ~= STATE_SIZE then
		return nil
	end
	local flags = buffer.readu8(data, 29)
	return {
		epoch = buffer.readu8(data, 0),
		ack = buffer.readu32(data, 1),
		state = {
			position = readVector(data, 5),
			velocity = readVector(data, 17),
			grounded = bit32.btest(flags, 1),
			stance = bit32.band(bit32.rshift(flags, 1), 3),
			sprinting = bit32.btest(flags, 8),
			aiming = bit32.btest(flags, 16),
			leanTicks = buffer.readi8(data, 30),
			jumpCooldown = buffer.readu8(data, 31),
			yaw = 0,
			pitch = 0,
			ammo = buffer.readu8(data, 32),
			reserve = buffer.readu16(data, 33),
			fireCooldown = buffer.readu8(data, 35),
			reloadTicks = buffer.readu16(data, 36),
			drawTicks = buffer.readu8(data, 65),
			raiseTicks = buffer.readu8(data, 38),
			triggerHeld = bit32.btest(flags, 32),
			canShoot = not bit32.btest(flags, 64),
			recoilPitch = buffer.readf64(data, 39),
			recoilYaw = buffer.readf64(data, 47),
			bloom = buffer.readf64(data, 55),
		},
		health = buffer.readu16(data, 63),
	}
end

function Protocol.encodeShot(effect: ShotEffect): buffer
	local data = buffer.create(SHOT_SIZE)
	buffer.writeu8(data, 0, effect.slot)
	writeVector(data, 1, effect.origin)
	writeVector(data, 13, effect.hit)
	buffer.writeu8(data, 25, effect.kind)
	return data
end

function Protocol.decodeShot(data: unknown): ShotEffect?
	if typeof(data) ~= "buffer" or buffer.len(data) ~= SHOT_SIZE then
		return nil
	end
	return {
		slot = buffer.readu8(data, 0),
		origin = readVector(data, 1),
		hit = readVector(data, 13),
		kind = buffer.readu8(data, 25),
	}
end

function Protocol.encodeSnapshot(tick: number, players: { [number]: Remote }): buffer
	local count = 0
	for _ in players do
		count += 1
	end
	local data = buffer.create(SNAPSHOT_HEADER_SIZE + count * SNAPSHOT_ENTRY_SIZE)
	buffer.writeu32(data, 0, tick)
	buffer.writeu8(data, 4, count)
	local offset = SNAPSHOT_HEADER_SIZE
	for slot, remote in players do
		buffer.writeu8(data, offset, slot)
		writeVector(data, offset + 1, remote.position)
		buffer.writei16(data, offset + 13, packYaw(remote.yaw))
		buffer.writei16(data, offset + 15, packPitch(remote.pitch))
		buffer.writeu8(data, offset + 17, remote.stance)
		buffer.writei8(data, offset + 18, packUnit(remote.leanOffset / M.leanDistance))
		offset += SNAPSHOT_ENTRY_SIZE
	end
	return data
end

function Protocol.decodeSnapshot(data: unknown): Snapshot?
	if typeof(data) ~= "buffer" or buffer.len(data) < SNAPSHOT_HEADER_SIZE then
		return nil
	end
	local count = buffer.readu8(data, 4)
	if buffer.len(data) ~= SNAPSHOT_HEADER_SIZE + count * SNAPSHOT_ENTRY_SIZE then
		return nil
	end
	local players: { [number]: Remote } = {}
	local offset = SNAPSHOT_HEADER_SIZE
	for _ = 1, count do
		players[buffer.readu8(data, offset)] = {
			position = readVector(data, offset + 1),
			yaw = buffer.readi16(data, offset + 13) / ANGLE_SCALE,
			pitch = buffer.readi16(data, offset + 15) / ANGLE_SCALE,
			stance = buffer.readu8(data, offset + 17),
			leanOffset = buffer.readi8(data, offset + 18) / UNIT_SCALE * M.leanDistance,
		}
		offset += SNAPSHOT_ENTRY_SIZE
	end
	return { tick = buffer.readu32(data, 0), players = players }
end

return table.freeze(Protocol)

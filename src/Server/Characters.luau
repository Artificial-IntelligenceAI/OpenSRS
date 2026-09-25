--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Server-authoritative characters. Clients only send inputs; the server runs
-- the movement simulation and tells each client where it really is.
--
-- Anti-speedhack: every player earns one input per server tick and can bank a
-- few. Sending inputs faster than the tick rate just makes them queue up.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Eye = require(Shared.Eye)
local Movement = require(Shared.Movement)
local Protocol = require(Shared.Protocol)
local Types = require(Shared.Types)
local Flags = require(script.Parent.Flags)
local Remotes = require(script.Parent.Remotes)
local Visibility = require(script.Parent.Visibility)

type Input = Types.Input
type State = Types.State

type Record = {
	player: Player,
	slot: number,
	state: State?, -- nil until spawned
	epoch: number,
	dirty: boolean, -- the client must be told about a server-side change
	nextSeq: number?, -- the next input to process; nil until the first one arrives
	inputs: { [number]: Input },
	lastInput: Input?,
	tokens: number, -- inputs this player may process right now
	packetBudget: number,
	droppedPackets: number,
	streamedAround: Vector3?,
}

local DT = 1 / Config.tickRate
local MAX_TOKENS = 8 -- how far (in ticks) a player can fall behind before the server moves them on
local MAX_AHEAD = 64 -- inputs further ahead than this are ignored
local MAX_TICKS_PER_FRAME = 4
local PACKET_BUDGET_PER_TICK = 2 -- 120 input packets a second
local MAX_PACKET_BUDGET = 30
local FLOOD_THRESHOLD = 600 -- dropped packets before a flag is raised
local STREAM_CHECK_TICKS = 30
local STREAM_DISTANCE = 32
local FALL_LIMIT = -500
local VISIBILITY_GROUPS = 4 -- each player's visibility is checked every 4 ticks (15 a second)

local Characters = {}

local records: { [Player]: Record } = {}
local slots: { [number]: Player } = {}
local world = Movement.newWorld({})
local remotes: Remotes.Remotes
local tickCount = 0

local function claimSlot(): number?
	for slot = 1, 255 do
		if not slots[slot] then
			return slot
		end
	end
	return nil
end

local function spawnPoint(): Vector3
	local spawns: { SpawnLocation } = {}
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			table.insert(spawns, descendant)
		end
	end
	if #spawns == 0 then
		return Vector3.new(0, 5, 0)
	end
	local chosen = spawns[math.random(#spawns)]
	return chosen.Position + Vector3.new(0, chosen.Size.Y / 2 + 0.1, 0)
end

local function streamAround(record: Record, position: Vector3)
	if not workspace.StreamingEnabled then
		return
	end
	record.streamedAround = position
	task.spawn(function()
		pcall(record.player.RequestStreamAroundAsync, record.player, position)
	end)
end

local function spawn(record: Record)
	local position = spawnPoint()
	if workspace.StreamingEnabled then
		-- Make sure the map around the spawn has reached the client first.
		record.streamedAround = position
		pcall(record.player.RequestStreamAroundAsync, record.player, position)
	end
	if records[record.player] ~= record then
		return
	end
	record.state = Movement.newState(position, 0)
	record.epoch = (record.epoch + 1) % 256
	record.dirty = true
end

local function onInput(player: Player, data: unknown)
	local record = records[player]
	if not record or not record.state then
		return
	end

	if record.packetBudget < 1 then
		record.droppedPackets += 1
		if record.droppedPackets % FLOOD_THRESHOLD == 0 then
			Flags.raise(player, "InputFlood", `{record.droppedPackets} input packets dropped`)
		end
		return
	end
	record.packetBudget -= 1

	local inputs = Protocol.decodeInputs(data)
	if not inputs then
		Flags.raise(player, "MalformedInput", "input packet failed validation")
		return
	end

	for _, input in inputs do
		local nextSeq: number = record.nextSeq or input.seq
		record.nextSeq = nextSeq
		if input.seq >= nextSeq and input.seq < nextSeq + MAX_AHEAD then
			record.inputs[input.seq] = input
		end
	end
end

local function simulate(record: Record)
	local state = record.state
	if not state then
		return
	end

	local processed = false
	local nextSeq = record.nextSeq
	if nextSeq then
		record.tokens = math.min(record.tokens + 1, MAX_TOKENS)
		record.packetBudget = math.min(record.packetBudget + PACKET_BUDGET_PER_TICK, MAX_PACKET_BUDGET)

		while record.tokens >= 1 do
			local input: Input
			local queued = record.inputs[nextSeq]
			if queued then
				record.inputs[nextSeq] = nil
				input = queued
			else
				local lastInput = record.lastInput
				if record.tokens < MAX_TOKENS or not lastInput then
					break
				end
				-- The client has gone quiet. Keep simulating with its last input so
				-- going silent can't freeze the character, such as mid-air.
				input = table.clone(lastInput)
				input.seq = nextSeq
			end

			state = Movement.step(state, input, world)
			record.lastInput = input
			record.tokens -= 1
			nextSeq += 1
			processed = true
		end
		record.nextSeq = nextSeq
	end

	if state.position.Y < FALL_LIMIT then
		-- Fell out of the map. Stop simulating until the respawn is done.
		record.state = nil
		task.spawn(spawn, record)
		return
	end
	record.state = state

	-- Always answer a spawn, even before the first input, since the client waits for it.
	if processed or record.dirty then
		record.dirty = false
		local ack = (nextSeq or 1) - 1
		remotes.state:FireClient(record.player, Protocol.encodeState(record.epoch, ack, state))
	end

	if tickCount % STREAM_CHECK_TICKS == 0 then
		local streamedAround = record.streamedAround
		if not streamedAround or (streamedAround - state.position).Magnitude > STREAM_DISTANCE then
			streamAround(record, state.position)
		end
	end
end

local function updateVisibility()
	local subjects: { Visibility.Subject } = {}
	for _, record in records do
		local state = record.state
		if state then
			table.insert(subjects, { slot = record.slot, state = state, leanOffset = Eye.leanOffset(state, world) })
		end
	end
	Visibility.update(subjects, os.clock(), tickCount % VISIBILITY_GROUPS, VISIBILITY_GROUPS)
end

local function sendSnapshots()
	local now = os.clock()
	local remote: { [Player]: Protocol.Remote } = {}
	for player, record in records do
		local state = record.state
		if state then
			remote[player] = {
				position = state.position,
				yaw = state.yaw,
				pitch = state.pitch,
				stance = state.stance,
				leanOffset = Eye.leanOffset(state, world),
			}
		end
	end

	for viewer, viewerRecord in records do
		local players: { [number]: Protocol.Remote } = {}
		for other, entry in remote do
			local slot = records[other].slot
			if other ~= viewer and Visibility.canSee(viewerRecord.slot, slot, now) then
				players[slot] = entry
			end
		end
		remotes.snapshot:FireClient(viewer, Protocol.encodeSnapshot(tickCount, players))
	end
end

local function tick()
	tickCount += 1
	for _, record in records do
		simulate(record)
	end
	updateVisibility()
	if tickCount % Config.snapshotInterval == 0 then
		sendSnapshots()
	end
end

local function onPlayerAdded(player: Player)
	local slot = claimSlot()
	if not slot then
		player:Kick("This server is full.")
		return
	end
	slots[slot] = player

	-- OpenSRS runs its own characters; Roblox's are never used.
	if player.Character then
		player.Character:Destroy()
	end
	player.CharacterAdded:Connect(function(character)
		character:Destroy()
	end)

	local record: Record = {
		player = player,
		slot = slot,
		state = nil,
		epoch = 0,
		dirty = false,
		nextSeq = nil,
		inputs = {},
		lastInput = nil,
		tokens = 0,
		packetBudget = MAX_PACKET_BUDGET,
		droppedPackets = 0,
		streamedAround = nil,
	}
	records[player] = record
	task.spawn(spawn, record)
end

local function onPlayerRemoving(player: Player)
	local record = records[player]
	if record then
		records[player] = nil
		slots[record.slot] = nil
		Visibility.forget(record.slot)
	end
end

function Characters.start(created: Remotes.Remotes)
	remotes = created
	Players.CharacterAutoLoads = false
	remotes.input.OnServerEvent:Connect(onInput)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(frameTime)
		accumulator += frameTime
		local ticks = 0
		while accumulator >= DT and ticks < MAX_TICKS_PER_FRAME do
			accumulator -= DT
			ticks += 1
			tick()
		end
		if ticks == MAX_TICKS_PER_FRAME then
			accumulator = 0
		end
	end)
end

return table.freeze(Characters)

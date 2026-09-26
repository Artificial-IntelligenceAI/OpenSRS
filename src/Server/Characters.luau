--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Server-authoritative characters. Clients only send inputs; the server runs
-- the movement and weapon simulation and tells each client where it really is.
--
-- Anti-speedhack: every player earns one input per server tick and can bank a
-- few. Sending inputs faster than the tick rate just makes them queue up, and
-- a queue that grows too long loses its oldest inputs.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Eye = require(Shared.Eye)
local Movement = require(Shared.Movement)
local Protocol = require(Shared.Protocol)
local Simulation = require(Shared.Simulation)
local Teammates = require(Shared.Teammates)
local Types = require(Shared.Types)
local Weapons = require(Shared.Weapons)
local Combat = require(script.Parent.Combat)
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
	canShoot: boolean, -- what the game last set with API.setCanShoot; kept through respawns
	lastSeq: number?, -- the last real input processed; nil until the first one
	pending: { Input }, -- received but not yet processed, oldest first
	lastInput: Input?,
	tokens: number, -- inputs this player may process right now
	packetBudget: number,
	droppedPackets: number,
	streaming: boolean, -- a streaming request is in flight
}

local DT = 1 / Config.tickRate
local MAX_TOKENS = 8 -- how far (in ticks) a player can fall behind before the server moves them on
local MAX_PENDING = 12 -- queued inputs beyond this are dropped, oldest first
local MAX_TICKS_PER_FRAME = 4
local PACKET_BUDGET_PER_TICK = 2 -- 120 input packets a second
local MAX_PACKET_BUDGET = 30
local FLOOD_THRESHOLD = 600 -- dropped packets before a flag is raised
local STREAM_REFRESH_TICKS = 60 -- streaming requests expire, so they're renewed every second
local TELEPORT_STREAM_WAIT = 0.3 -- seconds a teleport waits for the map there to load before going anyway
local RESEND_TICKS = 10 -- how often to repeat the spawn until the client starts sending inputs
local FALL_LIMIT = -500
local VISIBILITY_GROUPS = 4 -- each player's visibility is checked every 4 ticks (15 a second)
-- Buttons a filler input must never repeat: a silent client shouldn't keep shooting.
local ONE_SHOT_BUTTONS = Types.Buttons.Fire + Types.Buttons.Reload + Types.Buttons.Jump

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

-- Players have no Roblox character, so Roblox doesn't know where to stream the
-- map for them. Ask for it around their position, and keep asking.
local function streamAround(record: Record, position: Vector3)
	if not workspace.StreamingEnabled or record.streaming then
		return
	end
	record.streaming = true
	pcall(record.player.RequestStreamAroundAsync, record.player, position)
	record.streaming = false
end

local function spawn(record: Record)
	local position = spawnPoint()
	-- Make sure the map around the spawn has reached the client first.
	streamAround(record, position)
	if records[record.player] ~= record then
		return
	end
	local state = Simulation.newState(position, 0, Weapons.default)
	state.canShoot = record.canShoot
	record.state = state
	record.epoch = (record.epoch + 1) % 256
	record.dirty = true
	record.pending = {}
	Combat.spawned(record.slot)
	remotes.life:FireClient(record.player, true)
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

	local pending = record.pending
	for _, input in inputs do
		local lastSeq = record.lastSeq
		if lastSeq and input.seq <= lastSeq then
			continue -- already processed; packets repeat recent inputs
		end
		local index = #pending + 1
		while index > 1 and pending[index - 1].seq > input.seq do
			index -= 1
		end
		if index > 1 and pending[index - 1].seq == input.seq then
			continue
		end
		table.insert(pending, index, input)
	end
	-- A backlog (from a hitch, or someone trying to bank movement) loses its
	-- oldest inputs. Dropping inputs never helps anyone move faster.
	while #pending > MAX_PENDING do
		table.remove(pending, 1)
	end
end

local function simulate(record: Record)
	local state = record.state
	if not state then
		return
	end

	record.packetBudget = math.min(record.packetBudget + PACKET_BUDGET_PER_TICK, MAX_PACKET_BUDGET)

	local processed = false
	local started = record.lastSeq ~= nil or #record.pending > 0
	if started then
		record.tokens = math.min(record.tokens + 1, MAX_TOKENS)
		while record.tokens >= 1 do
			local input: Input
			local queued = table.remove(record.pending, 1)
			if queued then
				input = queued
				record.lastSeq = queued.seq
				Combat.observe(record.slot, queued, tickCount)
			else
				local lastInput = record.lastInput
				if record.tokens < MAX_TOKENS or not lastInput then
					break
				end
				-- The client has gone quiet. Keep simulating with its last input so
				-- going silent can't freeze the character, such as mid-air. This
				-- doesn't count as processing any input, so late ones still apply.
				input = table.clone(lastInput)
				input.buttons = bit32.band(input.buttons, bit32.bnot(ONE_SHOT_BUTTONS))
			end

			local shot
			state, shot = Simulation.step(state, input, world, Weapons.default)
			record.lastInput = input
			record.tokens -= 1
			processed = true
			if shot then
				record.state = state
				Combat.fire(record.slot, shot, input, tickCount)
			end
		end
	end

	if state.position.Y < FALL_LIMIT then
		-- Fell out of the map. Stop simulating until the respawn is done.
		record.state = nil
		task.spawn(spawn, record)
		return
	end
	record.state = state

	-- The spawn message can be lost (it's unreliable, and the client may still be
	-- loading), so keep repeating it until the client starts sending inputs.
	local waitingForClient = not started and (tickCount + record.slot) % RESEND_TICKS == 0
	if processed or record.dirty or waitingForClient then
		record.dirty = false
		local message = Protocol.encodeState(record.epoch, record.lastSeq or 0, state, Combat.health(record.slot))
		remotes.state:FireClient(record.player, message)
	end

	if (tickCount + record.slot) % STREAM_REFRESH_TICKS == 0 then
		task.spawn(streamAround, record, state.position)
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

	for player, entry in remote do
		Combat.record(tickCount, records[player].slot, entry)
	end

	for viewer, viewerRecord in records do
		local players: { [number]: Protocol.Remote } = {}
		for other, entry in remote do
			local slot = records[other].slot
			local shown = Visibility.canSee(viewerRecord.slot, slot, now)
				or (Config.teammateHighlights and Teammates.are(viewer, other))
			if other ~= viewer and shown then
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
	player:SetAttribute(Teammates.SLOT_ATTRIBUTE, slot)

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
		canShoot = true,
		lastSeq = nil,
		pending = {},
		lastInput = nil,
		tokens = 0,
		packetBudget = MAX_PACKET_BUDGET,
		droppedPackets = 0,
		streaming = false,
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
		Combat.forget(record.slot)
	end
end

local function lookup(slot: number): Combat.Target?
	local player = slots[slot]
	local record = player and records[player]
	if not record then
		return nil
	end
	return { player = record.player, epoch = record.epoch, alive = record.state ~= nil }
end

local function onDied(victim: Player)
	local record = records[victim]
	if not record or not record.state then
		return
	end
	record.state = nil
	remotes.life:FireClient(victim, false)
	task.delay(Config.respawnTime, function()
		if records[victim] == record and record.state == nil then
			spawn(record)
		end
	end)
end

-- Where a player's character stands, if they're alive.
function Characters.position(player: Player): Vector3?
	local record = records[player]
	local state = record and record.state
	return if state then state.position else nil
end

-- The slot a player's character uses, if they have one.
function Characters.slotOf(player: Player): number?
	local record = records[player]
	return if record then record.slot else nil
end

-- Lets a player shoot or not, until changed again (respawning doesn't reset
-- it). Their client is told, so it doesn't show shots that won't happen.
function Characters.setCanShoot(player: Player, allowed: boolean)
	local record = records[player]
	if not record then
		return
	end
	record.canShoot = allowed
	local state = record.state
	if state and state.canShoot ~= allowed then
		local changed = table.clone(state)
		changed.canShoot = allowed
		record.state = changed
		record.dirty = true
	end
end

-- Moves a living player's character to `position` (where their feet go),
-- stopping them. Their client starts over from there rather than sliding.
-- Returns whether they were moved.
function Characters.teleport(player: Player, position: Vector3): boolean
	local record = records[player]
	if not record or not record.state then
		return false
	end
	-- Give the map there a moment to reach the client, but don't hold the
	-- teleport up for it: loading can take over a second even for places the
	-- player has just been.
	local loaded = false
	task.spawn(function()
		streamAround(record, position)
		loaded = true
	end)
	local waited = 0
	while not loaded and waited < TELEPORT_STREAM_WAIT do
		waited += task.wait()
	end
	local state = record.state
	if records[player] ~= record or not state then
		return false
	end
	local moved = table.clone(state)
	moved.position = position
	moved.velocity = Vector3.zero
	record.state = moved
	record.epoch = (record.epoch + 1) % 256 -- the client sees a new epoch and starts over from the server's state
	record.dirty = true
	record.pending = {}
	return true
end

function Characters.start(created: Remotes.Remotes)
	remotes = created
	Combat.start(remotes, lookup)
	Combat.Died:Connect(onDied)
	Players.CharacterAutoLoads = false
	remotes.input.OnServerEvent:Connect(onInput)
	-- Roblox's menu Reset button: the player dies and respawns as usual. Only a
	-- living player can, so it can't be used to skip a respawn wait.
	remotes.reset.OnServerEvent:Connect(function(player: Player)
		local record = records[player]
		if record and record.state then
			Combat.kill(record.slot)
		end
	end)
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

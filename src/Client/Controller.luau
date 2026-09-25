--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The local player's side of movement. It predicts movement instantly with the
-- same simulation the server runs, sends its inputs, and when the server's
-- answer disagrees, it rewinds to the server's state and replays the inputs
-- the server hasn't processed yet.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Eye = require(Shared.Eye)
local Movement = require(Shared.Movement)
local Protocol = require(Shared.Protocol)
local Types = require(Shared.Types)
local InputMap = require(script.Parent.InputMap)
local Puppets = require(script.Parent.Puppets)

type Input = Types.Input
type State = Types.State
type HistoryEntry = { input: Input, state: State }

local DT = 1 / Config.tickRate
local MAX_TICKS_PER_FRAME = 8
local TOLERANCE = 1e-3
local CORRECTION_DECAY = 15 -- how fast a visible correction fades out
local EYE_SMOOTHING = 12 -- how fast the camera follows stance changes
local LEAN_ROLL = math.rad(12)

local Controller = {}

local function matches(a: State, b: State): boolean
	return (a.position - b.position).Magnitude < TOLERANCE
		and (a.velocity - b.velocity).Magnitude < TOLERANCE
		and a.grounded == b.grounded
		and a.stance == b.stance
		and a.leanTicks == b.leanTicks
		and a.jumpCooldown == b.jumpCooldown
end

function Controller.start()
	local remotes = script.Parent.Parent:WaitForChild("Remotes")
	local inputRemote = remotes:WaitForChild(Protocol.Remotes.Input) :: UnreliableRemoteEvent
	local stateRemote = remotes:WaitForChild(Protocol.Remotes.State) :: UnreliableRemoteEvent
	local snapshotRemote = remotes:WaitForChild(Protocol.Remotes.Snapshot) :: UnreliableRemoteEvent

	local world = Movement.newWorld({ Puppets.folder })
	local camera = workspace.CurrentCamera

	local state: State? = nil
	local previous: State? = nil
	local epoch = -1
	local seq = 0
	local history: { [number]: HistoryEntry } = {}
	local recent: { Input } = {}
	local accumulator = 0
	local correction = Vector3.zero
	local eyeOffset: Vector3? = nil

	stateRemote.OnClientEvent:Connect(function(data: unknown)
		local message = Protocol.decodeState(data)
		if not message then
			return
		end
		local server = message.state
		local predicted = state

		if predicted == nil or message.epoch ~= epoch then
			-- Spawned or moved by the server: start over from its state.
			epoch = message.epoch
			history = {}
			server.yaw, server.pitch = InputMap.look()
			state = server
			previous = server
			correction = Vector3.zero
			return
		end

		for entrySeq in history do
			if entrySeq < message.ack then
				history[entrySeq] = nil
			end
		end
		local entry = history[message.ack]
		history[message.ack] = nil
		if entry and matches(entry.state, server) then
			return
		end

		-- Misprediction: replay everything the server hasn't processed yet.
		local replayed = server
		local basis = if entry then entry.input else predicted
		replayed.yaw, replayed.pitch = basis.yaw, basis.pitch
		for replaySeq = message.ack + 1, seq do
			local pending = history[replaySeq]
			if pending then
				replayed = Movement.step(replayed, pending.input, world)
				pending.state = replayed
			end
		end
		correction += predicted.position - replayed.position
		state = replayed
	end)

	snapshotRemote.OnClientEvent:Connect(Puppets.receive)
	InputMap.start()

	task.delay(5, function()
		if state == nil then
			warn("OpenSRS: still waiting for the server to spawn this player after 5 seconds.")
		end
	end)

	RunService:BindToRenderStep("OpenSRS", Enum.RenderPriority.Camera.Value + 1, function(frameTime: number)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		camera.CameraType = Enum.CameraType.Scriptable
		InputMap.updateLook()

		local current = state
		if current then
			accumulator += frameTime
			local ticks = 0
			while accumulator >= DT and ticks < MAX_TICKS_PER_FRAME do
				accumulator -= DT
				ticks += 1
				seq += 1
				local input = Protocol.quantizeInput(InputMap.sample(seq))
				previous = current
				current = Movement.step(current, input, world)
				history[seq] = { input = input, state = current }
				table.insert(recent, input)
				if #recent > Protocol.MAX_INPUTS_PER_PACKET then
					table.remove(recent, 1)
				end
				inputRemote:FireServer(Protocol.encodeInputs(recent))
			end
			if ticks == MAX_TICKS_PER_FRAME then
				accumulator = 0
			end
			state = current

			-- Draw between the last two ticks, with any correction fading out.
			local last = previous or current
			correction *= math.exp(-CORRECTION_DECAY * frameTime)
			local yaw, pitch = InputMap.look()
			local shown = table.clone(current)
			shown.position = last.position:Lerp(current.position, accumulator / DT) + correction
			shown.yaw = yaw

			local leanOffset = Eye.leanOffset(shown, world)
			local target = Eye.position(shown, leanOffset) - shown.position
			local smoothed = eyeOffset or target
			smoothed = smoothed:Lerp(target, 1 - math.exp(-EYE_SMOOTHING * frameTime))
			eyeOffset = smoothed

			local roll = LEAN_ROLL * leanOffset / Config.movement.leanDistance
			camera.CFrame = CFrame.new(shown.position + smoothed)
				* CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(pitch, 0, 0)
				* CFrame.Angles(0, 0, -roll)
		end

		Puppets.render()
	end)
end

return table.freeze(Controller)

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The local player's side of the simulation. It predicts movement and shooting
-- instantly with the same code the server runs, sends its inputs, and when the
-- server's answer disagrees, it rewinds to the server's state and replays the
-- inputs the server hasn't processed yet. Hits are only ever decided by the
-- server; the client just shows them.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Eye = require(Shared.Eye)
local Firearm = require(Shared.Firearm)
local Movement = require(Shared.Movement)
local Protocol = require(Shared.Protocol)
local Simulation = require(Shared.Simulation)
local Types = require(Shared.Types)
local Weapons = require(Shared.Weapons)
local Casings = require(script.Parent.Casings)
local Effects = require(script.Parent.Effects)
local Hud = require(script.Parent.Hud)
local Impacts = require(script.Parent.Impacts)
local InputMap = require(script.Parent.InputMap)
local Puppets = require(script.Parent.Puppets)
local Sounds = require(script.Parent.Sounds)
local Viewmodel = require(script.Parent.Viewmodel)

type Input = Types.Input
type State = Types.State
type HistoryEntry = { input: Input, state: State }

local DT = 1 / Config.tickRate
local MAX_TICKS_PER_FRAME = 8
local TOLERANCE = 1e-3
local CORRECTION_DECAY = 15 -- how fast a visible correction fades out
local EYE_SMOOTHING = 12 -- how fast the camera follows stance changes
local LEAN_ROLL = math.rad(12)
local HIP_FOV = 70
local AIM_FOV = 64 -- aiming barely zooms
local FOV_SPEED = 14
local HANDS = Vector3.new(0.3, -0.7, -1.2) -- where the player's own gun is heard, from their view
local DISTANT_SHOT = 200 -- studs beyond which others' shots use the distant sound
local NEAR_MISS = 4 -- studs a bullet must pass within to be heard going by

local Controller = {}

local weapon = Weapons.default
local random = Random.new() -- only for how predicted tracers look; the server decides real spread

local function matches(a: State, b: State): boolean
	return (a.position - b.position).Magnitude < TOLERANCE
		and (a.velocity - b.velocity).Magnitude < TOLERANCE
		and a.grounded == b.grounded
		and a.stance == b.stance
		and a.sprinting == b.sprinting
		and a.aiming == b.aiming
		and a.leanTicks == b.leanTicks
		and a.jumpCooldown == b.jumpCooldown
		and a.ammo == b.ammo
		and a.reserve == b.reserve
		and a.fireCooldown == b.fireCooldown
		and a.reloadTicks == b.reloadTicks
		and a.drawTicks == b.drawTicks
		and a.raiseTicks == b.raiseTicks
		and a.triggerHeld == b.triggerHeld
		and math.abs(a.recoilPitch - b.recoilPitch) < TOLERANCE
		and math.abs(a.recoilYaw - b.recoilYaw) < TOLERANCE
		and math.abs(a.bloom - b.bloom) < TOLERANCE
end

-- Shows where a shot landed: a hole and a burst of particles, and its sound.
local function landed(shot: Protocol.ShotEffect)
	if shot.kind == Protocol.HitKind.World then
		Impacts.world(shot.origin, shot.hit)
		Sounds.at(weapon.name, Sounds.Cues.ImpactWorld, shot.hit)
	elseif shot.kind == Protocol.HitKind.Body or shot.kind == Protocol.HitKind.Head then
		Impacts.body(shot.origin, shot.hit)
		Sounds.at(weapon.name, Sounds.Cues.ImpactBody, shot.hit)
	end
end

function Controller.start()
	local remotes = script.Parent.Parent:WaitForChild("Remotes")
	local inputRemote = remotes:WaitForChild(Protocol.Remotes.Input) :: UnreliableRemoteEvent
	local stateRemote = remotes:WaitForChild(Protocol.Remotes.State) :: UnreliableRemoteEvent
	local snapshotRemote = remotes:WaitForChild(Protocol.Remotes.Snapshot) :: UnreliableRemoteEvent
	local shotResultRemote = remotes:WaitForChild(Protocol.Remotes.ShotResult) :: RemoteEvent
	local shotsRemote = remotes:WaitForChild(Protocol.Remotes.Shots) :: UnreliableRemoteEvent
	local lifeRemote = remotes:WaitForChild(Protocol.Remotes.Life) :: RemoteEvent

	local world = Movement.newWorld({ Puppets.folder, Effects.folder })
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
	local health = 0
	local fieldOfView = HIP_FOV
	local muzzle = Vector3.zero

	stateRemote.OnClientEvent:Connect(function(data: unknown)
		local message = Protocol.decodeState(data)
		if not message then
			return
		end
		health = message.health
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
			Viewmodel.show(true)
			Hud.setAlive(true)
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
				replayed = Simulation.step(replayed, pending.input, world, weapon)
				pending.state = replayed
			end
		end
		correction += predicted.position - replayed.position
		state = replayed
	end)

	lifeRemote.OnClientEvent:Connect(function(alive: unknown)
		if alive == false then
			state = nil
			Viewmodel.show(false)
			Hud.setAlive(false)
		end
	end)

	-- The server's verdict on our own shots: show the real impact, and a hit
	-- marker when the bullet arrives.
	shotResultRemote.OnClientEvent:Connect(function(data: unknown)
		local shot = Protocol.decodeShot(data)
		if not shot then
			return
		end
		local delay = if weapon.instantDamage then 0 else (shot.hit - shot.origin).Magnitude / weapon.bulletSpeed
		task.delay(delay, function()
			landed(shot)
			if shot.kind == Protocol.HitKind.Body or shot.kind == Protocol.HitKind.Head then
				Hud.hit(shot.kind)
				local played = shot.kind == Protocol.HitKind.Head and Sounds.play(weapon.name, Sounds.Cues.Headshot)
				if not played then
					Sounds.play(weapon.name, Sounds.Cues.HitMarker)
				end
			end
		end)
	end)

	-- Other players' shots nearby.
	shotsRemote.OnClientEvent:Connect(function(data: unknown)
		local shot = Protocol.decodeShot(data)
		if not shot then
			return
		end
		Effects.muzzleFlash(shot.origin)
		Effects.tracer(shot.origin, shot.hit, weapon.bulletSpeed)
		local port = Puppets.ejectionPort(shot.slot)
		if port then
			Casings.eject(weapon.name, port)
		end
		local listener = camera.CFrame.Position
		local far = (shot.origin - listener).Magnitude > DISTANT_SHOT
		if not (far and Sounds.at(weapon.name, Sounds.Cues.FireDistant, shot.origin)) then
			Sounds.shot(weapon.name, shot.origin)
		end
		-- A bullet passing close by is heard where it passes, when it gets there.
		local path = shot.hit - shot.origin
		local along = math.clamp((listener - shot.origin):Dot(path) / math.max(path:Dot(path), 1e-6), 0, 1)
		local closest = shot.origin + path * along
		if along > 0 and along < 1 and (closest - listener).Magnitude < NEAR_MISS then
			local arrive = (closest - shot.origin).Magnitude / weapon.bulletSpeed
			task.delay(arrive, Sounds.at, weapon.name, Sounds.Cues.NearMiss, closest)
		end
		local delay = path.Magnitude / weapon.bulletSpeed
		task.delay(delay, landed, shot)
	end)

	snapshotRemote.OnClientEvent:Connect(Puppets.receive)
	Sounds.preload(weapon.name)
	Casings.ignore({ camera, Puppets.folder, Effects.folder })
	Sounds.ignore({ camera, Puppets.folder, Effects.folder, Casings.folder })
	InputMap.start()
	Hud.start()

	task.delay(5, function()
		if state == nil and epoch == -1 then
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
				local viewTick = Puppets.renderTick() * Protocol.VIEW_TICK_SCALE
				local input = Protocol.quantizeInput(InputMap.sample(seq, viewTick))
				-- A fresh pull with nothing left to fire or reload just clicks.
				local pulled = bit32.btest(input.buttons, Types.Buttons.Fire) and not current.triggerHeld
				if
					pulled
					and current.ammo == 0
					and current.reserve == 0
					and current.reloadTicks == 0
					and current.drawTicks == 0
					and current.raiseTicks == 0
					and not current.sprinting
				then
					Sounds.near(weapon.name, Sounds.Cues.DryFire, HANDS)
				end
				previous = current
				local shot
				current, shot = Simulation.step(current, input, world, weapon)
				history[seq] = { input = input, state = current }
				table.insert(recent, input)
				if #recent > Protocol.MAX_INPUTS_PER_PACKET then
					table.remove(recent, 1)
				end
				inputRemote:FireServer(Protocol.encodeInputs(recent))

				if shot then
					-- Show the shot right away. Where it really lands comes back from the server.
					local direction = Firearm.scatter(Firearm.direction(shot.yaw, shot.pitch), shot.spread, random)
					local hit = workspace:Raycast(camera.CFrame.Position, direction * weapon.range, world.raycast)
					local target = if hit then hit.Position else camera.CFrame.Position + direction * weapon.range
					Viewmodel.fired()
					Sounds.shot(weapon.name, muzzle)
					Casings.eject(weapon.name, Viewmodel.ejectionPort(), current.velocity)
					Effects.muzzleFlash(muzzle)
					Effects.tracer(muzzle, target, weapon.bulletSpeed)
				end
			end
			if ticks == MAX_TICKS_PER_FRAME then
				accumulator = 0
			end
			state = current

			-- Draw between the last two ticks, with any correction fading out.
			local last = previous or current
			local alpha = accumulator / DT
			correction *= math.exp(-CORRECTION_DECAY * frameTime)
			local yaw, pitch = InputMap.look()
			local shown = table.clone(current)
			shown.position = last.position:Lerp(current.position, alpha) + correction
			shown.yaw = yaw

			local leanOffset = Eye.leanOffset(shown, world)
			local target = Eye.position(shown, leanOffset) - shown.position
			local smoothed = eyeOffset or target
			smoothed = smoothed:Lerp(target, 1 - math.exp(-EYE_SMOOTHING * frameTime))
			eyeOffset = smoothed

			-- Recoil moves the view, exactly as it moves the server's aim.
			local recoilPitch = last.recoilPitch + (current.recoilPitch - last.recoilPitch) * alpha
			local recoilYaw = last.recoilYaw + (current.recoilYaw - last.recoilYaw) * alpha
			local roll = LEAN_ROLL * leanOffset / Config.movement.leanDistance
			local view = CFrame.new(shown.position + smoothed)
				* CFrame.Angles(0, yaw + recoilYaw, 0)
				* CFrame.Angles(pitch + recoilPitch, 0, 0)
				* CFrame.Angles(0, 0, -roll)
			-- The reload's jolts nudge the head, not the hands: the gun stays put.
			camera.CFrame = view * Viewmodel.cameraOffset()

			local targetFov = if current.aiming then AIM_FOV else HIP_FOV
			fieldOfView += (targetFov - fieldOfView) * (1 - math.exp(-FOV_SPEED * frameTime))
			camera.FieldOfView = fieldOfView

			muzzle = Viewmodel.update(view, current, InputMap.mouseDelta(), frameTime)
			Hud.update(
				current.ammo,
				current.reserve,
				current.reloadTicks > 0,
				health,
				Firearm.spread(current, weapon),
				fieldOfView,
				not current.aiming and not current.sprinting
			)
		end

		Puppets.render()
		Effects.update(frameTime)
		Casings.update(frameTime)
	end)
end

return table.freeze(Controller)

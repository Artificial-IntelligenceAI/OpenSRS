--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Character movement. The server runs this as the authority; the local client
-- runs the same code to predict its own movement. It must stay deterministic:
-- the same state, input and map always give the same result.
--
-- The collision shape is a box that floats `stepUp` studs above the feet.
-- Anything lower than that is walked over, and a downward cast snaps the feet
-- onto the ground, which also handles stairs and slopes.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type Input = Types.Input
type State = Types.State
type StanceConfig = Config.StanceConfig

export type World = {
	raycast: RaycastParams,
}

local Buttons = Types.Buttons
local Stance = Types.Stance
local M = Config.movement
local DT = 1 / Config.tickRate
local SLIDE_ITERATIONS = 3

local Movement = {}

-- `exclude` lists things that must never block movement, such as client-side
-- character models.
function Movement.newWorld(exclude: { Instance }): World
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.FilterDescendantsInstances = exclude
	raycast.RespectCanCollide = true
	return { raycast = raycast }
end

local function hull(position: Vector3, stance: StanceConfig): (CFrame, Vector3)
	local height = stance.height - stance.stepUp
	local width = M.width - 2 * M.skin
	return CFrame.new(position + Vector3.new(0, stance.stepUp + height / 2, 0)), Vector3.new(width, height, width)
end

-- Moves the hull horizontally, sliding along anything it hits.
local function slide(
	position: Vector3,
	velocity: Vector3,
	displacement: Vector3,
	stance: StanceConfig,
	world: World
): (Vector3, Vector3)
	for _ = 1, SLIDE_ITERATIONS do
		local length = displacement.Magnitude
		if length < 1e-4 then
			break
		end

		local cframe, size = hull(position, stance)
		local result = workspace:Blockcast(cframe, size, displacement, world.raycast)
		if not result then
			position += displacement
			break
		end

		local normal = Vector3.new(result.Normal.X, 0, result.Normal.Z)
		if normal.Magnitude < 1e-4 then
			break
		end
		normal = normal.Unit

		local direction = displacement / length
		local travel = math.max(result.Distance, 0)
		-- Stop just short of the surface so the next cast doesn't start inside it.
		position += direction * travel + normal * M.skin

		local remaining = direction * (length - travel)
		displacement = remaining - normal * remaining:Dot(normal)

		local into = velocity:Dot(normal)
		if into < 0 then
			velocity -= normal * into
		end
	end
	return position, velocity
end

local function hasHeadroom(position: Vector3, from: StanceConfig, to: StanceConfig, world: World): boolean
	local rise = to.height - from.height
	if rise <= 0 then
		return true
	end
	local cframe, size = hull(position, from)
	return workspace:Blockcast(cframe, size, Vector3.new(0, rise, 0), world.raycast) == nil
end

local function speedFor(stance: number, buttons: number, sprinting: boolean): number
	if stance ~= Stance.Stand then
		return Config.stance(stance).speed
	elseif sprinting then
		return M.sprintSpeed
	elseif bit32.btest(buttons, Buttons.SlowWalk) then
		return M.slowWalkSpeed
	end
	return Config.stance(stance).speed
end

function Movement.step(state: State, input: Input, world: World): State
	local position = state.position
	local grounded = state.grounded
	local buttons = input.buttons
	local jumpCooldown = math.max(state.jumpCooldown - 1, 0)

	-- Stance. Standing up needs room above; going prone needs ground below.
	local stance = state.stance
	local wanted = input.stance
	if wanted ~= stance and (wanted ~= Stance.Prone or grounded) then
		if hasHeadroom(position, Config.stance(stance), Config.stance(wanted), world) then
			stance = wanted
		end
	end
	local stanceConfig = Config.stance(stance)

	local aiming = bit32.btest(buttons, Buttons.Aim)
	local sprinting = stance == Stance.Stand
		and not aiming
		and bit32.btest(buttons, Buttons.Sprint)
		and input.moveZ >= M.sprintMinForward

	-- Lean. Not while sprinting or prone.
	local leanTarget = 0
	if not sprinting and stance ~= Stance.Prone then
		if bit32.btest(buttons, Buttons.LeanRight) then
			leanTarget += M.leanTicks
		end
		if bit32.btest(buttons, Buttons.LeanLeft) then
			leanTarget -= M.leanTicks
		end
	end
	local leanTicks = state.leanTicks + math.sign(leanTarget - state.leanTicks)

	-- Horizontal velocity eases toward where the player wants to go.
	local yaw = input.yaw
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local move = right * input.moveX + forward * input.moveZ
	if move.Magnitude > 1 then
		move = move.Unit
	end

	local speed = speedFor(stance, buttons, sprinting)
	if input.moveZ < 0 then
		speed *= M.backwardMultiplier
	end
	if aiming then
		speed *= M.aimSpeedMultiplier
	end

	local horizontal = Vector3.new(state.velocity.X, 0, state.velocity.Z)
	local rate = if not grounded
		then M.airAcceleration
		elseif move.Magnitude > 0 then M.groundAcceleration
		else M.groundDeceleration
	local change = move * speed - horizontal
	local maxChange = rate * DT
	if change.Magnitude > maxChange then
		change = change.Unit * maxChange
	end
	horizontal += change

	-- Vertical velocity.
	local vertical = if grounded then 0 else state.velocity.Y
	if grounded and stance == Stance.Stand and jumpCooldown == 0 and bit32.btest(buttons, Buttons.Jump) then
		vertical = M.jumpVelocity
		jumpCooldown = M.jumpCooldownTicks
		grounded = false
	elseif not grounded then
		vertical = math.max(vertical - M.gravity * DT, -M.terminalVelocity)
	end

	position, horizontal = slide(position, horizontal, horizontal * DT, stanceConfig, world)

	local cframe, size = hull(position, stanceConfig)
	if vertical > 0 then
		local rise = vertical * DT
		local result = workspace:Blockcast(cframe, size, Vector3.new(0, rise, 0), world.raycast)
		if result then
			rise = math.max(result.Distance - M.skin, 0)
			vertical = 0
		end
		position += Vector3.new(0, rise, 0)
		grounded = false
	else
		local fall = -vertical * DT
		local probe = stanceConfig.stepUp + fall + (if grounded then M.groundSnap else 0)
		local result = workspace:Blockcast(cframe, size, Vector3.new(0, -probe, 0), world.raycast)
		local hullBottom = position.Y + stanceConfig.stepUp
		if result and result.Normal.Y >= M.minGroundNormal then
			position = Vector3.new(position.X, hullBottom - result.Distance, position.Z)
			vertical = 0
			grounded = true
		else
			if result then
				-- Too steep to stand on: slide off it instead of falling into it.
				local away = Vector3.new(result.Normal.X, 0, result.Normal.Z)
				if away.Magnitude > 1e-4 then
					position, horizontal = slide(position, horizontal, away.Unit * fall, stanceConfig, world)
				end
				fall = math.min(fall, math.max(result.Distance - stanceConfig.stepUp - M.skin, 0))
			end
			position -= Vector3.new(0, fall, 0)
			grounded = false
		end
	end

	local nextState = table.clone(state)
	nextState.position = position
	nextState.velocity = Vector3.new(horizontal.X, vertical, horizontal.Z)
	nextState.grounded = grounded
	nextState.stance = stance
	nextState.sprinting = sprinting
	nextState.aiming = aiming
	nextState.leanTicks = leanTicks
	nextState.jumpCooldown = jumpCooldown
	nextState.yaw = input.yaw
	nextState.pitch = input.pitch
	return nextState
end

return table.freeze(Movement)

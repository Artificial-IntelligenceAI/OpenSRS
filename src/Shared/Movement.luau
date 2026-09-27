--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Character movement. The server runs this as the authority; the local client
-- runs the same code to predict its own movement. It must stay deterministic:
-- the same state, input and map always give the same result.
--
-- The collision shape is a box that floats `stepUp` studs above the feet.
-- Anything lower than that is walked over, and a downward cast snaps the feet
-- onto the ground, which also handles stairs and slopes. Upright it's a
-- square column; prone it covers the whole lying body and turns with it, so
-- going prone, crawling and turning all need room for the body, and a body
-- that can't turn keeps facing (and aiming) where it was.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type Input = Types.Input
type State = Types.State
type StanceConfig = Config.StanceConfig

export type World = {
	raycast: RaycastParams,
	overlap: OverlapParams, -- the same filter, for checking whether a box fits somewhere
}

local Buttons = Types.Buttons
local Stance = Types.Stance
local M = Config.movement
local SLIDE_ITERATIONS = 3
local SLIDE_INSET = 0.05 -- how much narrower than the hull its sideways casts are, per side

local Movement = {}

-- `exclude` lists things that must never block movement, such as client-side
-- character models.
function Movement.newWorld(exclude: { Instance }): World
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.FilterDescendantsInstances = exclude
	raycast.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	overlap.RespectCanCollide = true
	return { raycast = raycast, overlap = overlap }
end

-- The collision box for `stance` at `position` with the body facing `yaw`.
local function hull(position: Vector3, stance: StanceConfig, yaw: number): (CFrame, Vector3)
	local height = stance.height - stance.stepUp
	local center = position + Vector3.new(0, stance.stepUp + height / 2, 0)
	local length, back, bodyWidth = stance.bodyLength, stance.bodyBack, stance.bodyWidth
	if length and back and bodyWidth then
		local facing = CFrame.Angles(0, yaw, 0)
		return CFrame.new(center + facing:VectorToWorldSpace(Vector3.new(0, 0, back))) * facing,
			Vector3.new(bodyWidth - 2 * M.skin, height, length - 2 * M.skin)
	end
	local width = M.width - 2 * M.skin
	return CFrame.new(center), Vector3.new(width, height, width)
end

-- Whether `stance`'s box fits at `position` facing `yaw` without overlapping
-- anything. (Casts can't tell: they ignore whatever they start inside.)
local function fits(position: Vector3, stance: StanceConfig, yaw: number, world: World): boolean
	local cframe, size = hull(position, stance, yaw)
	size -= Vector3.new(0, 2 * M.skin, 0)
	return #workspace:GetPartBoundsInBox(cframe, size, world.overlap) == 0
end

-- Moves the hull horizontally, sliding along anything it hits.
local function slide(
	position: Vector3,
	velocity: Vector3,
	displacement: Vector3,
	stance: StanceConfig,
	yaw: number,
	world: World
): (Vector3, Vector3)
	for _ = 1, SLIDE_ITERATIONS do
		local length = displacement.Magnitude
		if length < 1e-4 then
			break
		end
		local direction = displacement / length

		-- Shape casts ignore anything they start touching, so a hull that has
		-- crept up against a wall (moving nearly along it, or pushed into a
		-- corner) would pass straight through. Casting a hull SLIDE_INSET
		-- narrower keeps every cast clear of whatever the real hull touches.
		local cframe, size = hull(position, stance, yaw)
		size -= Vector3.new(2 * SLIDE_INSET, 0, 2 * SLIDE_INSET)
		local reach = length + M.skin + SLIDE_INSET
		local result = workspace:Blockcast(cframe, size, direction * reach, world.raycast)
		if not result then
			position += displacement
			break
		end

		local normal = Vector3.new(result.Normal.X, 0, result.Normal.Z)
		if normal.Magnitude < 1e-4 then
			break
		end
		normal = normal.Unit

		-- How far the real hull was from the surface, and how much of each
		-- stud moved along `direction` closes that gap.
		local facing = -direction:Dot(normal)
		local gap = result.Distance * math.max(facing, 0) - SLIDE_INSET
		-- Move until the real hull is a skin's width away, but never backward...
		local travel = if facing > 1e-4 then math.clamp((gap - M.skin) / facing, 0, length) else length
		position += direction * travel
		-- ...and if it was already closer than that, push it back out.
		local left = gap - travel * math.max(facing, 0)
		if left < M.skin then
			position += normal * (M.skin - left)
		end

		local remaining = direction * (length - travel)
		displacement = remaining - normal * remaining:Dot(normal)

		local into = velocity:Dot(normal)
		if into < 0 then
			velocity -= normal * into
		end
	end
	return position, velocity
end

-- Whether there's room to change from one stance to another here.
local function hasRoom(position: Vector3, from: StanceConfig, to: StanceConfig, yaw: number, world: World): boolean
	if from.bodyLength or to.bodyLength then
		-- Lying down or getting up: the whole new shape has to fit.
		return fits(position, to, yaw, world)
	end
	local rise = to.height - from.height
	if rise <= 0 then
		return true
	end
	local cframe, size = hull(position, from, yaw)
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

-- `speedMultiplier` and `aimSpeedMultiplier` come from the weapon in hand (a
-- light gun moves faster); without them, movement is at the base speeds.
function Movement.step(
	state: State,
	input: Input,
	world: World,
	speedMultiplier: number?,
	aimSpeedMultiplier: number?
): State
	local DT = 1 / Config.tickRate -- read now: settings may be applied after this module loads
	local position = state.position
	local grounded = state.grounded
	local buttons = input.buttons
	local jumpCooldown = math.max(state.jumpCooldown - 1, 0)

	-- Stance. Standing up needs room above; going prone needs ground below and
	-- room for the whole body.
	local stance = state.stance
	local wanted = input.stance
	if wanted ~= stance and (wanted ~= Stance.Prone or grounded) then
		if hasRoom(position, Config.stance(stance), Config.stance(wanted), input.yaw, world) then
			stance = wanted
		end
	end
	local stanceConfig = Config.stance(stance)

	-- Facing. Upright, the body turns with the view. Lying down it only turns
	-- if the body fits the new way; if not, it keeps facing where it was.
	local yaw = input.yaw
	if stanceConfig.bodyLength and yaw ~= state.yaw and stance == state.stance then
		if not fits(position, stanceConfig, yaw, world) then
			yaw = state.yaw
		end
	end

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
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local move = right * input.moveX + forward * input.moveZ
	if move.Magnitude > 1 then
		move = move.Unit
	end

	local speed = speedFor(stance, buttons, sprinting) * (speedMultiplier or 1)
	if input.moveZ < 0 then
		speed *= M.backwardMultiplier
	end
	if aiming then
		speed *= aimSpeedMultiplier or 1
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

	local beforeSlide = position
	position, horizontal = slide(position, horizontal, horizontal * DT, stanceConfig, yaw, world)

	local cframe, size = hull(position, stanceConfig, yaw)
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
		local ground = if result then hullBottom - result.Distance else 0
		local rise = ground - position.Y
		-- Stepping up raises the head as much as the feet. Casts ignore anything
		-- they start inside, so a head pushed into a low ceiling could then see
		-- and jump through it: with no room above, the step is a wall instead.
		local blocked = result ~= nil
			and rise > 0
			and workspace:Blockcast(cframe, size, Vector3.new(0, rise + M.skin, 0), world.raycast) ~= nil
		if blocked then
			position = Vector3.new(beforeSlide.X, position.Y, beforeSlide.Z)
			horizontal = Vector3.zero
			vertical = if grounded then 0 else vertical
		elseif result and result.Normal.Y >= M.minGroundNormal then
			position = Vector3.new(position.X, ground, position.Z)
			vertical = 0
			grounded = true
		else
			if result then
				-- Too steep to stand on: slide off it instead of falling into it.
				local away = Vector3.new(result.Normal.X, 0, result.Normal.Z)
				if away.Magnitude > 1e-4 then
					position, horizontal = slide(position, horizontal, away.Unit * fall, stanceConfig, yaw, world)
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
	nextState.yaw = yaw
	nextState.pitch = input.pitch
	return nextState
end

return table.freeze(Movement)

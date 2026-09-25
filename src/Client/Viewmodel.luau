--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The gun and arms in the player's own view. It only exists on this client and
-- never affects gameplay.
--
-- From the hip the gun comes in from the lower right. Aiming holds it out at
-- arm's length with both arms reaching up from the bottom of the screen and
-- the sights lined up on the center. It sways against mouse movement, bobs
-- while walking, and kicks back and up on each shot as the slide cycles. The slide locks
-- back on the last round. Reloading drops the old magazine, fetches a new one
-- with the left hand and seats it, then rolls the gun onto its side and racks
-- the slide over the top. So it reads as a person rather than a machine, the
-- gun follows the choreography through springs, gets jolted when the magazine
-- goes in and the slide slams home, hands move in arcs, and no two reloads are
-- timed or held quite the same.

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Weapons = require(Shared.Weapons)
local Avatar = require(script.Parent.Avatar)
local GunModel = require(script.Parent.GunModel)
local Spring = require(script.Parent.Spring)
local WeaponAnimation = require(script.Parent.WeaponAnimation)

type State = Types.State

-- Where the gun's grip sits relative to the camera in each pose.
local AIM_REACH = 1.2 -- how far in front of the eye the rear sight sits when aiming: arms outstretched
local HIP = CFrame.new(0.4, -0.7, -1.3) -- straight and level
local SPRINT = CFrame.new(0.22, -0.8, -0.75) * CFrame.Angles(-0.45, 0.85, 0.3)
local POSE_SPEED = 16

-- Arms: shoulders are fixed to the camera, hands follow the gun.
-- Two-handed pistol grip. Aiming: the right arm runs straight out to the
-- grip and the left arm comes across from the left to wrap around the right
-- hand. From the hip the gun sits lower right, so the arms come in at an
-- angle from the lower right and lower middle instead.
local AIM_RIGHT_SHOULDER = Vector3.new(0.2, -1.45, 0.5)
local AIM_LEFT_SHOULDER = Vector3.new(-1.2, -1.4, 0.15)
local HIP_RIGHT_SHOULDER = Vector3.new(1.1, -1.6, 0.1)
local HIP_LEFT_SHOULDER = Vector3.new(-0.5, -1.7, 0.1)
-- While reloading the left forearm comes in from the lower left, in front of the
-- eye rather than from behind it, so it never covers the view.
local RELOAD_LEFT_SHOULDER = Vector3.new(-2, -1.9, -0.6)
local RIGHT_HAND = Vector3.new(0.02, 0.2, 0.06) -- in the gun's space, around the grip
local ARM_WIDTH = 0.38
local ARM_LENGTH = 1.3 -- forearms only: long enough to run off screen, never near the eye

local SLIDE_TRAVEL = 0.19
local BARREL_TRAVEL = 0.06

-- The reload's choreography, as a fraction of the reload (see WeaponAnimation;
-- a game can change it per weapon).
type Key = WeaponAnimation.Key
local IDENTITY = CFrame.identity
local MAX_FRAME = 0.1 -- longer frames (hitches) are treated as this long

-- Eased position along a keyframe track at `t`, bowed out along `arc` in the
-- middle of each move.
local function sampleArc(keys: { Key }, t: number, arc: Vector3): Vector3
	if t <= keys[1].t then
		return keys[1].value.Position
	end
	for index = 2, #keys do
		local after = keys[index]
		if t <= after.t then
			local before = keys[index - 1]
			local u = (t - before.t) / (after.t - before.t)
			local eased = u * u * (3 - 2 * u)
			local from, to = before.value.Position, after.value.Position
			return from:Lerp(to, eased) + arc * (to - from).Magnitude * math.sin(u * math.pi) * 0.5
		end
	end
	return keys[#keys].value.Position
end

-- Eased value of a keyframe track at `t`.
local function sample(keys: { Key }, t: number): CFrame
	if t <= keys[1].t then
		return keys[1].value
	end
	for index = 2, #keys do
		local after = keys[index]
		if t <= after.t then
			local before = keys[index - 1]
			local u = (t - before.t) / (after.t - before.t)
			return before.value:Lerp(after.value, u * u * (3 - 2 * u))
		end
	end
	return keys[#keys].value
end

-- A small light that travels with the view, so the held gun reads clearly
-- whatever the map's lighting. Its short range keeps it off the world.
local FILL_OFFSET = CFrame.new(-0.2, 1.45, 0.45) -- in the gun's space: high above the slide, toward the eye
local FILL_BRIGHTNESS = 4
local FILL_RANGE = 1.35 -- reaches the slide, not the arms below it
local FILL_COLOR = Color3.fromRGB(255, 244, 230)

local SWAY_AMOUNT = 0.0025 -- radians per pixel of mouse movement
local SWAY_LIMIT = 0.08
local SWAY_RETURN = 12
local BOB_EASE = 6 -- how quickly the walking bob fades in and out
local AIMED_MOTION = 0.12 -- sway and bob keep this fraction while aiming

local Viewmodel = {}

local weapon = Weapons.default
local animation = WeaponAnimation.get(weapon.name)
local LEFT_HAND_AT = animation.leftHand
local model = GunModel.new(weapon.name, "FirstPerson")
model.Name = "OpenSRSViewmodel"

local gunParts: { BasePart } = {}
local rest: { CFrame } = {} -- each gun part relative to the grip
local pivot = model:GetPivot()
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") then
		table.insert(gunParts, part)
		table.insert(rest, pivot:ToObjectSpace(part.CFrame))
	end
end

local function limb(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

-- Plain R6 arms, ending at the hands, in the avatar's arm color.
local rightArm = limb("RightArm", Vector3.new(ARM_WIDTH, ARM_WIDTH, ARM_LENGTH), Avatar.armColor)
local leftArm = limb("LeftArm", Vector3.new(ARM_WIDTH, ARM_WIDTH, ARM_LENGTH), Avatar.armColor)

local function localPoint(name: string, fallback: Vector3): CFrame
	local attachment = GunModel.point(model, name)
	return if attachment then pivot:ToObjectSpace(attachment.WorldCFrame) else CFrame.new(fallback)
end

local MUZZLE = localPoint("Muzzle", Vector3.new(0, 0.44, -1))
local SIGHT = localPoint("RearSight", Vector3.new(0, 0.53, 0.05))
local AIM = CFrame.new(0, 0, -AIM_REACH) * CFrame.new(-SIGHT.Position)

local fill = limb("FillLight", Vector3.one * 0.05, Color3.new(1, 1, 1))
fill.Transparency = 1
local light = Instance.new("PointLight")
light.Brightness = FILL_BRIGHTNESS
light.Range = FILL_RANGE
light.Color = FILL_COLOR
light.Shadows = false
light.Parent = fill

local parts: { BasePart } = table.clone(gunParts)
table.insert(parts, rightArm)
table.insert(parts, leftArm)
table.insert(parts, fill)
local cframes: { CFrame } = table.create(#parts)

local current = HIP
local aimBlend = 0
local reloadBlend = 0
local kick = 0
local reloadLength = 0
local sway = Vector2.zero
local stepPhase = 0 -- through the walk cycle: each step is half a turn
local bobStrength = 0
local gunMove = Spring.new(animation.gunStiffness, animation.gunDamping)
local gunTurn = Spring.new(animation.gunStiffness, animation.gunDamping)
local look = Spring.new(animation.lookStiffness, animation.lookDamping)
local lastProgress = 0
local lastDrawTicks = 0
local lastDrawProgress = 0
local drift = 0
local hold = IDENTITY
local random = Random.new()

function Viewmodel.show(visible: boolean)
	model.Parent = if visible then workspace.CurrentCamera else nil
end

function Viewmodel.fired()
	kick = animation.slideCycle
	-- The shot knocks the gun through the same springs the reload uses, so it
	-- overshoots a little and settles, and each shot is a little different.
	local scale = 1 - (1 - animation.aimedFire) * aimBlend
	local variation = animation.fireVariation
	local wobble = Vector3.new(
		random:NextNumber(0, variation.X),
		random:NextNumber(-variation.Y, variation.Y),
		random:NextNumber(-variation.Z, variation.Z)
	)
	Spring.impulse(gunMove, animation.fireMove * scale)
	Spring.impulse(gunTurn, (animation.fireTurn + wobble) * scale)
end

-- A small turn of the view from the reload's jolts, to put on the camera.
function Viewmodel.cameraOffset(): CFrame
	local angles = look.position
	return CFrame.Angles(angles.X, angles.Y, angles.Z)
end

-- How far through the reload we are, from 0 to 1.
local function reloadProgress(state: State): number
	if state.reloadTicks <= 0 then
		reloadLength = 0
		return 0
	end
	reloadLength = math.max(reloadLength, state.reloadTicks)
	return 1 - state.reloadTicks / reloadLength
end

-- Where the magazine is relative to where it seats, and whether it's shown.
-- `hand` is where the left hand is, in the gun's space.
local function magazineAt(progress: number, hand: Vector3): (CFrame, boolean)
	if progress <= animation.magazineReleased then
		return IDENTITY, true
	elseif progress < animation.magazineFree then
		local u = (progress - animation.magazineReleased) / (animation.magazineFree - animation.magazineReleased)
		return CFrame.new(0, -0.35 * (1 - (1 - u) ^ 2), 0), true
	elseif progress < animation.magazineGone then
		-- Falling: slow at first, then faster, turning over as it goes.
		local u = (progress - animation.magazineFree) / (animation.magazineGone - animation.magazineFree)
		return CFrame.new(0.05 * u, -0.35 - 0.6 * u - 1.65 * u * u, 0.1 * u) * CFrame.Angles(0.8 * u * u, 0, 0.3 * u),
			true
	elseif progress < animation.magazineShown then
		return IDENTITY, false
	elseif progress < animation.magazineSeated then
		local remaining = (animation.magazineSeated - progress) / (animation.magazineSeated - animation.magazineShown)
		return CFrame.new(hand - animation.handWhenSeated) * CFrame.Angles(
			animation.magazineTilt * remaining * remaining,
			0,
			0
		),
			true
	end
	return IDENTITY, true
end

-- A rotation from a spring's rotation vector (axis times angle).
local function turned(rotation: Vector3): CFrame
	local angle = rotation.Magnitude
	return if angle > 1e-6 then CFrame.fromAxisAngle(rotation / angle, angle) else IDENTITY
end

-- A CFrame's rotation as a rotation vector, which springs can follow.
local function rotationOf(frame: CFrame): Vector3
	local axis, angle = frame:ToAxisAngle()
	return axis * angle
end

-- An arm reaching from a shoulder to a hand; only the hand end is usually on screen.
local function arm(shoulder: Vector3, hand: Vector3): CFrame
	local direction = (shoulder - hand).Unit
	return CFrame.lookAt(hand + direction * (ARM_LENGTH / 2), hand)
end

-- Positions the gun and arms for this frame and returns where the muzzle is.
function Viewmodel.update(camera: CFrame, state: State, mouseDelta: Vector2, frameTime: number): Vector3
	local raw = reloadProgress(state)
	if raw > 0 and lastProgress == 0 then
		-- A new reload: pick how this one differs.
		drift = random:NextNumber(-animation.timingDrift, animation.timingDrift)
		hold = CFrame.Angles(
			random:NextNumber(-animation.holdDrift.X, animation.holdDrift.X),
			random:NextNumber(-animation.holdDrift.Y, animation.holdDrift.Y),
			random:NextNumber(-animation.holdDrift.Z, animation.holdDrift.Z)
		)
	end
	local progress = if raw > 0 then raw + math.sin(raw * math.pi) * drift else 0
	local drawing = state.drawTicks > 0 and weapon.drawTicks > 0
	local drawProgress = if drawing then 1 - state.drawTicks / weapon.drawTicks else 0
	if drawing and state.drawTicks > lastDrawTicks then
		-- A fresh spawn: start from the draw's first position, not from wherever
		-- the gun was.
		local start = animation.drawTrack[1].value
		gunMove.position, gunMove.velocity = start.Position, Vector3.zero
		gunTurn.position, gunTurn.velocity = rotationOf(start), Vector3.zero
		lastDrawProgress = 0
	end
	lastDrawTicks = state.drawTicks
	local aiming = state.aiming and progress == 0 and not drawing and not state.sprinting and state.raiseTicks == 0
	-- Once the slide is home the gun comes back up ready, while the reload
	-- finishes.
	local handling = progress > 0 and progress < animation.readyAt
	local target = if handling
		then (if progress >= animation.rackStart then animation.rackPose else animation.reloadPose) * hold
		elseif state.sprinting or state.raiseTicks > 0 then SPRINT
		elseif aiming then AIM
		else HIP
	local blend = 1 - math.exp(-POSE_SPEED * frameTime)
	current = current:Lerp(target, blend)
	aimBlend += ((if aiming then 1 else 0) - aimBlend) * blend
	reloadBlend += ((if handling then 1 else 0) - reloadBlend) * blend
	local motion = 1 - (1 - AIMED_MOTION) * aimBlend

	-- Sway: the gun lags behind the mouse, then settles.
	sway -= mouseDelta * SWAY_AMOUNT
	sway = Vector2.new(math.clamp(sway.X, -SWAY_LIMIT, SWAY_LIMIT), math.clamp(sway.Y, -SWAY_LIMIT, SWAY_LIMIT))
	sway *= math.exp(-SWAY_RETURN * frameTime)
	local swayFrame = CFrame.Angles(sway.Y * motion, sway.X * motion, sway.X * 0.5 * motion)

	-- Bob: while walking the gun sways side to side once every two steps,
	-- dipping smoothly on each step, at about the pace a person walks. It
	-- fades in and out rather than following every change in speed.
	local speed = if state.grounded then Vector3.new(state.velocity.X, 0, state.velocity.Z).Magnitude else 0
	local walkSpeed = Config.stance(0).speed
	local pace = if walkSpeed > 0 then speed / walkSpeed else 0
	bobStrength += (math.min(pace, 1.4) * motion - bobStrength) * (1 - math.exp(-BOB_EASE * frameTime))
	-- Longer strides, not just quicker ones, when going faster.
	local steps = animation.walkSteps * math.sqrt(math.min(pace, 2))
	stepPhase = (stepPhase + steps * math.pi * frameTime) % (2 * math.pi)
	local side = math.sin(stepPhase)
	local bob =
		CFrame.new(side * animation.walkSway * bobStrength, -side * side * animation.walkBounce * bobStrength, 0)
	local bobRoll = CFrame.Angles(0, 0, -side * animation.walkRoll * bobStrength) -- around the gun, not the view

	kick = math.max(kick - frameTime, 0)
	local cycle = if animation.slideCycle > 0 then kick / animation.slideCycle else 0

	local reloading = progress > 0
	local empty = reloading and state.ammo == 0 -- the new rounds only count once the reload is done

	-- The gun follows the reload's guide through springs, and gets knocked at
	-- the moments that would jolt it; the view gets a smaller nudge.
	local step = math.min(frameTime, MAX_FRAME)
	for _, hit in animation.hits do
		if lastProgress < hit.t and progress >= hit.t then
			Spring.impulse(gunMove, hit.move)
			Spring.impulse(gunTurn, hit.turn)
			Spring.impulse(look, hit.look)
		end
	end
	lastProgress = progress
	for _, hit in animation.drawHits do
		if lastDrawProgress < hit.t and drawProgress >= hit.t then
			Spring.impulse(gunMove, hit.move)
			Spring.impulse(gunTurn, hit.turn)
			Spring.impulse(look, hit.look)
		end
	end
	lastDrawProgress = drawProgress
	local guide = if reloading
		then sample(animation.gunTrack, progress)
		elseif drawing then sample(animation.drawTrack, drawProgress)
		else IDENTITY
	Spring.step(gunMove, guide.Position, step)
	Spring.step(gunTurn, rotationOf(guide), step)
	Spring.step(look, Vector3.zero, step)
	local gunMotion = CFrame.new(gunMove.position) * turned(gunTurn.position)
	local origin = camera * bob * swayFrame * current * bobRoll * gunMotion

	-- The slide locks back on an empty magazine; the reload's rack pulls it
	-- back and lets it go.
	local slideBack
	if not reloading then
		slideBack = if state.ammo == 0 then 1 else cycle
	elseif progress >= animation.rackRelease then
		slideBack = 0
	elseif progress >= animation.rackPull then
		slideBack = math.max(
			if empty then 1 else 0,
			math.min((progress - animation.rackPull) / (animation.rackRelease - animation.rackPull - 0.01), 1)
		)
	else
		slideBack = if empty then 1 else 0
	end
	local slide = CFrame.new(0, 0, SLIDE_TRAVEL * slideBack)
	local barrel = CFrame.new(0, 0, BARREL_TRAVEL * slideBack)
	local leftHand = if reloading
		then CFrame.new(sampleArc(animation.leftHandTrack, progress, animation.arc))
		elseif drawing then CFrame.new(sampleArc(animation.drawLeftHandTrack, drawProgress, animation.arc))
		else LEFT_HAND_AT
	local magazine, magazineShown = magazineAt(progress, leftHand.Position)
	for index, part in gunParts do
		local offset = rest[index]
		if part.Name == "Slide" then
			offset = slide * offset
		elseif part.Name == "Barrel" then
			offset = barrel * offset
		elseif part.Name == "Magazine" then
			offset = magazine * offset
			part.LocalTransparencyModifier = if magazineShown then 0 else 1
		end
		cframes[index] = origin * offset
	end

	local leftHandPoint = (origin * leftHand).Position
	local rightHandPoint = (origin * CFrame.new(RIGHT_HAND)).Position
	local count = #gunParts
	local rightShoulder = HIP_RIGHT_SHOULDER:Lerp(AIM_RIGHT_SHOULDER, aimBlend)
	local leftShoulder = HIP_LEFT_SHOULDER:Lerp(AIM_LEFT_SHOULDER, aimBlend):Lerp(RELOAD_LEFT_SHOULDER, reloadBlend)
	cframes[count + 1] = arm((camera * CFrame.new(rightShoulder)).Position, rightHandPoint)
	cframes[count + 2] = arm((camera * CFrame.new(leftShoulder)).Position, leftHandPoint)
	cframes[count + 3] = origin * FILL_OFFSET
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	return (origin * MUZZLE).Position
end

return table.freeze(Viewmodel)

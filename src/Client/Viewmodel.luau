--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The gun and arms in the player's own view. It only exists on this client and
-- never affects gameplay.
--
-- From the hip the gun comes in from the lower right. Aiming holds it out at
-- arm's length with both arms reaching up from the bottom of the screen and
-- the sights lined up on the center. It sways against mouse movement, bobs
-- while walking, and kicks on each shot as the slide cycles. The slide locks
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

type State = Types.State

-- Where the gun's grip sits relative to the camera in each pose.
local AIM_REACH = 1.2 -- how far in front of the eye the rear sight sits when aiming: arms outstretched
local HIP = CFrame.new(0.4, -0.7, -1.3) -- straight and level
local SPRINT = CFrame.new(0.22, -0.8, -0.75) * CFrame.Angles(-0.45, 0.85, 0.3)
local RELOAD = CFrame.new(0.05, -0.32, -1.15) * CFrame.Angles(0.75, 0.25, -0.35) -- muzzle up, grip toward you: the magazine well shows
-- Racking: the gun is brought toward the middle, level, and rolled fully onto
-- its side, the top of the slide facing left, so the left hand can come over
-- the top.
local RACK = CFrame.new(0.2, -0.38, -1.35) * CFrame.Angles(0, 0.45, math.pi / 2)
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
local LEFT_HAND_AT = CFrame.new(-0.1, 0.1, 0.02) -- in the gun's space: wrapped around the right hand, from the left
local ARM_WIDTH = 0.38
local ARM_LENGTH = 1.3 -- forearms only: long enough to run off screen, never near the eye

local KICK_TIME = 0.07
local KICK_BACK = 0.05
local KICK_UP = 0.025
local KICK_TILT = 0.12
local SLIDE_TRAVEL = 0.19
local BARREL_TRAVEL = 0.06

-- Reload choreography: keyframes over the reload's progress, from 0 to 1.
-- Offsets are in the gun's space. Every reload ends with a rack: the left hand
-- pulls the slide back and lets it snap forward (on an empty gun that also
-- releases the locked slide).
type Key = { t: number, value: CFrame }

local function key(t: number, value: CFrame): Key
	return { t = t, value = value }
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local IDENTITY = CFrame.identity

-- Where the gun is guided during the reload. It follows this through a spring
-- (so it has weight), and the moments below knock it around on top.
local GUN_TRACK = {
	key(0, IDENTITY),
	key(0.1, IDENTITY),
	key(0.32, CFrame.Angles(0.06, 0.05, 0.12)), -- turn to meet the incoming magazine
	key(0.47, CFrame.Angles(0.02, 0, 0.05)),
	key(0.55, IDENTITY),
	key(0.6, CFrame.new(0, 0, -0.05)), -- the right hand pushes against the rack
	key(0.68, CFrame.new(0, 0, -0.07)),
	key(0.8, IDENTITY),
}
-- Moments that knock the gun (and nudge the view): velocity kicks in the
-- gun's space, as position and rotation (radians a second).
type Hit = { t: number, move: Vector3, turn: Vector3, look: Vector3 }
local HITS: { Hit } = {
	{ t = 0.12, move = Vector3.new(0, 0.4, 0), turn = Vector3.new(0.9, 0, 0.5), look = Vector3.new(0.2, 0, 0.1) }, -- magazine release
	{ t = 0.47, move = Vector3.new(0, 1.6, 0.1), turn = Vector3.new(-1.4, 0, -0.6), look = Vector3.new(-0.3, 0, 0.15) }, -- magazine slapped home
	{ t = 0.6, move = Vector3.new(0, 0, 0.35), turn = Vector3.new(0.3, 0, 0), look = Vector3.zero }, -- slide grabbed
	{ t = 0.68, move = Vector3.new(0, 0, -1.4), turn = Vector3.new(1.6, 0, 0.4), look = Vector3.new(0.4, 0, 0) }, -- slide slams forward
}
-- How the gun and the view respond: stiff enough to follow, loose enough to
-- overshoot a little and settle.
local GUN_STIFFNESS = 260
local GUN_DAMPING = 0.5
local LOOK_STIFFNESS = 180
local LOOK_DAMPING = 0.6
local MAX_FRAME = 0.1 -- longer frames (hitches) are treated as this long
-- No two reloads are quite the same: the timing drifts a little in the middle
-- and the gun is held at a slightly different angle.
local TIMING_DRIFT = 0.02
local HOLD_DRIFT = Vector3.new(0.05, 0.06, 0.06) -- radians
-- The old magazine slides out, then falls out of view, tumbling.
local OLD_MAGAZINE_RELEASED = 0.12
local OLD_MAGAZINE_FREE = 0.18
local OLD_MAGAZINE_GONE = 0.28
-- The new magazine rides in the left hand until it's seated.
local NEW_MAGAZINE_SHOWN = 0.32
local NEW_MAGAZINE_SEATED = 0.47
local NEW_MAGAZINE_TILT = 0.3 -- radians, nose first into the well, straightening as it goes in
local HAND_WHEN_SEATED = Vector3.new(-0.05, -0.15, 0.02) -- where the hand is when the magazine is home
-- Hands travel in arcs, swinging out to the left and toward the player
-- between keyframes, rather than in straight lines.
local ARC = Vector3.new(-0.3, 0, 0.2)
local LEFT_HAND_TRACK = {
	key(0, LEFT_HAND_AT),
	key(0.12, LEFT_HAND_AT),
	key(0.24, at(-0.3, -1.2, 0.35)),
	key(0.3, at(-0.3, -2, 0.35)),
	key(0.33, at(-0.05, -1.55, 0.22)),
	key(0.41, at(-0.05, -0.45, 0.02)),
	key(0.47, at(-0.05, -0.15, 0.02)),
	key(0.52, at(-0.4, 0.3, 0.2)), -- around the side of the gun
	key(0.57, at(0, 0.6, 0.1)), -- over the top: grab the back of the slide
	key(0.6, at(0, 0.6, 0.1)),
	key(0.67, at(0, 0.6, 0.3)), -- rack it back
	key(0.7, at(-0.15, 0.85, 0.4)), -- let go, the hand flying off
	key(0.8, LEFT_HAND_AT),
}
-- The gun starts rolling onto its side as soon as the magazine is home.
local RACK_START = 0.48
local RACK_END = 0.72
local RACK_PULL = 0.6
local RACK_RELEASE = 0.68

-- Eased position along a keyframe track at `t`, bowed out along ARC in the
-- middle of each move.
local function sampleArc(keys: { Key }, t: number): Vector3
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
			return from:Lerp(to, eased) + ARC * (to - from).Magnitude * math.sin(u * math.pi) * 0.5
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
local BOB_SPEED = 1.1 -- steps per stud walked
local BOB_AMOUNT = 0.025
local AIMED_MOTION = 0.12 -- sway and bob keep this fraction while aiming

local Viewmodel = {}

local weapon = Weapons.default
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
local walked = 0
local gunMove = Spring.new(GUN_STIFFNESS, GUN_DAMPING)
local gunTurn = Spring.new(GUN_STIFFNESS, GUN_DAMPING)
local look = Spring.new(LOOK_STIFFNESS, LOOK_DAMPING)
local lastProgress = 0
local drift = 0
local hold = IDENTITY
local random = Random.new()

function Viewmodel.show(visible: boolean)
	model.Parent = if visible then workspace.CurrentCamera else nil
end

function Viewmodel.fired()
	kick = KICK_TIME
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
	if progress <= OLD_MAGAZINE_RELEASED then
		return IDENTITY, true
	elseif progress < OLD_MAGAZINE_FREE then
		local u = (progress - OLD_MAGAZINE_RELEASED) / (OLD_MAGAZINE_FREE - OLD_MAGAZINE_RELEASED)
		return CFrame.new(0, -0.35 * (1 - (1 - u) ^ 2), 0), true
	elseif progress < OLD_MAGAZINE_GONE then
		-- Falling: slow at first, then faster, turning over as it goes.
		local u = (progress - OLD_MAGAZINE_FREE) / (OLD_MAGAZINE_GONE - OLD_MAGAZINE_FREE)
		return CFrame.new(0.05 * u, -0.35 - 0.6 * u - 1.65 * u * u, 0.1 * u) * CFrame.Angles(0.8 * u * u, 0, 0.3 * u),
			true
	elseif progress < NEW_MAGAZINE_SHOWN then
		return IDENTITY, false
	elseif progress < NEW_MAGAZINE_SEATED then
		local remaining = (NEW_MAGAZINE_SEATED - progress) / (NEW_MAGAZINE_SEATED - NEW_MAGAZINE_SHOWN)
		return CFrame.new(hand - HAND_WHEN_SEATED) * CFrame.Angles(NEW_MAGAZINE_TILT * remaining * remaining, 0, 0),
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
		drift = random:NextNumber(-TIMING_DRIFT, TIMING_DRIFT)
		hold = CFrame.Angles(
			random:NextNumber(-HOLD_DRIFT.X, HOLD_DRIFT.X),
			random:NextNumber(-HOLD_DRIFT.Y, HOLD_DRIFT.Y),
			random:NextNumber(-HOLD_DRIFT.Z, HOLD_DRIFT.Z)
		)
	end
	local progress = if raw > 0 then raw + math.sin(raw * math.pi) * drift else 0
	local aiming = state.aiming and progress == 0 and not state.sprinting and state.raiseTicks == 0
	local target = if progress > 0
		then (if progress >= RACK_START and progress < RACK_END then RACK else RELOAD) * hold
		elseif state.sprinting or state.raiseTicks > 0 then SPRINT
		elseif aiming then AIM
		else HIP
	local blend = 1 - math.exp(-POSE_SPEED * frameTime)
	current = current:Lerp(target, blend)
	aimBlend += ((if aiming then 1 else 0) - aimBlend) * blend
	reloadBlend += ((if progress > 0 then 1 else 0) - reloadBlend) * blend
	local motion = 1 - (1 - AIMED_MOTION) * aimBlend

	-- Sway: the gun lags behind the mouse, then settles.
	sway -= mouseDelta * SWAY_AMOUNT
	sway = Vector2.new(math.clamp(sway.X, -SWAY_LIMIT, SWAY_LIMIT), math.clamp(sway.Y, -SWAY_LIMIT, SWAY_LIMIT))
	sway *= math.exp(-SWAY_RETURN * frameTime)
	local swayFrame = CFrame.Angles(sway.Y * motion, sway.X * motion, sway.X * 0.5 * motion)

	-- Bob: a figure-eight while walking on the ground.
	local speed = if state.grounded then Vector3.new(state.velocity.X, 0, state.velocity.Z).Magnitude else 0
	walked += speed * frameTime
	local strength = math.min(speed / Config.stance(0).speed, 1.6) * BOB_AMOUNT * motion
	local phase = walked * BOB_SPEED * math.pi
	local bob = CFrame.new(math.sin(phase) * strength, -math.abs(math.cos(phase)) * strength, 0)

	kick = math.max(kick - frameTime, 0)
	local amount = kick / KICK_TIME
	local recoil = CFrame.new(0, KICK_UP * amount, KICK_BACK * amount) * CFrame.Angles(KICK_TILT * amount, 0, 0)

	local reloading = progress > 0
	local empty = reloading and reloadLength > weapon.reloadTicks

	-- The gun follows the reload's guide through springs, and gets knocked at
	-- the moments that would jolt it; the view gets a smaller nudge.
	local step = math.min(frameTime, MAX_FRAME)
	for _, hit in HITS do
		if lastProgress < hit.t and progress >= hit.t then
			Spring.impulse(gunMove, hit.move)
			Spring.impulse(gunTurn, hit.turn)
			Spring.impulse(look, hit.look)
		end
	end
	lastProgress = progress
	local guide = if reloading then sample(GUN_TRACK, progress) else IDENTITY
	Spring.step(gunMove, guide.Position, step)
	Spring.step(gunTurn, rotationOf(guide), step)
	Spring.step(look, Vector3.zero, step)
	local gunMotion = CFrame.new(gunMove.position) * turned(gunTurn.position)
	local origin = camera * bob * swayFrame * current * recoil * gunMotion

	-- The slide locks back on an empty magazine; the reload's rack pulls it
	-- back and lets it go.
	local slideBack
	if not reloading then
		slideBack = if state.ammo == 0 then 1 else amount
	elseif progress >= RACK_RELEASE then
		slideBack = 0
	elseif progress >= RACK_PULL then
		slideBack =
			math.max(if empty then 1 else 0, math.min((progress - RACK_PULL) / (RACK_RELEASE - RACK_PULL - 0.01), 1))
	else
		slideBack = if empty then 1 else 0
	end
	local slide = CFrame.new(0, 0, SLIDE_TRAVEL * slideBack)
	local barrel = CFrame.new(0, 0, BARREL_TRAVEL * slideBack)
	local leftHand = if reloading then CFrame.new(sampleArc(LEFT_HAND_TRACK, progress)) else LEFT_HAND_AT
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

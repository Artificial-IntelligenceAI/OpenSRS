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
-- with the left hand and seats it; from empty, the thumb then hits the slide
-- release and the slide snaps forward.

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Weapons = require(Shared.Weapons)
local Avatar = require(script.Parent.Avatar)
local GunModel = require(script.Parent.GunModel)

type State = Types.State

-- Where the gun's grip sits relative to the camera in each pose.
local AIM_REACH = 1.2 -- how far in front of the eye the rear sight sits when aiming: arms outstretched
local HIP = CFrame.new(0.4, -0.7, -1.3) -- straight and level
local SPRINT = CFrame.new(0.22, -0.8, -0.75) * CFrame.Angles(-0.45, 0.85, 0.3)
local RELOAD = CFrame.new(0.05, -0.32, -1.15) * CFrame.Angles(0.75, 0.25, -0.35) -- muzzle up, grip toward you: the magazine well shows
local RACK = RELOAD * CFrame.new(0, 0, -0.1) -- pushed out a little for racking the slide
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

-- Gun: a flick when the magazine release is pressed, a bump up as the new
-- magazine seats, and a jolt when the racked slide slams forward.
local GUN_TRACK = {
	key(0, IDENTITY),
	key(0.1, CFrame.Angles(0.06, 0, 0.05)),
	key(0.2, IDENTITY),
	key(0.46, IDENTITY),
	key(0.49, CFrame.new(0, 0.05, 0) * CFrame.Angles(-0.05, 0, 0)),
	key(0.53, IDENTITY),
	key(0.67, IDENTITY),
	key(0.7, CFrame.new(0, 0, 0.05) * CFrame.Angles(0.06, 0, 0)),
	key(0.78, IDENTITY),
}
-- The old magazine slides out, then drops out of view.
local OLD_MAGAZINE = { key(0.12, IDENTITY), key(0.18, at(0, -0.35, 0)), key(0.28, at(0, -2.6, 0)) }
local OLD_MAGAZINE_GONE = 0.28
-- The new magazine comes up from below in the left hand and goes straight in.
local NEW_MAGAZINE = { key(0.32, at(0, -1.4, 0.2)), key(0.41, at(0, -0.3, 0.02)), key(0.47, IDENTITY) }
local NEW_MAGAZINE_SHOWN = 0.32
local LEFT_HAND_TRACK = {
	key(0, LEFT_HAND_AT),
	key(0.12, LEFT_HAND_AT),
	key(0.24, at(-0.3, -1.2, 0.35)),
	key(0.3, at(-0.3, -2, 0.35)),
	key(0.33, at(-0.05, -1.55, 0.22)),
	key(0.41, at(-0.05, -0.45, 0.02)),
	key(0.47, at(-0.05, -0.15, 0.02)),
	key(0.56, at(-0.2, 0.45, 0.1)), -- pinch the back of the slide from its left side
	key(0.6, at(-0.2, 0.45, 0.1)),
	key(0.67, at(-0.2, 0.45, 0.31)), -- rack it back
	key(0.7, at(-0.28, 0.4, 0.26)), -- let go
	key(0.8, LEFT_HAND_AT),
}
-- The gun is pushed out a little for the rack; the left hand pinches the slide
-- from its left side, so the forearm stays below it.
local RACK_START = 0.5
local RACK_END = 0.72
local RACK_PULL = 0.6
local RACK_RELEASE = 0.68

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

function Viewmodel.show(visible: boolean)
	model.Parent = if visible then workspace.CurrentCamera else nil
end

function Viewmodel.fired()
	kick = KICK_TIME
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
local function magazineAt(progress: number): (CFrame, boolean)
	if progress <= 0 then
		return IDENTITY, true
	elseif progress < OLD_MAGAZINE_GONE then
		return sample(OLD_MAGAZINE, progress), true
	elseif progress < NEW_MAGAZINE_SHOWN then
		return IDENTITY, false
	end
	return sample(NEW_MAGAZINE, progress), true
end

-- An arm reaching from a shoulder to a hand; only the hand end is usually on screen.
local function arm(shoulder: Vector3, hand: Vector3): CFrame
	local direction = (shoulder - hand).Unit
	return CFrame.lookAt(hand + direction * (ARM_LENGTH / 2), hand)
end

-- Positions the gun and arms for this frame and returns where the muzzle is.
function Viewmodel.update(camera: CFrame, state: State, mouseDelta: Vector2, frameTime: number): Vector3
	local progress = reloadProgress(state)
	local aiming = state.aiming and progress == 0 and not state.sprinting and state.raiseTicks == 0
	local target = if progress > 0
		then (if progress >= RACK_START and progress < RACK_END then RACK else RELOAD)
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
	local gunMotion = if reloading then sample(GUN_TRACK, progress) else IDENTITY
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
	local magazine, magazineShown = magazineAt(progress)
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

	local leftHand = if reloading then sample(LEFT_HAND_TRACK, progress) else LEFT_HAND_AT
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

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The gun and arms in the player's own view. It only exists on this client and
-- never affects gameplay.
--
-- From the hip the gun comes in from the lower right. Aiming holds it out at
-- arm's length with both arms reaching up from the bottom of the screen and
-- the sights lined up on the center. It sways against mouse movement, bobs
-- while walking, kicks on each shot (the slide cycles), and drops the magazine
-- while reloading.

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
local RELOAD = CFrame.new(0.12, -0.62, -0.8) * CFrame.Angles(0.55, 0.25, 0.6)
local POSE_SPEED = 16

-- Arms: shoulders are fixed to the camera, hands follow the gun.
-- Two-handed pistol grip: the right arm runs straight out to the grip, and
-- the left arm comes across from the left to wrap around the right hand.
local RIGHT_SHOULDER = Vector3.new(0.2, -1.45, 0.5)
local LEFT_SHOULDER = Vector3.new(-1.2, -1.4, 0.15)
local RIGHT_HAND = Vector3.new(0.02, 0.2, 0.06) -- in the gun's space, around the grip
local LEFT_HAND = Vector3.new(-0.1, 0.1, 0.02) -- wrapped around the right hand, from the left
local ARM_WIDTH = 0.38
local ARM_LENGTH = 2.6 -- long enough to reach off screen from the hand

local KICK_TIME = 0.07
local KICK_BACK = 0.05
local KICK_UP = 0.025
local KICK_TILT = 0.12
local SLIDE_TRAVEL = 0.19
local BARREL_TRAVEL = 0.06
local MAGAZINE_DROP = 0.9

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

-- How far the magazine is out, from 0 (seated) to 1 (gone), during a reload.
local function magazineOut(progress: number): number
	if progress <= 0 then
		return 0
	elseif progress < 0.3 then
		return progress / 0.3
	elseif progress < 0.55 then
		return 1
	elseif progress < 0.75 then
		return 1 - (progress - 0.55) / 0.2
	end
	return 0
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
		then RELOAD
		elseif state.sprinting or state.raiseTicks > 0 then SPRINT
		elseif aiming then AIM
		else HIP
	local blend = 1 - math.exp(-POSE_SPEED * frameTime)
	current = current:Lerp(target, blend)
	aimBlend += ((if aiming then 1 else 0) - aimBlend) * blend
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

	local origin = camera * bob * swayFrame * current * recoil

	local slide = CFrame.new(0, 0, SLIDE_TRAVEL * amount)
	local barrel = CFrame.new(0, 0, BARREL_TRAVEL * amount)
	local out = magazineOut(progress)
	local magazine = CFrame.new(0, -MAGAZINE_DROP * out, 0)
	for index, part in gunParts do
		local offset = rest[index]
		if part.Name == "Slide" then
			offset = slide * offset
		elseif part.Name == "Barrel" then
			offset = barrel * offset
		elseif part.Name == "Magazine" then
			offset = magazine * offset
			part.LocalTransparencyModifier = if out >= 1 then 1 else 0
		end
		cframes[index] = origin * offset
	end

	-- While reloading the support hand goes down to fetch the magazine.
	local leftHandPoint = (origin * CFrame.new(LEFT_HAND + Vector3.new(0, -MAGAZINE_DROP * out, 0))).Position
	local rightHandPoint = (origin * CFrame.new(RIGHT_HAND)).Position
	local count = #gunParts
	cframes[count + 1] = arm((camera * CFrame.new(RIGHT_SHOULDER)).Position, rightHandPoint)
	cframes[count + 2] = arm((camera * CFrame.new(LEFT_SHOULDER)).Position, leftHandPoint)
	cframes[count + 3] = origin * FILL_OFFSET
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	return (origin * MUZZLE).Position
end

return table.freeze(Viewmodel)

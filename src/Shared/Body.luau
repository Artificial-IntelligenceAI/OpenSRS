--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The R6 body layout for every stance. Avatars are drawn from these part
-- positions, and hitboxes will use the same ones, so what players see is
-- exactly what they can hit.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local Stance = Types.Stance

-- One of Body.PART_NAMES.
export type PartName = string
export type Pose = { [PartName]: CFrame }

local Body = {}

Body.PART_NAMES = table.freeze({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" })

Body.SIZES = table.freeze({
	Head = Vector3.new(1.2, 1.2, 1.2),
	Torso = Vector3.new(2, 2, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
})

local HALF_PI = math.pi / 2

-- Arms held forward, aiming along the pitch, from a shoulder at `shoulder`.
local function aimingArm(shoulder: Vector3, pitch: number): CFrame
	return CFrame.new(shoulder) * CFrame.Angles(HALF_PI + pitch, 0, 0) * CFrame.new(0, -1, 0)
end

local function upright(pitch: number, hipHeight: number, legTilt: number): Pose
	local torsoY = hipHeight + 1
	local shoulderY = torsoY + 0.8
	return {
		["Left Leg"] = CFrame.new(-0.5, hipHeight, 0) * CFrame.Angles(legTilt, 0, 0) * CFrame.new(0, -1, 0),
		["Right Leg"] = CFrame.new(0.5, hipHeight, 0) * CFrame.Angles(legTilt, 0, 0) * CFrame.new(0, -1, 0),
		Torso = CFrame.new(0, torsoY, 0),
		Head = CFrame.new(0, torsoY + 1, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0.6, 0),
		["Left Arm"] = aimingArm(Vector3.new(-1.5, shoulderY, 0), pitch),
		["Right Arm"] = aimingArm(Vector3.new(1.5, shoulderY, 0), pitch),
	}
end

local function prone(pitch: number): Pose
	-- Lying face down with the head over the feet point and the body behind it.
	local flat = CFrame.Angles(-HALF_PI, 0, 0)
	return {
		Head = CFrame.new(0, 0.7, 0) * CFrame.Angles(pitch, 0, 0),
		Torso = CFrame.new(0, 0.5, 1.6) * flat,
		["Left Leg"] = CFrame.new(-0.5, 0.5, 3.6) * flat,
		["Right Leg"] = CFrame.new(0.5, 0.5, 3.6) * flat,
		-- Arms reach forward; their -Y points ahead, like the upright aiming arms.
		["Left Arm"] = CFrame.new(-1.2, 0.5, -0.6) * CFrame.Angles(HALF_PI, 0, 0),
		["Right Arm"] = CFrame.new(1.2, 0.5, -0.6) * CFrame.Angles(HALF_PI, 0, 0),
	}
end

-- World-space CFrames for every body part.
function Body.pose(position: Vector3, yaw: number, pitch: number, stance: number, leanOffset: number): Pose
	local local_: Pose
	if stance == Stance.Prone then
		local_ = prone(pitch)
	elseif stance == Stance.Crouch then
		local_ = upright(pitch, 1.1, -math.rad(60))
	else
		local_ = upright(pitch, 2, 0)
	end

	-- Leaning rolls the upper body around a pivot until the head is over the lean offset.
	local config = Config.stance(stance)
	if leanOffset ~= 0 and stance ~= Stance.Prone then
		local reach = config.eyeHeight - config.leanPivot
		local roll = -math.asin(math.clamp(leanOffset / reach, -1, 1))
		local pivot = CFrame.new(0, config.leanPivot, 0)
		local rotate = pivot * CFrame.Angles(0, 0, roll) * pivot:Inverse()
		for _, name in { "Torso", "Head", "Left Arm", "Right Arm" } do
			local_[name] = rotate * local_[name]
		end
	end

	local root = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local world: Pose = {}
	for name, cframe in local_ do
		world[name] = root * cframe
	end
	return world
end

-- The right hand, facing where the arm points (-Z) with +Y up. Held guns are
-- placed relative to this. Not a hitbox.
function Body.hand(pose: Pose): CFrame
	return pose["Right Arm"] * CFrame.new(0, -1.1, 0) * CFrame.Angles(-HALF_PI, 0, 0)
end

return table.freeze(Body)

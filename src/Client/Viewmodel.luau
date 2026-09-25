--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The gun in the player's own hands. It only exists on this client and never
-- affects gameplay: the slide kicks back on each shot, the magazine drops out
-- and goes back in while reloading, and aiming lines the rear sight up with the
-- center of the screen.

local Shared = script.Parent.Parent.Shared
local Types = require(Shared.Types)
local Weapons = require(Shared.Weapons)
local GunModel = require(script.Parent.GunModel)

type State = Types.State

local AIM_DISTANCE = 0.9 -- how far in front of the eye the rear sight sits when aiming
local HIP = CFrame.new(0.45, -0.95, -1.3)
local SPRINT = CFrame.new(0.3, -1.15, -1.0) * CFrame.Angles(-0.35, 0.7, 0.15)
local RELOAD = CFrame.new(0.25, -0.95, -1.15) * CFrame.Angles(0.45, 0.3, 0.5)
local BLEND_SPEED = 14
local KICK_TIME = 0.07
local KICK_BACK = 0.1
local KICK_UP = 0.06
local SLIDE_TRAVEL = 0.19
local BARREL_TRAVEL = 0.06
local MAGAZINE_DROP = 0.9

local Viewmodel = {}

local weapon = Weapons.default
local model = GunModel.new(weapon.name, "FirstPerson")
model.Name = "OpenSRSViewmodel"

local parts: { BasePart } = {}
local rest: { CFrame } = {} -- each part relative to the grip
local pivot = model:GetPivot()
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") then
		table.insert(parts, part)
		table.insert(rest, pivot:ToObjectSpace(part.CFrame))
	end
end

local function localPoint(name: string, fallback: Vector3): CFrame
	local attachment = GunModel.point(model, name)
	return if attachment then pivot:ToObjectSpace(attachment.WorldCFrame) else CFrame.new(fallback)
end

local MUZZLE = localPoint("Muzzle", Vector3.new(0, 0.44, -1))
local SIGHT = localPoint("RearSight", Vector3.new(0, 0.53, 0.05))
local AIM = CFrame.new(0, 0, -AIM_DISTANCE) * CFrame.new(-SIGHT.Position)

local cframes: { CFrame } = table.create(#parts)
local current = HIP
local kick = 0
local reloadLength = 0

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

-- Positions the gun for this frame and returns where its muzzle is.
function Viewmodel.update(camera: CFrame, state: State, frameTime: number): Vector3
	local progress = reloadProgress(state)
	local target = if progress > 0
		then RELOAD
		elseif state.sprinting or state.raiseTicks > 0 then SPRINT
		elseif state.aiming then AIM
		else HIP
	current = current:Lerp(target, 1 - math.exp(-BLEND_SPEED * frameTime))

	kick = math.max(kick - frameTime, 0)
	local amount = kick / KICK_TIME
	local recoil = CFrame.new(0, KICK_UP * amount, KICK_BACK * amount) * CFrame.Angles(0.1 * amount, 0, 0)
	local origin = camera * current * recoil

	local slide = CFrame.new(0, 0, SLIDE_TRAVEL * amount)
	local barrel = CFrame.new(0, 0, BARREL_TRAVEL * amount)
	local magazine = CFrame.new(0, -MAGAZINE_DROP * magazineOut(progress), 0)
	for index, part in parts do
		local offset = rest[index]
		if part.Name == "Slide" then
			offset = slide * offset
		elseif part.Name == "Barrel" then
			offset = barrel * offset
		elseif part.Name == "Magazine" then
			offset = magazine * offset
			part.LocalTransparencyModifier = if magazineOut(progress) >= 1 then 1 else 0
		end
		cframes[index] = origin * offset
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	return (origin * MUZZLE).Position
end

return table.freeze(Viewmodel)

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The gun in the player's own hands. A block stand-in until the X16 model is
-- ready. It only exists on this client and never affects gameplay.

local Types = require(script.Parent.Parent.Shared.Types)

type State = Types.State

local HIP = CFrame.new(0.55, -0.55, -1.5)
local AIM = CFrame.new(0, -0.32, -1.25) -- sights centered on the screen
local SPRINT = CFrame.new(0.35, -0.75, -1.2) * CFrame.Angles(-0.35, 0.7, 0.15)
local RELOAD = CFrame.new(0.3, -0.75, -1.3) * CFrame.Angles(0.5, 0.3, 0.6)
local BLEND_SPEED = 14
local KICK_TIME = 0.06
local SLIDE_TRAVEL = 0.3

local Viewmodel = {}

local model = Instance.new("Model")
model.Name = "OpenSRSViewmodel"

local function block(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = Color3.fromRGB(30, 30, 32)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

-- Offsets are from the gun's origin at the rear of the slide; the gun points toward -Z.
local slide = block("Slide", Vector3.new(0.24, 0.2, 1.2))
local frame = block("Frame", Vector3.new(0.22, 0.14, 1.05))
local grip = block("Grip", Vector3.new(0.22, 0.6, 0.32))
local SLIDE_OFFSET = CFrame.new(0, 0.12, -0.6)
local FRAME_OFFSET = CFrame.new(0, -0.05, -0.62)
local GRIP_OFFSET = CFrame.new(0, -0.35, -0.12) * CFrame.Angles(0.3, 0, 0)
local MUZZLE_OFFSET = CFrame.new(0, 0.12, -1.2)

local current = HIP
local kick = 0

function Viewmodel.show(visible: boolean)
	model.Parent = if visible then workspace.CurrentCamera else nil
end

function Viewmodel.fired()
	kick = KICK_TIME
end

-- Positions the gun for this frame and returns where its muzzle is.
function Viewmodel.update(camera: CFrame, state: State, frameTime: number): Vector3
	local target = if state.reloadTicks > 0
		then RELOAD
		elseif state.sprinting or state.raiseTicks > 0 then SPRINT
		elseif state.aiming then AIM
		else HIP
	current = current:Lerp(target, 1 - math.exp(-BLEND_SPEED * frameTime))

	kick = math.max(kick - frameTime, 0)
	local kickAmount = kick / KICK_TIME
	local recoil = CFrame.new(0, 0, 0.12 * kickAmount) * CFrame.Angles(0.08 * kickAmount, 0, 0)
	local origin = camera * current * recoil

	slide.CFrame = origin * SLIDE_OFFSET * CFrame.new(0, 0, SLIDE_TRAVEL * kickAmount)
	frame.CFrame = origin * FRAME_OFFSET
	grip.CFrame = origin * GRIP_OFFSET
	return (origin * MUZZLE_OFFSET).Position
end

return table.freeze(Viewmodel)

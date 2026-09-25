--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Turns keyboard and mouse into inputs.
--
-- WASD move, mouse looks, Space jumps, Left Shift sprints, Left Alt slow-walks,
-- C toggles crouch, Z toggles prone, Q and E lean.

local UserInputService = game:GetService("UserInputService")

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)

type Input = Types.Input

local Buttons = Types.Buttons
local Stance = Types.Stance
local RADIANS_PER_PIXEL = 0.004

local InputMap = {}

local yaw = 0
local pitch = 0
local stance: number = Stance.Stand

local function down(key: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(key)
end

function InputMap.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			stance = if stance == Stance.Crouch then Stance.Stand else Stance.Crouch
		elseif input.KeyCode == Enum.KeyCode.Z then
			stance = if stance == Stance.Prone then Stance.Stand else Stance.Prone
		elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.LeftShift then
			stance = Stance.Stand
		end
	end)
end

-- Called every frame, before sampling.
function InputMap.updateLook()
	local delta = UserInputService:GetMouseDelta()
	yaw = (yaw - delta.X * RADIANS_PER_PIXEL + math.pi) % (2 * math.pi) - math.pi
	pitch = math.clamp(pitch - delta.Y * RADIANS_PER_PIXEL, -Config.movement.maxPitch, Config.movement.maxPitch)
end

function InputMap.look(): (number, number)
	return yaw, pitch
end

function InputMap.sample(seq: number): Input
	local input: Input = {
		seq = seq,
		moveX = 0,
		moveZ = 0,
		yaw = yaw,
		pitch = pitch,
		buttons = 0,
		stance = stance,
	}
	if UserInputService:GetFocusedTextBox() then
		return input
	end

	input.moveX = (if down(Enum.KeyCode.D) then 1 else 0) - (if down(Enum.KeyCode.A) then 1 else 0)
	input.moveZ = (if down(Enum.KeyCode.W) then 1 else 0) - (if down(Enum.KeyCode.S) then 1 else 0)

	local buttons = 0
	if down(Enum.KeyCode.Space) then
		buttons += Buttons.Jump
	end
	if down(Enum.KeyCode.LeftShift) then
		buttons += Buttons.Sprint
	end
	if down(Enum.KeyCode.LeftAlt) then
		buttons += Buttons.SlowWalk
	end
	if down(Enum.KeyCode.Q) then
		buttons += Buttons.LeanLeft
	end
	if down(Enum.KeyCode.E) then
		buttons += Buttons.LeanRight
	end
	input.buttons = buttons
	return input
end

return table.freeze(InputMap)

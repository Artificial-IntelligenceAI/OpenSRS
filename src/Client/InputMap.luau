--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Turns keyboard and mouse into inputs.
--
-- WASD move, mouse looks, Space jumps, Left Shift sprints, Left Alt slow-walks,
-- C toggles crouch, Z toggles prone, Q and E toggle leaning left and right.

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
local lean = 0 -- -1 left, 0 upright, 1 right

local function down(key: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(key)
end

function InputMap.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.C then
			stance = if stance == Stance.Crouch then Stance.Stand else Stance.Crouch
		elseif key == Enum.KeyCode.Z then
			stance = if stance == Stance.Prone then Stance.Stand else Stance.Prone
			lean = 0
		elseif key == Enum.KeyCode.Space then
			stance = Stance.Stand
		elseif key == Enum.KeyCode.LeftShift then
			stance = Stance.Stand
			lean = 0
		elseif key == Enum.KeyCode.Q then
			lean = if lean == -1 then 0 else -1
		elseif key == Enum.KeyCode.E then
			lean = if lean == 1 then 0 else 1
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
	if lean == -1 then
		buttons += Buttons.LeanLeft
	elseif lean == 1 then
		buttons += Buttons.LeanRight
	end
	input.buttons = buttons
	return input
end

return table.freeze(InputMap)

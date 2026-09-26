--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Turns keyboard and mouse into inputs.
--
-- WASD move, mouse looks, Space jumps, Left Shift sprints, Left Alt slow-walks,
-- C toggles crouch, Z toggles prone, Q and E lean left and right. Left click
-- fires, right click aims, R reloads. Whether aiming and leaning are held or
-- toggled are the AimToggle and LeanToggle settings.

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
local lean = 0 -- -1 left, 0 upright, 1 right, while leaning is toggled
local aimToggled = false -- aiming, while aiming is toggled
-- Presses shorter than a tick still count.
local firePressed = false
local reloadPressed = false

local function down(key: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(key)
end

function InputMap.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			firePressed = true
			return
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			aimToggled = Config.aimToggle and not aimToggled
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.R then
			reloadPressed = true
		elseif key == Enum.KeyCode.C then
			stance = if stance == Stance.Crouch then Stance.Stand else Stance.Crouch
		elseif key == Enum.KeyCode.Z then
			stance = if stance == Stance.Prone then Stance.Stand else Stance.Prone
			lean = 0
		elseif key == Enum.KeyCode.Space then
			stance = Stance.Stand
		elseif key == Enum.KeyCode.LeftShift then
			stance = Stance.Stand
			lean = 0
			aimToggled = false
		elseif key == Enum.KeyCode.Q and Config.leanToggle then
			lean = if lean == -1 then 0 else -1
		elseif key == Enum.KeyCode.E and Config.leanToggle then
			lean = if lean == 1 then 0 else 1
		end
	end)
end

local lastDelta = Vector2.zero

-- Called every frame, before sampling.
function InputMap.updateLook()
	local delta = UserInputService:GetMouseDelta()
	lastDelta = delta
	yaw = (yaw - delta.X * RADIANS_PER_PIXEL + math.pi) % (2 * math.pi) - math.pi
	pitch = math.clamp(pitch - delta.Y * RADIANS_PER_PIXEL, -Config.movement.maxPitch, Config.movement.maxPitch)
end

function InputMap.look(): (number, number)
	return yaw, pitch
end

-- Points the view (and so the aim) straight at `newYaw`/`newPitch`, and pulls
-- the trigger once. For tools and tests, like the test place's fake aimbot:
-- a client can always steer itself, which is why the server judges its aim.
function InputMap.setLook(newYaw: number, newPitch: number)
	yaw = (newYaw + math.pi) % (2 * math.pi) - math.pi
	pitch = math.clamp(newPitch, -Config.movement.maxPitch, Config.movement.maxPitch)
end

function InputMap.pullTrigger()
	firePressed = true
end

-- How far the mouse moved this frame, in pixels.
function InputMap.mouseDelta(): Vector2
	return lastDelta
end

-- `viewTick` is the server tick other players are currently drawn at.
function InputMap.sample(seq: number, viewTick: number): Input
	local input: Input = {
		seq = seq,
		moveX = 0,
		moveZ = 0,
		yaw = yaw,
		pitch = pitch,
		buttons = 0,
		stance = stance,
		viewTick = viewTick,
	}
	local fire = firePressed
	local reload = reloadPressed
	firePressed = false
	reloadPressed = false
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
	local leaning = if Config.leanToggle
		then lean
		else (if down(Enum.KeyCode.E) then 1 else 0) - (if down(Enum.KeyCode.Q) then 1 else 0)
	if leaning == -1 then
		buttons += Buttons.LeanLeft
	elseif leaning == 1 then
		buttons += Buttons.LeanRight
	end
	if fire or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		buttons += Buttons.Fire
	end
	local aiming = if Config.aimToggle
		then aimToggled
		else UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	if aiming then
		buttons += Buttons.Aim
	end
	if reload then
		buttons += Buttons.Reload
	end
	input.buttons = buttons
	return input
end

return table.freeze(InputMap)

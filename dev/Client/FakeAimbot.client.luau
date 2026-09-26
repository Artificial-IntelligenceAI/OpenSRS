--!strict
-- SPDX-License-Identifier: Apache-2.0

-- A fake aimbot, for testing OpenSRS's aimbot flags in the test place. Only
-- dev.project.json syncs this. B cycles it: off, lock-on (the view stays glued
-- to the nearest shown player's head, and looks away when they go out of view,
-- so it has to turn to react when they're back), snap (every 1.5 s it looks
-- away, then flicks straight onto their head and fires). Flags raised show on
-- screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local OpenSRS = ReplicatedStorage:WaitForChild("OpenSRS")
repeat
	task.wait()
until OpenSRS:GetAttribute("Ready")
local InputMap = require(OpenSRS:WaitForChild("Client"):WaitForChild("InputMap")) :: any

local MODES = { "off", "lock-on", "snap" }
local SNAP_EVERY = 1.5
local LOOK_AWAY = 0.35 -- radians turned away before each snap

local mode = 1
local camera = workspace.CurrentCamera

local gui = Instance.new("ScreenGui")
gui.Name = "OpenSRSFakeAimbot"
gui.ResetOnSpawn = false
local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 16, 1, -94)
status.Size = UDim2.fromOffset(460, 24)
status.BackgroundTransparency = 0.5
status.BackgroundColor3 = Color3.new(0, 0, 0)
status.TextColor3 = Color3.fromRGB(255, 200, 80)
status.Font = Enum.Font.GothamMedium
status.TextSize = 14
status.Parent = gui
local flag = status:Clone()
flag.Position = UDim2.new(0.5, -300, 0, 60)
flag.AnchorPoint = Vector2.new(0, 0)
flag.Size = UDim2.fromOffset(600, 48)
flag.TextWrapped = true
flag.TextColor3 = Color3.fromRGB(255, 90, 90)
flag.Visible = false
flag.Parent = gui
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local function show()
	status.Text = `Fake aimbot (B): {MODES[mode]}`
end
show()

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.B and not processed then
		mode = mode % #MODES + 1
		show()
	end
end)

local flagged = ReplicatedStorage:WaitForChild("OpenSRSDevFlag") :: RemoteEvent
flagged.OnClientEvent:Connect(function(text: string)
	flag.Text = text
	flag.Visible = true
	task.delay(6, function()
		if flag.Text == text then
			flag.Visible = false
		end
	end)
end)

-- The head of the nearest player being shown.
local function target(): Vector3?
	local puppets = workspace:FindFirstChild("OpenSRSPuppets")
	local eye = camera.CFrame.Position
	local best, bestDistance = nil, math.huge
	for _, puppet in (if puppets then puppets:GetChildren() else {}) do
		local head = puppet:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local distance = (head.Position - eye).Magnitude
			if distance < bestDistance then
				best, bestDistance = head.Position, distance
			end
		end
	end
	return best
end

local function lookAt(point: Vector3, turn: number?)
	local direction = (point - camera.CFrame.Position).Unit
	InputMap.setLook(math.atan2(-direction.X, -direction.Z) + (turn or 0), math.asin(direction.Y))
end

local sinceSnap = 0
local lookedAway = false
local hadTarget = false
-- Before OpenSRS's own frame, so the view it draws and sends is the aimbot's.
RunService:BindToRenderStep("OpenSRSFakeAimbot", Enum.RenderPriority.Camera.Value, function(frameTime)
	local head = target()
	if MODES[mode] == "off" then
		return
	end
	if not head then
		if hadTarget and MODES[mode] == "lock-on" then
			local look = camera.CFrame.LookVector
			InputMap.setLook(math.atan2(-look.X, -look.Z) + LOOK_AWAY * 2, 0)
		end
		hadTarget = false
		return
	end
	hadTarget = true
	if MODES[mode] == "lock-on" then
		lookAt(head)
	else
		sinceSnap += frameTime
		if not lookedAway and sinceSnap >= SNAP_EVERY - 0.4 then
			lookedAway = true
			lookAt(head, if math.random() < 0.5 then LOOK_AWAY else -LOOK_AWAY)
		elseif sinceSnap >= SNAP_EVERY then
			sinceSnap = 0
			lookedAway = false
			lookAt(head)
			InputMap.pullTrigger()
		end
	end
end)

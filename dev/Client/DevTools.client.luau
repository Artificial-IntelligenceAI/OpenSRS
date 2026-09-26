--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The OpenSRS test place's keys (see DevTools.server): J goes inside the spawn
-- box, K outside it, L to the zombie arena, and N switches your shooting off
-- and on. Only dev.project.json syncs this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.J] = "Inside",
	[Enum.KeyCode.K] = "Outside",
	[Enum.KeyCode.L] = "Arena",
	[Enum.KeyCode.N] = "ToggleShooting",
}

local teleport = ReplicatedStorage:WaitForChild("OpenSRSDevTeleport") :: RemoteEvent

UserInputService.InputBegan:Connect(function(input, processed)
	local where = KEYS[input.KeyCode]
	if where and not processed then
		teleport:FireServer(where)
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "OpenSRSDev"
gui.ResetOnSpawn = false
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0, 1)
hint.Position = UDim2.new(0, 16, 1, -64)
hint.Size = UDim2.fromOffset(460, 24)
hint.BackgroundTransparency = 0.5
hint.BackgroundColor3 = Color3.new(0, 0, 0)
hint.TextColor3 = Color3.new(1, 1, 1)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 14
hint.Text = "Dev:  J inside  ·  K outside  ·  L zombie arena  ·  N shooting on/off"
hint.Parent = gui
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

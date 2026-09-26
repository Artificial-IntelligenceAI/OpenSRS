--!strict
-- SPDX-License-Identifier: Apache-2.0

-- The on-screen HUD: crosshair, ammo, health, hit markers, the death notice,
-- and a tag while the game has stopped the player shooting.

local Players = game:GetService("Players")

local Protocol = require(script.Parent.Parent.Shared.Protocol)

local HITMARKER_TIME = 0.15
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 70, 70)
local CANT_SHOOT_TEXT = "Can't shoot"

local Hud = {}

local gui = Instance.new("ScreenGui")
gui.Name = "OpenSRSHud"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false

local function label(name: string, anchor: Vector2, position: UDim2, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = anchor
	text.Position = position
	text.Size = UDim2.fromOffset(300, size + 8)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = size
	text.TextColor3 = WHITE
	text.TextStrokeTransparency = 0.5
	text.TextXAlignment = if anchor.X == 1 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	text.Parent = gui
	return text
end

local ammo = label("Ammo", Vector2.new(1, 1), UDim2.new(1, -24, 1, -20), 28)
local health = label("Health", Vector2.new(0, 1), UDim2.new(0, 24, 1, -20), 28)
local cantShoot = label("CantShoot", Vector2.new(1, 1), UDim2.new(1, -24, 1, -56), 18)
cantShoot.Text = CANT_SHOOT_TEXT
cantShoot.TextColor3 = RED
cantShoot.Visible = false
local notice = label("Notice", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.4), 32)
notice.TextXAlignment = Enum.TextXAlignment.Center
notice.Visible = false

-- Four short lines around the center; their gap shows the current spread.
local crosshair: { Frame } = {}
for index = 1, 4 do
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundColor3 = WHITE
	line.BorderSizePixel = 0
	line.Size = if index <= 2 then UDim2.fromOffset(2, 8) else UDim2.fromOffset(8, 2)
	line.Parent = gui
	crosshair[index] = line
end

local hitmarker: { Frame } = {}
for index = 1, 2 do
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.5)
	line.Size = UDim2.fromOffset(2, 18)
	line.Rotation = if index == 1 then 45 else -45
	line.BorderSizePixel = 0
	line.Visible = false
	line.Parent = gui
	hitmarker[index] = line
end
local hitmarkerUntil = 0

function Hud.start()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- `spreadDegrees` and `fieldOfView` size the crosshair to match real spread.
function Hud.update(
	ammoCount: number,
	reserve: number,
	reloading: boolean,
	healthPoints: number,
	spreadDegrees: number,
	fieldOfView: number,
	showCrosshair: boolean,
	canShoot: boolean
)
	ammo.Text = if reloading then "Reloading…" else `{ammoCount} / {reserve}`
	cantShoot.Visible = not canShoot
	health.Text = `{math.ceil(healthPoints)} HP`

	local viewport = workspace.CurrentCamera.ViewportSize
	local gap = math.tan(math.rad(spreadDegrees)) / math.tan(math.rad(fieldOfView / 2)) * viewport.Y / 2 + 4
	local offsets =
		{ Vector2.new(0, -gap - 4), Vector2.new(0, gap + 4), Vector2.new(-gap - 4, 0), Vector2.new(gap + 4, 0) }
	for index, line in crosshair do
		line.Visible = showCrosshair
		line.Position = UDim2.new(0.5, offsets[index].X, 0.5, offsets[index].Y)
	end

	local showHit = os.clock() < hitmarkerUntil
	for _, line in hitmarker do
		line.Visible = showHit
	end
end

function Hud.hit(kind: number)
	hitmarkerUntil = os.clock() + HITMARKER_TIME
	for _, line in hitmarker do
		line.BackgroundColor3 = if kind == Protocol.HitKind.Head then RED else WHITE
	end
end

function Hud.setAlive(alive: boolean)
	notice.Text = "You died"
	notice.Visible = not alive
	ammo.Visible = alive
	health.Visible = alive
	if not alive then
		cantShoot.Visible = false
	end
end

return table.freeze(Hud)

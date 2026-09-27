--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Damage numbers: each hit's damage pops off the spot it hit, drifts up with a
-- little sideways kick and fades. White for body hits, yellow for headshots,
-- red for the hit that kills. Only the shooter sees them, and only for damage
-- that really landed (the server sends it; see Combat). Purely cosmetic.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local LIFETIME = 0.8 -- seconds a number stays up
local RISE = 2.2 -- studs it drifts up
local DRIFT = 0.9 -- studs it may drift sideways, either way
local SIZE = 26
local WHITE = Color3.new(1, 1, 1)
local YELLOW = Color3.fromRGB(255, 214, 64)
local RED = Color3.fromRGB(255, 70, 70)

local DamageNumbers = {}

local random = Random.new()

function DamageNumbers.show(at: Vector3, amount: number, head: boolean, killed: boolean)
	local anchor = Instance.new("Attachment")
	anchor.Name = "SecureRGSDamageNumber"
	anchor.WorldPosition = at -- attachments on Terrain are in world space
	anchor.Parent = workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 48)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 1000
	gui.Adornee = anchor
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = tostring(math.max(math.round(amount), 1))
	label.TextSize = if killed or head then SIZE + 4 else SIZE
	label.TextColor3 = if killed then RED elseif head then YELLOW else WHITE
	label.TextStrokeTransparency = 0.35
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label

	-- Pop in, overshooting a little, then settle.
	TweenService:Create(scale, TweenInfo.new(0.09, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.15,
	}):Play()
	task.delay(0.09, function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	-- Drift up and a little to one side.
	local drift = random:NextNumber(-DRIFT, DRIFT)
	TweenService:Create(gui, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(drift, RISE, 0),
	}):Play()
	-- Fade over the second half.
	local fade = TweenInfo.new(LIFETIME / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, LIFETIME / 2)
	TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	Debris:AddItem(anchor, LIFETIME + 0.1)
end

return table.freeze(DamageNumbers)

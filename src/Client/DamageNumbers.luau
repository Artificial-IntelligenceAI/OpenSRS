--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Damage numbers: each hit's damage pops up beside the spot it hit (so it
-- doesn't cover the target), drifts up and further away, and fades. Only the
-- shooter sees them, and only for damage that really landed (the server sends
-- it; see Combat). Purely cosmetic. Everything about how they look is the
-- DamageNumbers settings (see Config.damageNumbers).

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Parent.Shared.Config)

local POP_TIME = 0.09 -- seconds to pop in
local SETTLE_TIME = 0.12 -- seconds to settle after overshooting

local DamageNumbers = {}

local random = Random.new()

function DamageNumbers.show(at: Vector3, amount: number, head: boolean, killed: boolean)
	local settings = Config.damageNumbers
	local anchor = Instance.new("Attachment")
	anchor.Name = "SecureRGSDamageNumber"
	anchor.WorldPosition = at -- attachments on Terrain are in world space
	anchor.Parent = workspace.Terrain

	local size = if killed or head then settings.size * 1.15 else settings.size
	local width = size * 5
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, size * 1.9)
	-- The offset is in pixels, so it's the same on screen at any distance.
	gui.SizeOffset = Vector2.new(settings.offset / width, 0)
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
	label.TextSize = size
	label.TextColor3 = if killed then settings.killColor elseif head then settings.headshotColor else settings.bodyColor
	label.TextStrokeTransparency = 0.35
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label

	-- Pop in, overshooting a little, then settle.
	TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.15,
	}):Play()
	task.delay(POP_TIME, function()
		TweenService:Create(scale, TweenInfo.new(SETTLE_TIME), { Scale = 1 }):Play()
	end)
	-- Drift up and a little further out, on the side it appears on.
	local lifetime = settings.lifetime
	local side = if settings.offset < 0 then -1 else 1
	local drift = random:NextNumber(0, settings.drift) * side
	TweenService:Create(gui, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(drift, settings.rise, 0),
	}):Play()
	-- Fade over the second half.
	local fade = TweenInfo.new(lifetime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, lifetime / 2)
	TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	Debris:AddItem(anchor, lifetime + 0.1)
end

return table.freeze(DamageNumbers)

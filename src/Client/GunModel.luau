--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Builds a gun model to draw: the real art if it shipped, otherwise a block
-- stand-in with the same layout. Either way the model's pivot is the grip,
-- it faces -Z, and it has Muzzle and RearSight attachments.

local Assets = require(script.Parent.Assets)

local GunModel = {}

local function block(model: Model, name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = Color3.fromRGB(30, 30, 32)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = model
	return part
end

local function standIn(): Model
	local model = Instance.new("Model")
	model.Name = "StandIn"
	local slide = block(model, "Slide", Vector3.new(0.16, 0.16, 1.2), CFrame.new(0, 0.44, -0.4))
	block(model, "Frame", Vector3.new(0.14, 0.14, 0.95), CFrame.new(0, 0.32, -0.45))
	block(model, "Grip", Vector3.new(0.14, 0.5, 0.25), CFrame.new(0, 0.12, 0.02) * CFrame.Angles(0.3, 0, 0))
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = slide
	muzzle.WorldPosition = Vector3.new(0, 0.44, -1)
	local sight = Instance.new("Attachment")
	sight.Name = "RearSight"
	sight.Parent = slide
	sight.WorldPosition = Vector3.new(0, 0.53, 0.18)
	model.WorldPivot = CFrame.identity
	return model
end

-- `view` is "FirstPerson" or "ThirdPerson".
function GunModel.new(weapon: string, view: string): Model
	local model = Assets.weapon(weapon, view) or standIn()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if view == "FirstPerson" then
				part.CastShadow = false
			end
		end
	end
	return model
end

-- Finds an attachment anywhere in the model.
function GunModel.point(model: Model, name: string): Attachment?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("Attachment") then found else nil
end

return table.freeze(GunModel)

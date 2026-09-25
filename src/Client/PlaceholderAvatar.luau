--!strict
-- SPDX-License-Identifier: Apache-2.0

-- A plain blocky R6 figure, used until real avatar models exist.

local Body = require(script.Parent.Parent.Shared.Body)

export type Avatar = {
	model: Model,
	parts: { [Body.PartName]: BasePart },
}

local SKIN = Color3.fromRGB(204, 170, 140)
local SHIRT = Color3.fromRGB(70, 80, 95)
local PANTS = Color3.fromRGB(45, 50, 55)

local COLORS: { [Body.PartName]: Color3 } = {
	Head = SKIN,
	Torso = SHIRT,
	["Left Arm"] = SHIRT,
	["Right Arm"] = SHIRT,
	["Left Leg"] = PANTS,
	["Right Leg"] = PANTS,
}

local PlaceholderAvatar = {}

function PlaceholderAvatar.new(name: string): Avatar
	local model = Instance.new("Model")
	model.Name = name
	local parts: { [Body.PartName]: BasePart } = {}
	for _, partName in Body.PART_NAMES do
		local part = Instance.new("Part")
		part.Name = partName
		part.Size = Body.SIZES[partName]
		part.Color = COLORS[partName]
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = model
		parts[partName] = part
	end
	return { model = model, parts = parts }
end

function PlaceholderAvatar.apply(avatar: Avatar, pose: Body.Pose)
	for name, cframe in pose do
		avatar.parts[name].CFrame = cframe
	end
end

return table.freeze(PlaceholderAvatar)

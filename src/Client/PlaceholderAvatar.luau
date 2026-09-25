--!strict
-- SPDX-License-Identifier: Apache-2.0

-- A plain blocky R6 figure, used until real avatar models exist.

local Shared = script.Parent.Parent.Shared
local Body = require(Shared.Body)
local Weapons = require(Shared.Weapons)
local GunModel = require(script.Parent.GunModel)

export type Avatar = {
	model: Model,
	parts: { [Body.PartName]: BasePart },
	gun: Model,
}

local SKIN = Color3.fromRGB(204, 170, 140)
local SHIRT = Color3.fromRGB(70, 80, 95)
local PANTS = Color3.fromRGB(45, 50, 55)
-- Where the gun's grip sits relative to the hand.
local GRIP_IN_HAND = CFrame.new(0, -0.25, 0.05)

local COLORS: { [Body.PartName]: Color3 } = {
	Head = SKIN,
	Torso = SHIRT,
	["Left Arm"] = SHIRT,
	["Right Arm"] = SHIRT,
	["Left Leg"] = PANTS,
	["Right Leg"] = PANTS,
}

local PlaceholderAvatar = {}

local function block(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
	return part
end

function PlaceholderAvatar.new(name: string): Avatar
	local model = Instance.new("Model")
	model.Name = name
	local parts: { [Body.PartName]: BasePart } = {}
	for _, partName in Body.PART_NAMES do
		parts[partName] = block(partName, Body.SIZES[partName], COLORS[partName], model)
	end
	local gun = GunModel.new(Weapons.default.name, "ThirdPerson")
	gun.Name = "Gun"
	gun.Parent = model
	return { model = model, parts = parts, gun = gun }
end

function PlaceholderAvatar.apply(avatar: Avatar, pose: Body.Pose)
	for name, cframe in pose do
		avatar.parts[name].CFrame = cframe
	end
	avatar.gun:PivotTo(Body.hand(pose) * GRIP_IN_HAND)
end

return table.freeze(PlaceholderAvatar)

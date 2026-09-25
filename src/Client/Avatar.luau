--!strict
-- SPDX-License-Identifier: Apache-2.0

-- How other players look. Games can ship their own avatar as a Model in
-- Assets/Avatars/Default with R6 parts named Head, Torso, Left Arm, Right Arm,
-- Left Leg and Right Leg; OpenSRS moves those parts to match each player's
-- pose. Without one, everyone is a plain R6 figure: the classic shapes in one
-- neutral grey, with no face or clothing.
--
-- Hitboxes never depend on the avatar; they always use the fixed R6 layout.

local Shared = script.Parent.Parent.Shared
local Body = require(Shared.Body)
local Weapons = require(Shared.Weapons)
local Assets = require(script.Parent.Assets)
local GunModel = require(script.Parent.GunModel)

export type Avatar = {
	model: Model,
	parts: { [Body.PartName]: BasePart },
	gun: Model,
}

local PLAIN = Color3.fromRGB(163, 162, 165)
local HEAD_SCALE = Vector3.one * 1.25 -- the classic R6 head is a 2x1x1 part with a scaled head mesh
local R6_SIZES: { [Body.PartName]: Vector3 } = {
	Head = Vector3.new(2, 1, 1),
	Torso = Vector3.new(2, 2, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
}
-- Where the gun's grip sits relative to the hand.
local GRIP_IN_HAND = CFrame.new(0, -0.25, 0.05)

local Avatar = {}

local function plain(): Model
	local model = Instance.new("Model")
	for _, name in Body.PART_NAMES do
		local part = Instance.new("Part")
		part.Name = name
		part.Size = R6_SIZES[name]
		part.Color = PLAIN
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if name == "Head" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Head
			mesh.Scale = HEAD_SCALE
			mesh.Parent = part
		end
		part.Parent = model
	end
	return model
end

-- The avatar model to use: the game's own if it shipped one, otherwise plain.
local function template(): Model
	local custom = Assets.avatar("Default")
	if custom then
		for _, name in Body.PART_NAMES do
			if not custom:FindFirstChild(name) then
				warn(`OpenSRS: the custom avatar has no part named "{name}"; using the plain avatar instead.`)
				return plain()
			end
		end
		return custom
	end
	return plain()
end

local base = template()
for _, part in base:GetDescendants() do
	if part:IsA("BasePart") then
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
end

-- The color of the avatar's arms, for the arms in the player's own view.
Avatar.armColor = (base:FindFirstChild("Right Arm") :: BasePart).Color

function Avatar.new(name: string): Avatar
	local model = base:Clone()
	model.Name = name
	local parts: { [Body.PartName]: BasePart } = {}
	for _, partName in Body.PART_NAMES do
		parts[partName] = model:FindFirstChild(partName) :: BasePart
	end
	local gun = GunModel.new(Weapons.default.name, "ThirdPerson")
	gun.Name = "Gun"
	gun.Parent = model
	return { model = model, parts = parts, gun = gun }
end

function Avatar.apply(avatar: Avatar, pose: Body.Pose)
	for name, cframe in pose do
		avatar.parts[name].CFrame = cframe
	end
	avatar.gun:PivotTo(Body.hand(pose) * GRIP_IN_HAND)
end

return table.freeze(Avatar)

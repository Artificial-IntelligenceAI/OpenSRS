--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Finds art assets shipped with OpenSRS. The "systems only" download has none,
-- so every lookup can come back empty and callers fall back to stand-ins.

local Assets = {}

local root = script.Parent.Parent:FindFirstChild("Assets")

-- A fresh copy of a weapon model: `view` is "FirstPerson" or "ThirdPerson".
function Assets.weapon(name: string, view: string): Model?
	local weapons = root and root:FindFirstChild("Weapons")
	local weapon = weapons and weapons:FindFirstChild(name)
	local model = weapon and weapon:FindFirstChild(view)
	if model and model:IsA("Model") then
		return model:Clone()
	end
	return nil
end

return table.freeze(Assets)

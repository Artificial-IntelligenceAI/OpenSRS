--!strict
-- SPDX-License-Identifier: Apache-2.0

-- What counts as alive besides players: anything a game gives a Humanoid, the
-- way Roblox marks living things (NPCs, zombies, animals). Bullets hurt it and
-- it bleeds.

local Living = {}

-- The Humanoid of whatever `part` belongs to, if it's something alive.
function Living.humanoidOf(part: Instance): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

return table.freeze(Living)

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Who is on whose team. Teams come from Roblox's own Teams service: players
-- on the same Team, and not Neutral, are teammates.

local Teammates = {}

-- Set on each Player by the server to their character's slot, so clients can
-- tell whose character is whose.
Teammates.SLOT_ATTRIBUTE = "OpenSRSSlot"

function Teammates.are(a: Player, b: Player): boolean
	local team: Team? = a.Team
	return a ~= b and not a.Neutral and not b.Neutral and team ~= nil and team == b.Team
end

return table.freeze(Teammates)

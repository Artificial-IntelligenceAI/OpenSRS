--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Cheat flags. OpenSRS never punishes anyone by itself: it reports suspicious
-- behavior here and the game decides what to do.
--
--     local Flags = require(game.ServerScriptService.OpenSRS.Server.Flags)
--     Flags.Flagged:Connect(function(player: Player, reason: string, details: string)
--         warn(player.Name, "flagged:", reason, details)
--     end)

local event = Instance.new("BindableEvent")

local Flags = {}

Flags.Flagged = event.Event

function Flags.raise(player: Player, reason: string, details: string)
	event:Fire(player, reason, details)
end

return table.freeze(Flags)

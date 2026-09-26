--!strict
-- SPDX-License-Identifier: Apache-2.0

-- What a game's own server scripts can do with OpenSRS players. Characters
-- are run entirely by OpenSRS (that's what makes them hard to cheat with), so
-- this is the way in: move them, hurt them, and hear about it.
--
--     local OpenSRS = require(game.ServerScriptService.OpenSRS.Server.API)
--
--     OpenSRS.teleport(player, Vector3.new(0, 5, 0)) -- where their feet go
--     OpenSRS.damage(player, 25)
--     OpenSRS.setCanShoot(player, false) -- lobbies, safe zones, round countdowns
--     print(OpenSRS.position(player), OpenSRS.health(player))
--
--     OpenSRS.Died:Connect(function(victim: Player, killer: Player?)
--         print(victim.Name, "was killed by", if killer then killer.Name else "the world")
--     end)
--
-- Anything else alive in the game, like NPCs or zombies, needs nothing from
-- here: give it a Humanoid and bullets hurt it and it bleeds.

local Characters = require(script.Parent.Characters)
local Combat = require(script.Parent.Combat)
local Flags = require(script.Parent.Flags)

local API = {}

-- (victim: Player, attacker: Player?, amount: number, part: string)
API.Damaged = Combat.Damaged
-- (victim: Player, killer: Player?)
API.Died = Combat.Died
-- (player: Player, reason: string, details: string); see Flags.
API.Flagged = Flags.Flagged

-- Moves a living player's character so its feet are at `position`, and stops
-- it. Returns whether they were moved (they may be dead or not spawned yet).
function API.teleport(player: Player, position: Vector3): boolean
	return Characters.teleport(player, position)
end

-- Takes `amount` health from a living player, as if from no one; if it's
-- enough, they die and respawn as usual.
function API.damage(player: Player, amount: number)
	local slot = Characters.slotOf(player)
	if slot then
		Combat.hurt(slot, amount)
	end
end

-- Stops a player shooting (false) or lets them again (true). It lasts until
-- changed, through deaths and respawns. While stopped, pulling the trigger
-- does nothing, their HUD says they can't shoot, and aiming and reloading
-- still work. Players can shoot by default.
function API.setCanShoot(player: Player, allowed: boolean)
	Characters.setCanShoot(player, allowed)
end

-- Where a living player's feet are, or nil if they're dead or not spawned.
function API.position(player: Player): Vector3?
	return Characters.position(player)
end

-- A player's health, 0 if they're dead or not spawned.
function API.health(player: Player): number
	local slot = Characters.slotOf(player)
	return if slot then Combat.health(slot) else 0
end

return table.freeze(API)

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Where a player's eyes are. The camera uses this, and the server uses it to
-- decide what each player can see and shoot. The eye always stays directly
-- above the feet (plus lean), never outside the collision box, so nobody can
-- poke their view through a wall.

local Config = require(script.Parent.Config)
local Movement = require(script.Parent.Movement)
local Types = require(script.Parent.Types)

type State = Types.State
type World = Movement.World

local M = Config.movement

local Eye = {}

local function rightVector(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

-- Sideways lean distance, shortened if a wall is in the way. Negative is left.
function Eye.leanOffset(state: State, world: World): number
	if state.leanTicks == 0 then
		return 0
	end
	local wanted = M.leanDistance * state.leanTicks / M.leanTicks
	local base = state.position + Vector3.new(0, Config.stance(state.stance).eyeHeight, 0)
	local direction = rightVector(state.yaw) * wanted
	local result = workspace:Spherecast(base, M.eyeRadius, direction, world.raycast)
	if result then
		return math.sign(wanted) * math.min(result.Distance, math.abs(wanted))
	end
	return wanted
end

function Eye.position(state: State, leanOffset: number): Vector3
	local eyeHeight = Config.stance(state.stance).eyeHeight
	return state.position + Vector3.new(0, eyeHeight, 0) + rightVector(state.yaw) * leanOffset
end

return table.freeze(Eye)

--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Weapon rules: ammo, fire rate, reloading, recoil and bloom. Like Movement,
-- the server runs this as the authority and the client runs the same code to
-- predict, so it must stay deterministic. The one random part, where each
-- bullet goes within the spread, is only ever decided by the server.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)
local Weapons = require(script.Parent.Weapons)

type Input = Types.Input
type State = Types.State
type Weapon = Weapons.Weapon

local Buttons = Types.Buttons
local Stance = Types.Stance

local Firearm = {}

-- Applies one tick of trigger, reload and recoil to `state`, which has already
-- been moved this tick. Returns true if a shot was fired.
function Firearm.step(state: State, input: Input, weapon: Weapon): boolean
	local buttons = input.buttons
	state.fireCooldown = math.max(state.fireCooldown - 1, 0)
	-- Drawing the gun after spawning, and raising it after a sprint, take a moment.
	state.drawTicks = math.max(state.drawTicks - 1, 0)
	state.raiseTicks = if state.sprinting then weapon.raiseTicks else math.max(state.raiseTicks - 1, 0)

	if state.reloadTicks > 0 then
		state.reloadTicks -= 1
		if state.reloadTicks == 0 then
			local loaded = math.min(weapon.magazine - state.ammo, state.reserve)
			state.ammo += loaded
			state.reserve -= loaded
		end
	end

	local pulling = bit32.btest(buttons, Buttons.Fire)
	local wantsReload = bit32.btest(buttons, Buttons.Reload) or (pulling and state.ammo == 0)
	if
		wantsReload
		and state.reloadTicks == 0
		and state.drawTicks == 0
		and state.ammo < weapon.magazine
		and state.reserve > 0
	then
		state.reloadTicks = weapon.reloadTicks
	end

	-- Semi-automatic weapons need a fresh pull for every shot.
	local fresh = pulling and (weapon.automatic or not state.triggerHeld)
	local fired = fresh
		and state.ammo > 0
		and state.fireCooldown == 0
		and state.reloadTicks == 0
		and state.drawTicks == 0
		and state.raiseTicks == 0
		and not state.sprinting
	state.triggerHeld = pulling

	if fired then
		state.ammo -= 1
		state.fireCooldown = weapon.fireInterval
		state.recoilPitch += math.rad(weapon.recoilPitch)
		state.recoilYaw += math.rad(weapon.recoilYaw) * (if state.ammo % 2 == 0 then 1 else -1)
		state.bloom = math.min(state.bloom + weapon.bloomPerShot, weapon.bloomMax)
	else
		state.recoilPitch *= 1 - weapon.recoilRecovery
		state.recoilYaw *= 1 - weapon.recoilRecovery
		state.bloom = math.max(state.bloom - weapon.bloomRecovery, 0)
	end
	return fired
end

-- Half-angle of the spread cone, in degrees.
function Firearm.spread(state: State, weapon: Weapon): number
	local spread = weapon.spread
	local degrees = if state.stance == Stance.Prone
		then spread.prone
		elseif state.stance == Stance.Crouch then spread.crouch
		else spread.stand
	local speed = Vector3.new(state.velocity.X, 0, state.velocity.Z).Magnitude
	degrees += spread.moving * math.min(speed / Config.stance(Stance.Stand).speed, 1.5)
	if not state.grounded then
		degrees += spread.airborne
	end
	degrees += state.bloom
	if state.aiming then
		degrees *= spread.aimMultiplier
	end
	return degrees
end

function Firearm.direction(yaw: number, pitch: number): Vector3
	return (CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)).LookVector
end

-- A random direction inside the spread cone. On the server `random` must stay
-- secret, so nobody can predict and cancel the spread.
function Firearm.scatter(direction: Vector3, degrees: number, random: Random): Vector3
	local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
	local roll = random:NextNumber() * 2 * math.pi
	local frame = CFrame.lookAt(Vector3.zero, direction)
	return (frame * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

return table.freeze(Firearm)

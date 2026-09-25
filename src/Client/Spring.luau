--!strict
-- SPDX-License-Identifier: Apache-2.0

-- A damped spring for vectors. Things that follow a spring overshoot a little
-- and settle, which reads as weight instead of mechanical motion.

export type Spring = {
	position: Vector3,
	velocity: Vector3,
	stiffness: number,
	damping: number,
}

local MAX_STEP = 1 / 240

local Spring = {}

-- `dampingRatio` below 1 overshoots; 1 settles as fast as possible without overshooting.
function Spring.new(stiffness: number, dampingRatio: number): Spring
	return {
		position = Vector3.zero,
		velocity = Vector3.zero,
		stiffness = stiffness,
		damping = 2 * dampingRatio * math.sqrt(stiffness),
	}
end

function Spring.step(spring: Spring, target: Vector3, deltaTime: number)
	local steps = math.max(math.ceil(deltaTime / MAX_STEP), 1)
	local step = deltaTime / steps
	for _ = 1, steps do
		local acceleration = (target - spring.position) * spring.stiffness - spring.velocity * spring.damping
		spring.velocity += acceleration * step
		spring.position += spring.velocity * step
	end
end

function Spring.impulse(spring: Spring, velocity: Vector3)
	spring.velocity += velocity
end

return table.freeze(Spring)

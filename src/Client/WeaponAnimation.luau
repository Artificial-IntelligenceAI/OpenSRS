--!strict
-- SPDX-License-Identifier: Apache-2.0

-- How a weapon moves in the player's own view when fired, while drawing it
-- after a spawn and while reloading. Times are fractions of the draw or the reload, from 0
-- to 1, so the same animation fits any DrawTime or ReloadTime set in Settings. Positions are in studs, angles in radians, and offsets
-- are in the gun's space (grip at the origin, muzzle toward -Z) unless a field
-- says otherwise.
--
-- A game can change any of this for a weapon by adding a ModuleScript named
-- Animation to that weapon in Assets (Assets/Weapons/<Name>/Animation) that
-- returns a table of the fields to change, for example:
--
--     return { rackPose = CFrame.new(0.2, -0.4, -1.3) * CFrame.Angles(0, 0.4, math.pi / 2) }
--
-- Fields it leaves out keep the defaults below.

local Assets = require(script.Parent.Assets)

export type Key = { t: number, value: CFrame }
-- A moment that knocks the gun and nudges the view: velocity kicks, as
-- position (studs a second) and rotation (radians a second), in the gun's
-- space for the gun and the camera's for the view.
export type Hit = { t: number, move: Vector3, turn: Vector3, look: Vector3 }

export type Animation = {
	leftHand: CFrame, -- where the left hand holds the gun outside of reloads
	reloadPose: CFrame, -- the grip relative to the camera while changing magazines
	rackPose: CFrame, -- the grip relative to the camera while racking the slide
	rackStart: number, -- when the gun heads to the rack pose
	rackPull: number, -- when the slide starts coming back
	rackRelease: number, -- when the slide is let go
	readyAt: number, -- when the gun heads back to the ready position
	gunTrack: { Key }, -- where the gun is guided, on top of the pose; it follows through springs
	leftHandTrack: { Key }, -- where the left hand goes
	hits: { Hit },
	arc: Vector3, -- hands bow out this way between keys (times the distance), not in straight lines
	drawTrack: { Key }, -- drawing after a spawn: where the gun is, on top of the ready position; ends at no offset
	drawLeftHandTrack: { Key }, -- where the left hand goes while drawing
	drawHits: { Hit },
	fireMove: Vector3, -- each shot kicks the gun this fast (studs a second, in the gun's space; +Z is back toward you)
	fireTurn: Vector3, -- and turns it this fast (radians a second; +X is muzzle up)
	fireVariation: Vector3, -- plus up to this much random turn, so no two shots kick the same
	aimedFire: number, -- the kick is scaled by this while aiming, for a steadier sight picture
	slideCycle: number, -- seconds the slide takes to cycle after a shot
	walkSteps: number, -- steps a second at walking speed; a little faster when sprinting, slower when creeping
	walkSway: number, -- studs the gun sways side to side, one way per step
	walkBounce: number, -- studs the gun dips on each step
	walkRoll: number, -- radians it rolls with the sway
	magazineReleased: number, -- the old magazine starts sliding out
	magazineFree: number, -- it's out, and starts falling
	magazineGone: number, -- it's out of view
	magazineShown: number, -- the new one appears in the left hand
	magazineSeated: number, -- it's home
	magazineTilt: number, -- the new magazine goes in nose first, by this much, straightening as it goes
	handWhenSeated: Vector3, -- where the left hand is when the magazine is home
	gunStiffness: number, -- how tightly the gun follows gunTrack
	gunDamping: number, -- below 1 overshoots and settles; 1 doesn't overshoot
	lookStiffness: number,
	lookDamping: number,
	timingDrift: number, -- no two reloads are timed quite the same: up to this much, in the middle
	holdDrift: Vector3, -- or held at quite the same angle: up to this much, in radians
}

local function key(t: number, value: CFrame): Key
	return { t = t, value = value }
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local LEFT_HAND = CFrame.new(-0.1, 0.1, 0.02) -- wrapped around the right hand, from the left
local IDENTITY = CFrame.identity

-- The X16's: drop the old magazine, bring in the new one and slap it home,
-- then roll the gun onto its side, rack the slide over the top and come back
-- up ready.
local DEFAULT: Animation = {
	leftHand = LEFT_HAND,
	reloadPose = CFrame.new(0.05, -0.32, -1.15) * CFrame.Angles(0.75, 0.25, -0.35), -- muzzle up, the magazine well showing
	-- Level and fully on its side, the top of the slide facing left, so the
	-- left hand can come over the top.
	rackPose = CFrame.new(0.2, -0.38, -1.35) * CFrame.Angles(0, 0.45, math.pi / 2),
	rackStart = 0.6,
	rackPull = 0.75,
	rackRelease = 0.85,
	readyAt = 0.9,
	gunTrack = {
		key(0, IDENTITY),
		key(0.12, IDENTITY),
		key(0.4, CFrame.Angles(0.06, 0.05, 0.12)), -- turn to meet the incoming magazine
		key(0.59, CFrame.Angles(0.02, 0, 0.05)),
		key(0.69, IDENTITY),
		-- Push-pull: as the left hand pulls the slide back, the right hand
		-- pushes the gun forward along the barrel, so the hands part and
		-- neither does all the work.
		key(0.75, CFrame.new(0, 0, -0.02)), -- braced as the left hand takes hold
		key(0.84, CFrame.new(0, 0, -0.22)), -- pushed out as the slide comes back
		key(0.9, CFrame.new(0, 0, -0.03)),
		key(1, IDENTITY),
	},
	leftHandTrack = {
		key(0, LEFT_HAND),
		key(0.15, LEFT_HAND),
		key(0.3, at(-0.3, -1.2, 0.35)),
		key(0.38, at(-0.3, -2, 0.35)),
		key(0.41, at(-0.05, -1.55, 0.22)),
		key(0.51, at(-0.05, -0.45, 0.02)),
		key(0.59, at(-0.05, -0.15, 0.02)),
		key(0.65, at(-0.4, 0.3, 0.2)), -- around the side of the gun
		key(0.71, at(0, 0.6, 0.1)), -- over the top: grab the back of the slide
		key(0.75, at(0, 0.6, 0.1)),
		key(0.84, at(0, 0.6, 0.3)), -- rack it back
		key(0.87, at(-0.15, 0.85, 0.4)), -- let go, the hand flying off
		key(1, LEFT_HAND),
	},
	hits = {
		{ t = 0.15, move = Vector3.new(0, 0.4, 0), turn = Vector3.new(0.9, 0, 0.5), look = Vector3.new(0.2, 0, 0.1) }, -- magazine release
		{
			t = 0.59,
			move = Vector3.new(0, 1.6, 0.1),
			turn = Vector3.new(-1.4, 0, -0.6),
			look = Vector3.new(-0.3, 0, 0.15),
		}, -- magazine slapped home
		{ t = 0.75, move = Vector3.new(0, 0, 0.1), turn = Vector3.new(0.3, 0, 0), look = Vector3.zero }, -- slide grabbed
		{ t = 0.85, move = Vector3.new(0, 0, -1.4), turn = Vector3.new(1.6, 0, 0.4), look = Vector3.new(0.4, 0, 0) }, -- slide slams forward
	},
	arc = Vector3.new(-0.3, 0, 0.2),
	-- Drawing: the gun swings up from below, muzzle first down and canted, and
	-- levels out; the left hand comes up to meet it and wraps the grip.
	drawTrack = {
		key(0, CFrame.new(0.1, -0.9, 0.35) * CFrame.Angles(-1, 0.35, 0.5)),
		key(0.55, CFrame.new(0, 0.02, 0) * CFrame.Angles(0.06, 0, -0.04)),
		key(1, IDENTITY),
	},
	drawLeftHandTrack = {
		key(0, at(-0.4, -1.6, 0.4)),
		key(0.4, at(-0.4, -1.6, 0.4)),
		key(0.8, LEFT_HAND),
		key(1, LEFT_HAND),
	},
	fireMove = Vector3.new(0, 0.6, 1.6),
	fireTurn = Vector3.new(3.2, 0, 0),
	fireVariation = Vector3.new(0.4, 0.6, 0.8),
	aimedFire = 0.6,
	slideCycle = 0.07,
	walkSteps = 1.9,
	walkSway = 0.022,
	walkBounce = 0.014,
	walkRoll = 0.03,
	drawHits = {
		{ t = 0.8, move = Vector3.new(0, -0.3, 0), turn = Vector3.new(-0.4, 0, 0.2), look = Vector3.zero }, -- the left hand takes hold
	},
	magazineReleased = 0.15,
	magazineFree = 0.22,
	magazineGone = 0.35,
	magazineShown = 0.4,
	magazineSeated = 0.59,
	magazineTilt = 0.3,
	handWhenSeated = Vector3.new(-0.05, -0.15, 0.02),
	gunStiffness = 260,
	gunDamping = 0.5,
	lookStiffness = 180,
	lookDamping = 0.6,
	timingDrift = 0.02,
	holdDrift = Vector3.new(0.05, 0.06, 0.06),
}

local WeaponAnimation = {}

WeaponAnimation.default = table.freeze(DEFAULT)

-- The animation for a weapon: the defaults, with the game's changes on top.
function WeaponAnimation.get(name: string): Animation
	local animation = table.clone(DEFAULT)
	local module = Assets.weaponPart(name, "Animation")
	if not module then
		return animation
	end
	if not module:IsA("ModuleScript") then
		warn(`OpenSRS: Assets/Weapons/{name}/Animation should be a ModuleScript; using the default animation.`)
		return animation
	end
	local ok, changes = pcall(require, module)
	if not ok or type(changes) ~= "table" then
		warn(`OpenSRS: Assets/Weapons/{name}/Animation should return a table; using the default animation.`)
		return animation
	end

	local target = animation :: any
	for field, value in changes :: { [any]: unknown } do
		local default = target[field]
		if default == nil then
			warn(`OpenSRS: Assets/Weapons/{name}/Animation has an unknown field, {field}; ignoring it.`)
		elseif typeof(value) ~= typeof(default) then
			warn(`OpenSRS: Assets/Weapons/{name}/Animation's {field} should be a {typeof(default)}; using the default.`)
		else
			target[field] = value
		end
	end
	return animation
end

return table.freeze(WeaponAnimation)

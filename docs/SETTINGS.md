# OpenSRS Settings

<!-- Generated from src/Shared/SettingsSchema.luau by scripts/generate-settings.luau. Don't edit by hand. -->

Every value here can be changed in Roblox Studio without code: select a Configuration inside `ServerScriptService > OpenSRS > Settings` and edit its attributes in the Properties panel.

Values of the wrong type fall back to the default, and values outside the allowed range are clamped. Both print a warning in the Output window.

## Changing settings in code

For anything more advanced, add a ModuleScript named `Overrides` to the Settings folder. It returns a table shaped like the folder, and its values win over the attributes:

```lua
return {
	Movement = { WalkSpeed = 14 },
	Weapons = { X16 = { Damage = 30, Automatic = true } },
}
```

The server only uses its own copy of the settings. It sends the final values to players so their games predict with exactly the same numbers, but changing them on a player's computer does nothing.

## Game

| Setting | Default | Allowed | What it does |
| --- | --- | --- | --- |
| `TickRate` | 60 | 20 to 120 | Simulation updates a second. Higher is more precise and costs more server time. |
| `SnapshotRate` | 20 | 5 to 60 | How many times a second each player is told about the others. |
| `RespawnTime` | 3 | 0 to 60 | Seconds between dying and respawning. |
| `MaxHealth` | 100 | 1 to 10000 | Health each player spawns with. |

## Movement

| Setting | Default | Allowed | What it does |
| --- | --- | --- | --- |
| `WalkSpeed` | 12 | 0 to 100 | Studs a second when walking. |
| `SlowWalkSpeed` | 6 | 0 to 100 | Studs a second when slow-walking. |
| `SprintSpeed` | 19 | 0 to 100 | Studs a second when sprinting. |
| `CrouchSpeed` | 6 | 0 to 100 | Studs a second when crouched. |
| `ProneSpeed` | 2.5 | 0 to 100 | Studs a second when prone. |
| `AimSpeedMultiplier` | 0.6 | 0 to 1 | Movement speed while aiming down sights, as a fraction. |
| `BackwardSpeedMultiplier` | 0.8 | 0 to 1 | Movement speed when walking backwards, as a fraction. |
| `Acceleration` | 60 | 1 to 1000 | How quickly players speed up on the ground (studs a second, per second). |
| `Deceleration` | 80 | 1 to 1000 | How quickly players stop on the ground (studs a second, per second). |
| `AirAcceleration` | 6 | 0 to 1000 | How much players can steer in the air. Low stops bunny-hopping and air strafing. |
| `JumpHeight` | 3.7 | 0 to 50 | Studs a jump reaches. |
| `JumpCooldown` | 0.4 | 0 to 2 | Seconds before a player can jump again. |
| `Gravity` | 196.2 | 1 to 1000 | Downward pull, in studs a second squared. |
| `LeanDistance` | 1 | 0 to 2 | Studs the eye moves sideways when leaning. |
| `LeanTime` | 0.17 | 0.02 to 1 | Seconds to go from upright to a full lean. |

## Weapons / X16

| Setting | Default | Allowed | What it does |
| --- | --- | --- | --- |
| `Damage` | 25 | 0 to 10000 | Damage of a body shot at close range. |
| `HeadshotMultiplier` | 2 | 0 to 100 | Damage multiplier for headshots. |
| `LimbMultiplier` | 0.8 | 0 to 100 | Damage multiplier for arms and legs. |
| `FireRate` | 400 | 30 to 3600 | Rounds a minute. |
| `Automatic` | false | true or false | Keeps firing while the trigger is held. |
| `MagazineSize` | 17 | 1 to 255 | Rounds in a full magazine. |
| `ReserveAmmo` | 51 | 0 to 65535 | Spare rounds a player spawns with. |
| `ReloadTime` | 1.3 | 0.02 to 4 | Seconds to reload. The reload animation stretches to fit. |
| `RaiseTime` | 0.25 | 0 to 2 | Seconds after sprinting before the gun can fire. |
| `BulletSpeed` | 1340 | 1 to 100000 | Studs a second a bullet travels. |
| `InstantDamage` | false | true or false | Damage lands the moment the gun fires instead of when the bullet would arrive. |
| `Range` | 1000 | 1 to 10000 | Studs a bullet can reach. |
| `FullDamageRange` | 30 | 0 to 10000 | Studs before damage starts to drop off. |
| `MinDamageRange` | 100 | 0 to 10000 | Studs where damage stops dropping. |
| `MinDamageMultiplier` | 0.6 | 0 to 1 | Fraction of damage left at and beyond MinDamageRange. |
| `SpreadStanding` | 1 | 0 to 45 | Degrees of spread standing still, from the hip. |
| `SpreadCrouching` | 0.8 | 0 to 45 | Degrees of spread crouched. |
| `SpreadProne` | 0.6 | 0 to 45 | Degrees of spread prone. |
| `SpreadMoving` | 1.2 | 0 to 45 | Degrees added at full walking speed. |
| `SpreadAirborne` | 4 | 0 to 45 | Degrees added while in the air. |
| `AimSpreadMultiplier` | 0.3 | 0 to 1 | All spread is multiplied by this while aiming down sights. |
| `BloomPerShot` | 0.6 | 0 to 45 | Degrees of spread each shot adds. |
| `BloomMax` | 3 | 0 to 45 | Most spread shots can add. |
| `BloomRecovery` | 3 | 0 to 1000 | Degrees of added spread that fade a second. |
| `RecoilUp` | 1.6 | 0 to 45 | Degrees each shot kicks the aim up. |
| `RecoilSide` | 0.4 | 0 to 45 | Degrees each shot kicks the aim sideways. |
| `RecoilRecovery` | 6.3 | 0 to 100 | How fast the aim settles back after a kick. Higher settles faster. |

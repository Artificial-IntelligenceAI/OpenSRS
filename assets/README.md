# Assets

Everything in this directory (3D models, textures and other art) is licensed under the
[Creative Commons Attribution 4.0 International License](../LICENSE-CC-BY-4.0) (CC BY 4.0).

See the [main README](../README.md#crediting-the-models) for how to credit it.

## Contents

- `roblox/Assets.rbxm` — the Roblox-ready models, built into the "with models" release as `OpenSRS.Assets`.
  - `Weapons/X16/FirstPerson` — the X16 pistol as seen in the player's own hands (about 51k triangles).
  - `Weapons/X16/ThirdPerson` — the X16 as seen on other players (about 5.5k triangles).

Each weapon model's pivot is the grip, it faces -Z, and it has `Muzzle`, `EjectionPort`, `RearSight` and `Grip`
attachments. Moving parts are named `Slide`, `Barrel`, `Trigger` and `Magazine`.

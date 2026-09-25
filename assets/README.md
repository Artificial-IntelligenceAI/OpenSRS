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

## Source files

`weapons/X16/` holds the game-ready source the Roblox models were imported from:

- `FP/X16-2027-Edition_FP.fbx` and `TP/X16-2027-Edition_TP.fbx`, each with its four PBR texture maps per part (color, normal, roughness, metalness).
- `X16-attachments.json` — attachment points and animation pivots, in studs, relative to the grip.
- `X16-texture-manifest.json` — which textures go on which mesh.
- `validation.json` and `X16-comparison.png` — triangle counts, checks, and a render comparing both versions to the original.
- `ASTRA-NOTES.txt` — import notes from the model's author.

To use your own copy of the meshes and textures, import the FBX with Studio's 3D Importer, then scale it to 1.2 studs and turn it to face -Z.

The editable Blender files are too large for the repository and will be attached to GitHub Releases.

# OpenSRS

**Open-sourced Secure Roblox Systems** — cheat-resistant, server-authoritative characters and weapons for Roblox.

> **Status:** early development — nothing usable yet.

See [docs/DESIGN.md](docs/DESIGN.md) for how OpenSRS works and why, and [docs/SETTINGS.md](docs/SETTINGS.md) for every setting you can change.

## Official downloads

The **only** official source of OpenSRS is this repository's [Releases page](https://github.com/Artificial-IntelligenceAI/OpenSRS/releases). OpenSRS isn't published on the Creator Store or Toolbox, so any copy you find there isn't ours and may contain backdoors.

Each release comes in two versions:

- **Systems only:** the code, with no models. All Apache 2.0.
- **With models:** the code plus the OpenSRS avatar and weapon models (models under CC BY 4.0).

## Licensing

OpenSRS uses two licenses, split by directory:

| What | Where | License |
| --- | --- | --- |
| Code (Luau source, tooling, config) | everything outside `assets/` | [Apache License 2.0](LICENSE) |
| 3D models, sounds and other art assets | [`assets/`](assets/) | [Creative Commons Attribution 4.0 International](LICENSE-CC-BY-4.0) (CC BY 4.0) |

Release builds (e.g. `.rbxm` files) bundle both. The scripts inside are under Apache 2.0, and the models and sounds are under CC BY 4.0.

### Crediting the models and sounds

CC BY 4.0 requires attribution. If you use OpenSRS models or sounds in your game, credit them somewhere players can see, such as the game description or an in-game credits screen:

> Weapon models and sounds from OpenSRS (https://github.com/Artificial-IntelligenceAI/OpenSRS), licensed under CC BY 4.0.

The X16's magazine-drop sound is edited from "Pistol Reload" by Bunny_Clark (https://freesound.org/people/Bunny_Clark/sounds/377549/), also CC BY 4.0, so if your game uses it, add:

> Magazine drop sound edited from "Pistol Reload" by Bunny_Clark, licensed under CC BY 4.0.

Every other source recording is public domain (CC0); [SOURCES.md](assets/weapons/X16/sounds/SOURCES.md) lists them all.

## Developing OpenSRS

You only need this if you're working on OpenSRS itself.

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder to get the pinned tools.
2. Run `./scripts/check.sh` to check formatting, lint and strict types. CI runs the same script on every push.
3. To playtest, run `rojo serve dev.project.json` and connect with the Rojo plugin in Studio. It syncs `src/` into `ServerScriptService.OpenSRS`.

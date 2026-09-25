# OpenSRS Design

This is the single source of truth for how OpenSRS works and why. Anything not written here is still undecided.

## Goals

1. **Security first.** The server decides everything that matters. Clients send inputs, never results.
2. **Tactical first-person shooter feel.** Deliberate movement and forgiving but meaningful accuracy.
3. **Trustworthy, easy install.** One official source and a single drop-in model.
4. **No-code configuration.** Every gameplay number can be changed in Studio's Properties panel.

## Non-goals

OpenSRS deliberately does **not** support the following. Anyone who wants them can fork and modify it.

- Arcade movement (bunny-hopping, air strafing, run-and-gun accuracy)
- Third-person camera
- Players' own Roblox avatars
- Distribution anywhere other than GitHub Releases (no Creator Store, Toolbox or Wally)

## Threat model

A cheater fully controls their own client. Anything the client says can be a lie.

**Blocked outright.** The server owns these, so a modified client can't change them:

| Cheat | Why it fails |
| --- | --- |
| Fly, speed, teleport, noclip | The server simulates all movement from inputs. |
| Rapid fire, infinite ammo, no reload | The server tracks fire rate, ammo and reload timing. |
| Damage changes | The client never sends damage; the server looks it up. |
| Fake hits, wall shots, fake headshots | The client never says what it hit. The server raycasts itself against rewound hitboxes. |
| Remote spam ("kill all") | Every message is validated and rate-limited. |
| Wallhacks / ESP | Clients only receive characters they can actually see (see [Visibility](#visibility-anti-wallhack)). |

**Can't be fully blocked.** Aimbots and triggerbots only automate the player's own aim input. OpenSRS can make them harder and flag suspicious patterns (see [Cheat flags](#cheat-flags)), but no system can fully stop them.

**The code itself.** OpenSRS never uses `require()` by asset ID, `loadstring`, or HTTP requests, the usual ways backdoors hide in Toolbox models.

## Characters

Roblox's default characters are not used. OpenSRS runs its own server-authoritative characters.

- **Server-authoritative movement.** Clients send inputs only. The server simulates movement and is the ground truth. The local client predicts its own movement so it feels instant, then corrects itself to match the server.
- **Rig.** R6.
- **Hitboxes.** Fixed R6 hitboxes for standing, crouching and prone. A hitbox never depends on how an avatar looks.
- **Movement set:** walk, slow walk, sprint, crouch, prone, jump, lean left and right. Lean is a toggle (tap Q or E), and sprinting or going prone cancels it.
- **Feel.** Tactical: acceleration and deceleration have weight, there's no bunny-hopping or air strafing, and sprinting delays when you can fire.
- **Camera.** First-person only.

### Avatars

- Only OpenSRS avatars are used, never players' Roblox avatars.
- Games can add their own avatars in the OpenSRS avatar format, which will be documented with part names, sizes and attachment points.
- Without a custom avatar, everyone is a plain R6 figure: the classic R6 shapes (including the rounded head) in one neutral grey, with no face or clothing. It's built in code, so the "systems only" download has it too.
- A game's own avatar goes in `Assets/Avatars/Default` as a Model with R6 parts named `Head`, `Torso`, `Left Arm`, `Right Arm`, `Left Leg` and `Right Leg`. The arms in the first-person view take the avatar's arm color.

## Visibility (anti-wallhack)

- Each player only receives the characters they can see from their first-person eye position. This applies to **teammates too**.
- A target counts as visible if a clear line runs from any of the viewer's possible eye positions to any of the target's body parts (head, torso, arms, legs).
- **No pop-in.** Eyes and bodies are pushed 0.25 s ahead along their velocity, and the viewer's possible eyes include both full leans. Once seen, a target stays known for 0.4 s.
- **Nothing is pushed through walls.** Looking ahead stops at the first wall, so running at a wall never reveals what's behind it.
- **What blocks sight.** Any part that is less than 25% transparent blocks sight, even if it can be walked through (like bushes). Glass and other see-through parts don't.
- **Cost.** Each player's view is checked 15 times a second, with players split into four groups so the work is spread over ticks. In a worst-case test (32 players in a dense maze where only 3% of pairs can see each other), this took about 3 ms per server tick. Moving it onto several CPU cores with Parallel Luau is planned if real games need it.
- Gunshot effects and sounds (tracers, muzzle flashes) are only sent to players close enough to see or hear them.
- Each player only receives their own ammo and weapon state.

## Simulation

- **Server tick rate.** 60 per second by default, configurable. If load tests at 32 players can't hold 60, the default gets revisited.
- **Server size.** Configurable, with 32 players as the recommended maximum. Performance is designed and tested around 32.

## Weapons

- **Part of the input stream.** Fire, aim and reload are buttons in each tick's input. Server and client run the same weapon rules (ammo, fire rate, reload timing, the delay before firing after a sprint), so rapid fire and infinite ammo don't work.
- **Hitscan with rewind.** Each input also says which server tick the player was seeing others at. The server rewinds other players to that moment (from the same snapshots clients saw) and casts the bullet itself. The client never says what it hit.
- **No backtracking.** A shot may only rewind about as far as that player normally sees others behind (within 3 ticks, and never more than 0.4 s). Claiming to see further back, to hit someone who was exposed a moment ago, gets clamped.
- **Recoil is server-side.** The kick is added to the aim on the server, and the client shows the same kick on the camera. Skipping it on the client ("no recoil") changes nothing.
- **Spread is secret.** Where a bullet lands inside the spread cone is decided by a random generator only the server has, so "no spread" cheats can't predict and cancel it.
- **Bullet speed.** Set per weapon. By default the hit is decided the instant the gun fires, but damage lands when the bullet would arrive, based on distance and speed. Games can switch any weapon to instant damage instead.
- **Accuracy.** Spread depends on movement state (standing, walking, sprinting, jumping, crouching, prone, aiming down sights). The defaults are forgiving, not Valorant-harsh. Every value is configurable per weapon and per state.
- **Damage.** Per weapon, with falloff over distance, a headshot multiplier and a limb multiplier. Players have 100 health and respawn 3 seconds after dying.
- **Drawing.** After spawning, the gun takes `DrawTime` (0.5 s by default) to draw before it can fire or reload. The server enforces it like the delay after sprinting, so skipping the animation doesn't let a player shoot sooner.
- **Fire, draw and reload animations.** Only for show, in the player's own view. Each shot kicks the gun back and up through springs, a little differently every time and less while aiming. Walking bobs it at a person's pace; sprinting tucks it low with quicker, bigger strides, and after a sprint it rises back to ready over the raise time, arriving as it can fire again. The draw swings the gun up from below and the left hand comes in to grip it. The reload drops the old magazine, slaps in the new one, rolls the gun onto its side and racks the slide, then comes back up ready. Both are timed as fractions of the draw or reload, so they stretch to whatever `DrawTime` or `ReloadTime` a game sets. There's one reload time, empty or not; a game that wants empty reloads to be slower can mod that in. A game can change any part of either (poses, timings, hand paths, how springy they feel) per weapon with a ModuleScript at `Assets/Weapons/<Name>/Animation` that returns just the fields to change; the fields and their defaults are in `src/Client/WeaponAnimation.luau`.
- **Bullet impacts.** Where a bullet lands, there's a small hole and a burst of particles that fits the surface: light dust and dark chips for stone and concrete, sawdust and splinters for wood, sparks for metal, a soft puff for grass and dirt, glittering flecks for glass. A player who's hit gets a small red burst and a small hole that sticks to the body part and moves with it; holes on a player are cleared when they stop being shown, so none carry over to a respawn. It's client-side and cosmetic: the server decides the hit, and each client casts the same line against the map to find the surface. Every effect is customizable without code: a game can put its own templates (ParticleEmitters with a `Burst` count, plus an optional `Hole` part) in `Assets/Effects/Impacts`, named `Stone`, `Wood`, `Metal`, `Soft`, `Glass`, `Default` or `Body`. How long holes last and how many there can be are the `BulletHoleTime` and `MaxBulletHoles` settings.
- **Spent cases.** Each shot, yours or a visible player's, throws a case out of the gun's ejection port. It spins, bounces off whatever it hits, settles on its side, and its sound plays where it first lands. Cases are client-side and cosmetic, last 10 seconds, and at most 40 exist at once. A game can supply its own case as a part named `Casing` in `Assets/Weapons/<Name>`; otherwise a small brass cylinder is used.
- **Sounds.** Client-side only, through Roblox's audio API with acoustic simulation always on: sounds are muffled by walls, bend around corners and echo off their surroundings, worked out from the map. Other players' shots, impacts and near misses play where they happen; your own gun plays from its muzzle and your hands, so firing in a concrete room sounds like it. Only interface sounds like the hit marker play straight to your ears. A game's weapon sounds go in `Assets/Weapons/<Name>/Sounds` as Sound objects, one per cue named after it (`Fire`, `FireDistant`, `DryFire`, `Casing`, `Draw`, `MagazineOut`, `MagazineFloor`, `MagazineIn`, `SlideBack`, `SlideForward`, `ImpactWorld`, `ImpactBody`, `NearMiss`, `HitMarker`, `Headshot`), or a Folder of them to pick one at random each time. Each sets its volume, and its range with RollOffMinDistance (full volume within) and RollOffMaxDistance (silent beyond). Missing cues are silent, so the "systems only" download has no sound at all. Draw and reload sounds are timed cues in the weapon's animation.

## Networking

- OpenSRS uses its own networking layer with no third-party libraries.
- There are only a few message types: movement input, fire requests, and visibility snapshots.
- Every incoming message is strictly type- and range-checked, and rate-limited.

## Configuration

- **No code needed.** Every gameplay number lives in the `Settings` folder inside OpenSRS (Game, Movement, and one Configuration per weapon), editable as attributes in Studio's Properties panel. [SETTINGS.md](SETTINGS.md) lists them all.
- **Optional code file.** A ModuleScript named `Overrides` in that folder can change any value in code, and it wins over the attributes.
- **Checked.** Values of the wrong type fall back to the default, and out-of-range values are clamped, with a warning in Output.
- **The server's copy is the only one that counts.** The server resolves the settings, then publishes the final values so clients predict with exactly the same numbers. Changing them on a client does nothing.
- **One source of defaults.** Defaults and ranges are defined once in `src/Shared/SettingsSchema.luau`. The shipped Settings folder and SETTINGS.md are generated from it, and CI fails if they drift.

## Distribution and install

- **The only official source is GitHub Releases.** Each release has two downloads:
  - **Systems only:** code, Apache 2.0.
  - **With models:** code plus avatar and weapon models, with the models under CC BY 4.0.
- **Install.** Drop the model into ServerScriptService. On first run it moves its server, client and shared parts into place.

## First release scope

- The full character system: all movement including prone, server authority, anti-wallhack visibility, and the avatar system with the placeholder avatar.
- The X16 pistol: ammo, reload, recoil, accuracy and delayed damage. Until the game-ready model is done, a block stand-in is used.
- More weapons come after the core feels right in playtesting.

## Cheat flags

OpenSRS never punishes players on its own. When it spots something it can't block outright, like inhuman aim snaps, it reports the player and the reason to the game through a hook. Each game decides whether to log, kick or ban.

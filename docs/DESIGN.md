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

**Can't be fully blocked.** Aimbots and triggerbots only automate the player's own aim input. OpenSRS can make them harder and flag suspicious patterns, but no system can fully stop them.

**The code itself.** OpenSRS never uses `require()` by asset ID, `loadstring`, or HTTP requests, the usual ways backdoors hide in Toolbox models.

## Characters

Roblox's default characters are not used. OpenSRS runs its own server-authoritative characters.

- **Server-authoritative movement.** Clients send inputs only. The server simulates movement and is the ground truth. The local client predicts its own movement so it feels instant, then corrects itself to match the server.
- **Rig.** R6.
- **Hitboxes.** Fixed R6 hitboxes for standing, crouching and prone. A hitbox never depends on how an avatar looks.
- **Movement set:** walk, slow walk, sprint, crouch, prone, jump, lean left and right.
- **Feel.** Tactical: acceleration and deceleration have weight, there's no bunny-hopping or air strafing, and sprinting delays when you can fire.
- **Camera.** First-person only.

### Avatars

- Only OpenSRS avatars are used, never players' Roblox avatars.
- Games can add their own avatars in the OpenSRS avatar format, which will be documented with part names, sizes and attachment points.
- The first release ships a plain blocky R6 placeholder built from basic parts. A proper model will replace it later.

## Visibility (anti-wallhack)

- Each player only receives the characters they can see from their first-person eye position, including while leaning and prone. This applies to **teammates too**.
- Characters are sent slightly before they come into view so they don't pop in around corners.
- Visibility is checked less often than movement (about 15 times a second, with a margin) and runs across CPU cores with Parallel Luau.
- Gunshot effects and sounds (tracers, muzzle flashes) are only sent to players close enough to see or hear them.
- Each player only receives their own ammo and weapon state.

## Simulation

- **Server tick rate.** 60 per second by default, configurable. If load tests at 32 players can't hold 60, the default gets revisited.
- **Server size.** Configurable, with 32 players as the recommended maximum. Performance is designed and tested around 32.

## Weapons

- **Hitscan.** When a player fires, the server rewinds everyone's hitboxes to what the shooter saw at that moment and raycasts itself. The client only sends when and where it aimed.
- **Bullet speed.** Set per weapon. By default the hit is decided the instant the gun fires, but damage lands when the bullet would arrive, based on distance and speed. Games can switch any weapon to instant damage instead.
- **Accuracy.** Spread depends on movement state (standing, walking, sprinting, jumping, crouching, prone, aiming down sights). The defaults are forgiving, not Valorant-harsh. Every value is configurable per weapon and per state.
- **Server-validated:** fire rate, ammo, reload timing, and line of sight from the shooter.

## Networking

- OpenSRS uses its own networking layer with no third-party libraries.
- There are only a few message types: movement input, fire requests, and visibility snapshots.
- Every incoming message is strictly type- and range-checked, and rate-limited.

## Configuration

- Studio's Properties panel (Attributes) covers every common setting, with no code needed.
- An optional code settings file covers advanced setups.
- The server keeps its own copy of every setting, so changing values on a client does nothing.

## Distribution and install

- **The only official source is GitHub Releases.** Each release has two downloads:
  - **Systems only:** code, Apache 2.0.
  - **With models:** code plus avatar and weapon models, with the models under CC BY 4.0.
- **Install.** Drop the model into ServerScriptService. On first run it moves its server, client and shared parts into place.

## First release scope

- The full character system: all movement including prone, server authority, anti-wallhack visibility, and the avatar system with the placeholder avatar.
- The X16 pistol: ammo, reload, recoil, accuracy and delayed damage.
- More weapons come after the core feels right in playtesting.

## Proposed, not yet decided

- **Cheat flags.** OpenSRS reports suspicious behavior to the game through hooks, and each game decides what to do (log, kick or ban).

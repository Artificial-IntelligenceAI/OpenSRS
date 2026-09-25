# X16 sound sources

Every sound here is edited from a public-domain (CC0) original. The originals need no credit, but
they're listed so anyone can trace or re-cut them. The edits are shared under this folder's license
(CC BY 4.0, see [the assets README](../../../README.md)).

All files are 48 kHz mono WAV, trimmed to start at their first hit and peak-normalized to -1 dBFS.
Stereo originals were folded to mono.

## The Free Firearm Sound Library: Walther PPQ (9mm)

Real recordings by Ben Jaszczak, Brian Nelson, Kevin Heras and Matthew Nanney, CC0.
[OpenGameArt page](https://opengameart.org/content/the-free-firearm-sound-library),
[GitHub mirror](https://github.com/buddingmonkey/FreeFirearmsSFXLibrary) (files below are paths in it).

| File | Original | Edit |
| --- | --- | --- |
| `X16_Gunshot1.wav`, `2`, `3` | `Prepared SFX/Walther PPQ/X_39P.wav` (near distance), the three shots at 1.40, 6.44 and 10.66 s | 0.75 s each, light compression, then +12 dB into a limiter so the shot holds up at game volume |
| `X16_FireDistant1.wav`, `2` | `Prepared SFX/Walther PPQ/X_31P.wav` (far distance), shots at 1.08 and 5.24 s | 1.45 s each, same treatment |
| `X16_DryFire.wav` | `Master Tracks/Walther PPQ/X_18.wav` (dry fire from full trigger position) | 80 Hz high-pass |
| `X16_MagazineOut.wav` | `Master Tracks/Walther PPQ/X_3.wav` (detach mag) | 80 Hz high-pass |
| `X16_MagazineIn1.wav`, `2` | `Master Tracks/Walther PPQ/X_4.wav` (insert loaded mag), the insertions at 0.9 and 3.0 s | 80 Hz high-pass |
| `X16_SlideBack.wav` | `Master Tracks/Walther PPQ/X_23.wav` (full cycle, loaded mag), the pull back at 0.8 s | 80 Hz high-pass |
| `X16_SlideForward.wav` | `Master Tracks/Walther PPQ/X_23.wav`, the slide slamming home at 4.2 s | 80 Hz high-pass |

## BigSoundBank

Real recordings by Joseph Sardin, CC0 ([license](https://bigsoundbank.com/licence.html)).

| File | Original |
| --- | --- |
| `X16_Casing1.wav` | [Cartridge case 9 mm on concrete #1](https://bigsoundbank.com/bullet-case-9-mm-on-concrete-1-s1355.html) (`1355.wav`) |
| `X16_Casing2.wav` | [Cartridge case 9 mm on concrete #3](https://bigsoundbank.com/bullet-case-9-mm-on-concrete-3-s1357.html) (`1357.wav`) |

## Kenney

Sound effects by Kenney ([kenney.nl](https://kenney.nl)), CC0.

| File | Original |
| --- | --- |
| `X16_HitMarker.wav` | [Interface Sounds](https://kenney.nl/assets/interface-sounds), `tick_002.ogg` |
| `X16_ImpactWorld1.wav`, `2`, `3` | [Impact Sounds](https://kenney.nl/assets/impact-sounds), `impactMining_000` to `002.ogg` (rock, standing in for concrete) |
| `X16_ImpactBody1.wav`, `2`, `3` | [Impact Sounds](https://kenney.nl/assets/impact-sounds), `impactPunch_medium_000` to `002.ogg` |

## Not covered yet

There are no sounds yet for the draw, the magazine hitting the floor, or a bullet passing close by.
Those cues stay silent until a sound is added.

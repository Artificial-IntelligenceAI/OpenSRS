# X16 sound sources

Every sound here is edited from a public-domain (CC0) original. The originals need no credit, but
they're listed so anyone can trace or re-cut them. The edits are shared under this folder's license
(CC BY 4.0, see [the assets README](../../../README.md)).

All files are 48 kHz mono WAV, trimmed to start at their first hit and peak-normalized to -1 dBFS
(except the indoor tails, which keep their blast's gain so that blast + tail is the original shot).
Stereo originals were folded to mono.

## AlaskanMariner: Gun Range

A real indoor range, 9mm and .22, recorded on a Zoom H4n by AlaskanMariner, CC0.
[Freesound page](https://freesound.org/people/AlaskanMariner/sounds/811818/) (`811818__alaskanmariner__gun-range.wav`).

A gunshot is split in two so the room can change: the blast, then a tail picked by how enclosed
the shooter is. Each blast fades out linearly over 60 to 120 ms, and its tail fades in over the
same span, so a blast with its own tail adds back up to the original recording exactly.

| File | Original (9mm shots, at seconds into the recording) | Edit |
| --- | --- | --- |
| `X16_Blast1.wav`, `2`, `3` | shots at 251.39, 55.14 and 14.30 s | the first 120 ms of each: all of the first 60 ms, then a linear fade |
| `X16_TailIndoor1.wav`, `2` | the shots at 251.39 and 14.30 s | the rest of the shot to 1.6 s: a linear fade-in over 60 to 120 ms, a fade-out over the last 0.4 s, same gain as the blast |

## The Free Firearm Sound Library: Walther PPQ (9mm)

Real recordings by Ben Jaszczak, Brian Nelson, Kevin Heras and Matthew Nanney, CC0.
[OpenGameArt page](https://opengameart.org/content/the-free-firearm-sound-library),
[GitHub mirror](https://github.com/buddingmonkey/FreeFirearmsSFXLibrary) (files below are paths in it).

| File | Original | Edit |
| --- | --- | --- |
| `X16_FireDistant1.wav`, `2` | `Prepared SFX/Walther PPQ/X_31P.wav` (far distance), shots at 1.08 and 5.24 s | 1.45 s each, light compression, then +12 dB into a limiter so the shot holds up at game volume |
| `X16_TailOutdoor1.wav`, `2` | made from `X16_FireDistant1.wav` and `2` | the distant blast faded out: a linear fade-in over 60 to 120 ms, leaving the echoes off the surroundings, and a fade-out over the last 0.4 s |
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

## Handling and near misses from Freesound

| File | Original | License | Edit |
| --- | --- | --- | --- |
| `X16_Draw.wav` | ["Pistol Draw Unholster"](https://freesound.org/people/nioczkus/sounds/377145/) by nioczkus (`377145__nioczkus__pistol-draw-unholster.aiff`) | CC0 | 0.55 s from its first sound (the holster's click), resampled from 96 kHz |
| `X16_MagazineFloor.wav` | ["Pistol Reload"](https://freesound.org/people/Bunny_Clark/sounds/377549/) by Bunny_Clark (`377549__bunny_clark__pistol-reload.wav`): an empty S&W M&P9 magazine dropped on the floor, then a reload | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | 0.35 s from the magazine landing (1.39 s in), with its bounce |
| `X16_NearMiss.wav` | ["Fly-by whiz SFX (subsonic)"](https://freesound.org/people/modusmogulus/sounds/789222/) by modusmogulus (`789222__modusmogulus__fly-by-whiz-sfx-subsonic.wav`): a whip swung past the microphone | CC0 | 0.75 s from its start |

No properly licensed recording of a real bullet passing by could be found, so the near miss is a
whip, the way film sound often fakes one.

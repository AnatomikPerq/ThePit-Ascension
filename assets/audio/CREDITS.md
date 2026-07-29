# Audio credits

Every file here is **CC0 (public domain)**. Attribution is not legally required — this
file exists so the provenance of each asset is traceable and so any of them can be
swapped for something better without guesswork.

Sounds are referenced by *role*, not by their original filename. To replace one, drop a
new file over the existing path and keep the name: nothing in the code refers to the
source pack.

## Sound effects — `sfx/`

| File | Role in game | Source pack | Original name |
| --- | --- | --- | --- |
| `jump.ogg` | ground jump | Kenney — Digital Audio | `phaseJump2.ogg` |
| `double_jump.ogg` | mid-air second jump | Kenney — Digital Audio | `phaseJump5.ogg` |
| `land.ogg` | hard landing after a long fall | Kenney — Impact Sounds | `impactMetal_light_002.ogg` |
| `stomp.ogg` | stomping an enemy | Kenney — Impact Sounds | `impactMetal_heavy_003.ogg` |
| `kill.ogg` | enemy destroyed (pitch rises with combo) | Kenney — Digital Audio | `powerUp2.ogg` |
| `hurt.ogg` | player takes damage | Kenney — Digital Audio | `phaserDown1.ogg` |
| `crush.ogg` | player crushed between geometry | Kenney — Sci-fi Sounds | `lowFrequency_explosion_001.ogg` |
| `strike.ogg` | sideways strike attack | Kenney — Impact Sounds | `impactPunch_medium_001.ogg` |
| `shockwave.ogg` | shockwave blast | Kenney — Sci-fi Sounds | `forceField_000.ogg` |
| `bounce.ogg` | trampoline launch | Kenney — Digital Audio | `phaserUp3.ogg` |
| `thud.ogg` | golem petrifying into a platform | Kenney — Impact Sounds | `impactMetal_medium_000.ogg` |
| `upgrade.ogg` | upgrade menu opens | Kenney — Digital Audio | `powerUp1.ogg` |
| `heal.ogg` | +1 max HP / full heal | Kenney — Digital Audio | `powerUp7.ogg` |
| `die.ogg` | run over | Kenney — Music Jingles | `jingles_NES07.ogg` |
| `win.ogg` | surface reached | Kenney — Music Jingles | `jingles_NES13.ogg` |
| `click.ogg` | UI click | Kenney — Interface Sounds | `click_001.ogg` |

## Music — `music/`

| File | Role | Source | Author |
| --- | --- | --- | --- |
| `pit_ambience.ogg` | looping background ambience | [Loopable Dungeon Ambience](https://opengameart.org/content/loopable-dungeon-ambience) (OpenGameArt) | JaggedStone |

## Sources

- Kenney — <https://kenney.nl/assets/category:Audio> — all packs CC0.
  Packs used: Digital Audio, Impact Sounds, Sci-fi Sounds, Interface Sounds, Music Jingles.
- OpenGameArt — <https://opengameart.org/> — CC0 filter.

## Why these files exist

Before the refactor every one of these sounds was synthesised in GDScript at startup
(oscillators, envelopes and an 8-second procedural music loop in `scripts/sfx.gd`).
That meant a new sound had to be written as maths and could not be handed to anyone who
makes audio. These files replace that synthesis. `tools/` no longer contains a sound
generator, and none is coming back.

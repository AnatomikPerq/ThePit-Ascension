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
| `blast.ogg` | a bomb going off | Kenney — Sci-fi Sounds | `explosionCrunch_000.ogg` |
| `blast_close.ogg` | a bomb going off against **your** body | Kenney — Sci-fi Sounds | `lowFrequency_explosion_000.ogg` |
| `rubble.ogg` | a platform coming apart | Kenney — Impact Sounds | `impactMining_000.ogg` |

Three ids share `stomp.ogg` and `click.ogg` between them; see the table in
`tools/build_sound_bank.gd`. `bomb_hit` — a fist on a bomb's shell — is
`stomp.ogg` dropped a couple of semitones.

## Which sounds are heard where

Two facts about every sound live on its `SoundDef`, and they answer different
questions:

- **`positional`** — did this happen at a *place*? A positional sound plays
  through an `AudioStreamPlayer2D` where it happened, so it is quieter the
  further away you are. In 2D the listener is the active `Camera2D`, which in a
  session is each machine's own camera on its own avatar — so distance works in
  multiplayer with nothing about volume crossing the wire. `kill`, `thud`, `die`,
  `blast`, `rubble` and `bomb_hit` are positional.
- **Who plays it at all** — that is behaviour, not data, and it lives at the call
  site. Everything that belongs to *your* avatar (jump, land, hurt, crush,
  strike, shockwave, stomp, bounce) plays only on the machine steering it. A
  lobby does not hear everybody else's footsteps.

`test/audio_bank_test.gd` pins both lists, and fails if a new sound belongs to
neither.

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

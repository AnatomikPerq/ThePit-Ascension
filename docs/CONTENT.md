# Content

What is in the game, what it means, and where its numbers live. The
inventory below is **frozen**: nothing gets added without the owner asking
(see CLAUDE.md §1). Fixing and removing is always in scope.

## Theme

The game is a fan work inspired by ***Murder Drones*** (GLITCH), episode 5.
Open source, non-commercial, unaffiliated.

- **The Pit** is a trash pit where broken worker drones are dumped.
- **The player is Cyn** — her mansion-era look — climbing out after
  activating the **Absolute Solver**. Depth 8000 is the bottom; 0 is the
  surface. The victory line ("It's solver time") is hers.
- **Falling golems are broken drone heads** tumbling into the pit as you
  climb past them.
- The other enemies are drones or pit-creatures of looser canon; their
  long-term place in the project is undecided.

Sprite sources live in `assets/sprites/src/*.aseprite`; exported PNGs in
`assets/sprites/`.

## Inventory

| Kind | Entries |
| :--- | :--- |
| Enemies | Golem, Slime, Pursuer, Bat, Spitter |
| Unlockable upgrades | Double Jump, Sideways Strike, Shockwave — plus the +1 Max HP heal option |
| Built-in ability | Dash down |
| Objects | Trampoline (left by a killed slime) |
| Platforms | Static, Moving (horizontal / vertical) |
| Worlds | 1 (the pit), 4 levels × 2000 depth |
| Bosses | none |
| Modes | Solo, Co-op, Race |

### Enemies

| Enemy | Behaviour | Killed by | Leaves behind | Score |
| :--- | :--- | :--- | :--- | :--- |
| Golem | falls straight down | any stomp, strike | petrified platform | 100 |
| Slime | falls, drifts sideways | any stomp, strike | trampoline | 100 |
| Pursuer | ground chase, jumps walls/gaps | **dash** stomp, strike | — | 250 |
| Bat | flying homing with sine wobble | **dash** stomp, strike | — | 150 |
| Spitter | stationary, lobs acid | **dash** stomp, strike | — | 150 |

Landing on a dash-required enemy without dashing hurts you instead. The
full contact matrix is enforced by `test/enemy_contact_test.gd`.

A dead enemy leaves the screen. The two exceptions are the point of those
enemies: the golem's corpse *is* the platform, and the slime is replaced by
its trampoline. That is one flag, `frees_on_death` on the Combat component,
turned off in those two scenes.

### Other players

In **race** mode the other climbers are solid — you can stand on a head — and
your Strike, Shockwave and dash-stomp all land on them for one heart. In
**co-op** they are neither solid nor hittable: teammates pass through each
other. Solo is unaffected in every respect. See
[NETWORKING.md](NETWORKING.md#race-players-against-each-other).

### Getting crushed

Squeezed between two pieces of level geometry costs one heart, pops you clear
and lets you fall through the level for half a second before you become solid
again — and not while you are still inside the squeeze, because that is just
another heart. Rivals are not part of it: a race is fought with attacks, not
by standing on somebody until the ceiling logic notices.

## Where the numbers live

Code defines behaviour; `.tres` files define numbers. If you are tuning,
you should be in the inspector, not a script.

| Surface | File(s) |
| :--- | :--- |
| World geometry, platform ramps, spawn pacing, milestones, camera | `data/worlds/pit.tres` (WorldProfile) |
| World textures, background gradient | `data/worlds/pit_theme.tres` (WorldTheme) |
| Enemy spawn weights, placement, caps | `data/worlds/spawn/*.tres` (SpawnEntry) |
| Per-enemy combat numbers | `data/enemies/*.tres` (EnemyStats) |
| Particle burst shapes | `data/fx/*.tres` (BurstPreset) |
| Every sound: stream, volume, pitch range, bus | `data/audio/sound_bank.tres` (SoundBank) |
| Sprite animations (frame timing) | `data/animations/*_frames.tres` (SpriteFrames) |
| UI look | `assets/ui/pit_theme.tres` (Theme) |
| Crush recovery window | `CrushRecoveryTimer.wait_time` on `Player.tscn` |

Player movement constants are still literals in `player.gd` — they are the
game feel, changed rarely and reviewed hard. So are the two screen-shake
numbers in `fx.gd`. Everything else is data.

## Audio

16 CC0 sound effects (Kenney packs) and one ambience loop (OpenGameArt,
JaggedStone). Full provenance: `assets/audio/CREDITS.md`. Ids and tuning:
`data/audio/sound_bank.tres`. Buses: `Master / SFX / Music / UI`.

## Deliberate history

Bugs fixed on the owner's instruction that must not be "restored", plus the
mechanics removed on purpose (kill hitstop; `Engine.time_scale` is banned)
are listed in CLAUDE.md §4 and §6 — read them before "improving" anything
back in.

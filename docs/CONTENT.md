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
- **Bombs are heads that were still live when they were dumped** — a cracked
  shell with the core showing through. The pit throws away things that were
  never switched off.
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
| Objects | Trampoline (left by a killed slime), Bomb (falls past you) |
| Platforms | Static, Moving (horizontal / vertical) — both breakable |
| Worlds | 1 (the pit), 4 levels × 2000 depth |
| Bosses | none |
| Modes | Solo, Co-op, Race |

### Enemies

| Enemy | Behaviour | Killed by | Leaves behind | Score |
| :--- | :--- | :--- | :--- | :--- |
| Golem | falls straight down | any stomp, strike | petrified platform | 100 |
| Slime | falls, drifts sideways | any stomp, strike | trampoline | 100 |
| Pursuer | ground chase, jumps walls/gaps | any stomp, strike | — | 250 |
| Bat | flying homing with sine wobble | any stomp, strike | — | 150 |
| Spitter | stationary, lobs acid | **dash** stomp, strike | — | 150 |

A plain jump on the head kills everything except the **spitter**, which still
demands a dash and punishes a landing without one. That is one field per enemy
(`requires_dash_to_stomp` on its `EnemyStats`) and the full contact matrix is
enforced by `test/enemy_contact_test.gd`. Rivals in a race are the other
exception: standing on a head is legal, and only a dash-stomp hurts them.

A dead enemy leaves the screen. The two exceptions are the point of those
enemies: the golem's corpse *is* the platform, and the slime is replaced by
its trampoline. That is one flag, `frees_on_death` on the Combat component,
turned off in those two scenes.

### The bomb

Not an enemy — there is nothing to kill and no score for surviving it. It is a
hazard you can turn into a tool.

| | Behaviour |
| :--- | :--- |
| Falling | straight down, a shade quicker than the golem and the slime. It falls **through** the level: platforms, walls and floor are not there as far as it is concerned |
| Spawns | rarer than golems or slimes, at most three alive at once |
| Touch it | it goes off **against you** — the worst case in the game, see below |
| Strike / Shockwave | it is **thrown**, spinning, on the line away from where the swing came from, and from then on the first thing it touches sets it off. Aim it |
| A spitter's acid blob | sets it off, from either side of the above |
| The blast | 1 heart off every avatar inside it, every enemy in it dead, and every breakable thing whose strength the wave beats — see below. 50 points to whoever caused it; a bomb that goes off by itself pays nobody |
| The shove | every avatar inside the *push* radius is thrown away from the epicentre along both axes, harder the closer they were. The push reaches further than the damage does on purpose: a bomb going off nearby moves you even when it never got close enough to hurt you |

**How far it is thrown depends on how squarely you caught it.** Every hitbox
states its own reach, so "dead centre" means the same thing for a punch, for a
Shockwave that has grown to 300 px, and for another explosion. A bomb caught
right against you goes roughly twice as far as one clipped by the outer edge of
the same ring — which is the thing worth aiming for. And because the throw
follows the line away from the swing rather than a flat sideways push, where you
hit it decides where it goes: from below it sails up, from above it is driven
into the floor.

### Walking into one

Setting a bomb off with your own body is deliberately the harshest thing that
can happen to you, and it happens only to **you**:

- **two** hearts instead of one,
- thrown roughly two and a half times as far,
- a deeper, louder detonation — a different sound file, played flat, because it
  did not happen somewhere in the pit that you overheard,
- the screen filled by a fireball growing out of the middle of it, and the camera
  at full trauma.

Everyone else in the lobby gets the ordinary blast and watches that player leave
at speed. Nothing about the spectacle travels: the one machine that was hit
knows it was, and an avatar's position is already replicated.

Falling *through* the level is load-bearing, not an oversight. A bomb that
detonated on the first platform it met would quietly demolish the climb above
you before you ever got there; as it is, every hole in the pit is one somebody
made on purpose.

One consequence worth knowing: a blast is thrown by the same hitbox a punch is,
so an explosion **punts** any other falling bomb it engulfs rather than setting
it off. It sails out of the fireball and goes off on whatever it lands on,
credited to whoever started the chain.

### Breaking the pit

Anything with a `Destructible` component can be blown up. The rule is one
comparison: a blast's force falls off with distance from the epicentre, and an
object breaks when that force beats its own **strength**. Damage never
accumulates — a wave too weak to break something leaves no mark, so two near
misses are still two near misses.

| What | Strength | Breaks within |
| :--- | ---: | ---: |
| Static platform | 68 | ~166 px |
| Moving platform | 60 | ~208 px |
| Petrified golem (an activated golem) | 45 | ~286 px |
| Trampoline (an activated slime) | 30 | ~364 px |
| Walls, floor, level dividers | — | never |

The reach column is derived, not configured: it is where the pit's blast
(radius 520, peak force 100, linear falloff) drops to that strength. Tune the
strengths, not the distances.

The shaft is indestructible by *absence* rather than by a number — walls, the
floor and the dividers are assembled by `WorldBuilder` from the theme's
textures and never carry the component. Platforms and movers come from scenes
that do.

**Two ways to come apart**, and which is right depends on what the thing looks
like:

| Look | For | What it does |
| :--- | :--- | :--- |
| `debris` (`BurstPreset`) | objects visibly built from one repeating part — platforms, movers | throws copies of that block around, which is what a row of identical blocks should leave |
| `shards` (`ShardPreset`) | single drawings — trampolines, petrified golems, the bomb itself | cuts the sprite into a grid and throws the pieces |

The split matters: copies of a *drawing* read as the thing multiplying rather
than breaking, which is exactly what a slime looked like doing before. The shard
grid comes from a target piece size rather than fixed rows and columns, so one
preset gives sensible pieces for a 32×16 trampoline and a 39×36 bomb alike, with
a cap so nothing explodes into a hundred nodes.

The bomb uses shards on itself as a stand-in until there are explosion frames to
play — at least the shell is seen to come apart instead of simply vanishing.

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
| The bomb: fall speed, throw arc, spin, how much a clipped hit is worth, despawn | `data/enemies/bomb.tres` (BombStats) |
| The blast: radius, peak force, falloff curve, knockback, the point-blank case, score, shake, flash, particle layers | `data/fx/blast.tres` (BlastDef) |
| How tough one object is | `strength` on its `Destructible` node, in its `.tscn` |
| Particle burst shapes | `data/fx/*.tres` (BurstPreset) |
| How a drawing is cut up when it breaks | `data/fx/shards.tres` (ShardPreset) |
| Every sound: stream, volume, pitch range, bus, whether distance applies | `data/audio/sound_bank.tres` (SoundBank) |
| Sprite animations (frame timing) | `data/animations/*_frames.tres` (SpriteFrames) |
| UI look | `assets/ui/pit_theme.tres` (Theme) |
| Crush recovery window | `CrushRecoveryTimer.wait_time` on `Player.tscn` |

Player movement constants are still literals in `player.gd` — they are the
game feel, changed rarely and reviewed hard. So are the two screen-shake
numbers in `fx.gd`. Everything else is data.

## Audio

19 CC0 sound effects (Kenney packs) and one ambience loop (OpenGameArt,
JaggedStone). Full provenance: `assets/audio/CREDITS.md`. Ids and tuning:
`data/audio/sound_bank.tres`. Buses: `Master / SFX / Music / UI`.

Sound splits two ways, and the split is about *whose* sound it is:

- **World sounds** — an enemy dying, a golem setting, a bomb going off, a
  platform coming apart. Played on every machine from one replicated event,
  through an `AudioStreamPlayer2D` at the place it happened, so they fade with
  distance. The listener is each machine's own camera on its own avatar, which
  is why distance works in multiplayer with nothing about volume on the wire.
- **Avatar sounds** — your jump, your landing, your hurt, your punch, your
  stomp, your bounce. Flat, and played *only* on the machine steering that
  avatar. A lobby does not hear everybody else's footsteps.

## Sprites still to draw

Two animations are reserved and empty; both appear the moment the files exist
and `tools/build_sprite_frames.gd` is re-run, with no code change.

| Slot | Files | What it is |
| :--- | :--- | :--- |
| `bomb_frames.tres` → `explode` | `bomb_explode_1..3.png` | a drawn explosion. Until it exists the blast is carried by particles and by shards of the bomb's own shell, and `Explosion.tscn` keeps the sprite hidden; once it exists the sprite is scaled to the blast radius automatically |

The bomb's `falling` animation is complete: three frames at half a second each,
the core lighting up as it comes down.

## Deliberate history

Bugs fixed on the owner's instruction that must not be "restored", plus the
mechanics removed on purpose (kill hitstop; `Engine.time_scale` is banned)
are listed in CLAUDE.md §4 and §7 — read them before "improving" anything
back in.

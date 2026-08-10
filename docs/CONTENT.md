# Content

What is in the game, what it means, and where its numbers live. The
inventory below is **frozen**: nothing gets added without the owner asking
(see CLAUDE.md §1). Fixing and removing is always in scope.

## Theme

The game is a fan work inspired by ***Murder Drones*** (GLITCH), episode 5.
Open source, non-commercial, unaffiliated.

- **The Pit** is a trash pit where broken worker drones are dumped.
- **The player is Cyn** — her mansion-era look — climbing out after
  activating the **Absolute Solver**. Depth 16000 is the bottom; 0 is the
  surface. The victory line ("It's solver time") is hers.
- **Tessa** is the second climber: one heart, a shorter jump than Cyn's, and
  the second jump already hers. She fights with a blade rather than a fist.
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
| Characters | Cyn, Tessa, Uzi |
| Enemies | Golem, Slime, Pursuer, Bat, Spitter |
| Cyn's upgrades | Double Jump, Sideways Strike, Shockwave, +1 Max HP |
| Tessa's upgrades | Sword Slash, Pistol, Triple Jump |
| Uzi's upgrades | Railgun, Double Jump, +1 Max HP |
| Built-in ability | Dash down |
| Objects | Trampoline (left by a killed slime), Bomb (falls past you) |
| Platforms | Static, Moving (horizontal / vertical) — both breakable |
| Worlds | 1 (the pit), 8 levels × 2000 depth |
| Bosses | none |
| Modes | Solo, Co-op, Race — plus watching, in a session |

### The eight levels

The pit doubled in depth without the difficulty curve changing shape. Every ramp
in `WorldProfile` is a lerp over *ascent progress*, not over depth, so eight
levels sample the same curve the four-level pit had, at twice the resolution —
the endpoints deliberately did **not** move. `tools/world_balance.gd` measures
it: over 40 seeds the mean climb between two things you can stand on runs 81 px
at the floor to 359 px at the surface, against a standing jump of 281 px for Cyn
and 431 px for Tessa on her second. The pit has always expected you to make
some of the staircase yourself out of golems and slimes; that has not changed
either.

Two numbers did move, and both for the same reason — they are counted in
*spawns* rather than in depth, so leaving them alone would have put the whole
back half of a twice-as-long climb at the maximum rate:

- `spawn_interval_step` halved to 0.025, so the spawn rate ramps over twice as
  many enemies.
- Pursuers, bats and spitters now carry a small non-zero weight at the very
  bottom. Their weights ramp with progress, so without it the first *two* levels
  would have been nothing but golems and slimes. With it, level 1 of the eight
  has the same mix level 1 of the four did.

### The climbers

| | Cyn | Tessa | Uzi |
| :--- | :--- | :--- | :--- |
| Hearts | 5 | **1** | 3 |
| Jump | 100% | 92% of Cyn's | 100% |
| Jumps to start | 1 | 2 | 1 |
| Attack | fist, 0.35 s, 96×96 | blade, 0.23 s, 80×96, top to bottom | **none** — reserved |
| Second button | — | **pistol**: a bullet straight out to the side, 2 s cooldown | **railgun**: taken out and put away, aimed by mouse |
| Unlocks | Double Jump · Sideways Strike · Shockwave · +1 Max HP | Sword Slash · Pistol · Triple Jump | Railgun · Double Jump · +1 Max HP |

Everything in that table is a field on a `CharacterDef` in `data/characters/`.
Nothing in the game branches on *which* character it is steering, which is the
whole point: a third climber is a `SpriteFrames`, a `.tres` and a row in
`data/characters/roster.tres`.

Tessa is deliberately the harsher read of the same pit: one mistake ends her
run, and she has no heal to buy her way out of it. What she gets for it is
reach — the second jump from the first metre, a third one later, and a swing
that is over in two thirds the time Cyn's takes.

Cyn's fist is one drawing that **spins** while it grows out of nothing and
shrinks back into it — an `AnimationPlayer` clip on `Strike.tscn`, not a frame
sequence — and its hitbox is deliberately larger than the drawing. Tessa's blade
is five drawn crescents sweeping from above her head down past her feet.

**The pistol** is her only ranged thing and the only reason a second attack
button exists. The bullet is spawned on every machine by the same kind of
`call_local` RPC a Strike uses, then flies in a straight line at a fixed speed
from a muzzle position every machine agrees on — so it is in the same place
everywhere without a packet of its own. It joins the `"strike"` group like
everything else that can hurt an enemy, so no enemy scene knows guns exist.

**Uzi** starts with nothing on either button and an ordinary jump — the owner's
answer, on 10 August 2026, to what makes her different: three hearts, standard
jump height, no abilities at all until a milestone. Her left button is
deliberately empty rather than merely unwired, and `attack_scene` on her
`CharacterDef` is reserved for whatever is given to it later.

#### Uzi's railgun

The third climber's one unlock that is a mechanic rather than a number, and the
first weapon in the game that is a **thing she carries** rather than a shot she
throws. `CharacterDef` gained one field for it — `weapon_scene` — and the avatar
asks whatever is in it four questions and never what kind it is:
`wants_attack()`, `locks_facing()`, `pose()` and `setup()`.

- **Out and away.** Right mouse takes it off her back and puts it back, instantly
  and as often as you like. Nothing gates the toggle. While it is out it turns
  about its grip like a pin, following the cursor, and she faces where she is
  aiming rather than where she is running.
- **The shot** is on the left button, once every 3.3 s, and it costs one charge.
  The `enabled` art — the one with the energy visibly loose in the gun — is shown
  for a fifth of a second when it fires and at no other time.
- **The beam bounces five times.** It reflects off walls, platforms and golems in
  either state; it passes through slimes in any state, through every other enemy,
  through bombs and through climbers. Enemies it passes through die, and bombs it
  passes through go off where they stand.
- **It hits Uzi herself, in every mode**, which the owner asked for on purpose:
  firing down a corridor you are standing in is meant to be a decision. In a race
  it hits every other climber too.
- **It kicks.** The recoil goes through `Player.shove()`, the same one entry point
  a blast and a rival's hit use, so firing downwards carries a jump further than
  it would go on its own.

Almost none of that is written down as rules. The rule is decided by LAYER:
**anything on `WORLD` is a mirror, anything else is transparent.** Walls, floors
and both platform kinds are on it; slimes, bats, pursuers, spitters and bombs are
on none of it, so they are passed through for free. The killing is done
separately, by a hitbox laid along the beam in the `"strike"` group — which is
why it kills a bat the ray cannot even see.

The **golem** is the one exception, and it needed two fixes that are worth
naming because both were invisible in the code. Its solid `CrushBody` is 54×38
and sits low while the drawing is 64×64, so the top third of a golem had no
collider and a beam aimed at its head went through one that was plainly in the
way — `golem.gd` now claims its own hurt boxes as mirrors with `beam_response()`,
the single override in the game. And a hitbox that stopped exactly at the surface
it bounced off touched none of the areas that set the golem off, so it reflected
and nothing happened; every segment now carries `hit_overshoot` px past its
corner. `src/entities/rail_beam.gd`
is the whole solver and it is a pure function: a held beam whose reflections move
with the cursor is that function called again, which is what it was built for.

**The charge meter is the gun, drawn once.** Six charges, 600 score each — score
*earned*, never spent, so carrying a railgun never costs a place on the board,
and a full gun banks nothing. The widget is one drawing plus a greyscale **order
mask** in which every energy cell's brightness is its place in the fill order,
and one shader uniform from 0 to 1. Six frames would have been the obvious build
and it was rejected for a specific reason: the ult that is planned drains the
meter continuously, and no number of frames is a continuous value. Repainting
`assets/ui/rail_indicator_mask.png` changes the fill order with no code change;
`tools/aseprite/build_rail_mask.lua` generates the first draft.

**Upgrades are a single-use pool.** The menu offers only what that climber has
not taken yet; when one thing is left it is granted without asking, and once
there is nothing left the milestone pays score instead. Cyn has four offers and
four upgrades, so a clean run ends with all of them; Tessa and Uzi have three.

Milestones sit at the top of levels 1, 3, 5 and 7 —
`upgrade_fractions` on the profile.

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

### Dashing down

The dive is the one ability nobody has to unlock, and it is the only way to kill
a spitter. While it lasts the avatar carries a second hitbox two art pixels
wider than its body on every side, so a dive that clips a shoulder still counts
— measured, it reaches 57 px from an enemy's centre where the body alone reaches
53. It is on its own collision layer, not the one attacks use, because in a race
a rival's hurt box watches that layer and diving *past* somebody is not a hit on
them.

### Going down, and being picked up

In a **session**, running out of hearts is not the end of you.

| | |
| :--- | :--- |
| The body | falls onto its back — the `died` drawing, laid flat — and lies there. It is off every collision layer — no enemy, trampoline or rival can touch it — and keeps only the world in its mask, so it falls to the nearest floor instead of hanging where the last heart went |
| The sign | appears **over the body**, on the screen of any climber close enough to pick it up and able to afford it. It is local and cosmetic; nothing about it crosses the wire |
| The cost | one heart off the reviver. **You cannot revive on your last heart** — the pick-up would kill you |
| Coming back | one heart, where you fell, with a hop and a moment of invincibility so being revived under an enemy is not instantly being downed again |
| Meanwhile | that machine watches the pit instead (see below) until somebody spends a heart, or until everybody is down and the run ends |

All of that is multiplayer only. **Solo death is unchanged** — it ends the run,
with the same fall, fade and end screen it always had.

### Watching

Available two ways: pick **SPECTATOR** in the lobby instead of a climber and
never get an avatar at all, or be down and waiting for a pick-up.

`TAB` swaps between following a climber and a free camera, `A`/`D` cycle who
you are following, and the mouse wheel or `Q`/`E` zoom out — which is the point,
in a pit eight levels deep. A spectator changes nothing about the run and
nothing about their camera is replicated.

### Other players

In **race** mode the other climbers are solid — you can stand on a head — and
your Strike, Shockwave and dash-stomp all land on them for one heart. In
**co-op** they are neither solid nor hittable: teammates pass through each
other. Solo is unaffected in every respect. Reviving works in every mode,
including a race — spending one of your own hearts on a rival is a decision the
mode does not need to have an opinion about. See
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
| A climber: hearts, jump, starting jumps, attack scene, frames, upgrades | `data/characters/*.tres` (CharacterDef) |
| Which climbers exist and in what order | `data/characters/roster.tres` (CharacterRoster) |
| One upgrade: title, subtitle, effect | `data/upgrades/*.tres` (UpgradeDef) |
| One weapon: dwell, how far out it sits, reach | exports on `Strike.tscn` / `SwordStrike.tscn` |
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

One slot is reserved; it appears the moment the file exists and
`tools/build_sprite_frames.gd` is re-run, with no code change. The generator has
two ways of reserving: an animation that nothing plays is left empty, and one
that something *does* play falls back to a frame that exists, because an empty
clip draws nothing at all.

Several sounds are stand-ins rather than slots: the pistol borrows the punch's
`strike` sample, and the railgun borrows `shockwave` to fire, `upgrade` and
`ui_click` to come out and go away, and `bomb_hit` where the beam lands — because
a gunshot is an audio file to source rather than something to invent. All four
are `StringName`s on `data/weapons/railgun.tres`, so replacing them is four words
in a `.tres` and no code at all.

| Slot | Files | What it is |
| :--- | :--- | :--- |
| `bomb_frames.tres` → `explode` | `bomb_explode_1..3.png` | a drawn explosion. Until it exists the blast is carried by particles and by shards of the bomb's own shell, and `Explosion.tscn` keeps the sprite hidden; once it exists the sprite is scaled to the blast radius automatically |
| `uzi_frames.tres` → everything but `standing` | `uzi_running_1..3`, `uzi_jumping_1`, `uzi_falling_1`, `uzi_attacking_1`, `uzi_aiming_1`, `uzi_shooting_1..2`, `uzi_died`, `uzi_standing_2` | Uzi has one drawing so far. Every other clip stands in with it, so she is fully playable now and each file that arrives replaces its stand-in on the next generator run |
| `rail_indicator_mask.png` → hand-painted | — | the fill ORDER is generated left-to-right by `tools/aseprite/build_rail_mask.lua`. Repainting it in Aseprite is how the order changes — light the receiver before the barrel, or group the cells into six blocks that each light as one |
| `rail_indicator` → a drawn empty state | — | an unlit cell is currently its own pixel pushed down to a dead green. Drawing what an empty slot actually looks like and putting it in the shader's `drained_tex` needs no code change; the switch is `use_drained_tex` |

The bomb's `falling` animation is complete: three frames at half a second each,
the core lighting up as it comes down.

## What the dedicated server added, and what it did not

Added on the owner's instruction on **6 August 2026**: server software for the
game, with moderation and administration, rooms with different modes, control
over players, a domain, accounts and a protection scheme. He delegated the design
in the same message ("планирование за тобой", "тут планирование за тобой") and
asked explicitly for the game itself to be fixed wherever it got in the way.

**The inventory above is unchanged.** No enemy, ability, character, world,
structure or mechanic went in with it. What did go in is two player-facing
things that are not game content but are visible, and they are listed here so
that nobody has to guess later whether they were asked for:

| | What | Why it is there |
| :--- | :--- | :--- |
| **Chat** | a line of text, to the room you are in or to the whole server | moderation without it is a set of verbs with nothing to apply them to — you cannot mute somebody who cannot speak. Rate-limited, length-capped, word-filtered, and `moderation/chat` turns all of it off |
| **An administration panel** | in the game, on `F8`, for whoever the server gave the right to | he asked for the settings to be in the server's interface in the game. Its buttons build the same command lines the console takes, so there is no second implementation of moderation |

Neither appears in a solo game, and neither exists without a server: the panel
refuses to open, and there is nobody to chat to.

Three things about the *game* changed, all of them fixing something that was
already wrong and only became visible once a second room existed — a blast's
hitbox hanging off the cosmetics root, tree-wide group queries answering with
another room's pit, and run state being a global that a second run cleared. They
are in CLAUDE.md §7 with the rest of the fixed bugs.

The server's own tuning surface is **not** in `data/`. It is `server.cfg`, an INI
the server writes itself, because it is edited by an operator on a headless
machine with no Godot on it — see `src/server/setting_def.gd` for why that is a
deliberate departure from "numbers live in a `.tres`" and not an oversight.

## Deliberate history

Bugs fixed on the owner's instruction that must not be "restored", plus the
mechanics removed on purpose (kill hitstop; `Engine.time_scale` is banned)
are listed in CLAUDE.md §4 and §7 — read them before "improving" anything
back in.

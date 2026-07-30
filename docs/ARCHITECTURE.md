# Architecture

How the game is put together, and — more importantly — where a change goes.
The measure of this codebase is that the owner's planned features (new
worlds, bosses, abilities, characters, mouse control) would slot in without
restructuring anything. Every section below ends with the seam a future
feature would use.

## The one-screen map

```
autoloads   Fx        cosmetics: shake, pooled bursts, popups, ghosts
            Audio     SoundBank playback over AudioStreamPolyphonic
            Game      per-player run state (PlayerRun), score events, save
            Router    the only place scenes swap; runs start seeded here
            Net       ENet session lifecycle; inert until host()/join()

scene flow  MainMenu ──► Lobby ──► World        (Router.start_run(seed))
                └────────────────► World        (solo, fresh seed)

world       WorldProfile ─► WorldGenerator ─► WorldPlan ─► WorldBuilder
pipeline    (.tres numbers)  (seeded draws)    (records)    (nodes)

entities    Player (one per peer)   enemies = movement script + EnemyCombat
            Strike/Shockwave        component + stats .tres + Sync
            Bomb                    breakables = Destructible component

events      Blast     the one explosion: decide once, replay everywhere
```

## Autoloads

- **`Fx`** (`scripts/fx.gd`) — screen shake (trauma model), particle bursts,
  score popups, dash ghosts, debris, damage flashes, screen flash. Everything
  world-space spawns under `Fx.effects_root`, which the active scene registers
  (World does) — there is no fallback to `current_scene`, and effects die with
  their scene. Bursts are pooled per root and returned on the particles'
  `finished` signal. The look of each burst is a `BurstPreset` resource in
  `data/fx/`. `Fx.listener_position` is where this machine's eyes are (World
  keeps it on the local avatar): `loudness_at` and `shake_from` read it, so
  feedback from an event across the pit fades instead of jumping every player's
  camera for everybody else's fights.
- **`Audio`** (`src/audio/audio_manager.gd`) — loads
  `data/audio/sound_bank.tres` (a `SoundBank` of `SoundDef`s) and plays ids
  through one `AudioStreamPolyphonic` player per bus. No synthesis, no
  hand-rolled voice pool. `play_at(id, pos)` adds a positional voice
  (`WorldSound.tscn`, an `AudioStreamPlayer2D`) under `Audio.world_root` —
  whether distance actually applies is a flag on the `SoundDef`, so which
  sounds attenuate is an inspector decision. The 2D listener is the active
  `Camera2D`, i.e. each machine's own avatar, which is the whole of the
  multiplayer story for audio distance.
- **`Game`** (`scripts/game_state.gd`) — `runs: Dictionary[int, PlayerRun]`,
  one entry per peer; solo play is the single-entry case. Kills and score
  carry the credited peer. Emits `score_changed(peer_id, score, combo)`.
  Persists the local best score.
- **`Router`** (`src/core/router.gd`) — the only place scenes swap.
  `start_run(seed)` instantiates World and sets `world_seed` **before**
  `_ready()` generates the level — the same seam used by the fingerprint
  harness and the multiplayer host. Every transition lands unpaused.
- **`Net`** (`src/net/net.gd`) — see [NETWORKING.md](NETWORKING.md).
  `Net.active` is false until the lobby opens a session; with no session,
  every networked code path is skipped and the game is the solo game.

## World pipeline

One source of truth, four stages:

1. **`WorldProfile`** (`src/world/world_profile.gd`, instance:
   `data/worlds/pit.tres`) — every number the pit is built and paced from:
   shaft dimensions, platform-row ramps, mover odds and speeds, spawn table,
   camera limits, milestone fractions. References a **`WorldTheme`**
   (`pit_theme.tres`): textures and the background gradient.
2. **`WorldGenerator.generate(profile, seed)`** — deterministic; draws from
   the global RNG after `seed()` (measured: a `RandomNumberGenerator`
   instance produces a *different* stream for the same seed, and the global
   stream is what all existing worlds were built from). **The draw order is
   a contract** — reordering it silently changes every world and desyncs
   every session. New draws go at the end of a block, never between
   existing ones.
3. **`WorldPlan`** — pure placement records (statics, movers, free zones).
   Never travels over the network; every peer rebuilds it from the seed.
4. **`WorldBuilder.build(plan, theme, parent)`** — turns records into
   bodies. Static platforms instantiate the authored `Platform.tscn`;
   walls/floor/dividers are assembled from the theme's textures the way a
   TileMap emits colliders.

The oracle: `tools/world_fingerprint.tscn` hashes the generated collision
rects per seed. It proved the stage-4 refactor byte-identical, and it is the
same property multiplayer stands on.

Every piece the builder makes is **named after its place in the plan**
(`Plat17`, `Mover3`, `Wall8`). That is load-bearing, not tidiness: the world
never travels, so a platform destroyed mid-run can only be identified to the
other peers by name, and a name derived from the plan means the same node
everywhere. Left to Godot's duplicate-name handling they would be
`@Platform@7`-style names off a per-instance counter, which agree between peers
only by luck.

*Seam:* a *new world* is a new `WorldProfile` + `WorldTheme` pair — two
`.tres` files, zero scripts. Procedural structures would extend the
generator with new record types and the builder with their constructors,
gated behind profile fields — and if they should be breakable, a `Destructible`
node with a strength on their scene, nothing more.

## Entities

- **Player** (`scenes/Player.tscn`, `scripts/player.gd`) — physics, input,
  damage, crush handling. Carries `peer_id`; input runs only on the owning
  machine, remote copies run a puppet branch fed by a
  `MultiplayerSynchronizer`. Animations are `SpriteFrames` clips picked by a
  tiny state function; the invincibility blink is an `AnimationPlayer` clip.
  `shove(from, strength)` is the one entry point for "something moved this avatar
  that was not its input" — a blast, a rival's hit, whatever comes next. It is a
  decaying impulse *added* to velocity rather than a write to it, because
  `_handle_input()` assigns `velocity.x` outright every frame and a knock written
  straight into velocity is erased on the next tick.
- **Enemies** — each is a movement script plus two authored `Area2D`s
  (`StompArea`, `DamageArea`) plus the shared **`EnemyCombat`** component
  (`src/entities/enemy_combat.gd`): the whole contact matrix (strike beats
  stomp beats contact damage), despawning, kill credit, and the
  nearest-living-avatar retargeting. Per-enemy numbers (score, rebound,
  dash requirement, sounds) are `EnemyStats` resources in `data/enemies/`.
  Death *reactions* stay in the owner script, hooked to the `killed` signal
  — golem petrifies into a platform, slime leaves a trampoline.
- **Attacks** — `Strike` and `Shockwave` put their hitbox in the `"strike"`
  group and stamp `owner_peer` metadata on it; enemies react to the group
  and credit the metadata, so neither side knows the other's scenes. They also
  stamp `hit_reach`, how far the hitbox extends from its own centre, so anything
  that cares *how squarely* it was hit can ask — the bomb throws roughly twice as
  far for a dead-centre catch. A Shockwave updates it as the ring grows; a blast's
  own hitbox reports the blast radius.
- **Bomb** (`scenes/Bomb.tscn`, `scripts/bomb.gd`) — a falling hazard rather
  than an enemy: no `EnemyCombat`, no stomp, no kill. It has three states
  (falling, thrown, spent) and its whole job is deciding *when* to go off.
  Falling, it passes through the level entirely — no `move_and_collide` in that
  branch. Thrown by a Strike or Shockwave, it becomes a real body on an arc and
  the next thing it touches ends it. All its numbers are a `BombStats` `.tres`.

## Blasts and destruction

An explosion is the one event that changes the world after it is built, so it
gets its own seam: **`Blast`** (`src/core/blast.gd`), two static functions.

- `Blast.targets(from, epicentre, def)` — sim authority only. Walks the
  `"destructible"` group and answers in absolute node paths.
- `Blast.detonate(from, epicentre, def, credited_peer, doomed, point_blank_peer)`
  — runs on every machine off one replicated event: fireball, rubble, positional
  sound, distance-scaled shake and flash, the named pieces broken, this machine's
  own avatar hurt and shoved if it was inside, and the score credited by the
  authority. `point_blank_peer` names the one player who set it off with their
  own body; that machine, and only that machine, gets the harsher version — two
  hearts, a much bigger shove, a flat deep boom and a screen-filling fireball.
  Nothing about the spectacle travels, because the avatar's position already
  does: everyone else watches them leave at speed.

Why two steps rather than "every peer recomputes it from the seed": a moving
platform's live position is a function of how many physics ticks *that* machine
has run, so a mover at the edge of a wave breaks on one screen and survives on
another. The host decides once and names the casualties.

Enemies die through the hitbox on `Explosion.tscn`, which joins the `"strike"`
group and carries `owner_peer` — the same contract a punch uses. No enemy scene
knows bombs exist, and the spitter's acid blobs fizzle for free.

**`Destructible`** (`src/entities/destructible.gd`) is the other half: a
component, like `EnemyCombat`, because the things that break share no root type
(`StaticBody2D`, `AnimatableBody2D`, `Area2D`, `Node2D`). It carries one number
— `strength`, in the same units as `BlastDef.peak_force` — plus how its removal
replicates (locally-built geometry is freed by everyone; a spawner-owned
trampoline or petrified golem only by the authority) and how it comes apart.
Distance is measured to the object's nearest edge, not its centre, so a platform
eight blocks wide is not treated as a dot.

Coming apart is two mechanics, because objects are two kinds of thing.
`Fx.debris` throws copies of the object's texture around — right for something
visibly built from one repeating block, like a platform. `Fx.shards` cuts the
sprite into a grid (from a target piece size, so it adapts to any sprite) and
throws the pieces — right for a single drawing, like a trampoline or a petrified
golem, where copies read as the thing multiplying instead of breaking. Neither
draws or builds a texture: a shard is a `Sprite2D` looking at one `region_rect`
of the texture the object already had.

*Seam:* a *new enemy* = scene (movement script + areas + `Combat` +
`Sync`) + an `EnemyStats` `.tres` + a `SpawnEntry` row in the profile's
spawn table. A *boss* would be the same shape with its own controller; the
host-authoritative simulation and spawner replication already cover it — and
`Blast` is already the way for it to blow anything up. A *new ability* follows
the Strike pattern: cooldown on the player, an `@rpc("call_local")` spawn so the
host gets the hitbox, `"strike"` group + `owner_peer` meta for free enemy
interaction. A *new breakable structure* is a `Destructible` node and a
strength. A *new character* is a different avatar scene with the same
synchronizer contract.

## Input

Three layers, deliberately separate:

- **Gameplay** actions (`move_*`, `jump`, `dash_down`, `attack`,
  `shockwave`, `toggle_flight`) — bound to *physical* keycodes: WASD is
  where your fingers are on any layout.
- **UI** actions (`pause`, `restart`, `music_toggle`, `debug_toggle`,
  `upgrade_1..4`) — bound to *logical* keycodes: a key advertised on screen
  as "R" must be the key that types R.
- **`UIInputHandler`** (`scripts/ui_input.gd`) — a node in World.tscn with
  `process_mode = ALWAYS`, so R and ESC keep working while the tree is
  paused. It consumes the event *before* dispatch, because `restart` frees
  the handler mid-call. It drives World's public API only.

## UI

All layout is authored: `scenes/ui/` (HUD, UpgradeMenu with all four
buttons, PauseOverlay, EndScreen used twice with per-instance overrides),
`scenes/MainMenu.tscn`, `scenes/Lobby.tscn`, with one shared `Theme`
(`assets/ui/pit_theme.tres`) carrying button/panel/progress-bar styles.
Scripts only feed data in (`src/ui/*.gd`). `tools/ui_check.tscn`
screenshots every surface for eyeballing.

## Presentation rules

- Cosmetics are local. Shake, particles, popups, ghosts and sound never
  replicate as state; networked machines fire them from replicated events.
- **Feedback from an event fades with distance from the local avatar.** Kills,
  blasts and shockwaves all fire on every machine, so their shake and flash go
  through `Fx.shake_from` / `Fx.loudness_at`; their sound goes through
  `Audio.play_at`. Without that, a session is every player's camera jumping for
  everybody else's fights on the far side of the pit.
- **A sound that belongs to one avatar plays on one machine.** Jump, land,
  hurt, crush, strike, shockwave, stomp and bounce are fired by the owning
  machine only — not inside the `call_local` RPC that spawns the attack, and not
  by whichever machine happened to resolve the contact.
- `Engine.time_scale` is never written (enforced by a convention gate).
- Shared timing reads the physics tick (fixed 120 Hz), never a wall-clock
  or float accumulator. `MovingPlatform` is a pure function of
  ticks-since-ready.
- Pause is owned in two principled places only: World's run state machine
  (during a run, solo) and the Router (every transition lands unpaused).
  In a session the tree never pauses.

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
```

## Autoloads

- **`Fx`** (`scripts/fx.gd`) — screen shake (trauma model), particle bursts,
  score popups, dash ghosts, damage flashes. Everything world-space spawns
  under `Fx.effects_root`, which the active scene registers (World does) —
  there is no fallback to `current_scene`, and effects die with their scene.
  Bursts are pooled per root and returned on the particles' `finished`
  signal. The look of each burst is a `BurstPreset` resource in `data/fx/`.
- **`Audio`** (`src/audio/audio_manager.gd`) — loads
  `data/audio/sound_bank.tres` (a `SoundBank` of `SoundDef`s) and plays ids
  through one `AudioStreamPolyphonic` player per bus. No synthesis, no
  hand-rolled voice pool.
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

*Seam:* a *new world* is a new `WorldProfile` + `WorldTheme` pair — two
`.tres` files, zero scripts. Procedural structures would extend the
generator with new record types and the builder with their constructors,
gated behind profile fields.

## Entities

- **Player** (`scenes/Player.tscn`, `scripts/player.gd`) — physics, input,
  damage, crush handling. Carries `peer_id`; input runs only on the owning
  machine, remote copies run a puppet branch fed by a
  `MultiplayerSynchronizer`. Animations are `SpriteFrames` clips picked by a
  tiny state function; the invincibility blink is an `AnimationPlayer` clip.
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
  and credit the metadata, so neither side knows the other's scenes.

*Seam:* a *new enemy* = scene (movement script + areas + `Combat` +
`Sync`) + an `EnemyStats` `.tres` + a `SpawnEntry` row in the profile's
spawn table. A *boss* would be the same shape with its own controller; the
host-authoritative simulation and spawner replication already cover it. A
*new ability* follows the Strike pattern: cooldown on the player, an
`@rpc("call_local")` spawn so the host gets the hitbox, `"strike"` group +
`owner_peer` meta for free enemy interaction. A *new character* is a
different avatar scene with the same synchronizer contract.

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
- `Engine.time_scale` is never written (enforced by a convention gate).
- Shared timing reads the physics tick (fixed 120 Hz), never a wall-clock
  or float accumulator. `MovingPlatform` is a pure function of
  ticks-since-ready.
- Pause is owned in two principled places only: World's run state machine
  (during a run, solo) and the Router (every transition lands unpaused).
  In a session the tree never pauses.

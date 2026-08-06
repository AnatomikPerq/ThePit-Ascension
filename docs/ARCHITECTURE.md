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
            Game      this MACHINE: roster, the climber it picked, best score
            Router    the only place scenes swap; runs start seeded here
            Net       this machine's CONNECTION; inert until host()/join()
            Hub       the one door between a client and a dedicated server

scene flow  MainMenu ──► MultiplayerMenu ──► Lobby ──► World  (peer-to-peer)
                │              └► ServerConnect ─► ServerLobby ─► World
                └──────────────────────► World      (solo, fresh seed)

server      PitServer ─► RoomManager ─► Room ─► World  (one per room,
            (--server)   AuthService    NetSession      simulation_only)

directory   PitDirectory ─► HttpListener ─► DirectoryStore ─► VerifyKeyStore
            (--directory)   lists servers; the only thing that grants a badge

world       WorldProfile ─► WorldGenerator ─► WorldPlan ─► WorldBuilder
pipeline    (.tres numbers)  (seeded draws)    (records)    (nodes)

entities    Player (one per peer,   enemies = movement script + EnemyCombat
            a CharacterDef each)    component + stats .tres + Sync
            Strike/SwordStrike      breakables = Destructible component
            Shockwave / Bomb        spectators = SpectatorCam, no avatar

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
- **`Game`** (`scripts/game_state.gd`) — what belongs to this MACHINE rather
  than to a run: the `CharacterRoster`, the climber this machine picked, the best
  score it has ever set, and which peer it is. It answers the old run questions
  (`Game.local_run()`, `Game.add_score()`) by forwarding to whichever `RunLedger`
  the active world registered, the same "the active scene registers itself"
  arrangement `Fx.effects_root` uses.
- **`RunLedger`** (`src/core/run_ledger.gd`) — the score, kills and combo of ONE
  run, authored into `World.tscn` as `Run`. It moved out of `Game` for two
  reasons and the second is the one that forced it: `new_run()` clears the table,
  so a fourth room starting a climb wiped three others; and the score and kill
  events are `@rpc`s, addressed by node path, and the autoload's path is one path
  shared by every room. Inside the world it is `World3/Run` — a path that exists
  only for that room's peers.
- **`Hub`** (`src/net/hub.gd`) — every message between a client and a dedicated
  server, in one node at one path. Not tidiness: it is where the sender is
  resolved, rate-limited and checked, and a server with twenty doors to guard
  will eventually leave one unguarded. In-run traffic does not come through it —
  once a room starts, the room's own world replicates.
- **`Router`** (`src/core/router.gd`) — the only place scenes swap.
  `start_run(seed)` instantiates World and sets `world_seed` **before**
  `_ready()` generates the level — the same seam used by the fingerprint
  harness and the multiplayer host. Every transition lands unpaused.
- **`Net`** (`src/net/net.gd`) — see [NETWORKING.md](NETWORKING.md).
  `Net.active` is false until the lobby opens a session; with no session,
  every networked code path is skipped and the game is the solo game. It
  describes this MACHINE's connection; **which room a thing is in** is a
  `NetSession`, one per run, held by the world — a distinction that did not
  matter until one process hosted several runs.

## The dedicated server

`src/server/`, and it is a build of this project rather than a separate program:
it runs the same `WorldGenerator` and the same entities, with presentation turned
off (`World.simulation_only`). A server written separately would diverge from the
game on the first patch, and the divergence would show as players falling through
platforms rather than as a compile error.

```
PitServer          boot, the socket, the gatekeeper, who is connected, the tick
  AuthService      the handshake, on Godot's own auth hook
  RoomManager      rooms; each running one holds a World at /root/World<id>
  ChatService      chat, and the reason mute exists
  Moderation       kick / ban / mute / warn / move — the verbs, in one place
  MovementGuard    a tripwire on client-authoritative movement, not a wall
  RconService      the same commands over TCP
  StatusEndpoint   one line of JSON for a monitor
  CommandRegistry  one command set; the console, rcon and the in-game panel
                   all dispatch through it, permission check included
  ServerSettings   the schema; server.cfg, `set`/`get` and the panel's editor
                   are all generated from it
```

*Seam:* a new setting is one line in `ServerSettings._declare()`. A new command
is one `ServerCommand.make(...)` and it appears in all three front-ends with its
right enforced. A new moderation verb goes in `Moderation` and gets a command.
Operating it is [SERVER.md](SERVER.md); the rule that it must be rebuilt with the
game is [CLAUDE.md §8](../CLAUDE.md).

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

## Characters

One `Player` scene, one `player.gd`, and a **`CharacterDef`** resource
(`src/defs/character_def.gd`, instances in `data/characters/`) for everything
that differs between climbers: hearts, jump strength, how many jumps come free,
which attack scene, which `SpriteFrames`, and the upgrade pool. `player.gd`
reads it once in `_ready()` and nothing in the game asks *who* it is steering —
if a difference cannot be expressed as a field there, the field is what is
missing, not an `if`.

**`UpgradeDef`** (`data/upgrades/`) is one thing a climb can hand you: a title
and one of five effects (extra jump, attack, shockwave, +1 max HP, ranged).
A character's `upgrades` array is a **single-use pool** — an upgrade leaves it
when taken, so the menu only ever offers what is missing, one left is granted
without asking, and a milestone with nothing left pays score instead.

**`CharacterRoster`** (`data/characters/roster.tres`) is the ordered list the
select screen shows, a resource rather than a folder scan because the order is
a design decision. `Game.roster` loads it; `Game.selected_character` is this
machine's pick, saved between runs and resolved through the roster so an
unknown id falls back instead of failing.

In a session the picks are locked into the roster **with the seed**
(`Net.session_characters`), so every machine builds the same avatars in the
same order before the first frame, with no handshake. A peer may also pick
nothing at all, which is what a spectator is.

*Seam:* a *new character* is a `SpriteFrames`, a `CharacterDef` `.tres`, its
upgrade `.tres` files and a row in the roster — no scene and no script. A *new
kind of upgrade* is one more `Effect` and one more branch in
`World._apply_upgrade`.

## Entities

- **Player** (`scenes/Player.tscn`, `scripts/player.gd`) — physics, input,
  damage, crush handling, and the downed state. Carries `peer_id` and a
  `CharacterDef`; input runs only on the owning machine, remote copies run a
  puppet branch fed by a `MultiplayerSynchronizer`. Animations are
  `SpriteFrames` clips picked by a tiny state function; the invincibility blink
  is an `AnimationPlayer` clip.
  The art is authored on a 32×38 canvas against a 48×64 collision box, so the
  `AnimatedSprite2D` is offset 6 px up to stand the feet on the bottom of the
  box — `tools/visual_check.tscn` puts every climber on one baseline for exactly
  this reason.
  `DashBox` is a second `Area2D`, the body grown two art pixels on every side
  and live only while a dive is: a dash that clips a shoulder still lands. It is
  on its own `player_stomp` layer rather than `player_attack`, because a race
  rival's `HurtBox` watches that layer and diving past somebody is not a punch.
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
- **Bullet** (`scenes/Bullet.tscn`, `scripts/bullet.gd`) — Tessa's shot, and the
  only ranged thing in the game. Spawned by the same kind of `call_local` RPC a
  Strike is, then flat and straight at a fixed speed from a muzzle position every
  machine agrees on, through geometry every machine rebuilt from the same seed —
  so it needs no replication of its own. It dies on the first surface, and one
  physics frame after touching an enemy rather than inside the overlap callback,
  because an enemy resolves its own kills in `_physics_process` and would
  otherwise sometimes find the hitbox already gone.
- **Attacks** — `Strike`, `SwordStrike` and `Shockwave` put their hitbox in the
  `"strike"` group and stamp `owner_peer` metadata on it; enemies react to the
  group and credit the metadata, so neither side knows the other's scenes. The
  first two are the *same script* with different exports: dwell, how far out it
  sits, reach, shape and frames are all authored per scene, and which one a
  climber swings is a field on their `CharacterDef`. Cyn's is one drawing spun
  and scaled by an `AnimationPlayer` clip rather than a frame sequence, which is
  the same rule as everywhere else: a transform that moves over time is a clip,
  never a `sin()` in `_physics_process`. They also
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
- **Spectating** (`spectate_toggle`, `spectate_zoom_in/out`) and `revive` —
  physical, like the gameplay actions they sit next to. `revive` and
  `spectate_zoom_in` share E on purpose: you can only be doing one of the two,
  because reviving needs an avatar and spectating means not having one.
- **`UIInputHandler`** (`scripts/ui_input.gd`) — a node in World.tscn with
  `process_mode = ALWAYS`, so R and ESC keep working while the tree is
  paused. It consumes the event *before* dispatch, because `restart` frees
  the handler mid-call. It drives World's public API only.

## Spectating

**`SpectatorCam`** (`src/core/spectator_cam.gd`, a node in World.tscn) drives
World's existing `Camera2D` rather than owning one, so screen shake, the 2D
audio listener and `Fx.listener_position` still come from the same node they
always did — a spectator hears the pit from where they are looking. Two modes,
one key apart: follow a chosen climber, or fly free. Both zoom out, which is the
point once the pit is eight levels deep.

Two ways in, and neither is a mode the game is in: a peer that picked nothing in
the lobby simply never gets an avatar, and a peer whose avatar is down has one
lying on a platform. Both are the same code path — `World.player` is null or
`is_downed`, so the camera has nothing to sit on.

Nothing about it replicates. Where somebody's camera is pointing is their own
business, and a spectator changes nothing about the run.

## UI

All layout is authored: `scenes/ui/` (HUD, UpgradeMenu, PauseOverlay, EndScreen
used twice with per-instance overrides, CharacterSelect + CharacterStand),
`scenes/MainMenu.tscn`, `scenes/Lobby.tscn`, with one shared `Theme`
(`assets/ui/pit_theme.tres`) carrying button/panel/progress-bar styles.
Scripts only feed data in (`src/ui/*.gd`). `tools/ui_check.tscn`
screenshots every surface for eyeballing.

Two surfaces build their children rather than authoring a fixed set, because the
count is not fixed: the upgrade menu instances one `UpgradeButton.tscn` per
remaining upgrade, and the character select one `CharacterStand.tscn` per roster
entry. That is still "author it in a scene" — what the rule forbids is
`Button.new()` plus a hand-built `StyleBoxFlat`, not instancing a scene.

`CharacterSelect.tscn` is a panel, not a scene of its own, instanced into both
the main menu and the lobby: it is the same question in both places and the
answer goes to the same place.

`MultiplayerMenu.tscn` is the one door out of the main menu, and it instances one
`ServerRow.tscn` per server found. Each row carries three verification badges
authored into the scene, one visible at a time — three pills a designer can open
and restyle, rather than a colour computed in GDScript and a `StyleBoxFlat` built
in a function, which is what §2 of CLAUDE.md is about.

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

# CLAUDE.md — working rules for this repository

The PIT: Ascension. Godot 4.7, GDScript. A vertical platformer: Cyn — or Tessa —
climbs out of a trash pit from depth 16000 to the surface at 0, while broken drone
parts fall past her.
Fan project, open source, non-commercial. Theme: *Murder Drones* (Glitch), episode 5.

Read this before changing anything.

---

## 1. The one rule that gets changes reverted

**Do not add game content.** The inventory is frozen unless the owner asks:

> 3 characters (Cyn, Tessa, Uzi) · 5 enemies (Golem, Slime, Pursuer, Bat,
> Spitter) · Cyn's 4 upgrades (double jump, sideways strike, shockwave, +1 HP) ·
> Tessa's 3 (sword slash, pistol, triple jump) · Uzi's 3 (railgun, double jump,
> +1 HP) · 1 built-in dash-down · 1 trampoline · 1 bomb · 2 platform kinds, both
> breakable · 8 levels · 1 world · no bosses.

The **bomb** and the destruction mechanic were added on the owner's instruction
(30 July 2026), with the design decided by him in advance: it falls through the
level rather than detonating on it, player abilities *throw* it instead of setting
it off, and toughness is one `strength` number per object compared against a
blast force that falls off with distance — chosen that way because the map is
going to grow more kinds of breakable furniture. See docs/CONTENT.md. Nothing
else went in with it.

Added on the owner's instruction (5 August 2026), with his answers to four
design questions on the record — see docs/CONTENT.md for what each one is:

- **Tessa**, the second climber. One heart, jumps 92% of Cyn's height, starts
  with the double jump, unlocks a sword and a triple jump — he was offered a
  heal option for her and said no on purpose.
- **Tessa's pistol**, added on his instruction on 6 August 2026 with the design
  in the same message: a third upgrade for her, on the second attack button
  (right mouse; the sword is on the left), a fast pose, a bullet that leaves the
  muzzle straight out to the side she is facing, ordinary attack damage, gone on
  the first surface it meets with a few particles, and a two-second cooldown.
- **Reviving** in multiplayer, in every mode. A body stays where it fell, the
  sign is over the body rather than on the reviver's HUD, and the cost is one of
  the reviver's own hearts. Solo death is untouched.
- **Spectating**: for a downed player until somebody picks them up, and for
  anyone who chose SPECTATOR in the lobby instead of a climber.
- **A character-select screen**, on the main menu and in the lobby.
- **Four more levels**, to eight. His words on the upgrade pacing: an offer at
  every other level starting with the first, the menu shows only what you have
  not taken, one left is granted automatically, and once there is nothing left
  it pays experience instead.

Added on the owner's instruction (10 August 2026), with his answers to four
design questions on the record — see docs/CONTENT.md:

- **Uzi**, the third climber. Three hearts, an ordinary jump, and *nothing* on
  either button to start with; her left button is deliberately empty and
  `attack_scene` is reserved rather than merely unset. Her three unlocks are the
  railgun, the double jump and a heart.
- **The railgun**, and it is the reason she exists. Right mouse takes it off her
  back and puts it back — instantly, spammably, nothing gates it. It turns about
  its grip following the cursor, and she faces where she aims. Left mouse fires,
  once every 3.3 s, and the beam **reflects five times**. Walls, platforms and
  golems in either state are mirrors; slimes in any state, every other enemy,
  bombs and climbers are passed through — enemies passed through die and bombs
  passed through go off where they stand. It hits Uzi herself in every mode, and
  every other climber in a race, both on purpose. It kicks her backwards through
  `Player.shove()`, so firing downwards carries a jump.
- **Six charges, 600 score each, earned and never spent.** The run's own number is
  untouched: the railgun feeds on what you earn rather than taking it off the
  board, and a full gun banks nothing.

Two decisions inside that are worth naming because the obvious build was
rejected:

- **The beam has no rules in it.** The table of interactions above reads like a
  list of exceptions and is implemented as none: everything solid is on the
  `WORLD` layer — including a *falling* golem — and slimes, bats, pursuers,
  spitters and bombs are on no solid layer at all, so a `WORLD`-masked ray with
  `collide_with_areas` off produces the whole table for free. The killing is a
  separate hitbox in the `"strike"` group laid along the beam, which is why it
  kills a bat the ray cannot see. `RailBeam.trace` is a pure function of
  (origin, direction, geometry) because the owner asked for it to scale up to a
  HELD beam whose reflections move with the cursor: that is this function called
  again, with nothing to fall out of step.
- **The charge indicator is one drawing and one float, not six frames.** A
  greyscale order mask says which energy cell lights when; a shader compares it
  against `fill`. Six frames was rejected because the planned ult drains the
  meter continuously and no number of frames is a continuous value. The fill
  order is a picture — repaint `rail_indicator_mask.png` and it changes.

This brought the first `.gdshader`, the first `Line2D` and the first custom mouse
cursor in the repo. All three are engine features rather than hand-rolled
equivalents, which is the distinction §2 is about.

Everything about a climber is a `CharacterDef` resource. Nothing in the game may
branch on *which* character it is steering — if a difference cannot be expressed
as a field there, the missing field is the bug. A weapon she *carries* is one
more field (`weapon_scene`) and a four-method interface, not a branch.

Added on the owner's instruction (6 August 2026): a **dedicated server**. He
asked for console server software with moderation and administration, rooms with
different modes, player control, a domain, accounts and a protection scheme,
explicitly delegating the design ("планирование за тобой") and explicitly asking
for the game to be fixed where it got in the way. It brought two things that are
not in the inventory above and are therefore worth naming:

- **Chat**, in a room's lobby and over the whole server, with a rate limit, a
  word filter and mute. It is here because moderation without it is a set of
  verbs with nothing to apply them to — you cannot mute somebody who cannot
  speak. `moderation/chat` turns all of it off.
- **An administration panel** in the game (`F8`), for whoever the server has
  given the right to. Its buttons build the same command lines the console takes.

Neither is a game mechanic: no new enemy, ability, character, world or structure
went in with the server, and the inventory above is unchanged. See
[docs/SERVER.md](docs/SERVER.md).

Added on the owner's instruction the same day, and again with the design
delegated ("как находить их точно не скажу, подумай сам"): **one MULTIPLAYER
entry on the main menu instead of two**, holding a LAN game, connect-by-address,
and a **server browser**. Nothing in it is game content either — it is how a
player finds somewhere to play. What it brought that is worth naming:

- **A server directory**: a third program in this same binary
  (`--directory`, `src/directory/`), which servers announce themselves to over
  HTTP and clients read a list from.
- **Verification.** He asked for it in these terms: he hands a host a key, the
  host registers it, the server runs with it, and the key IS the badge — with a
  description on hover. So the badge is decided by the DIRECTORY and never by the
  server: an announce is signed with the key's secret, the signature covers the
  name and address, and a server's own claim to a badge is discarded before it is
  stored. `check_conventions.sh` gates the two places allowed to write one.
- **A LAN beacon**, because a browser that is empty without infrastructure is not
  a browser. One UDP packet each way, answered on request, never broadcast.

He also said a **large interface rewrite is coming**, for looks and for more
function. Everything above was built to be restyled: the badges are three
authored pills in `ServerRow.tscn`, not a colour computed in a script; the
browser is one scene with one shared `Theme`; `ServerFinder` knows nothing about
drawing and `multiplayer_menu.gd` knows nothing about where servers come from.

Changed on the owner's instruction the same day, and not to be "restored":

- **A plain jump on the head kills the pursuer and the bat.** Only the spitter
  still demands a dash. Rivals in a race are unchanged — a dash-stomp is still
  what hurts them.
- Three player-facing mechanics were made general rather than one-off, because
  more things will use them: `Player.shove()` (anything that pushes an avatar
  without deciding its damage), `Fx.shards()` (anything that is one drawing
  coming apart, as opposed to `Fx.debris()` for things built from a repeating
  block), and the `hit_reach` metadata every hitbox now stamps (anything that
  cares how squarely it was hit).

No new enemy, ability, boss, world, structure, character or mechanic. A previous
refactor was thrown away for exactly this: it produced a clean architecture *and* a
boss, a teleport, clones and procedural structures nobody ordered.

The owner's list of planned future features — procedural structures, further worlds,
bosses with phase arenas, new abilities, new characters, mouse control — is a
**specification for extensibility, not a work order**. The measure of this codebase is
that those things would be easy to add, not that they exist.

**Removing and fixing is encouraged.** That is the opposite side of the same rule.
Crutches, dead code and bugs should go. What must not happen is new content sneaking in
under the banner of a refactor.

## 2. Idiomatic Godot, not hand-rolled equivalents

The owner's word for the thing being removed is *AI slop*: a one-off that works today
and scales terribly. Concretely, do not reintroduce any of these — each was already
removed once:

| Never | Use instead |
| --- | --- |
| Synthesising audio at runtime (`AudioStreamWAV` from oscillators) | Real audio files + `SoundBank` |
| A hand-written voice pool with manual stealing | `AudioStreamPolyphonic` |
| Drawing textures with `Image.set_pixel` loops | PNG assets |
| Frame arrays + millisecond accumulators | `AnimatedSprite2D` + `SpriteFrames` |
| Animating a transform from `sin()` every physics tick | `AnimationPlayer` clip |
| Blinking via `Time.get_ticks_msec()` | `AnimationPlayer` clip |
| `Label.new()` / `StyleBoxFlat.new()` in a function | `.tscn` scenes + one `Theme` |
| `set_script()` or `load()` of a script in `_ready()` | Author the node in the scene |
| Tuning numbers as literals in a script | `@export` on a `Resource`, one `.tres` per thing |
| `Engine.time_scale` | Nothing. It is banned — see §4 |

If a change needs a number tuned, that number belongs in a `.tres`. If it needs a
widget, that widget belongs in a `.tscn`.

## 3. Layout

```
src/       code by system (audio/, core/, entities/, world/, ui/, net/, fx/, defs/,
           server/ — the dedicated server, and server/commands/;
           directory/ — the server list, its client and the LAN beacon)
scripts/   entity controllers and the older autoloads (Fx, Game, world, player, enemies)
data/      .tres resources — the tuning surface
           (audio/, animations/, characters/, enemies/, fx/, upgrades/, worlds/)
scenes/    .tscn by category (fx/, ui/, ui/server/, server/, entities at the top level)
assets/    sprites/ (cyn/, tessa/, src/), audio/ (+ CREDITS.md), ui/
test/      GdUnit4 suites
tools/     headless probes, one-shot generators, the test harness
           hooks/ what Claude Code runs after an edit · lib/ shared shell helpers
           setup_claude.sh brings the toolchain up on a fresh clone
docs/      ARCHITECTURE, CONTENT, NETWORKING, SERVER, TESTING
addons/    AsepriteWizard, gdUnit4, godot_mcp — committed, they are part of the project
.claude/   settings.json, the PostToolUse hook wiring
.mcp.json  the godot-mcp server entry, paths via ${VAR:-default}
gdlintrc   linter config, with the three disabled rules explained in the file
godot-pixel-stack-setup.md   how the toolchain was installed, and the path map
```

Anything in `tools/` named `build_*.gd` is a **one-shot generator**: it produced a
resource once and re-running it overwrites inspector edits. Generators exist so the
origin of the numbers is traceable. They are not part of the build.

## 4. Standing technical rules

- **`Engine.time_scale` is never written.** The kill hitstop that used it was removed on
  the owner's instruction. It was a global mutable clock that had to be manually reset in
  three places, it fought `get_tree().paused`, and it cannot exist in a networked session
  where one peer's slowdown desyncs everyone. Kill feedback is screen shake, particles,
  the score popup and the sound. `tools/check_conventions.sh` enforces this.
- **Shared timing reads the physics tick, never a local float accumulator.** Physics is
  fixed at 120 Hz. Any entity whose position must agree across peers is a pure function
  of `(tick, spawn parameters)`.
- **Cosmetics are local.** Shake, particles, popups, ghosts and sound never replicate as
  state. They are triggered by replicated *events*.
- **Feedback from an event fades with distance from the local avatar.** Anything fired on
  every machine — a kill, a blast, a shockwave — goes through `Fx.shake_from` /
  `Fx.screen_flash` and `Audio.play_at`, never plain `Fx.shake` / `Audio.play`. Otherwise a
  session is every player's camera jumping for everybody else's fights across the pit.
- **A sound that belongs to one avatar plays on one machine.** Jump, land, hurt, crush,
  strike, shockwave, stomp, bounce. Never inside the `call_local` RPC that spawns an
  attack, and never on whichever machine happened to resolve a contact.
- **Destruction is decided once and travels by name.** The world is otherwise a pure
  function of the seed, but a moving platform is a few ticks out of step between peers, so
  letting each recompute what a blast broke desyncs the climb. `WorldBuilder` names pieces
  after their place in the plan for exactly this reason — do not "tidy" those names away.
- **Single-player never opens a socket.** Every probe must pass with no networking active.
- **Collision layers are named** in `project.godot`. Never write a raw bitmask literal.
- **Pause is owned in one place.** No script sets `get_tree().paused` ad hoc.
- **A downed avatar is not a dead one.** In a session, running out of hearts
  leaves a body on the floor that a teammate can spend a heart on;
  `_any_avatar_alive()`, every milestone and every ending ask `is_downed`, not
  `is_instance_valid`. Solo death is unchanged and must stay that way.
- **`Net` is this MACHINE; a `NetSession` is one ROOM.** Net answers "am I
  connected, am I the server, who am I talking to". A `NetSession` answers "who
  is in this run, in what mode". A player's machine has one of each and they used
  to be the same object; a dedicated server has one socket and several runs and
  cannot conflate them. Nothing under `src/server/` may read `Net.mode`,
  `Net.session_peers` or `Net.is_versus()` — it would be describing whichever
  room wrote last. `check_conventions.sh` enforces it.
- **A gameplay message is addressed to a room, never broadcast.** `node.rpc(...)`
  reaches every peer the socket knows about; on a server that is three other
  rooms as well, on a node path they do not have. Use
  `NetSession.of(node).broadcast(...)`. Gated.
- **Never ask the tree for "the nearest player" or "the destructibles".** Every
  room's pit is built in the SAME coordinate space, so a tree-wide group query
  answers with a climber in a pit this room cannot see, or a platform in it.
  `NetSession.avatars_of(node)` and `NetSession.in_world(node, group)` are the
  scoped answers, and they fall back to the group when there is no world above —
  which is every unit suite.
- **Anything that is simulation goes in the world, not under `Fx.effects_root`.**
  A dedicated server registers no effects root, so a hitbox parented there simply
  does not exist. `Blast` learned this the hard way: its explosion hitbox is what
  kills the enemies in the wave, and hanging it off the cosmetics root would have
  meant bombs quietly killing nothing on every server.
- **Committed text is LF, and it is not a style preference.** A `.tscn` string
  spans real file lines, so one CRLF file puts a stray carriage return *inside*
  every multi-line label — and Godot treats it as a line break of its own, which
  silently double-spaces the text with no error anywhere. It cost an afternoon,
  twice. `.gitattributes` has said `eol=lf` all along; `check_conventions.sh` now
  checks the working tree too, because the files that broke it were written by
  scripts that used the platform default.
- **An `Area2D` that others must detect needs `monitoring` AS WELL AS
  `monitorable`, and `monitoring` set last.** Godot does not report an area with
  monitoring off from another area's `get_overlapping_areas()`, and setting the
  two the other way round does not pair either. The dash-down box was silently
  doing nothing until `test/character_test.gd` measured its reach against a
  golem: 53 px (the body) instead of 57 (the box).

## 5. Verifying a change

Nothing here needs a running editor. One command runs everything:

```bash
bash tools/run_tests.sh
```

Individually:

```bash
# GdUnit4 suite in test/ — sound bank, world generation, enemy contact matrix.
# --ignoreHeadlessMode is required: GdUnit refuses headless by default because
# its own scene-runner input simulation does not work there. No suite uses it.
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
      --ignoreHeadlessMode --add res://test

godot --headless --path . -s tools/smoke_test.gd        # autoloads, buses, bank, every scene
godot --headless --path . tools/state_probe.tscn        # pause, input, restart, shake, exit to menu
godot --headless --path . tools/world_fingerprint.tscn  # same seed => same geometry hash
bash tools/run_net_probe.sh                             # real host+client over a localhost socket
bash tools/run_server_probe.sh                          # real dedicated server + 2 clients, 2 rooms
bash tools/run_directory_probe.sh                       # real directory + announcing server + browser
godot --path . --fixed-fps 60 tools/visual_check.tscn -- out.png   # sprite gallery
godot --path . tools/ui_check.tscn -- out_dir           # every UI surface, for eyeballing (advisory)
bash tools/check_conventions.sh                         # grep gates for the rules above

godot --headless --path . -s tools/world_balance.gd     # the pit level by level (advisory)
godot --headless --path . -s tools/build_protocol_stamp.gd  # regenerate the build fingerprint
```

`world_balance` is a measuring stick, not a gate. Every ramp in `WorldProfile`
is a lerp over ascent *progress*, so changing `level_count` restretches all of
them at once — it prints, per level, how far apart the things you can stand on
actually are, against what each climber can jump. Read it before retuning any
of those numbers, and after.

**Write tests against physics frames, never wall-clock.** Two harnesses in this
repo have already been wrong in exactly that way. `await await_millis(50)` looked
fine until the first case in a run spent its budget loading scenes off disk and
saw fewer physics steps than the rest, failing at random. Use
`for i in N: await get_tree().physics_frame`.

**Free what a test spawns, immediately.** The contact suite originally reused the
tree between cases, and a golem petrified in one case became a StaticBody2D at
the same coordinates in the next — so the player landed on it, `is_on_floor()`
cleared `dashing_down`, and three enemies "mysteriously" stopped dying.

**Do not hash a clock, and sample a random effect more than once.** The net
probe's world hash folds moving platforms back to their authored position:
their live position is a function of ticks-since-ready, so hashing the live
picture compares when two peers entered the world rather than what they built —
it reported "the restarted worlds differ" for two identical worlds. And screen
shake is a fresh random offset each frame inside a decaying envelope, so a
single read lands near zero often enough to fail one run in twenty; assert the
peak over a handful of frames.

`visual_check` freezes every entity to `PROCESS_MODE_DISABLED` after `_ready()` and runs
at a fixed frame rate. That discipline is not optional: an earlier version left entities
running and two captures of the *same commit* differed by 8.6% of pixels from tween and
particle timing, which makes the harness worse than useless — it reports noise as
regression.

Pixel identity is a **detector, not a gate**. The owner explicitly relaxed it: bugs get
fixed even when the fix is visible. When a capture changes, say what changed and why, and
re-baseline deliberately.

## 6. The toolchain around the editor

Installed 31 July 2026 on the owner's instruction, from `godot-pixel-stack-setup.md`.
Every piece exists so a change can be *seen*, not guessed at.

**On a fresh clone, run `bash tools/setup_claude.sh` first.** Everything that can live in
git does: the addons, the hook, `gdlintrc`, `.mcp.json`, the scripts. The setup script
installs the two things that cannot — the gdtoolkit venv and the godot-mcp Node server —
and *checks* the two it must not install behind your back, Godot and Aseprite, printing
the exact fix for whatever is missing. It is idempotent.

It also **imports the project once**, and that step is not optional. `.godot/` is ignored,
so a clone has no `global_script_class_cache.cfg`, and without it no `class_name` resolves:
`SoundBank`, `SoundDef` and the rest come back as "Could not find type", every suite drowns
in parse errors, and the net probe hangs instead of failing. Only *editor* mode builds that
cache, so this is the one place the rule below is deliberately broken — do it before
opening the editor, not while it is open. `run_tests.sh` checks for the cache and says what
to run rather than grinding for ten minutes.

**No committed file names a machine-specific path.** `tools/lib/find_godot.sh` and the
matching logic in the hook discover the binaries; `GODOT`/`GODOT_CLI`, `GODOT_DIR`,
`GODOT_MCP_SERVER`, `GODOT_MCP_PORT`, `GDLINT` and `ASEPRITE` override the search. The
table in §0 of the setup doc lists the defaults. When a tool is genuinely absent the hook
says which file went unchecked and names the setup script — it never fails silently and
never blocks.

This machine, for reference:

```
GODOT_CLI  C:/tools/godot/Godot_v4.7.1-stable_win64_console.exe   headless, CI, hooks
GODOT_GUI  Steam "Godot Engine"/godot.windows.opt.tools.64.exe    hand work, godot-mcp
ASEPRITE   Steam "Aseprite"/Aseprite.exe                          1.3.18.1
```

**Use the console build for anything headless.** Both are 4.7.1 off commit `a13da4fe`,
but the Steam exe is linked as a Windows GUI-subsystem app: started from a terminal it
attaches to no console and prints nothing. `run_tests.sh` only ever looked fine because
every line of it pipes into `grep`, and a redirected handle it does write to. Steam
auto-updates and the standalone does not — after a Steam update, check `--version` on
both before trusting a run.

Godot and Aseprite each keep **two** setting stores here, which is the usual reason a
plugin "silently does nothing":

- The Steam install is *self-contained* (there is a `._sc_` marker in it), so its editor
  settings are `<steam>/Godot Engine/editor_data/editor_settings-4.7.tres`. The standalone
  uses `%APPDATA%/Godot/`. Aseprite Wizard's path to `Aseprite.exe` is an **editor**
  setting, so it is written in both.
- Everything else the Wizard reads is a *project* setting and lives in `project.godot`
  under `[aseprite]`. `default_automatic_importer="SpriteFrames"` is what makes a saved
  `.aseprite` turn into a `SpriteFrames` with no manual step; the other importers
  (Tileset Texture, Static Texture) are per-file choices in the Import dock.

Sprites come out of Aseprite, through the Wizard, into `AnimatedSprite2D`. A tag becomes
an animation and Aseprite's frame durations become the Godot FPS — a 100 ms frame lands as
10 FPS. Generating image data in code stays banned, exactly as §2 already says: that ban
is about `Image.set_pixel` loops, and it is the reason the Wizard is here.

`addons/godot_mcp` is a WebSocket bridge into a **running** editor (port 6505; the Node
side is built outside the repo and declared in this project's `.mcp.json`).
Nothing to connect to with the editor closed. **Registering it globally does not work**: the
Node server binds 6505 the moment it starts, so with a user-scoped entry every open Claude
session races for the port and all but the first die with `EADDRINUSE` — which reads as
"the MCP silently has no tools". It is per-project for that reason, and even then only one
session at a time gets the bridge.

**Never run Godot in *editor* mode while the editor is open** — that means `--import` and
`--editor`, with or without `--headless`. The bridge keeps exactly one client and the
newest wins (`this.client = ws` in `godot-bridge.ts`); a second Godot loads the plugin,
steals the slot, and takes the bridge down with it when it exits. The live editor's socket
stays ESTABLISHED, so its plugin never notices and never reconnects — the only way back is
to restart the editor. Everything in §5 is safe: those runs are *game* mode (`-s` or a
scene path), where editor plugins do not load at all.

Two tools do not do what their names promise, and both fail *quietly*.
`update_property` runs the value through a type parser that returns a `res://` path as a
plain String, so it cannot set any resource-typed property — it assigns the string, Godot
drops it, and the tool still reports success with the path echoed back. `execute_editor_script`
is an `Expression`, not a script: no `var`, no statements, no singletons, and `load()` fails.
Wiring a resource into a property is the case §2's "author it in the scene" covers — edit
the `.tscn`, and let the `.tscn` hook confirm it loads.

While it runs the plugin injects three autoloads —
`MCPRuntimeBridge`, `MCPInputBridge`, `MCPScreenshotBridge` — into `project.godot` and
removes them on a clean shutdown. **If they show up in `git status`, the editor did not
exit cleanly; drop them, do not commit them.** Its edits go through the editor's UndoRedo,
so Ctrl+Z reverses them.

`gdlint` runs from the project venv (`.venv/`, git-ignored) and is wired to a PostToolUse
hook in `.claude/settings.json`: write a `.gd` and the linter answers in the same turn;
write a `.tscn` and `tools/hooks/check_scene.gd` loads and instantiates it, which is what
catches a dead `ext_resource`, a stale UID or a node path that no longer resolves. Neither
blocks — a warning is not a reason to stop. `gdlintrc` turns off three rules this repo
disagrees with on purpose and says why in the file.

`check_scene` is a **scene**, not a `-s` script, and that is load-bearing: under `-s` the
main loop is replaced, the autoloads never register, and every script that names `Fx`,
`Audio`, `Game` or `Net` fails to compile — so the probe reports a wall of errors about a
scene that is fine.

`gdformat` is installed but **not** wired to anything. It would reformat 53 of the 74
scripts here. Running it is the owner's call, not a side effect of editing one file.

## 7. Bugs that are deliberate, and bugs that were fixed

Fixed on the owner's instruction (do not "restore" them):

- The upgrade menu advertised the wrong hotkeys — the Strike button said `Z`, which is the
  attack key; it is `X`.
- Crush recovery used `get_tree().create_timer(2.0)`, which counts down while the tree is
  paused, so pausing skipped the penalty. It is a `Timer` node now.
- Pursuers, bats and spitters never disappeared when killed. Collapsing the five contact
  ladders into `EnemyCombat` left the death *reaction* with each owner, and those three
  had none — their sprites sat frozen where they died for the rest of the run. The
  component frees the corpse by default now (`frees_on_death`); golem and slime turn it
  off in their scenes because their corpse is the point.
- Killing something did not shake the screen, and every other shake was ±3.7 px for
  150 ms — invisible. §4 has claimed since the hitstop was removed that kill feedback is
  "screen shake, particles, the score popup and the sound"; the shake was the one nobody
  wired up, and the amplitude was too small to see anyway.
- The crush penalty was two seconds of drifting down at a fifth of gravity with the
  controls dead, which read as the game having broken rather than having hit you. It is a
  heart, a pop clear of the squeeze, and half a second of falling through the level at
  normal speed — and recovery waits for the geometry as well as the clock, because
  handing collision back inside the same squeeze is just another heart.
- `R` did nothing at all in a session, so a second round meant everyone rejoining. The
  host restarts the run for everyone now; clients are told it is not theirs to do.
- A run could only be left by dying. Pause offers RESUME / RESTART / MAIN MENU, and both
  end screens offer the same, in every mode.
- **Race mode is player-versus-player, on the owner's instruction.** Rivals are solid to
  each other and Strike, Shockwave and dash-stomp all land. Co-op and solo are untouched:
  the single predicate is `Net.is_versus()`.
- A host restart handed every client that had climbed past 75% a free upgrade at the
  bottom of the new pit — and would have ended the fresh run outright for anyone near the
  surface. An avatar's node path is identical in every run, so for a few frames the host
  was still receiving where that player had been in the run that just ended, and reading
  it as progress. Every avatar now reports `run_seed` in the same replicated packet as its
  position, and `World._reports_this_run()` gates every award and every ending. Riding
  along with the position is the point: a stale position arrives labelled stale, with no
  assumption about packet ordering.
- Bats never turned around: `abs(dir.x) > 4.0` tested a normalized vector whose maximum is
  1.0, so the branch was unreachable.
- `slime.gd` parented new trampolines to `get_parent()`, which is `Enemies`, so the
  `Trampolines` container in `World.tscn` had been empty since it was created.
- Dash-stomping a Pursuer usually hurt you instead of killing it. Its `DamageArea`
  spans the whole body while `StompArea` is a 4 px strip on top, so a descending
  player entered both at once — and the engine reported the damage overlap one
  frame earlier. By the time the stomp check ran, `take_damage()` had already
  knocked the player upward and its `velocity.y >= 0` guard failed. The damage
  path now skips a player who is dashing down from above. Found by
  `test/enemy_contact_test.gd`, not by reading the code.
- World generation re-created the wall segment already authored in `World.tscn`, leaving
  two identical colliders at the same position.
- `Shockwave.tscn` shared one `CircleShape2D` across every instance while writing its
  radius every frame.
- Every machine in a lobby heard every other player's avatar. `Audio.play(&"strike")` and
  `Audio.play(&"shockwave")` sat *inside* the `@rpc("call_local")` that spawns the attack, so
  a punch thrown anywhere in the pit played on every screen; the stomp sound played wherever
  the contact was resolved, which meant the host heard every client's boots; and the
  trampoline's bounce fired on whichever machine saw the overlap, which is all of them. The
  attack sounds are now played by the swinging machine before the RPC, the stomp travels with
  `remote_stomp` to the avatar's own machine, and the trampoline launches (and is heard by)
  only the player who landed on it — everyone still sees the pad flex.
- A remote kill shook your camera as hard as one under your feet, wherever in the pit it
  happened. `Game._kill_feedback` and the shockwave now go through `Fx.shake_from`.
- The trampoline wrote velocity, `jump_count` and `dashing_down` onto *puppet* avatars. It
  never did anything — the owner's next sync packet overwrote all three — but it was
  somebody else's machine deciding about your movement, and the noise it made was real.
Found and fixed while building the dedicated server (6 August 2026) — every one
of these was already wrong, and only became visible once a second room existed:

- **A blast's own hitbox was parented to `Fx.effects_root`.** That hitbox is what
  kills the enemies caught in the wave — simulation, not decoration — and a
  dedicated server registers no effects root. Bombs would have killed nothing on
  every server in existence. It goes in the world now, which is the same node on
  a player's machine and so changes nothing there.
- **Tree-wide group queries.** "The nearest player", "the destructibles in
  range", "the trampoline container": every one of them answered across the whole
  tree. With one room that is the same as answering within it. With four, every
  pit stands in the SAME coordinate space, so an enemy would chase a climber in a
  room it cannot reach and a bomb would break platforms in a pit nobody present
  can see.
- **Run state was a global singleton.** `Game.runs` was one table and
  `new_run()` cleared it, so a fourth room starting a climb wiped the scores of
  the three already going — and the score and kill events were `@rpc`s on the
  autoload's node path, one path shared by every room, so room 3's kill was
  deliverable to room 1's players. It is a `RunLedger` node inside each World now.
- **`DirAccess.rename` and `.copy` do not resolve a path against the directory
  the object was opened at**, whatever it looks like. The atomic account write
  silently left an `accounts.json.tmp` and no `accounts.json`. The `*_absolute`
  statics take a path and mean it.
- **The frame-time warning measured the frame interval, not the work.** With
  `max_fps` at 60 every idle server on earth would have reported itself
  overloaded. It reads `TIME_PROCESS` and `TIME_PHYSICS_PROCESS` now.
- **`OS.read_string_from_stdin(n)` reads up to n BYTES, not one line.** From a
  terminal it usually looks like a line; from a pipe or a file it returns as much
  as it can, and the console treated a whole script of commands as one command.
- **ENet compression has to match on both ends or no connection ever forms** — no
  error, no log line, just a client stuck on "contacting…". It was briefly a
  server setting, which is a way to break every client with one word. It lives in
  `NetProtocol` now, where neither side can disagree about it.

Found and fixed while building the server browser (6 August 2026), reading the
server code back with fresh eyes. Every one of these was already wrong:

- **`bans.json` was written straight over the live file.** The account file had
  been written carefully — temporary, backup, rename — and the ban file, twenty
  lines of the same idea, had not. A server killed mid-write left a truncated
  JSON, and a truncated ban list is every ban on the server. Worse, a ban file
  that would not parse loaded as an *empty* one, which is the same thing as
  quietly unbanning everybody, and said nothing. There is one `JsonFile` now and
  both use it; `test/server_storage_test.gd` pins it.
- **Two of `RateLimiter`'s four users never pruned their tables**, and they were
  the two keyed on a stranger's address: failed logins and rcon attempts. The
  class's own comment says why that matters — "one entry per address that ever
  touched the port, which is exactly the thing an attacker would be feeding".
- **`auth/logins_per_minute` says FAILED logins and counted every attempt**, so
  the player reconnecting eleven times on a bad line was locked out by a setting
  that was never about them. The allowance is read at the start of a login and
  spent only when one turns out to be wrong.
- **The audit line for a command was written after the command ran** — so `stop`,
  which closes the log, was the one command that never reached the log file.
- **A finished room that everybody walked out of kept a fully simulated pit** for
  the rest of the server's life when `rooms/empty_close_seconds` was 0, which is
  exactly the setting a persistent room uses. The end-screen timer only advances
  while somebody is there to watch it.
- **The handshake read bytes off the wire straight into a typed variable.** A
  peer that has not authenticated yet sending a string where the salt should be
  is a runtime error in the middle of the auth callback. `NetProtocol.bytes_of`
  is the only way it reads bytes now — the same fix `decode()` already had.
- **`scenes/MainMenu.tscn` was inside the content fingerprint**, only because it
  sits at the top of `scenes/` rather than under `scenes/ui/`. Moving a button on
  the main menu obliged every server on earth to redeploy.

Found and fixed while adding Uzi (10 August 2026). It was already wrong, it was
total, and nothing in the game looked wrong because of it:

- **On a dedicated server, a client's attack never reached the server, and the
  server is where every kill is resolved.** `Room.lock_roster` sets
  `session.peers = members.duplicate()`, and the server is a member of no room —
  it has no avatar and no climb — so `NetSession._send`, which only walks
  `peers`, addressed every other client and stopped. `EnemyCombat._resolve_kills`
  runs under `Net.is_sim_authority()` and nowhere else, so no client could kill
  an enemy by punching, swinging, shooting or firing a railgun. Only stomps
  worked, because a stomp travels by `rpc_id` to a named peer instead. The same
  hole swallowed `_go_down`, `stand_up` and `pay_revive`.
  The other half was `scope_sync`, which handed the avatar's synchronizer the
  same member list — so the server never received a client's position either, and
  resolved everything against a climber it believed was still on the spawn pad.
  Both now name peer 1 explicitly. It is NOT added to `session.peers`: that list
  is the roster, and `World._playing_peers()` builds one avatar per entry.
  `tools/run_server_probe.sh` now hunts an enemy down with a client's swing and
  asserts the kill came back `by_strike`. The first version of that check walked
  the avatar *onto* the enemy, which kills a pursuer by landing on it — so it
  passed against the broken build, measuring position replication and reporting
  it as an attack. A probe that can pass for the wrong reason is worse than none.

- Knockback was in the code and not on the screen. A rival's hit set `velocity.x`
  directly, and `_handle_input()` assigns `velocity.x` outright on the very next frame,
  so the shove lasted one tick and moved the player by about a pixel. Impulses go through
  `Player.shove()` now: added on top of movement and decayed, so being blown across a gap
  is something you can see and have to recover from.

## 8. The server moves with the game

**From now on, every change to the game is a change to the dedicated server.**
Not because the server has a copy of anything — it is a build of this same
repository, and that is exactly why. It *runs* the simulation: the same
`WorldGenerator`, the same enemies, the same `Blast`. A server left up across a
game update does not report an error. It hands its clients a seed, they build a
*different* pit from it, and they fall through geometry the server does not have.

Two numbers travel in the first packet either side sends, and a mismatch is
refused with a sentence naming which side is stale:

- **`NetProtocol.VERSION`** — the shape of the conversation. Hand-maintained,
  because it describes code and code cannot be hashed out of an exported build.
  Bump it when a message gains, loses or repurposes a field, when an `@rpc`
  signature changes, or when authority moves between machines.
- **the content fingerprint** — generated by `tools/build_protocol_stamp.gd`
  over every file the simulation is a function of. Never hand-edited.

`tools/run_tests.sh` regenerates the fingerprint on every run and says out loud
when it moved. When it does: **commit the regenerated
`data/net/protocol_stamp.tres` with the change, and rebuild and restart every
server.**

### The checklist, when you add something to the game

Most of it costs nothing, because most of it already works — the server runs the
same code. It is written down so that the parts which do not are not discovered
by a player.

1. **Does it spawn a replicated node?** Scope it before `add_child`:
   `session.scope(node)`. Not after — the packet has already gone.
2. **Does it broadcast?** `NetSession.of(node).broadcast(...)`, never `.rpc()`.
3. **Does it ask the tree for a group?** Use `NetSession.avatars_of()` or
   `NetSession.in_world()`. Every room is at the same coordinates.
4. **Does it hang anything off `Fx.effects_root`?** Only if it is a cosmetic. A
   server has no effects root; simulation goes in the world.
5. **Does it add a tuning number an operator might want?** Consider one line in
   `ServerSettings._declare()` — it appears in `server.cfg`, in `set`/`get`, and
   in the admin panel, with no further work.
6. **Does it add a moderation verb?** It goes in `Moderation` and gets a command;
   the console, rcon and the panel then all have it.
7. **Run `bash tools/run_tests.sh`.** The server probe boots a real server and
   two clients in two rooms; the fingerprint step tells you to redeploy.
8. **Does it change what a server tells the world about itself?** The browser
   row, the LAN beacon and the announce are one shape — `DirectoryEntry` — and a
   field added to `PitServer._beacon_payload` belongs in `DirectoryClient.
   build_message` too, or a server will describe itself differently depending on
   how it was found.
9. **Update [docs/SERVER.md](docs/SERVER.md)** if an operator would need to know.

### What is deliberately NOT in the fingerprint

`scenes/ui`, `scenes/fx`, `src/ui`, `data/fx`, `data/audio`, the sprites,
`scenes/MainMenu.tscn` and `scenes/Lobby.tscn` with their scripts, `scenes/server`,
`src/server` itself — and `src/directory`, which is metadata ABOUT servers rather
than part of one. The first group is presentation: a new particle preset must
not oblige every player to download a new client. The last is the other side of
the same coin — a client never runs a line of the server's own code, so it cannot
be out of step with it, and fixing a typo in a log message must not invalidate
every client in existence.

## 9. Talking to the owner

Russian. He is the sole developer and treats this repo as his. Ask before adding
anything; report what actually happened, including what failed.

**Commit and push straight to `main`.** He asked for this explicitly on 30 July
2026 — there is no branch protection here and no second reviewer to wait for, so
a feature branch is a step that only gets in his way. Still commit only when he
asks for it, and still run `bash tools/run_tests.sh` green first.

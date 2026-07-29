# CLAUDE.md — working rules for this repository

The PIT: Ascension. Godot 4.7, GDScript. A vertical platformer: Cyn climbs out of a
trash pit from depth 8000 to the surface at 0, while broken drone parts fall past her.
Fan project, open source, non-commercial. Theme: *Murder Drones* (Glitch), episode 5.

Read this before changing anything.

---

## 1. The one rule that gets changes reverted

**Do not add game content.** The inventory is frozen unless the owner asks:

> 5 enemies (Golem, Slime, Pursuer, Bat, Spitter) · 3 unlockable upgrades (double jump,
> sideways strike, shockwave) plus the +1 HP heal option · 1 built-in dash-down ·
> 1 trampoline · 2 platform kinds · 4 levels · 1 world · no bosses.

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
src/       code by system (audio/, core/, entities/, world/, ui/, net/, fx/, defs/)
scripts/   entity controllers and the older autoloads (Fx, Game, world, player, enemies)
data/      .tres resources — the tuning surface (audio/, animations/, enemies/, fx/, worlds/)
scenes/    .tscn by category (fx/, ui/, entities at the top level)
assets/    sprites/, audio/ (+ CREDITS.md), ui/
test/      GdUnit4 suites
tools/     headless probes, one-shot generators, the test harness
docs/      ARCHITECTURE, CONTENT, NETWORKING, TESTING
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
- **Single-player never opens a socket.** Every probe must pass with no networking active.
- **Collision layers are named** in `project.godot`. Never write a raw bitmask literal.
- **Pause is owned in one place.** No script sets `get_tree().paused` ad hoc.

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
godot --path . --fixed-fps 60 tools/visual_check.tscn -- out.png   # sprite gallery
godot --path . tools/ui_check.tscn -- out_dir           # every UI surface, for eyeballing (advisory)
bash tools/check_conventions.sh                         # grep gates for the rules above
```

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

## 6. Bugs that are deliberate, and bugs that were fixed

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

## 7. Talking to the owner

Russian. He is the sole developer and treats this repo as his. Ask before adding
anything; report what actually happened, including what failed.

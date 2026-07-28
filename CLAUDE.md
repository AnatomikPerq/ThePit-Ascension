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
data/      .tres resources — the tuning surface (audio/, animations/, enemies/, worlds/)
scenes/    .tscn by category
assets/    sprites/, audio/ (+ CREDITS.md), ui/
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

Nothing here needs a running editor.

```bash
godot --headless --path . -s tools/smoke_test.gd          # autoloads, buses, sound bank, every scene
godot --headless --path . -s tools/world_fingerprint.gd   # same seed => same geometry hash
godot --headless --path . -s tools/contact_matrix.gd      # how each enemy resolves each contact
godot --path . --fixed-fps 60 tools/visual_check.tscn -- out.png   # deterministic sprite gallery
bash tools/check_conventions.sh                           # grep gates
```

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
- Bats never turned around: `abs(dir.x) > 4.0` tested a normalized vector whose maximum is
  1.0, so the branch was unreachable.
- `slime.gd` parented new trampolines to `get_parent()`, which is `Enemies`, so the
  `Trampolines` container in `World.tscn` had been empty since it was created.
- World generation re-created the wall segment already authored in `World.tscn`, leaving
  two identical colliders at the same position.
- `Shockwave.tscn` shared one `CircleShape2D` across every instance while writing its
  radius every frame.

## 7. Talking to the owner

Russian. He is the sole developer and treats this repo as his. Ask before adding
anything; report what actually happened, including what failed.

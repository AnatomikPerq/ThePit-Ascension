# Testing

Nothing here needs a running editor. One command runs every gate:

```bash
bash tools/run_tests.sh
```

`GODOT` can be overridden; it defaults to the Steam install path.

## The gates

| Step | What it proves |
| :--- | :--- |
| **GdUnit4 suites** (`test/`) | sound bank integrity, and that every sound is classified as an avatar's or the world's; the enemy contact matrix (stomp/strike/damage for all five, and whose corpse stays); the bomb's contact matrix (falls through the level, goes off against a body for two hearts, is *thrown* by an ability along both axes and harder for a centred hit, blows up on whatever it lands on), what its blast reaches, and how it throws the player (both axes, further than it hurts, nothing beyond the push radius, and far harder point blank); the destruction rule (strength vs. falloff force, nearest-edge distance, no accumulation, the strength ladder, blocks vs. shards, and that the shaft is indestructible in a real generated world); world generation is a pure function of the seed; Fx pooling, the effects-root contract, the shake amplitude and its distance falloff; per-player run state; session ending semantics (co-op vs race); what race mode changes and what co-op/solo must not notice; the crush penalty; what a restart must not carry over |
| **smoke test** (`tools/smoke_test.gd`) | every autoload configured and loadable, every audio bus present, every sound id resolves to a real stream on a real bus, every scene instantiates |
| **state probe** (`tools/state_probe.tscn`) | real `InputEventKey`s through `Input.parse_input_event()`: pause, input reachability while paused, restart-while-paused actually reloads, shake reaching the camera, and leaving a run for the main menu through the pause button |
| **world fingerprint** (`tools/world_fingerprint.tscn`) | same seed ⇒ same geometry SHA256, no stacked duplicate colliders. The oracle for generator refactors and the property multiplayer stands on |
| **net probe** (`tools/run_net_probe.sh`) | a real host + client over a localhost socket: identical world hash from the shared seed, both avatars with correct authorities, enemies mirrored, score replicated, a host restart landing both machines in the same new world, a race in which the client's strike costs the host a heart on the host's own machine, and a bomb the host sets off taking the same named platform out of the **client's** world while a control platform survives |
| **conventions** (`tools/check_conventions.sh`) | grep gates for CLAUDE.md rules: no `Engine.time_scale` writes, no runtime texture drawing, no runtime audio synthesis, no `set_script()`, no raw collision bitmask literals |

Individual invocations are listed in CLAUDE.md §5.

## Advisory (not gates)

- **`tools/visual_check.tscn`** — deterministic sprite gallery. Every entity
  is frozen to `PROCESS_MODE_DISABLED` after `_ready()` and captured at a
  fixed frame rate; two runs of the same commit are byte-identical. Pixel
  identity is a **detector, not a gate**: bugs get fixed even when the fix
  is visible. When a capture changes, say what changed and why, and
  re-baseline deliberately.
  ```bash
  godot --path . --fixed-fps 60 tools/visual_check.tscn -- out.png
  ```
- **`tools/build_readme_shots.tscn`** — one-shot generator for the images in
  README.md, into `docs/images/`. Not a check: it exists so the README's
  pictures have a traceable origin — the project's own scenes rendered by its
  own renderer at a fixed seed. Re-running overwrites them.
  ```bash
  godot --path . tools/build_readme_shots.tscn
  ```
- **`tools/ui_check.tscn`** — screenshots every UI surface (menu, lobby,
  HUD, pause, upgrade menu, both end screens) for eyeballing. Not
  deterministic (embers drift); use it to see that a layout change did what
  you meant.
- **`tests_e2e/`** — PlayGodot end-to-end suite driving the whole running
  application. Runs under WSL on a Godot 4.6 automation fork, so a failure
  there can be a version difference; the gate is `run_tests.sh` on stock
  4.7. Its input injection does not reach the game — see
  `tests_e2e/README.md` for the whole story.
  ```bash
  bash tools/setup_e2e.sh   # once
  bash tools/run_e2e.sh
  ```

## Hard-won rules

These were each learned from a harness that lied. Full stories in CLAUDE.md §5.

1. **Count physics frames, never wall-clock.** `await await_millis(50)`
   failed at random when scene loading ate the budget.
   `for i in N: await get_tree().physics_frame`.
2. **Free what a test spawns, immediately.** A golem petrified in one case
   became a platform under the next case's player.
3. **Freeze what you screenshot.** Unfrozen entities made two captures of
   the same commit differ by 8.6% — a harness that reports noise as
   regression is worse than none.
4. **Refactor against an oracle.** The generator rework was provable only
   because the fingerprint hashes existed *before* the first line changed.
5. **Probes must survive scene swaps.** The Router frees `current_scene`;
   a probe that *is* the current scene dies mid-await. Hand it a
   placeholder (see `net_probe.gd`, `state_probe.gd`).
6. **Do not hash a clock.** The net probe's world hash folds moving
   platforms back to their authored position. Their live position depends
   on how many ticks that machine has run, so hashing the live picture
   compares when the two peers entered the world, not what they built.
7. **Sample a random effect more than once.** Screen shake is a fresh random
   offset each frame inside a decaying envelope: a single read lands near
   zero often enough to fail one run in twenty. Assert the peak over a
   handful of frames.
8. **A probe with no exit is a hung test run.** A parse error in
   `net_probe.gd` leaves Godot spinning on an empty scene, and
   `run_net_probe.sh` waited on it forever. Both halves run under `timeout`
   now; exit 124 is reported as "never reached `_finish`".
9. **Barriers between probe steps, not sleeps.** The host asserting the
   client's score while the client was already climbing turned an expected
   100 into 850. The two sides checkpoint each other by RPC. The same trap bit
   the destruction stage from the other end: the host finished first and quit,
   which closed the socket and sent the client to the main menu, and the client
   then reported "no world to blow anything up in".
10. **An RPC is queued, not sent.** The client signalled the host and called
    `get_tree().quit()` on the next line; the process ended before the socket was
    flushed, so about one run in three the host failed with "the client never
    reported on the blast" while the client's own log said PASSED. Spend a few
    frames after the last packet before quitting.
11. **Position a body BEFORE add_child.** Setting `global_position` afterwards
    leaves the physics server holding the overlap the body had at the origin for
    one step, so a player parked 44 px clear of a bomb still set it off. World
    spawns everything this way already; tests have to as well.
12. **Global state on an autoload leaks between suites.** `Fx.listener_position`
    is set by every World that is built, and a suite that builds one leaves it
    7700 px down the pit — which silently zeroed every distance-scaled
    assertion in whatever suite ran next. Reset it in `before_test`, like
    `effects_root`.
13. **An enemy despawns below the avatar it tracks.** Parking a test's player
    3000 px above the enemies made all five leave on their own, and the case
    asserting that a blast kills them passed for the wrong reason. Keep the
    bystander level with them and put it out of range sideways instead.

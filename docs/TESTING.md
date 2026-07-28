# Testing

Nothing here needs a running editor. One command runs every gate:

```bash
bash tools/run_tests.sh
```

`GODOT` can be overridden; it defaults to the Steam install path.

## The gates

| Step | What it proves |
| :--- | :--- |
| **GdUnit4 suites** (`test/`) | sound bank integrity; the enemy contact matrix (stomp/strike/damage for all five); world generation is a pure function of the seed; Fx pooling and the effects-root contract; per-player run state; session ending semantics (co-op vs race) |
| **smoke test** (`tools/smoke_test.gd`) | every autoload configured and loadable, every audio bus present, every sound id resolves to a real stream on a real bus, every scene instantiates |
| **state probe** (`tools/state_probe.tscn`) | real `InputEventKey`s through `Input.parse_input_event()`: pause, input reachability while paused, restart-while-paused actually reloads |
| **world fingerprint** (`tools/world_fingerprint.tscn`) | same seed ⇒ same geometry SHA256, no stacked duplicate colliders. The oracle for generator refactors and the property multiplayer stands on |
| **net probe** (`tools/run_net_probe.sh`) | a real host + client over a localhost socket: identical world hash from the shared seed, both avatars with correct authorities, enemies mirrored, score replicated |
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

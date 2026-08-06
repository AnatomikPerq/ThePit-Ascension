# Testing

Nothing here needs a running editor. One command runs every gate:

```bash
bash tools/run_tests.sh
```

On a clone, run `bash tools/setup_claude.sh` once first — it installs gdtoolkit
and imports the project. Without that import there is no
`.godot/global_script_class_cache.cfg`, no `class_name` resolves, and the gates
below fail on parse errors instead of on anything real. `run_tests.sh` checks
for it and says so rather than grinding.

`GODOT` (or `GODOT_CLI`) pins the binary. Left unset, `tools/lib/find_godot.sh`
discovers one and the run prints which it picked; it prefers the standalone
*console* build, because the Steam exe writes nothing unless its output is
redirected.

## The gates

| Step | What it proves |
| :--- | :--- |
| **GdUnit4 suites** (`test/`) | sound bank integrity, and that every sound is classified as an avatar's or the world's; the enemy contact matrix (stomp/strike/damage for all five, and whose corpse stays); the bomb's contact matrix (falls through the level, goes off against a body for two hearts, is *thrown* by an ability along both axes and harder for a centred hit, blows up on whatever it lands on), what its blast reaches, and how it throws the player (both axes, further than it hurts, nothing beyond the push radius, and far harder point blank); the destruction rule (strength vs. falloff force, nearest-edge distance, no accumulation, the strength ladder, blocks vs. shards, and that the shaft is indestructible in a real generated world); world generation is a pure function of the seed; Fx pooling, the effects-root contract, the shake amplitude and its distance falloff; per-player run state; session ending semantics (co-op vs race); what race mode changes and what co-op/solo must not notice; the crush penalty; what a restart must not carry over; the two climbers and that nothing branches on which one it is; that the dash-down box reaches further than the body and is armed only while diving; going down, the body that is left, and the arithmetic of a pick-up; **for the server**: password hashing against a published PBKDF2 vector, a login proof bound to its nonce, the decoy salt that stops account names being probed, the permission ladder and its wildcards, bans and their expiry, token-bucket rate limits, every setting's default surviving its own validation, the `server.cfg` round trip, permission being checked before syntax, two-word commands, room addressing and password hashing, a roster locked with the seed, and the build fingerprint's refusal messages |
| **smoke test** (`tools/smoke_test.gd`) | every autoload configured and loadable, every audio bus present, every sound id resolves to a real stream on a real bus, every scene instantiates |
| **state probe** (`tools/state_probe.tscn`) | real `InputEventKey`s through `Input.parse_input_event()`: pause, input reachability while paused, restart-while-paused actually reloads, shake reaching the camera, and leaving a run for the main menu through the pause button |
| **world fingerprint** (`tools/world_fingerprint.tscn`) | same seed ⇒ same geometry SHA256, no stacked duplicate colliders. The oracle for generator refactors and the property multiplayer stands on |
| **net probe** (`tools/run_net_probe.sh`) | a real host + client over a localhost socket: identical world hash from the shared seed, both avatars with correct authorities, enemies mirrored, score replicated, a host restart landing both machines in the same new world, both machines building the two DIFFERENT climbers the two peers picked, a race in which the client's strike costs the host a heart on the host's own machine, the client running out of hearts and the host paying one of its own to stand it back up, and a bomb the host sets off taking the same named platform out of the **client's** world while a control platform survives |
| **server probe** (`tools/run_server_probe.sh`) | THREE processes on one real socket: a dedicated server and two clients that end up in **different rooms** of it. Registering, and the first account becoming the owner; two rooms running at once with each client holding exactly one world — its own, named after its own room, carrying only its own avatar; two different pits; enemies mirrored into each room separately; chat addressed to a room and not overheard from the next; the admin path (the owner reads the player list and the whole settings schema over the game socket) and the refusals (an ordinary player denied `stop` and `kick`); and both client logs grepped for the replication errors a packet arriving for the wrong room would produce. The only harness that can check room isolation — one process always agrees with itself |
| **conventions** (`tools/check_conventions.sh`) | grep gates for CLAUDE.md rules: no `Engine.time_scale` writes, no runtime texture drawing, no runtime audio synthesis, no `set_script()`, no raw collision bitmask literals, no object decoding over the wire, no server code reading the local machine's session, no unaddressed gameplay broadcast, no bare `print()` in the server, and LF line endings — a stray carriage return inside a `.tscn` string double-spaces the label with no error anywhere |
| **protocol fingerprint** (`tools/build_protocol_stamp.gd`) | not a gate, a **notice**. Regenerated on every run; when it moves, the run says loudly that the dedicated server must be rebuilt and restarted from this commit or it will refuse every client built from it. Regenerating it here is what makes the stamp get committed *with* the change that moved it |

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
- **`tools/ui_check.tscn`** — screenshots every UI surface (menu, character
  select, lobby, HUD, pause, the upgrade menu both full and part-spent, the
  spectator view with a revive sign, both end screens) plus the three attacks
  caught mid-swing, which is the only way to look at them: Cyn's fist is one
  drawing spun by an `AnimationPlayer`, so a single still of it says nothing.
  Not deterministic (embers drift); use it to see that a change did what you
  meant.
- **`tools/world_balance.gd`** — the pit level by level: rows, platforms, the
  mean and worst climb between two things you can stand on, and the enemy mix,
  against what each character can actually jump. Every ramp in `WorldProfile` is
  a lerp over ascent *progress*, so changing `level_count` restretches all of
  them at once and this is the only honest way to see what that did.
  ```bash
  godot --headless --path . -s tools/world_balance.gd [seeds]
  ```
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
   placeholder (see `net_probe.gd`, `server_probe.gd`, `state_probe.gd`). The
   server probe hit it too, and the symptom is a hang rather than a failure:
   the freed probe stops printing and the shell waits out its whole deadline.
6. **Want the answer you asked for.** The server probe listens for admin data on
   a signal that every admin request answers — including the ones the panel
   instanced into the running world makes for itself. Unfiltered, it caught
   whichever reply landed first and reported the one it wanted as missing. Match
   on the kind.
7. **Do not hash a clock.** The net probe's world hash folds moving
   platforms back to their authored position. Their live position depends
   on how many ticks that machine has run, so hashing the live picture
   compares when the two peers entered the world, not what they built.
8. **Sample a random effect more than once.** Screen shake is a fresh random
   offset each frame inside a decaying envelope: a single read lands near
   zero often enough to fail one run in twenty. Assert the peak over a
   handful of frames.
9. **A probe with no exit is a hung test run.** A parse error in
   `net_probe.gd` leaves Godot spinning on an empty scene, and
   `run_net_probe.sh` waited on it forever. Both halves run under `timeout`
   now; exit 124 is reported as "never reached `_finish`".
10. **Barriers between probe steps, not sleeps.** The host asserting the
   client's score while the client was already climbing turned an expected
   100 into 850. The two sides checkpoint each other by RPC. The same trap bit
   the destruction stage from the other end: the host finished first and quit,
   which closed the socket and sent the client to the main menu, and the client
   then reported "no world to blow anything up in".
11. **`physics_frame` fires at the START of the frame.** Awaiting it once
    returns *before* any `_physics_process` has run, so "wait one frame and read
    the result" reads the state you already had. Two frames is the minimum for
    anything a node does to itself.
12. **An RPC is queued, not sent.** The client signalled the host and called
    `get_tree().quit()` on the next line; the process ended before the socket was
    flushed, so about one run in three the host failed with "the client never
    reported on the blast" while the client's own log said PASSED. Spend a few
    frames after the last packet before quitting.
13. **Position a body BEFORE add_child.** Setting `global_position` afterwards
    leaves the physics server holding the overlap the body had at the origin for
    one step, so a player parked 44 px clear of a bomb still set it off. World
    spawns everything this way already; tests have to as well.
14. **Global state on an autoload leaks between suites.** `Fx.listener_position`
    is set by every World that is built, and a suite that builds one leaves it
    7700 px down the pit — which silently zeroed every distance-scaled
    assertion in whatever suite ran next. Reset it in `before_test`, like
    `effects_root`.
15. **An `Area2D` others must see needs `monitoring` too, set LAST.** Godot does
    not report an area with monitoring off from another area's
    `get_overlapping_areas()`, whatever `monitorable` says — and setting the two
    the other way round does not pair them either. The dash-down box was
    silently inert: measured against a golem it reached 53 px (the body's own
    width) instead of 57 (the box). Nothing failed until a test asked for the
    number.
16. **An enemy despawns below the avatar it tracks.** Parking a test's player
    3000 px above the enemies made all five leave on their own, and the case
    asserting that a blast kills them passed for the wrong reason. Keep the
    bystander level with them and put it out of range sideways instead.

# End-to-end suite (PlayGodot)

Drives the **whole running application** — boot, menu, world, pause, restart —
over Godot's native RemoteDebugger protocol.

```bash
bash tools/setup_e2e.sh   # once
bash tools/run_e2e.sh     # ~15 s
```

## This suite is advisory, not the gate

The gate is `bash tools/run_tests.sh`, which runs on the same **Godot 4.7** that
builds the game. Read that difference before trusting a failure here.

PlayGodot's automation commands are compiled into the engine rather than shipped
as an addon, so it needs the [Randroids-Dojo automation
fork](https://github.com/Randroids-Dojo/godot). That fork:

- publishes **Linux and macOS binaries only** — there is no Windows build, which
  is why everything runs under WSL;
- is based on **Godot 4.6**, while this project targets 4.7;
- ships as a **mono** build, so it will not start without the .NET 8 runtime.

A failure here can therefore be a 4.6-vs-4.7 difference rather than a real bug.
Confirm anything surprising against stock 4.7 before acting on it.

The project is **copied into WSL** rather than opened from `/mnt/c`, because a
4.6 editor writing its import cache into the working tree could downgrade files
that 4.7 owns.

## What it does not test: input

`press_key` and `press_action` **do not reach the game** — verified both headless
and with a real WSLg window. This is the same limitation GdUnit4 warns about
("Godot InputEvents are not transported by the engine in headless mode"). A
direct method call through the same connection works fine, which is how these
tests trigger everything.

Keyboard paths are covered instead by `tools/state_probe.gd`. It runs on stock
Godot 4.7 and feeds real `InputEventKey` objects through
`Input.parse_input_event()`, which does work — it is what proved the
restart-while-paused fix. Between the two:

| | covers |
| --- | --- |
| `tools/state_probe.gd` (Godot 4.7) | InputMap wiring: a physical key reaching a handler that can still process while paused |
| `tests_e2e/` (Godot 4.6) | the application holding together across a scene change: autoloads, world construction, pause state, reload |

## Layout

- `conftest.py` — launches the game per test and tears it down.
- `test_gameplay.py` — the suite.

`E2E_PROJECT`, `GODOT_PATH` and `E2E_TIMEOUT` override the defaults if you want
to point it somewhere else.

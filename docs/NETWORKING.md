# Networking

Plain ENet (UDP) over an open port. One player hosts; the rest join by
address. No accounts, no relays, no service integration. The host forwards
one UDP port (default **24565**) and everyone connects directly.

**Single-player never opens a socket.** `Net.active` is false until the
lobby calls `Net.host()` or `Net.join()`; every networked code path in the
game is gated on it. With no session, the game is bit-for-bit the solo game
— which is why every solo probe and test runs with networking inert.

## Session flow

1. Host: **MULTIPLAYER → HOST** (opens the port, up to 8 players).
2. Clients: enter address + port → **JOIN**. The lobby lists everyone.
3. Host picks **CO-OP** or **RACE** and starts. `Net.start_session()` locks
   the roster and broadcasts `(mode, seed, peers)`; every machine sets its
   local peer id, starts a run for the roster, and enters the world through
   `Router.start_run(seed)`.
4. There is **no join-in-progress** and no host migration. A client that
   drops is removed everywhere; if the host drops, clients return to the
   menu.

The world itself never travels: every machine rebuilds identical geometry
from the shared seed (the same determinism the fingerprint harness
enforces). What travels is avatar state, spawn/despawn of host-simulated
entities, and events.

## Authority model — "one-peer mirror"

Each avatar is simulated by the machine of the player steering it and
mirrored to everyone else. Everything about the *world* is simulated by the
host and mirrored to clients. `Net.is_sim_authority()` answers "does the
world simulation run here" — true solo and on the host.

### Element by element: client-side vs server-side

| Element | Simulated on | Replicated by |
| :--- | :--- | :--- |
| Avatar movement, input, physics | **client** (owning machine) | `MultiplayerSynchronizer` on Player.tscn: position, velocity, facing, dash, flight, health, animation |
| Avatar health & damage | **client** (the victim's machine decides its own damage) | health synced; invincibility window absorbs duplicate resolutions |
| Avatar death | **client** (owner) | one `@rpc` runs the death visuals on every machine |
| Strike / Shockwave | **client** initiates | `@rpc("call_local")` spawns the scene on *every* machine — the host needs the hitbox, the rest the visual; strikes snap themselves to their owner |
| Enemy AI & movement | **server** (host) | per-enemy `MultiplayerSynchronizer` (position + minimal visual state) |
| Enemy spawning | **server** | `MultiplayerSpawner` on `World/Enemies` |
| Enemy kills (strike & stomp resolution) | **server** | one `@rpc` marks the death on every machine (so golems petrify into local platforms everywhere); the spawner mirrors frees |
| Stomp rebound on a client's avatar | **server** detects | `remote_stomp` RPC to the avatar's owner |
| Mistimed-stomp punishment | **server** detects | `remote_hurt` RPC to the avatar's owner |
| Projectiles | **server** (motion, lifetime, free) | spawner + synchronizer; each machine hurts only its own avatar on overlap |
| Trampolines (from slimes) | **server** spawns | `MultiplayerSpawner` on `World/Trampolines`; the bounce itself is local physics on whoever touches it |
| Score, kills, combo | **server** | kill events broadcast the resulting numbers; client score requests route through the host |
| Upgrade milestones, zone crossings | **server** detects | RPC to the earning peer opens *its* menu / notification |
| Upgrade choice & ability flags | **client** (owner machine) | abilities affect only the owner's simulation; attacks replicate as above |
| Victory / race outcome | **server** | `_end_session(winner)` RPC; +2000 surface bonus lands host-side first |
| World geometry | deterministic everywhere | never transported — rebuilt from the seed |
| Moving platforms | deterministic everywhere | pure function of ticks-since-ready at 120 Hz |
| Cosmetics (shake, particles, popups, sounds) | **local, always** | fired from replicated events, never replicated as state |
| Pause | **local** | in a session the tree never pauses; the overlay shows and the local avatar stops listening |

### Rules this stands on

- **Determinism**: world generation draw order is a contract
  (`world_generator.gd`); physics is fixed at 120 Hz; shared timing reads
  the physics tick, never wall-clock.
- **Cosmetics are local** — a machine's juice is its own business; only
  events cross the wire.
- **Host owns consequences, victims own pain**: kills, score and endings
  are the host's call; damage to an avatar is applied only by the machine
  that steers it, so lag never makes someone else's overlap test hurt you.

## Known limitations (accepted, documented)

- Remote stomp resolution reads synced position/velocity, so a laggy
  client's stomps land with the host's view of the world.
- Moving platforms count ticks from their own scene entry, so peers can be
  offset by the few ticks between their world builds (constant, no drift).
  Perfect alignment would need a session tick broadcast — the seam exists
  in `MovingPlatform` (a pure function of tick).
- The stomp sound of a remote player's kill plays on the host machine only;
  the kill popup/burst play everywhere via the kill event.
- `R` (restart) is disabled in a session: one shared run. Leave with ESC.

## Verifying

```bash
bash tools/run_net_probe.sh   # part of tools/run_tests.sh
```

boots a real headless host and client over a localhost socket and asserts:
identical world hash from the shared seed, both avatars present with the
right authorities on both machines, host-spawned enemies mirrored to the
client, and a host-credited kill visible in the client's run mirror.
`test/net_session_test.gd` pins the mode semantics (co-op = shared victory,
race = one winner, ending stops the simulation).

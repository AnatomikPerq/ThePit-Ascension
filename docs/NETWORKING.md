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
2. Clients: enter address + port → **JOIN**. The lobby lists everyone, and
   what each of them will be.
3. Everyone picks a **climber**, or **SPECTATOR** instead. Each peer speaks
   only for itself (`Net.announce_choice`), and everyone re-announces whenever
   somebody arrives, so a late joiner learns the whole picture without the host
   keeping a master copy.
4. Host picks **CO-OP** or **RACE** and starts. `Net.start_session()` locks
   the roster and broadcasts `(mode, seed, peers, picks)`; every machine sets
   its local peer id, starts a run for the peers that picked a climber, and
   enters the world through `Router.start_run(seed)`. The picks travel *with*
   the roster rather than being asked for afterwards, because every machine has
   to build the same avatars in the same order before the first frame.
5. The host can **restart** at any point — `R`, the pause menu, or the end
   screen. `Net.restart_session()` rolls a fresh seed and goes back through
   `start_session()`, so a restart is not a special case: the roster is
   re-locked from whoever is still connected and every machine enters the new
   run exactly the way it entered the first one. Clients cannot restart a
   shared run; their buttons say so.
6. There is **no join-in-progress** and no host migration. A client that
   drops is removed everywhere; if the host drops, clients return to the
   menu. Anyone can leave for the main menu at any time, from the pause
   overlay or the end screen.

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
| Avatar death, solo | **client** (owner) | one `@rpc` runs the death visuals on every machine |
| Avatar death, session | **client** (owner) | `_go_down` on every machine: the body drops off every collision layer, keeps WORLD in its mask so it falls to a floor, and stays. `is_downed` is replicated |
| The revive sign over a body | **local, always** | nothing crosses the wire — each machine asks whether ITS climber is close enough and can afford it |
| Whether a revive happened | **server** decides | the presser asks the host; the host judges from replicated state and asks the two owning machines. Health is never written by anyone else |
| Standing up, and the heart it cost | **client** (each owner) | `remote_revive` / `remote_pay_revive` from the host, then `call_local` from the owner so every machine sees it |
| Everybody down | **server** | `_end_session_wiped` — the run is over when nobody is left to pick anyone up |
| Which climber each peer is | **server** locks it | `session_characters`, broadcast in the same packet as the roster and the seed |
| Where a spectator is looking | **local, always** | never replicated; a spectator changes nothing about the run |
| Strike / Shockwave | **client** initiates | `@rpc("call_local")` spawns the scene on *every* machine — the host needs the hitbox, the rest the visual; strikes snap themselves to their owner |
| Enemy AI & movement | **server** (host) | per-enemy `MultiplayerSynchronizer` (position + minimal visual state) |
| Enemy spawning | **server** | `MultiplayerSpawner` on `World/Enemies` |
| Enemy kills (strike & stomp resolution) | **server** | one `@rpc` marks the death on every machine (so golems petrify into local platforms everywhere); the spawner mirrors frees |
| Stomp rebound on a client's avatar | **server** detects | `remote_stomp` RPC to the avatar's owner |
| Mistimed-stomp punishment | **server** detects | `remote_hurt` RPC to the avatar's owner |
| Projectiles | **server** (motion, lifetime, free) | spawner + synchronizer; each machine hurts only its own avatar on overlap |
| Trampolines (from slimes) | **server** spawns | `MultiplayerSpawner` on `World/Trampolines`; the bounce launch and its sound belong to the machine steering the player who landed — every machine still sees the pad flex |
| Bombs: fall, being thrown, flight | **server** | spawner + synchronizer (position, rotation, thrown flag) |
| Whether a bomb goes off | **server** decides (it is the machine that can see every avatar) | one `@rpc("call_local")` carrying the epicentre, the destroyed list and who is credited |
| What a blast destroys | **server** decides | the *names* of the pieces travel; every machine breaks exactly those. Never recomputed per peer — see below |
| Blast damage to an avatar | **client** (the victim) | nothing crosses the wire: the event says where it went off and each machine measures its own avatar |
| Being thrown by a blast | **client** (the victim) | same event, same rule — the shove is applied where the velocity lives |
| A bomb set off by a body | **server** names the peer in the event | that one machine takes two hearts, a much bigger shove, a flat deep boom and a screen-filling fireball. Everyone else plays the ordinary blast; the spectacle needs no packet of its own because the avatar's position is already replicated |
| Enemies caught in a blast | **server** | the blast's hitbox is in the `"strike"` group, so it resolves down the existing kill path |
| Score, kills, combo | **server** | kill events broadcast the resulting numbers; client score requests route through the host |
| Upgrade milestones, zone crossings | **server** detects | RPC to the earning peer opens *its* menu / notification |
| Upgrade choice & ability flags | **client** (owner machine) | abilities affect only the owner's simulation; attacks replicate as above |
| Victory / race outcome | **server** | `_end_session(winner)` RPC; +2000 surface bonus lands host-side first |
| Restarting a shared run | **server** decides | `Net.restart_session()` → `_begin_run(mode, new seed, roster)` on every machine |
| Which run an avatar is reporting from | **client** (owner) | `run_seed` on Player, replicated ALWAYS alongside `position`; the host awards nothing to an avatar whose seed is not this run's |
| Player-vs-player collision (race) | **client** (each machine's own physics) | nothing crosses the wire — rivals are already synced bodies, and each machine adds the PLAYER bit to its own avatar's mask |
| Player-vs-player damage (race) | **client** (the victim) | the victim's HurtBox sees the rival's already-replicated attack hitbox locally; a dash-stomp sends `remote_hurt` to the victim's machine |
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
- **A new run is a new run.** An avatar's node path is the same in every run,
  so after a restart the previous run's position packets still land on the
  fresh puppet. Every avatar therefore states which run it is reporting from,
  in the same packet as its position, and the host awards and ends nothing
  without checking (`World._reports_this_run()`). Putting the run id in the
  same packet rather than in a separate handshake is deliberate: a stale
  position then arrives *labelled* stale, and no ordering has to be assumed
  between the reliable and unreliable channels.
- **The host decides that a revive happened; the two machines involved do it.**
  Health belongs to the machine steering the avatar, so the host cannot simply
  write it — but two climbers reaching the same body on the same frame must not
  both be charged for one pick-up. So the presser asks the host, the host judges
  from replicated state (both alive-or-not, the reviver above one heart, the two
  within range plus slack for lag) and then asks each owner to do its own half.
  `is_downed` clears on the body's own machine and takes a few frames to come
  back, so the host also latches the decision until it sees that avatar standing
  — without it the window between deciding and hearing about it is wide enough
  for a second request to pay a second heart.
- **One predicate per mode difference.** `Net.is_versus()` — a live session
  in RACE mode — is the only thing that decides whether players are solid to
  each other and whether their attacks land. Nothing else in the game tests
  the mode, and it is false in co-op and false solo, so single-player physics
  is untouched.
- **Destruction is decided once and named, not recomputed.** Everything else
  about the world is a pure function of the seed, so it is tempting to let each
  peer work out for itself what a blast broke. It does not hold: a moving
  platform's live position is a function of how many physics ticks *that*
  machine has run, so a mover at the edge of a wave breaks on one screen and
  survives on another — and a platform that exists for one player and not
  another is a desync you climb into. The host therefore sends the *names* of
  the casualties. `WorldBuilder` names every piece after its place in the plan
  precisely so that a name means the same node on every machine, and
  `test/destruction_test.gd` pins that every name a blast emits resolves back to
  a `Destructible`.
- **A sound that belongs to one avatar plays on one machine.** Your jump, your
  landing, your punch, your stomp, your bounce. This is a real rule, not a
  detail: strike and shockwave sounds used to sit *inside* the `call_local` RPC
  that spawns the attack, so every punch anyone threw played in every lobby, and
  the stomp sound played wherever the contact was resolved, which meant the host
  heard every client's boots. Things that happen at a *place* in the pit — an
  enemy dying, a golem setting, a bomb, a platform coming apart — do play
  everywhere, positionally, and fade with distance.

## Race: players against each other

In a race the other climbers are obstacles and targets. In co-op they are
neither: teammates pass through each other and cannot do each other harm.

- **Solid.** Each machine turns on the PLAYER bit in its own avatar's
  collision mask. A remote avatar is a synced body, so standing on a rival's
  head needs no new replication at all.
- **Strike and Shockwave.** Attacks already spawn on every machine. Each
  avatar carries a `HurtBox` that monitors PLAYER_ATTACK hitboxes — but only
  on the machine that steers it, and only in a race. It ignores hitboxes
  whose `owner_peer` is its own. So the victim, and nobody else, decides that
  it was hit.
- **Dash-stomp.** Coming down on a rival while dashing reads the collision
  from `move_and_slide`, applies the rebound locally, and sends `remote_hurt`
  to the victim's machine.
- **Trust.** `remote_hurt` accepts the host for world hazards, and in a race
  any peer, because a rival's stomp is resolved on the rival's machine. Peers
  in a session are trusted — the same assumption that already lets a client
  tell the host where it moved. This game is played with people you gave your
  address to.

## Known limitations (accepted, documented)

- Remote stomp resolution reads synced position/velocity, so a laggy
  client's stomps land with the host's view of the world.
- Moving platforms count ticks from their own scene entry, so peers can be
  offset by the few ticks between their world builds (constant, no drift).
  Perfect alignment would need a session tick broadcast — the seam exists
  in `MovingPlatform` (a pure function of tick).
- A bomb going off is the host's call, so a client walking into one detonates it
  with the host's view of where that client was — the same trade as remote stomp
  resolution above.
- A race hit is judged on the victim's machine from the attacker's synced
  position, so on a bad connection the attacker can see a hit the victim
  never takes. The alternative — the attacker deciding — puts someone else's
  lag on your health bar, which is the trade this whole model refuses.
- Restarting a session logs one `ERR_UNAUTHORIZED … on_despawn_receive` on
  each client. Every machine drops the old world at once, and the host's
  spawners announce the enemies they lose on the way out; those packets land
  on a peer that has already discarded the same world. It is a report about a
  node nobody has any more — harmless, and not worth guessing frame counts to
  suppress. (Detaching or freeing the spawners first does not help: Godot
  tracks each spawned node individually, and freeing the spawner only trades
  this line for a null-spawner one.)

## Verifying

```bash
bash tools/run_net_probe.sh   # part of tools/run_tests.sh
```

boots a real headless host and client over a localhost socket and asserts:
identical world hash from the shared seed, both avatars present with the
right authorities on both machines, host-spawned enemies mirrored to the
client, a host-credited kill visible in the client's run mirror, and a host
restart landing both machines in the same *new* world with both avatars, in
`PLAYING` with nothing on offer — without anybody rejoining. The client climbs
past the first upgrade milestone *before* the restart on purpose: that is the
progress a restart must not carry over.

The two peers deliberately pick **different climbers** — the host is Cyn, the
client Tessa — and both machines have to end up with one of each, carrying that
character's hearts. If the picks ever stopped travelling with the roster, every
machine would fall back to the default and the probe would report two Cyns.

It then starts a **race** and checks the part a single instance can never
check, because one machine always agrees with itself: both machines report
`is_versus()`, each avatar is solid to rivals, each machine watches its own
hurt box and not the rival's, and the client walking up and striking the host
takes a heart off the host's avatar **on the host's machine**.

Then the client runs itself out of hearts. Its body has to still be there, on
both machines; the host walks over, pays, and the client has to stand back up on
one heart with exactly one heart gone from the host. Three machines' worth of
opinion about one event — the one that goes down, the one that decides, the one
that pays — which is precisely why it cannot be checked anywhere else.

Finally it blows something up. The host aims a real bomb at one named platform
and sets it off; the **client**, which decided nothing, has to lose exactly that
platform and keep a control platform three radii away. The bomb is held still
while the spawn packet travels — a live one falls 600 px a second, and the first
version of this stage moved the epicentre a quarter of a blast below its target
and reported that destruction does not replicate.

`test/net_session_test.gd` pins the mode semantics (co-op = shared victory,
race = one winner, ending stops the simulation).
`test/versus_test.gd` pins what race mode changes and, just as importantly,
what co-op and solo must not notice.

The probe's world hash folds moving platforms back to the position they were
authored at. Their live position is a function of how many physics ticks that
machine has run since building the world, and two peers never enter a world
on the same tick — hashing the live picture compares clocks, not layouts.

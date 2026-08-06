<div align="center">

![The PIT: Ascension](docs/images/menu.png)

**A seeded vertical platformer for Godot 4.7. You start at depth 16000.
The surface does not expect you.**

Solo · Co-op · Race · a dedicated server with rooms, accounts and moderation.

</div>

---

You are **Cyn** — or **Tessa** — at the bottom of a trash pit where broken worker
drones are dumped. The Absolute Solver is active. Their heads are falling past
you on the way down. Climb out.

A fan project inspired by ***Murder Drones*** (GLITCH), episode 5. Open source,
non-commercial, unaffiliated. The theme and the full content inventory are in
[docs/CONTENT.md](docs/CONTENT.md).

## The cast

![Cyn and the five enemies of the pit](docs/images/cast.png)

| | Who | What it does | How it dies | What it leaves |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Cyn** | you: five hearts, a heavy jump, everything earned on the way up | falling, mostly | — |
| 1b | **Tessa** | you, harder: one heart, a shorter jump, but the second one from the start — and a blade, and a pistol | one mistake | — |
| 2 | **Golem** | a broken drone head, falling straight down | any stomp, or a strike | a petrified platform |
| 3 | **Slime** | falls while drifting sideways | any stomp, or a strike | a trampoline |
| 4 | **Pursuer** | chases along the ground, jumps walls and gaps | any stomp, or a strike | — |
| 5 | **Bat** | flies at you with a sine wobble | any stomp, or a strike | — |
| 6 | **Spitter** | sits on a platform and lobs acid | **dash** stomp, or a strike | — |
| 7 | **Trampoline** | what a stomped slime becomes | — | altitude |
| 8 | **Bomb** | a head that was still live when it was dumped, falling past you | it does not die — it goes off | a hole in the pit |

A jump on the head kills anything except the **spitter**, which demands a dash
and costs you a heart if you land on it without one. A golem you turned into a
platform is a step; a slime you turned into a trampoline is a shortcut. The whole
point of the pit is that it is built out of the things that were trying to kill
you.

## The bomb

It falls a shade quicker than the rest, and it falls **through** the level —
platforms and walls are not there as far as it is concerned.

Hit it with a **Strike** or a **Shockwave** and it is not fired, it is *thrown* —
spinning, along the line away from wherever the swing came from, so a hit from
below sails it up and one from above drives it into the floor. Catch it right
against you and it goes about twice as far as one clipped by the outer edge of
the same ring. From that moment the first thing it touches ends it. That is the
whole mechanic: the hazard becomes a demolition charge you can aim.

Anything caught in the blast is thrown away from it, along both axes and harder
the closer it was — the shove reaches further than the damage does, so a bomb
going off nearby moves you even when it never got close enough to hurt you.

And do not walk into one. Setting a bomb off with your own body costs **two**
hearts, throws you across the shaft, and fills your screen with it. Nobody else
sees any of that — they get the ordinary blast, and watch you leave at speed.

Whatever the blast covers dies. Whatever it *outmuscles* breaks: the wave's force
falls off with distance, and every breakable thing in the pit has a strength it
is compared against. A platform is tougher than the platform a golem petrified
into, which is tougher than a slime's trampoline. Cracks do not accumulate — a
near miss is a near miss. The shaft itself, the floor and the level dividers
never break; everything else is fair game.

In a session the host decides what a blast destroyed and tells everyone *which
pieces*, by name — the pit is rebuilt from a seed on every machine, so the hole
has to be the same hole. Explosions are heard from where they happened and get
quieter the further away you are.

## The climb

![Climbing out of the pit](docs/images/gameplay.png)

Every pit is a deterministic function of one seed — platform rows, moving
platforms, walls, level dividers, enemy pacing. The same seed builds the same
world on every machine, which is what lets multiplayer send a number instead
of a level.

The pit is **eight levels**, 2000 deep each, and at the top of every other one
the climb pays out:

![Choosing an upgrade](docs/images/upgrades.png)

Cyn is offered Double Jump, Sideways Strike, Shockwave Blast and +1 max HP;
Tessa, a Sword Slash, a Pistol and a Triple Jump. Each is a one-time pick — the menu only
ever shows what you have not taken, the last one left is simply handed to you,
and a milestone with nothing left to give pays experience instead. Chained kills
within three seconds multiply the score, and the best run persists between
sessions.

## Multiplayer

![The multiplayer lobby](docs/images/lobby.png)

**MULTIPLAYER** on the main menu is a list of somewhere to play. It fills from
three places at once — a directory on the internet, a shout on your own network
that needs no infrastructure at all, and the servers you have played on before —
and a coloured badge next to a name is a server the developer has checked, with
the reason on hover. Under the list: **CONNECT BY ADDRESS**, for a server
somebody gave you, and **OPEN MY OWN GAME**.

That last one is the peer-to-peer half, pictured above. One player forwards a UDP
port (default **24565**) and hosts; everyone else joins by address. The host picks
the mode and starts the climb for all of them.

- **Co-op** — the first to the surface wins it for the team.
- **Race** — exactly one winner, and the other climbers are in your way for
  real: rivals are solid, so you can stand on a head, and Strike, Shockwave and
  dash-stomp all land on them.

Everyone picks their own climber in the lobby — or picks **SPECTATOR** and comes
along to watch.

**Running out of hearts is not the end of you.** Your body drops where it fell
and stays there; anyone still climbing can walk up and spend one of their own
hearts to put you back on your feet with one of yours. You cannot pay on your
last heart, and while you wait you watch the pit — following whoever you like,
or flying the camera yourself. It works in every mode, race included. Solo death
is exactly what it always was.

The host can restart the run for everyone at any time. Anyone can leave for the
main menu at any time. **Single-player never opens a socket.**

Which parts of the game are simulated where — element by element, with the
rules the model stands on — is [docs/NETWORKING.md](docs/NETWORKING.md).

## A dedicated server

The other way to play: a console program that hosts **several rooms at once** and
keeps them going whether or not the person who started them is playing. It is a
build of this same repository with its presentation turned off, so it cannot be
wrong about the game — it runs the same generator and the same entities.

```bash
godot --headless --path . -- --server      # from a checkout
thepit --server                            # from a build
```

- **Rooms**, each with its own mode, seats, password and owner. One UDP port for
  all of them, and players move between them without reconnecting.
- **Found without being typed** — it answers discovery probes on its own network
  out of the box, and can announce itself to a directory to appear in the browser
  everywhere. A third mode of the same binary, `--directory`, *is* that service.
- **Accounts**, or guests, or neither — `auth/mode` decides. The password never
  leaves the player's machine.
- **Moderation**: kick, ban (timed or not, by account or address), mute, warn,
  move, close a room, announce. From the console, from a remote console over TCP,
  or from an administration panel **inside the game** on `F8` — the same commands
  with the same permission check in front of all three.
- **Rights are named, not ranked**, so somebody can be given the ability to kick
  and nothing else. `op` makes an admin; the first account on a fresh server
  becomes the owner.
- **Around ninety settings**, in a `server.cfg` the server writes itself with a
  comment above every key explaining it — and editable live from the panel.

Everything an operator needs, including a domain, running it as a service, what
the protection actually covers and what it does not, is
[docs/SERVER.md](docs/SERVER.md).

## Controls

| Action | Key(s) |
| :--- | :--- |
| Move left / right | `A` / `D`, `←` / `→` |
| Jump | `Space`, `W` |
| Dash down | `S`, `↓` |
| Strike / Sword (when unlocked) | `Z`, `LMB` |
| Tessa's pistol (when unlocked) | `RMB`, `X` |
| Shockwave (when unlocked) | `C` |
| Revive a downed teammate | `E` |
| Upgrade menu picks | `Z / X / C / V` |
| Spectating: follow ↔ free camera | `TAB` |
| Spectating: switch who you watch | `A` / `D` |
| Spectating: zoom | mouse wheel, `Q` / `E` |
| Pause / back | `ESC` |
| Restart | `R` (in a session, host only — restarts for everyone) |
| Music on/off | `M` |
| Debug hitboxes | `U` |
| Flight (cheat) | `F` |

Movement keys are bound to physical positions, so WASD works on any keyboard
layout; menu keys are bound to the letters printed on screen. Pausing offers
**RESUME / RESTART / MAIN MENU** as buttons, in every mode — a run can be left
whenever you like, not only after dying.

## Running it

```bash
git clone https://github.com/AnatomikPerq/ThePit-Ascension.git
```

Open **Godot 4.7** (or a compatible 4.x), import `project.godot`, press `F5`.

That is all you need to play it. If you also want to *work* on it — headless
tests, the linter, sprites round-tripping out of Aseprite — there is one more
command:

```bash
bash tools/setup_claude.sh
```

It is idempotent, it installs only what git cannot carry, and it tells you what
is missing instead of guessing. [godot-pixel-stack-setup.md](godot-pixel-stack-setup.md)
explains the whole toolchain and lists every environment variable that overrides
a path.

### Multiplayer quickstart

One button on the main menu, **MULTIPLAYER**, and everything is behind it: a
list of servers, a box to type an address into, and your own game.

1. The list finds servers three ways — a directory on the internet, a shout on
   your own network, and the ones you have played on before. A coloured badge
   next to a name is a server the developer has checked; hover it to read why.
2. **OPEN MY OWN GAME** is the peer-to-peer half: forward the UDP port, **HOST**,
   everyone else **JOIN**s by address. The host picks **CO-OP** or **RACE** and
   starts; the roster locks at that moment, so there is no join-in-progress.

### Dedicated server quickstart

1. `godot --headless --path . -- --server`, then read the `server.cfg` it wrote.
2. `account register yourname a-good-password` on its console — the first
   account is the owner.
3. Players find it on their own network at once. To be in the list on the
   internet, set `directory/announce` and `directory/url` — see
   [Being found](docs/SERVER.md#being-found).
4. `F8` in the game opens the administration panel for anybody you have given
   `server.panel` to.

### Server list quickstart

The same binary again, third job: the service that lists servers.

1. `godot --headless --path . -- --directory`.
2. `key issue official "My server" "Run by me."` prints two lines to paste into
   a host's `server.cfg`. That, and only that, is what puts a badge on a name.
3. Point players at it by setting the URL in `data/net/directory.tres`.

## How it is put together

```
src/       code by system (audio/, core/, entities/, world/, ui/, net/, fx/, defs/,
           server/ — the dedicated server, directory/ — the server list)
scripts/   entity controllers and the older autoloads
data/      .tres resources — the tuning surface (audio/, animations/, enemies/, fx/, worlds/)
scenes/    .tscn by category (fx/, ui/, ui/server/, server/, entities at the top level)
assets/    sprites/, audio/ (+ CREDITS.md), ui/
tools/     headless probes, one-shot generators, the test harness, setup_claude.sh
docs/      ARCHITECTURE, CONTENT, NETWORKING, SERVER, TESTING
test/      GdUnit4 suites
addons/    AsepriteWizard, gdUnit4, godot_mcp — committed with the project
```

Code defines behaviour; `.tres` files define numbers. If you are tuning
something, you should be in the inspector and not in a script — enemy stats,
world layout, spawn weights, particle shapes and every sound all live in
`data/`. Layout lives in scenes, not in `Label.new()`.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) names the seam for each thing the
project is meant to grow into next.

## Verifying a change

```bash
bash tools/run_tests.sh
```

Everything headless, one command: the GdUnit4 suites, a 73-check smoke test, an
input/state probe driving real key events, the world-generation fingerprint, a
two-instance multiplayer probe over a localhost socket — including a host
restart, a race hit landing across machines, and a bomb the host sets off taking
the same platform out of the client's world — a **three-process server probe**
putting two clients in two different rooms of one real dedicated server, and the
convention gates. See [docs/TESTING.md](docs/TESTING.md).

The run also regenerates the build fingerprint the game and the server compare,
and says loudly when it moved: a commit that changes the simulation is a commit
that obliges you to redeploy the server, and that is not left to memory.

The images in this README are generated by
`tools/build_readme_shots.tscn`: the project's own scenes, its own renderer, a
fixed seed. Re-running it overwrites them.

## Credits

All audio is CC0 (Kenney + OpenGameArt) — full provenance in
[assets/audio/CREDITS.md](assets/audio/CREDITS.md). *Murder Drones* and its
characters belong to GLITCH; this is an unaffiliated, non-commercial fan work.

---

*Originally a Python-to-Godot port; since rebuilt around data-driven resources,
authored scenes and a host-authoritative network model.*

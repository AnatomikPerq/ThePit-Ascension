# The dedicated server

A console program that hosts several rooms of The PIT at once and keeps them
running whether or not the person who started them is playing. It is a build of
**this** repository with its presentation turned off — see [Why it is the game
and not a separate program](#why-it-is-the-game-and-not-a-separate-program).

> **Every time the game changes, the server has to be rebuilt and restarted from
> the same commit.** This is not advice: the two sides compare a fingerprint of
> the build before they will play together, and a stale server refuses every
> client with a sentence saying so. [The rule](#the-rule-the-server-moves-with-the-game).

---

## Running it

From a source checkout:

```bash
godot --headless --path . -- --server
```

From an exported build, the same binary with a flag — or the dedicated-server
export, which needs no flag at all:

```bash
thepit --server
thepit-server
```

Options, and only these — everything else is in `server.cfg`:

| | |
| --- | --- |
| `--server` | be a server rather than the game |
| `--directory` | be the service that LISTS servers, instead — see [The server list](#the-server-list) |
| `--data <dir>` | where accounts, bans, logs and `server.cfg` live |
| `--port <n>` | short for `--set network/port=<n>` |
| `--set <key>=<value>` | override one setting for this run only; repeatable |
| `--help` | the same list |

The same binary is three programs: the game, the dedicated server, and the
directory that lists dedicated servers. They write different files under the same
names, so **give each one its own `--data` directory** — the defaults already do
(`./server-data` and `./directory-data`).

A relative `--data` is resolved against the folder the program lives in, not the
working directory — a server started by a service manager, a shortcut or a
scheduled task gets a working directory nobody chose, and "the data appeared
somewhere else this time" is not a thing to have to debug.

### First run

The first boot writes `server.cfg` with **every** setting and a comment above
each one saying what it does. Read that file; it is the reference, and it is
regenerated on every boot so a setting added by a new build appears in it the
first time you run that build.

Then make yourself an account. Either register from inside the game — the first
account on a fresh server becomes the **owner** (`auth/first_account_is_owner`) —
or do it from the console, which is the one route that never sends anything
across a network:

```
account register yourname a-good-password
```

`op somebody` makes an existing account an admin. `account role <name> <role>` is
the general form; the roles are `player`, `moderator`, `admin`, `owner`.

### Stopping it

`stop` on the console, or `Ctrl+C`. Everyone is told why, every room is closed,
accounts and bans are written, and only then does the process exit.

---

## The console

Type `help`. It lists what you may run, generated from the commands themselves,
so it cannot fall behind them. `help <command>` explains one.

Arguments with spaces go in `"quotes"`. That is the whole syntax — this is not a
shell, and every feature past quoting is a way to be surprised.

The same commands are available from three places, with the same permission check
in front of all three:

- **the console**, on the machine the server runs on;
- **the remote console** over TCP (`rcon/*`), for an operator who is not sitting
  at it;
- **the admin panel inside the game** (`F8`), for whoever holds
  `server.panel` — its buttons build command lines and send them.

There is no second implementation of moderation for any of them to get wrong.

### The commands worth knowing first

| | |
| --- | --- |
| `status` · `players` · `rooms` | what is going on |
| `player <name>` | everything known about one connected player |
| `kick` · `ban` · `unban` · `mute` · `warn` · `move` | moderation |
| `bans` | every ban in force |
| `room open` · `room close` · `room start` · `room restart` · `room set` | rooms |
| `account list` · `account info` · `account register` · `account role` | accounts |
| `op` · `deop` | the short forms of `account role` |
| `get <key>` · `set <key> <value>` · `config [filter]` | settings, live |
| `log [lines] [level]` | the last thing the server said |
| `say <message>` | an announcement to everybody |
| `top` | the best climbs this server has seen |
| `version` | the build, and what a client must match |

---

## Configuration

`server.cfg`, an ordinary INI in the data directory. Change it and restart, or
change it live with `set <key> <value>` — which validates against the setting's
own type and range and writes the file immediately, so a live change survives a
restart. Keys marked `(restart)` are read only at startup; `set` saves them and
says so rather than pretending.

The schema lives in `src/server/server_settings.gd`, one line per setting. That
file is the reason adding a setting is one line and never two: the console, the
generated file, the validation, the permission check and the admin panel's editor
are all derived from it.

Sections: `server` (identity and MOTD) · `network` · `auth` · `rooms` ·
`moderation` · `protection` · `directory` (how this server is found) ·
`performance` · `log` · `rcon` · `status` · `storage`.

Run with `--directory` and the file is a different one: `server` (its own name),
`listing` (everything about the list it serves), `log` and `storage`. Two
programs, two schemas, one file format — a settings file two thirds of which does
nothing is a settings file nobody reads.

A few worth setting deliberately:

- **`auth/mode`** — `open` (anybody, no name check: a LAN party), `guest` (a name
  for the session, owning nothing), `account` (registered name and password).
- **`network/max_peers_per_ip`** — the cheapest defence there is against
  somebody opening a thousand sockets.
- **`rooms/max_rooms`** — see [Capacity](#capacity).
- **`moderation/ban_evasion_by_ip`** — see [what an address ban
  costs](#what-an-address-ban-costs).
- **`protection/movement_guard`** — see [What the movement guard is
  not](#what-the-movement-guard-is-not).
- **`directory/announce`** — off by default; see [Being found](#being-found).

---

## Rooms

A room is a lobby that becomes a run. It has a name, a mode (co-op or race), a
number of seats, optionally a password, and an owner — the account that opened
it. `rooms/who_may_start` and `rooms/who_may_restart` decide whether that is the
owner, anybody in the room, or staff.

A room opened from the console belongs to the server and is **persistent**: it
survives being empty, which is the whole reason to open one before anybody has
arrived. A room opened by a player closes when it empties
(`rooms/empty_close_seconds`).

**There is no join-in-progress for a climber.** Every machine builds its avatars
from the roster before its first frame, so a run that has started can be joined
only to watch. Watching is a first-class thing: spectators fly the pit freely and
change nothing about the run.

### How several rooms share one port

Worth understanding, because it is the load-bearing part of the design and it was
measured before it was relied on.

Each room's world is a node at `/root/World<id>` — on the server and on every
client in that room. Node paths are how Godot's replication layer addresses
everything, so two rooms cannot collide in the path space. The other half is
visibility: every `MultiplayerSynchronizer` in a room is set to
`public_visibility = false` plus an explicit yes per member, **before** the node
enters the tree, so the spawn packet itself is already addressed.

That second half rests on a property the documentation states and does not
demonstrate: that synchronizer visibility gates the `MultiplayerSpawner`'s spawn
packet and not only the sync stream. It was checked with three real processes
over a real socket before any of this was written, and
`tools/run_server_probe.sh` checks it on every test run — two clients in two
rooms, each ending up with exactly one world, its own, and both logs grepped for
the replication errors a stray packet would produce.

The same reasoning is why nothing in the game asks the tree for "the nearest
player" or "the destructibles" any more: every room's pit is built in the *same
coordinate space*, so a tree-wide group answer is a climber in a pit this room
cannot see. `NetSession.avatars_of()` and `NetSession.in_world()` are the scoped
answers.

---

## Accounts and authentication

The password never leaves the player's machine.

1. The server sends the account's salt, its iteration count and a nonce.
2. The client computes `PBKDF2-HMAC-SHA256(password, salt, iterations)` and
   answers with `HMAC(that, nonce)`.
3. The server recomputes the same thing from the verifier it stored.

A captured answer is worthless on the next connection, because the nonce is new.
The stored verifier cannot be used to log in anywhere. The expensive half runs on
the client, which also means the login endpoint cannot be used to burn the
server's CPU.

An unknown account still gets a challenge, built from the server's own secret, so
that "no such name" and "wrong password" are indistinguishable — otherwise the
port answers "who plays here" to anybody who asks.

### The one thing that does cross

**Registering** sends the derived key, because the server needs something to
check against later. On an open network that is sniffable. Three ways to deal
with it, in order of how much they help:

1. `account register` on the console or over rcon — nothing crosses at all.
2. `auth/registration_token` — an invite code, so at least it is not open.
3. `auth/allow_registration = false` and hand out accounts yourself.

It is written here rather than buried because it is the one weak point in the
scheme and an operator should decide about it knowingly.

### Roles and rights

Rights are **named**, not ranked: `player.kick`, `server.settings.write`,
`room.close.any`, and so on — `permissions` lists them all. A role is a bundle of
them. That is what lets somebody be given the ability to kick without also being
given the ability to edit settings:

```
account grant somebody player.kick
account revoke somebody chat.broadcast
```

A revoke beats the role that grants it.

**Nobody may act on somebody at or above their own rank.** Two admins cannot
depose each other and a moderator cannot remove the owner. The console outranks
everyone, because an operator locked out of their own server by somebody they
promoted would have no way back in.

---

## Protection

What is here, honestly labelled.

- **The handshake is Godot's own** (`SceneMultiplayer.auth_callback`), so a peer
  that fails it never becomes a peer: no RPC of theirs reaches any node.
- **`network/relay_between_clients` is off.** A client cannot address a packet to
  another client *through* the server; everything a peer sends is something this
  server received and judged.
- **Object decoding is off, everywhere.** The decoder that honours it
  instantiates classes named in the packet, which on a public socket is remote
  code execution wearing a serialisation format. A convention gate keeps it off.
- **Every client message arrives at one place** (`Hub`), where the sender is
  resolved, rate-limited and checked before anything else sees it.
- **Rate limits** are token buckets, not windows: on messages per peer, on
  connections per address, on login attempts, and on chat.
- **Bans** by account and by address, with expiry, a reason and who issued it.
- **The build fingerprint** refuses a client that is not this build.

### What the movement guard is not

Movement in this game is **client-authoritative and stays that way**: each avatar
is simulated by the machine of the player steering it (see
[NETWORKING.md](NETWORKING.md)). That is what keeps somebody else's lag off your
controls, and making it server-authoritative would change how the game feels for
every honest player in order to inconvenience a cheat.

So `protection/movement_guard` is a **tripwire, not a wall**. It notices an
avatar reporting a position it could not have reached — speed hacks, teleports,
flying outside the shaft — and logs, warns or disconnects. It does not catch
somebody moving legally but inhumanly well, and nothing here pretends it does.

The thresholds are deliberately loose. A false positive costs a real player their
run on a bad connection, which is worse than a cheat getting a few more seconds;
`protection/violations_before_action` exists so one hiccup is never enough.

### What an address ban costs

`moderation/ban_evasion_by_ip` makes a ban also refuse the address the account
last used. It catches the obvious evasion — and it also catches everybody else
behind that address, which for a household, a campus or a phone network is a lot
of people. It is on by default because most servers are small and evasion is the
common case. Turn it off if your players share connections.

### Encryption

There is none. Traffic is plain ENet over UDP, and the handshake is designed
around that: a password never crosses, a proof is bound to a nonce, and the one
exception is registration, above. What an observer on the wire *can* see is who
is playing, what they say in chat, and where their climber is.

For a fan game among people who gave each other an address, that is the right
trade. If it is not yours, put the server behind a VPN.

---

## Remote console

Off by default. It needs a password, and it refuses to listen without one.

```
[rcon]
enabled = true
password = "something long"
```

Line-based text, so `nc host 24566` is a working client:

```
AUTH something long
OK The PIT — up 2h14m · 6 players · 3 rooms (2 running) · 12 accounts · 0 bans
--END ok
players
  somebody             room 2  10.0.0.4
--END ok
```

**It binds to `127.0.0.1` by default and that is not timidity.** One password on
an open TCP port stands between a stranger and `server stop`, `account role
<them> owner`, and every other command there is. Reach it through an SSH tunnel:

```bash
ssh -N -L 24566:127.0.0.1:24566 you@your-server
```

`rcon/bind_address` will happily be changed by an operator who has read that and
decided otherwise.

---

## The status endpoint

Off by default. One line of JSON to anybody who connects, then the socket closes
— for uptime monitoring, or a website that wants to show whether the server is
up. It is read-only, unauthenticated and accepts no input, which is why player
names are off by default (`status/show_player_names`): who is playing right now
is not something an anonymous port should tell.

```bash
nc play.example.com 24567
```

---

## A domain, and getting connected to

One UDP port has to be reachable from outside: `network/port`, 24565 by default.
Nothing else does — rcon should be tunnelled, and the status port is optional.

1. Forward that **UDP** port to the machine. Not TCP; ENet is UDP.
2. Point a DNS `A` record (and `AAAA` if you have IPv6) at the address.
3. Set `server/public_address` to the name. It does not affect what is listened
   on — it is what the logs and the status endpoint report, so that the answer to
   "what do I type" is in the server's own output.
4. Players type the name under **MULTIPLAYER → CONNECT BY ADDRESS**. Hostnames
   are resolved by ENet, so `play.example.com` works as typed. Or they never type
   it at all — see [Being found](#being-found).

`network/upnp` asks a home router to forward the port on startup. It is for a
server behind a home router and useless in a data centre.

### As a service

The server writes to stdout with timestamps and no colour when you ask
(`log/colour = false`), which is what a service manager wants. A `systemd` unit:

```ini
[Service]
ExecStart=/opt/thepit/thepit-server --data /var/lib/thepit
Restart=always
StandardOutput=journal
```

With no terminal there is no typed console — the server says so at boot and
carries on. Use rcon or the in-game panel.

---

## Being found

A player opens **MULTIPLAYER** and sees a list. Three things put a server in it,
and they are independent — a server can use all three, one, or none. A server
nobody can find is still perfectly playable; somebody types its address.

| | how | reaches |
| --- | --- | --- |
| **the directory** | this server POSTs a description to a listing service every minute | anybody, anywhere |
| **the local network** | this server answers a UDP probe the browser broadcasts | the same network only |
| **saved** | the player connected once and the game remembered | that one player |

### Announcing to a directory

Off by default: being listed is a decision, not something that happens to you.

```
set directory/announce true
set directory/url https://list.example.com
announce
```

`announce` sends one immediately instead of waiting out the interval, and
`status` then shows what came back. The settings:

| | |
| --- | --- |
| `directory/announce` | announce at all |
| `directory/url` | the directory's base URL. Empty uses the one the game ships with |
| `directory/interval_seconds` | how often. Also how quickly a crashed server disappears |
| `directory/verify_id` · `directory/verify_key` | a verification key, if you have one |
| `server/public_address` | the address players should use. Empty lets the directory use the one your announce arrived from — right unless you are behind a tunnel, or want a name shown rather than a number |
| `server/description` · `server/tags` · `server/region` | what the row says about you |

An announce carries only what the status endpoint already serves to anybody who
asks, plus the build fingerprint — which is what lets the browser say *that
server is on a different version* instead of letting the player find out by being
refused ten seconds after pressing CONNECT.

If the directory is down, the server backs off exponentially to ten minutes and
says so once rather than every minute. Nothing else about the server is affected.

### The local network

On by default, and worth understanding because it costs nothing: the server binds
one UDP port (`directory/lan_port`, 24568) and answers a probe with one packet.
It never broadcasts on its own. A browser on the same network finds it with no
directory, no account, no port forwarding and nothing typed — which is what makes
a LAN party work on a network with no way out.

Only one process per machine can hold that port. Running two servers on one box,
give the second `directory/lan_port = 24569`; the browser probes 24568–24570.
`directory/lan_beacon = false` turns it off.

A server never sends a badge over this path and the browser would ignore one if
it did. A badge is the directory's word, and on the local network there is no
directory in the path to give it.

---

## The server list

The directory is the **third program in this binary**. It lists dedicated
servers so that a player who has just installed the game has somewhere to go.

```bash
godot --headless --path . -- --directory
thepit --directory
```

It is small and deliberately unimportant: it never sees a player, holds no
account, and no game traffic passes through it. Losing it costs the browser and
nothing else. It is a separate process from any game server for exactly that
reason.

### Putting one on the internet

It speaks plain HTTP and does not do TLS — half a TLS implementation would be
worse than none. Put nginx or Caddy in front:

```nginx
location /v1/ {
    proxy_pass http://127.0.0.1:24570;
    proxy_set_header X-Forwarded-For $remote_addr;
}
```

and then `set listing/bind_address 127.0.0.1` and `set listing/trust_forwarded
true`. **Only turn `trust_forwarded` on when something you control is in front**:
any client can send that header, so trusting it on a directly-exposed port is
trusting a stranger about who they are.

Three endpoints, and they are curl-able on purpose:

```bash
curl https://list.example.com/v1/servers
curl https://list.example.com/v1/servers?verified=1
curl https://list.example.com/v1/health
```

### What it refuses

| | |
| --- | --- |
| `listing/stale_seconds` | a server that has not announced for this long stops being listed |
| `listing/forget_seconds` | and is dropped from the table entirely |
| `listing/announce_per_minute` | announces accepted from one address |
| `listing/max_per_address` | servers one address may list |
| `listing/max_servers` | ceiling; a new one past it is refused rather than evicting somebody who was there first |
| `listing/require_key` | list only verified servers — turns it into a curated list |
| `listing/blocked` | addresses never listed, whatever they claim |

Everything a server claims about itself is clamped rather than believed: a name
too long is shortened, control characters are stripped, tags are cut and
de-duplicated. Exactly one thing cannot be claimed at all — the badge.

### Commands

`help`, `get`, `set`, `config`, `save`, `log`, `stop` behave exactly as they do
on a game server, because they are the same code. On top of those:

| | |
| --- | --- |
| `status` | what is listed, and how busy this has been |
| `servers [filter]` | every server currently listed |
| `forget <address> [port]` | drop one until it announces again |
| `key issue <badge> <label> [note...]` | make a verification key |
| `key list`, `key show <id>` | what has been issued |
| `key secret <id>` | print a secret again, for a host who lost it |
| `key revoke <id> [reason]`, `key delete <id>` | withdraw one |
| `key bind <id> <address>` | tie a key to one address; `-` unties it |
| `block <address>`, `unblock <address>` | never list that address |

---

## Verification: the badge next to a name

A verified server wears a coloured badge in the browser, and hovering it explains
what the badge means. There are three, and they say different things:

| | |
| --- | --- |
| **OFFICIAL** | run by the developer of the game |
| **PARTNER** | somebody else's, that the developer vouches for |
| **VERIFIED** | the person running it has been identified |

**Only the directory can give one.** A server that puts `"badge": "official"` in
its own announce gets exactly nothing for it, and a server answering a probe on
your local network cannot carry one at all. That asymmetry is the whole scheme;
without it the badge would be decoration anybody could paint on.

### Handing one out

On the directory's console:

```
key issue official "The PIT" "The developer runs this one. Downtime is announced on Discord."
```

It prints two lines **once**:

```
  verify_id  = "pitk_3f9a2b7c1d0e"
  verify_key = "…64 hex characters…"
```

Send them to the host. They go in their `server.cfg` under `[directory]`, with
`announce = true`, and the badge appears on their next announce. Nothing else has
to happen on either side. `key secret <id>` prints them again for somebody who
lost them; it is a command of its own rather than part of `key list` so that it
is written into the audit log when it is used.

### How the secret is used, and why it never travels

The server signs its announce with the secret and sends the **signature**. The
directory recomputes the same signature from what arrived and compares. Two
things follow, and both are the point:

- the key cannot be lifted out of a captured announce, because it is not in one;
- the signature covers the **name, address and port** as well as the key, so a
  captured announce cannot be replayed to put somebody else's badge on a
  different machine. Changing any of them invalidates it.

A timestamp and a nonce close the last window: an announce more than five minutes
old is refused, and so is one whose nonce has already been seen inside that
window — which is what stops a *correct* announce being replayed by whoever was
listening.

### Binding, and what a leaked key costs

The secret is the authority, so whoever holds it can badge whatever they like —
which matters when a host hands their server on, or leaves the key in a pasted
config. `listing/bind_keys_on_first_use` is **on by default**: the first
successful announce ties the key to the address it came from, and every later one
has to match. The directory logs it, and a host who genuinely moved is told
exactly why the badge stopped — their server hears the refusal in the answer.
Undo it with `key bind <id> -`.

`key revoke` withdraws a badge immediately, from servers already listed as well
as from future announces — it does not wait for a server to announce again, which
it might never do, having got what it wanted.

**A failed claim never costs a server its listing.** It loses the badge and stays
in the browser: the key is the operator's problem, and the players on that server
did nothing.

---

## Capacity

Every running room is a **full pit being simulated at 120 Hz**, because physics
is fixed at 120 Hz and the pit's determinism depends on it. That rate is not
tunable and `performance/max_fps` does not change it; it changes only how often
the server's frame loop runs.

So capacity is about *rooms*, not players. An empty room is not stepped at all
(`performance/hibernate_empty_rooms`). `performance/frame_warn_ms` logs when a
frame spends more than its budget in the tree — that is the first sign a box is
carrying more than it can, and it measures work rather than the frame interval,
so an idle server never reports itself overloaded.

Start at `rooms/max_rooms = 8`, watch the log, and adjust.

---

## The data directory

| | |
| --- | --- |
| `server.cfg` | every setting, with its description as a comment |
| `accounts.json` | accounts; written atomically, with numbered backups |
| `bans.json` | bans in force |
| `server.secret` | per-install random bytes. **Back it up with the accounts** |
| `logs/server.log` | rotating, `log/max_files` kept |

The directory keeps its own, in its own directory:

| | |
| --- | --- |
| `server.cfg` | its settings — the `listing/*` section, not the game server's |
| `servers.json` | the servers it is listing, so a restart does not empty the browser |
| `keys.json` | **every verification key ever issued, secrets included.** Back this one up and keep it off shared machines: losing it means reissuing every key |
| `logs/server.log` | the same rotating log |

Every one of those JSON files is written to a temporary file first, the old one
is copied to a `.bak`, and only then is the temporary moved into place — a server
killed mid-write leaves a truncated JSON otherwise, and a truncated JSON is every
account on the server. A file that will not parse is reported and **left alone**
rather than replaced: it is the only copy of whatever was in it, and the newest
`.bak` next to it is usually the one you want.

---

## The rule: the server moves with the game

**A server left running across a game update is the failure this whole section
exists to prevent.** The symptom without a check is not an error message: the
client rebuilds a *different* pit from the same seed and falls through geometry
its server does not have.

So two numbers travel in the first packet either side sends:

- **`NetProtocol.VERSION`** — the shape of the conversation. Hand-maintained,
  because it describes code. Bump it when a message gains, loses or repurposes a
  field, when an `@rpc` signature changes, or when authority moves.
- **the content fingerprint** — generated. Every file the simulation is a
  function of goes into it: the entity and world code, every scene the server
  instantiates, `src/net`, and the tuning resources those read.

A mismatch is refused with a sentence naming which side is stale.

Cosmetics are deliberately **out** of the fingerprint — `scenes/ui`, `scenes/fx`,
`src/ui`, `data/fx`, the sprites and the sound bank — so a new particle preset
does not oblige every player to update. `src/server` is out for the same reason
from the other side: a client never runs a line of it.

### What this means in practice

`tools/run_tests.sh` regenerates the fingerprint on every run and prints a loud
notice when it moved:

```
  *** THE GAME CHANGED. THE DEDICATED SERVER MUST BE REBUILT AND RESTARTED
  *** FROM THIS COMMIT, OR IT WILL REFUSE EVERY CLIENT BUILT FROM IT.
```

When you see it: commit the regenerated `data/net/protocol_stamp.tres` with the
change, then rebuild and restart every server. `version` on the console prints
what a server is running; the two hashes appear in the refusal message, so
diagnosing it takes one look.

### And when you add something to the game

Adding content or a mechanic means adding it to the server too, because the
server *runs* the simulation. The checklist is in
[CLAUDE.md](../CLAUDE.md#8-the-server-moves-with-the-game) — it is short, and it
is there rather than here because it belongs with the rules that get changes
reverted.

---

## Why it is the game and not a separate program

The most important decision in the design, and the reason everything else was
possible.

The pit is a pure function of a seed. Enemies are simulated by the authority and
mirrored. A blast decides once what it broke and names the pieces. Every one of
those is an agreement between two builds of the same code. A server written
separately — in another language, against a copy of the rules — would have to
reimplement the simulation and would diverge from it on the first patch, and the
divergence would show up as players falling through platforms rather than as a
compile error.

So the server *is* the game, with one thing turned off: presentation. No camera,
no HUD, no particles, no audio, no ledger registered with `Game`. Underneath,
`World` builds the same pit from the same generator and steps the same entities.

The cost is that the server carries the whole game's code and its assets. The
benefit is that it cannot be wrong about the game.

---

## Verifying

```bash
bash tools/run_server_probe.sh       # part of tools/run_tests.sh
bash tools/run_directory_probe.sh    # likewise
```

Three processes on one real socket: a dedicated server and two clients that end
up in **different** rooms. It asserts registering and the first account becoming
the owner; two rooms running at once, each client holding exactly one world, its
own, named after its own room, carrying only its own avatar; two different pits;
enemies mirrored into each room separately; chat addressed to a room and not
overheard from the next; the admin path (the owner reads the player list and the
whole settings schema over the game socket) and the refusals (an ordinary player
denied `stop` and `kick`); and, in both client logs, none of the replication
errors a packet arriving for the wrong room would produce.

`run_directory_probe.sh` starts three more: a directory, a dedicated server
announcing to it with a key issued on the directory's own console, and a real
client's browser. It asserts the whole chain — the badge appearing in the browser
having been decided by the directory, the same server also found by shouting on
the local network, and every answer about it merging into one row rather than one
row per address the machine can be reached at.

The unit suites cover what the probes exercise but cannot enumerate:
`test/server_security_test.gd` (password hashing against a published vector,
permissions, bans, rate limits), `test/server_config_test.gd` (the settings and
command registries), `test/server_rooms_test.gd` (rooms and room addressing),
`test/server_storage_test.gd` (the atomic write, the backups, and a file that
will not parse), `test/directory_test.gd` (every way a verification claim fails,
and the fact that failing one loses the badge and not the listing) and
`test/protocol_test.gd` (the fingerprint and the refusal messages).

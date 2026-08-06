# Running the server

Start here: **[../docs/SERVER.md](../docs/SERVER.md)** — installing it, the
console, every setting, accounts and roles, moderation, a domain, rcon, capacity,
and what the protection covers.

This folder holds only the launchers and the service units to copy.

| | |
| --- | --- |
| `run-server.sh` | from a source checkout, on anything with bash |
| `run-server.bat` | from a source checkout, on Windows — **use the console build of Godot** |
| `run-directory.sh` | the service that LISTS servers — a different program, same binary |
| `thepit.service` | a systemd unit for the server |
| `thepit-directory.service` | and one for the directory |

A built server needs none of them: `thepit-server` runs directly, and any build
of the game becomes one with `--server` or `--directory`.

The two programs write different files under the same names. **Give each its own
data directory** — the defaults already differ (`./server-data` and
`./directory-data`), and `--data` moves either.

## The one rule

**Rebuild and restart the server whenever the game changes.** The two sides
compare a fingerprint of the build before they will play together, so a stale
server refuses every client rather than desyncing them — but it does refuse them,
and the fix is always the same: build the server from the same commit as the
game. `bash tools/run_tests.sh` prints a loud notice on any commit that moves the
fingerprint.

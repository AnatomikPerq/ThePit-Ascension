#!/usr/bin/env bash
# Three processes, one real socket: a dedicated server and two clients that end
# up in DIFFERENT rooms on it.
#
#   bash tools/run_server_probe.sh [godot_binary]
#
# This is the only harness that can check the thing the whole single-socket room
# design rests on — that room 3's packets never reach room 1 — because one
# process always agrees with itself. It asserts, over a real handshake with real
# accounts:
#
#   * registering, and the first account becoming the owner
#   * two rooms running at once, each client holding exactly ONE world, its own,
#     named after its own room, carrying only its own avatar
#   * two different pits: the geometry fingerprints must NOT match
#   * enemies the server spawned mirrored into each room separately
#   * chat addressed to a room and not overheard from the next one
#   * the admin path: the owner reads the player list and the whole settings
#     schema over the game socket; an ordinary player is refused `stop` and `kick`
#   * that a CLIENT'S ATTACK REACHES THE SERVER. Kills are resolved only where
#     the sim authority lives, so a hitbox the server never receives never kills
#     anything — and for a while none of them did. The check asserts the enemy
#     died `by_strike`, from a standoff, because walking onto an enemy kills it
#     by stomp and the first version of this measured that instead.
#   * and, in both client logs, none of the replication errors that a packet
#     arriving for the wrong room would produce
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${1:-${GODOT:-godot}}"
PORT=25901
DATA=".probe-server-data"
SRV_LOG=$(mktemp); A_LOG=$(mktemp); B_LOG=$(mktemp)
trap 'rm -f "$SRV_LOG" "$A_LOG" "$B_LOG"; rm -rf "$DATA"' EXIT

# A fresh account store every run: the probe registers `alpha` first on purpose,
# and a leftover accounts.json would make it the second.
rm -rf "$DATA"

DEADLINE=180

timeout "$DEADLINE" "$GODOT" --headless --path . -- --server \
  --set "storage/dir=./$DATA" --set "network/port=$PORT" \
  --set auth/mode=account --set log/colour=false --set log/level=debug \
  --set rooms/empty_close_seconds=0 --set performance/status_interval_seconds=0 \
  </dev/null >"$SRV_LOG" 2>&1 &
SERVER_PID=$!
sleep 3

timeout "$DEADLINE" "$GODOT" --headless --path . tools/server_probe.tscn -- alpha "$PORT" \
  >"$A_LOG" 2>&1 &
A_PID=$!
timeout "$DEADLINE" "$GODOT" --headless --path . tools/server_probe.tscn -- beta "$PORT" \
  >"$B_LOG" 2>&1 &
B_PID=$!

wait "$A_PID"; A_RC=$?
wait "$B_PID"; B_RC=$?
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null

grep '^PROBE' "$A_LOG" | sed 's/^/  alpha  /'
grep '^PROBE' "$B_LOG" | sed 's/^/  beta   /'

fail=0
if [ "$A_RC" -ne 0 ]; then echo "FAIL: alpha exited $A_RC"; fail=1; fi
if [ "$B_RC" -ne 0 ]; then echo "FAIL: beta exited $B_RC"; fail=1; fi
if [ "$A_RC" = 124 ] || [ "$B_RC" = 124 ]; then
  echo "       (124 = killed after ${DEADLINE}s; a probe never reached _finish)"
fi

# Two rooms, two seeds, two pits. Identical geometry would mean one client had
# built the other room's world.
A_HASH=$(grep '^PROBE world_hash' "$A_LOG" | awk '{print $3}')
B_HASH=$(grep '^PROBE world_hash' "$B_LOG" | awk '{print $3}')
if [ -z "$A_HASH" ] || [ -z "$B_HASH" ]; then
  echo "FAIL: a client never built a world"; fail=1
elif [ "$A_HASH" = "$B_HASH" ]; then
  echo "FAIL: both rooms built the SAME pit ($A_HASH) — the seeds did not differ"
  fail=1
fi

# The signature of a packet delivered to a client that has no such node: the
# replication layer cannot find the spawner, or the path, and says so. If room
# scoping ever regresses, this is what it looks like.
for log in "$A_LOG" "$B_LOG"; do
  leak=$(grep -E "on_spawn_receive|Node not found|not found in cache" "$log" || true)
  if [ -n "$leak" ]; then
    echo "FAIL: a packet from another room reached a client:"
    echo "$leak" | head -5
    fail=1
  fi
done

if grep -q 'PROBE FAIL' "$A_LOG" "$B_LOG"; then fail=1; fi

if [ "$fail" -ne 0 ]; then
  echo "--- server log ---"; tail -40 "$SRV_LOG"
  echo "--- alpha log ---";  tail -25 "$A_LOG"
  echo "--- beta log ---";   tail -25 "$B_LOG"
  exit 1
fi
echo "server probe ok: two accounts, two rooms, two pits, no cross-room packets, a client's strike killing on the server, admin path, refusals"

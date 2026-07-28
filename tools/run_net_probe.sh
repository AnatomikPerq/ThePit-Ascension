#!/usr/bin/env bash
# Two-instance multiplayer probe over a real ENet socket on localhost.
#
#   bash tools/run_net_probe.sh [godot_binary]
#
# Starts a headless host and a headless client, waits for both, then verifies
# that the two machines agree on what matters: same world geometry from the
# shared seed, both avatars with the right authorities, enemies mirrored to
# the client, and a host-credited kill visible in the client's run mirror.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${1:-${GODOT:-godot}}"
PORT=25765
HOST_LOG=$(mktemp)
CLIENT_LOG=$(mktemp)
trap 'rm -f "$HOST_LOG" "$CLIENT_LOG"' EXIT

"$GODOT" --headless --path . tools/net_probe.tscn -- host "$PORT" >"$HOST_LOG" 2>&1 &
HOST_PID=$!
# Give the host a moment to open the port before the client dials it.
sleep 2
"$GODOT" --headless --path . tools/net_probe.tscn -- client "$PORT" >"$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

wait "$CLIENT_PID"; CLIENT_RC=$?
wait "$HOST_PID"; HOST_RC=$?

grep '^PROBE' "$HOST_LOG" | sed 's/^/  host   /'
grep '^PROBE' "$CLIENT_LOG" | sed 's/^/  client /'

fail=0
if [ "$HOST_RC" -ne 0 ]; then echo "FAIL: host probe exited $HOST_RC"; fail=1; fi
if [ "$CLIENT_RC" -ne 0 ]; then echo "FAIL: client probe exited $CLIENT_RC"; fail=1; fi

HOST_HASH=$(grep '^PROBE world_hash' "$HOST_LOG" | awk '{print $3}')
CLIENT_HASH=$(grep '^PROBE world_hash' "$CLIENT_LOG" | awk '{print $3}')
if [ -z "$HOST_HASH" ] || [ "$HOST_HASH" != "$CLIENT_HASH" ]; then
  echo "FAIL: world hashes differ (host=$HOST_HASH client=$CLIENT_HASH)"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "--- host log ---"; tail -30 "$HOST_LOG"
  echo "--- client log ---"; tail -30 "$CLIENT_LOG"
  exit 1
fi
echo "net probe ok: same world, both avatars, mirrored enemies, replicated score"

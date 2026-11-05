#!/usr/bin/env bash
# Three processes, one real socket: a dedicated server and two clients in the
# SAME room on it.
#
#   bash tools/run_roommate_probe.sh [godot_binary]
#
# The server probe deliberately puts its clients in different rooms, so it
# cannot see whether two players in one room see EACH OTHER — and for a while
# they did not: clients on a dedicated server have no connection to one another
# and the server does not relay between them, so each saw the other frozen on
# the spawn pad. Each side here walks and swings, and must see the other do it.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${1:-${GODOT:-godot}}"
PORT=25911
DATA=".probe-roommate-data"
SRV_LOG=$(mktemp); A_LOG=$(mktemp); B_LOG=$(mktemp)
trap 'rm -f "$SRV_LOG" "$A_LOG" "$B_LOG"; rm -rf "$DATA"' EXIT
rm -rf "$DATA"

DEADLINE=120

timeout "$DEADLINE" "$GODOT" --headless --path . -- --server \
  --set "storage/dir=./$DATA" --set "network/port=$PORT" \
  --set auth/mode=account --set log/colour=false \
  --set directory/lan_beacon=false --set performance/status_interval_seconds=0 \
  </dev/null >"$SRV_LOG" 2>&1 &
SERVER_PID=$!
sleep 3

timeout "$DEADLINE" "$GODOT" --headless --path . tools/roommate_probe.tscn -- host "$PORT" \
  >"$A_LOG" 2>&1 &
A_PID=$!
timeout "$DEADLINE" "$GODOT" --headless --path . tools/roommate_probe.tscn -- mate "$PORT" \
  >"$B_LOG" 2>&1 &
B_PID=$!

wait "$A_PID"; A_RC=$?
wait "$B_PID"; B_RC=$?
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null

grep '^PROBE' "$A_LOG" | sed 's/^/  host  /'
grep '^PROBE' "$B_LOG" | sed 's/^/  mate  /'

fail=0
if [ "$A_RC" -ne 0 ]; then echo "FAIL: host exited $A_RC"; fail=1; fi
if [ "$B_RC" -ne 0 ]; then echo "FAIL: mate exited $B_RC"; fail=1; fi
if [ "$A_RC" = 124 ] || [ "$B_RC" = 124 ]; then
  echo "       (124 = killed after ${DEADLINE}s; a probe never reached _finish)"
fi
if grep -q "SCRIPT ERROR" "$A_LOG" "$B_LOG" "$SRV_LOG"; then
  echo "FAIL: script errors:"; grep -h -A2 "SCRIPT ERROR" "$A_LOG" "$B_LOG" "$SRV_LOG" | head -20
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "roommate probe ok: two clients in one room see each other move and swing"
else
  echo "--- server log (tail) ---"; tail -20 "$SRV_LOG"
fi
exit "$fail"

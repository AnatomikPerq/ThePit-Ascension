#!/usr/bin/env bash
# Three processes, two protocols: the directory, a dedicated server announcing
# itself to it with a verification key, and a real client's browser reading the
# result.
#
#   bash tools/run_directory_probe.sh [godot_binary]
#
# It is the only harness that can check the badge at all, because a badge is one
# program's decision about another program's claim — a single process would be
# agreeing with itself. It asserts, over real HTTP and a real UDP broadcast:
#
#   * a key issued on the directory console, pasted into a server's settings,
#     and the badge appearing in the browser as a result
#   * the same server found a second way, by shouting on the local network with
#     the directory taken out of the path
#   * the two answers merging into ONE row
#   * and the badge surviving that merge, having come from the directory
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${1:-${GODOT:-godot}}"
DIR_PORT=25921
SRV_PORT=25920
DIR_DATA=".probe-directory-data"
SRV_DATA=".probe-directory-server-data"
DIR_LOG=$(mktemp); SRV_LOG=$(mktemp); CLIENT_LOG=$(mktemp); KEY_LOG=$(mktemp)
trap 'rm -f "$DIR_LOG" "$SRV_LOG" "$CLIENT_LOG" "$KEY_LOG"; rm -rf "$DIR_DATA" "$SRV_DATA"' EXIT

# Fresh every run. A leftover keys.json would mean the key issued below is the
# second one, and a leftover servers.json would list a server that is not up.
rm -rf "$DIR_DATA" "$SRV_DATA"

DEADLINE=120

# ── 1. Issue a key, exactly as the developer would ──────────────────────────
# A short-lived directory run, driven from stdin. The secret is printed once and
# only once, which is the point of `key issue`; here that once is captured.
printf 'key issue official "The PIT" "Run by the developer."\nstop issued\n' \
  | timeout "$DEADLINE" "$GODOT" --headless --path . -- --directory \
    --set "storage/dir=./$DIR_DATA" --set "listing/port=$DIR_PORT" \
    --set log/colour=false >"$KEY_LOG" 2>&1

KEY_ID=$(grep -o 'verify_id = "[^"]*"' "$KEY_LOG" | head -1 | cut -d'"' -f2)
KEY_SECRET=$(grep -o 'verify_key = "[^"]*"' "$KEY_LOG" | head -1 | cut -d'"' -f2)
if [ -z "$KEY_ID" ] || [ -z "$KEY_SECRET" ]; then
  echo "FAIL: 'key issue' printed no key"
  tail -30 "$KEY_LOG"
  exit 1
fi

# ── 2. The directory, for real ──────────────────────────────────────────────
timeout "$DEADLINE" "$GODOT" --headless --path . -- --directory \
  --set "storage/dir=./$DIR_DATA" --set "listing/port=$DIR_PORT" \
  --set log/colour=false --set log/level=debug \
  </dev/null >"$DIR_LOG" 2>&1 &
DIR_PID=$!
sleep 3

# ── 3. A dedicated server that announces to it ──────────────────────────────
# The LAN beacon is left on its default port on purpose: the client probes the
# default and a few above it, and moving both would leave that path untested.
timeout "$DEADLINE" "$GODOT" --headless --path . -- --server \
  --set "storage/dir=./$SRV_DATA" --set "network/port=$SRV_PORT" \
  --set directory/announce=true --set "directory/url=http://127.0.0.1:$DIR_PORT" \
  --set "directory/verify_id=$KEY_ID" --set "directory/verify_key=$KEY_SECRET" \
  --set directory/interval_seconds=15 \
  --set "server/name=The PIT Probe" --set "server/public_address=127.0.0.1" \
  --set "server/tags=coop,probe" --set "server/region=Probe" \
  --set log/colour=false --set log/level=debug \
  --set rooms/empty_close_seconds=0 --set performance/status_interval_seconds=0 \
  </dev/null >"$SRV_LOG" 2>&1 &
SRV_PID=$!
sleep 4

# ── 4. A real browser ───────────────────────────────────────────────────────
timeout "$DEADLINE" "$GODOT" --headless --path . tools/directory_probe.tscn -- \
  --directory-url "http://127.0.0.1:$DIR_PORT" --server-port "$SRV_PORT" \
  >"$CLIENT_LOG" 2>&1
CLIENT_RC=$?

kill "$SRV_PID" "$DIR_PID" 2>/dev/null
wait "$SRV_PID" 2>/dev/null
wait "$DIR_PID" 2>/dev/null

grep '^PROBE' "$CLIENT_LOG" | sed 's/^/  /'

fail=0
if [ "$CLIENT_RC" -ne 0 ]; then
  echo "FAIL: the browser probe exited $CLIENT_RC"
  fail=1
fi
if [ "$CLIENT_RC" = 124 ]; then
  echo "       (124 = killed after ${DEADLINE}s; the probe never reached _finish)"
fi

# The directory must have SAID it accepted a verified announce. A browser that
# showed a badge without this line would mean the badge came from somewhere else.
if ! grep -q 'OFFICIAL' "$DIR_LOG"; then
  echo "FAIL: the directory never logged an announce carrying the badge"
  fail=1
fi
# And the server must have been told it was listed, rather than assuming so.
if ! grep -q 'listed as' "$SRV_LOG"; then
  echo "FAIL: the server was never told it had been listed"
  fail=1
fi
# Binding on first use is on by default: the key must now be tied to what it
# announced, so that the same secret cannot badge another machine.
if ! grep -q 'is now bound to' "$DIR_LOG"; then
  echo "FAIL: the key was not bound to the address it was first used from"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "--- directory log ---"; tail -30 "$DIR_LOG"
  echo "--- server log ---";    tail -30 "$SRV_LOG"
  echo "--- client log ---";    tail -30 "$CLIENT_LOG"
  exit 1
fi
echo "directory probe ok: key issued, announce signed and verified, badge in the browser, same server found on the local network, one row"

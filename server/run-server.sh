#!/usr/bin/env bash
# Start the dedicated server from a source checkout.
#
#   bash server/run-server.sh [--set key=value ...]
#
# For a built server, run the binary itself: `thepit-server` needs no flag, and
# any build of the game takes `--server`. Everything else is server.cfg, which
# is written into the data directory on the first run with a comment above every
# setting explaining it. See docs/SERVER.md.
set -uo pipefail
cd "$(dirname "$0")/.."
source tools/lib/find_godot.sh
if ! GODOT="$(find_godot)"; then
  printf 'No Godot binary found. Set GODOT, or run: bash tools/setup_claude.sh
' >&2
  exit 1
fi

# `exec`, so that a service manager's stop signal reaches Godot rather than this
# wrapper — the server shuts down cleanly on it, telling everyone why first.
exec "$GODOT" --headless --path . -- --server "$@"

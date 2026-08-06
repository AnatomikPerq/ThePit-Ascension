#!/usr/bin/env bash
# Start the SERVER DIRECTORY from a source checkout — the service that lists
# dedicated servers so they appear in the browser inside the game.
#
#   bash server/run-directory.sh [--set key=value ...]
#
# It is not a game server and hosts nothing: no player ever connects to it, and
# losing it costs the browser and nothing else. It writes its own files, so give
# it its own data directory — the default already differs (./directory-data).
# See docs/SERVER.md, "The server list".
set -uo pipefail
cd "$(dirname "$0")/.."
source tools/lib/find_godot.sh
if ! GODOT="$(find_godot)"; then
  printf 'No Godot binary found. Set GODOT, or run: bash tools/setup_claude.sh\n' >&2
  exit 1
fi

# `exec`, so that a service manager's stop signal reaches Godot rather than this
# wrapper — the directory writes its tables and its keys out before exiting.
exec "$GODOT" --headless --path . -- --directory "$@"

#!/usr/bin/env bash
# Full verification pass. Every step is headless except the sprite gallery,
# which needs a real renderer to produce an image.
#
#   bash tools/run_tests.sh
#
# GODOT can be pinned; otherwise tools/lib/find_godot.sh discovers one, and
# prefers the standalone console build over the Steam exe for the reason
# spelled out in that file.
set -uo pipefail

cd "$(dirname "$0")/.."
source tools/lib/find_godot.sh
if ! GODOT="$(find_godot)"; then
  printf 'No Godot binary found. Set GODOT, or run: bash tools/setup_claude.sh\n' >&2
  exit 1
fi
printf 'godot: %s\n' "$GODOT"

# A clone with no .godot/ has no global script class cache, so every `class_name`
# type fails to resolve and the suites below drown in parse errors — or hang.
# Game mode cannot build that cache; say so instead of running for ten minutes.
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  printf 'No .godot/global_script_class_cache.cfg — the project has never been imported.\n' >&2
  printf 'Run: bash tools/setup_claude.sh\n' >&2
  exit 1
fi
fail=0

step() { printf '\n=== %s ===\n' "$1"; }

step "GdUnit4 suite"
# --ignoreHeadlessMode: GdUnit refuses headless by default because its own
# scene-runner input simulation does not work there. None of our suites use it.
"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode --add res://test --continue 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E "PASSED|FAILED|Overall Summary" || true
"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode --add res://test >/dev/null 2>&1 || fail=1

step "smoke test"
"$GODOT" --headless --path . -s tools/smoke_test.gd 2>&1 | grep -E "PASSED|FAILED" || fail=1

step "state probe (pause, input reachability, restart)"
"$GODOT" --headless --path . tools/state_probe.tscn 2>&1 | grep -E "PASSED|FAILED" || fail=1

step "world fingerprint"
"$GODOT" --headless --path . tools/world_fingerprint.tscn 2>&1 | grep -E "seed|WARNING" || fail=1

step "net probe (host + client over a localhost socket)"
bash tools/run_net_probe.sh "$GODOT" | tail -1 || fail=1

step "conventions"
bash tools/check_conventions.sh || fail=1

if [ "$fail" -ne 0 ]; then
  printf '\nVERIFICATION FAILED\n'; exit 1
fi
printf '\nall green\n'

#!/usr/bin/env bash
# Full verification pass. Every step is headless except the sprite gallery,
# which needs a real renderer to produce an image.
#
#   bash tools/run_tests.sh
#
# GODOT can be overridden; it defaults to the Steam install.
set -uo pipefail

GODOT="${GODOT:-C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
cd "$(dirname "$0")/.."
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

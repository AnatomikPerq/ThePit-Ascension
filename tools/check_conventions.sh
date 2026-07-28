#!/usr/bin/env bash
# Grep gates for the rules in CLAUDE.md. A rule with no gate is a comment.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

gate() { # description, pattern, paths...
  local desc="$1"; local pattern="$2"; shift 2
  local hits
  hits=$(grep -rn --include='*.gd' -E "$pattern" "$@" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    printf 'FAIL: %s\n%s\n\n' "$desc" "$hits"
    fail=1
  else
    printf 'ok: %s\n' "$desc"
  fi
}

gate "Engine.time_scale is never written (the kill hitstop was removed)" \
  'Engine\.time_scale *=' src scripts tools

gate "no texture is drawn at runtime" \
  'Image\.create|set_pixel' src scripts

gate "no audio is synthesised at runtime" \
  'AudioStreamWAV' src scripts

gate "no script is loaded and attached at runtime" \
  'set_script\(' src scripts

gate "no raw collision bitmask literals (layers are named in project.godot)" \
  '^[^#]*collision_(layer|mask) *= *[0-9]' src scripts

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "conventions ok"

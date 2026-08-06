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

# Not a style preference. A .tscn string spans real file lines, so a CRLF file
# puts a \r INSIDE every multi-line label — and Godot breaks on \r as well as on
# \n, which double-spaces the text with no error anywhere. It cost an afternoon
# once. .gitattributes already says eol=lf; this is the working tree saying it.
CR=$(printf '\r')
crlf=$(grep -rlU "$CR" --include='*.gd' --include='*.tscn' --include='*.tres' \
  --include='*.sh' --include='*.md' src scripts scenes data test tools docs 2>/dev/null || true)
if [ -n "$crlf" ]; then
  printf 'FAIL: CRLF line endings (a \\r inside a .tscn string double-spaces the label)\n%s\n\n' "$crlf"
  fail=1
else
  printf 'ok: %s\n' "line endings are LF"
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "conventions ok"

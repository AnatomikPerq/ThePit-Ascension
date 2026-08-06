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

gate "no object decoding over the wire (it instantiates classes named in the packet)" \
  '^[^#]*(var_to_bytes_with_objects|bytes_to_var_with_objects|allow_object_decoding *= *true)' \
  src scripts tools

# `Net` describes THIS MACHINE's connection, and a machine is in at most one
# room. A dedicated server is in none and hosts several, so a server that read
# the autoload's session fields would be describing whichever room wrote last.
# Every one of these has a per-room answer: the room's own NetSession.
gate "the server never reads the local machine's session (it has no room)" \
  '^[^#]*Net\.(session_peers|session_characters|is_versus|mode)\b' \
  src/server src/directory

# A badge is the DIRECTORY's decision about a server's claim. The moment
# anything else writes one — an announce believed as it arrives, a LAN answer
# taken at face value — the whole scheme becomes decoration that any server can
# put on itself. The places allowed to are DirectoryStore._stamp_badge, which
# reads it off a key this directory issued; DirectoryEntry and ServerFinder,
# which copy one out of a listing they have already established came from a
# directory; and VerifyKey itself, which IS the thing that confers one.
badge_writers=$(grep -rn --include='*.gd' -E '^[^#]*\.badge *=' src scripts \
  | grep -v 'src/directory/directory_store.gd' \
  | grep -v 'src/directory/directory_entry.gd' \
  | grep -v 'src/directory/server_finder.gd' \
  | grep -v 'src/directory/verify_key.gd' || true)
if [ -n "$badge_writers" ]; then
  printf 'FAIL: %s\n%s\n\n' "a verification badge is only ever set from a key the directory issued" "$badge_writers"
  fail=1
else
  printf 'ok: %s\n' "a verification badge is only ever set from a key the directory issued"
fi

# `.rpc()` reaches every peer the socket knows about. On a player's machine that
# is the room; on a dedicated server it is three other rooms as well, on a node
# path they do not have. Gameplay addresses its messages: session.broadcast().
gate "gameplay broadcasts are addressed to a room, not to the whole socket" \
  '^[^#]*[a-z_]\.rpc\(' src/core src/entities src/world scripts

# Everything the server says has to reach stdout, the log file and the ring
# buffer the admin panel reads. A bare print() reaches only the first.
bare_print=$(grep -rn --include='*.gd' -E '^[^#]*\bprint(err|_rich)?\(' src/server src/directory \
  | grep -v 'src/server/server_log.gd' | grep -v 'src/server/server_boot.gd' || true)
if [ -n "$bare_print" ]; then
  printf 'FAIL: %s\n%s\n\n' "server output goes through the logger, not print()" "$bare_print"
  fail=1
else
  printf 'ok: %s\n' "server output goes through the logger, not print()"
fi

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

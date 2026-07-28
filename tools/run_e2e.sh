#!/usr/bin/env bash
# Runs the PlayGodot end-to-end suite under WSL.
#
#   bash tools/run_e2e.sh
#
# Why this is separate from tools/run_tests.sh:
#
#   PlayGodot drives the game through automation commands that are compiled into
#   the engine, not shipped as an addon, so it needs the Randroids-Dojo
#   automation fork. That fork publishes Linux and macOS binaries only — there
#   is no Windows build — and it is based on Godot 4.6 while this project
#   targets 4.7. So these tests run in WSL, against that older engine.
#
#   Consequences, stated plainly: a failure here can be a 4.6/4.7 difference
#   rather than a real bug, and this suite is therefore ADVISORY. The gate is
#   tools/run_tests.sh, which runs on the same Godot 4.7 that builds the game.
#
#   The project is copied into WSL rather than opened from /mnt/c, because a 4.6
#   editor writing its import cache into the working tree could downgrade it.
set -uo pipefail

DISTRO="${WSL_DISTRO:-Ubuntu-24.04}"
cd "$(dirname "$0")/.." || exit 1
PROJECT_WIN="$(pwd -W 2>/dev/null || pwd)"

# Everything below runs inside WSL.
wsl.exe -d "$DISTRO" -- bash <<'INNER'
set -uo pipefail
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.local/bin:$DOTNET_ROOT:$PATH"

GODOT="$HOME/godot-automation/godot.linuxbsd.editor.x86_64.mono"
VENV="$HOME/pgvenv"
DEST="$HOME/thepit_e2e"

for required in "$GODOT" "$VENV/bin/python"; do
  if [ ! -e "$required" ]; then
    echo "missing: $required"
    echo "run tools/setup_e2e.sh first"
    exit 1
  fi
done

# Sync the working tree, excluding build caches and the .NET-less report dirs.
SRC="$(cat "$HOME/.thepit_e2e_src" 2>/dev/null)"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "source path not recorded; run tools/setup_e2e.sh first"
  exit 1
fi
rm -rf "$DEST"
mkdir -p "$DEST"
tar -C "$SRC" --exclude=.godot --exclude=reports --exclude=.git -cf - . | tar -C "$DEST" -xf -

export E2E_PROJECT="$DEST"
export GODOT_PATH="$GODOT"

echo "--- warming the import cache (4.6 reads a 4.7 project) ---"
timeout 420 "$GODOT" --headless --path "$DEST" --import >/dev/null 2>&1

echo "--- pytest ---"
cd "$DEST" && "$VENV/bin/python" -m pytest tests_e2e -v --tb=short 2>&1 | tail -40
INNER

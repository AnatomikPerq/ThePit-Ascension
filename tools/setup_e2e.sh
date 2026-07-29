#!/usr/bin/env bash
# One-time setup for the PlayGodot end-to-end suite. Idempotent.
#
#   bash tools/setup_e2e.sh
#
# Installs, all inside WSL and all without root:
#   ~/godot-automation   the Randroids-Dojo automation fork (Godot 4.6, mono)
#   ~/.dotnet            .NET 8 runtime, which that mono build refuses to start without
#   ~/.local/bin/uv      used because python3-venv is not installed and apt needs a password
#   ~/pgvenv             playgodot + pytest
#
# See tests_e2e/README.md for why this lives in WSL and what it can and cannot test.
set -uo pipefail

DISTRO="${WSL_DISTRO:-Ubuntu-24.04}"
cd "$(dirname "$0")/.." || exit 1

# Record where the working tree is, as WSL sees it, for tools/run_e2e.sh.
WIN_PATH="$(pwd -W 2>/dev/null || pwd)"
WSL_PATH="$(wsl.exe -d "$DISTRO" -- wslpath -a "$WIN_PATH" | tr -d '\r')"
printf '%s' "$WSL_PATH" | wsl.exe -d "$DISTRO" -- bash -c 'cat > "$HOME/.thepit_e2e_src"'
echo "project path recorded: $WSL_PATH"

wsl.exe -d "$DISTRO" -- bash <<'INNER'
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.dotnet:$PATH"

GODOT_DIR="$HOME/godot-automation"
GODOT_BIN="$GODOT_DIR/godot.linuxbsd.editor.x86_64.mono"
URL="https://github.com/Randroids-Dojo/godot/releases/download/automation-latest/godot-automation-linux-x86_64.zip"

if [ ! -x "$GODOT_BIN" ]; then
  echo "--- fetching the automation build (110 MB) ---"
  mkdir -p "$GODOT_DIR" && cd "$GODOT_DIR" || exit 1
  curl -sSL -o godot-automation.zip "$URL"
  # unzip is not installed and apt needs a password.
  python3 -c 'import zipfile; zipfile.ZipFile("godot-automation.zip").extractall(".")'
  chmod +x "$GODOT_BIN"
  rm -f godot-automation.zip
fi
echo "godot: $("$GODOT_BIN" --headless --version 2>&1 | tail -1)"

if [ ! -x "$HOME/.dotnet/dotnet" ]; then
  echo "--- installing .NET 8 (the mono build will not start without it) ---"
  curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel 8.0 --install-dir "$HOME/.dotnet" >/dev/null 2>&1
fi
echo "dotnet: $("$HOME/.dotnet/dotnet" --version 2>&1)"

if ! command -v uv >/dev/null 2>&1; then
  echo "--- installing uv ---"
  curl -sSL https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
  export PATH="$HOME/.local/bin:$PATH"
fi
echo "uv: $(uv --version 2>&1)"

if [ ! -x "$HOME/pgvenv/bin/python" ]; then
  uv venv "$HOME/pgvenv" --python 3.12 >/dev/null 2>&1
fi
uv pip install --quiet --python "$HOME/pgvenv/bin/python" playgodot pytest pytest-asyncio
echo "playgodot: $("$HOME/pgvenv/bin/python" -c 'import playgodot; print("ok")' 2>&1)"

echo "--- ready: bash tools/run_e2e.sh ---"
INNER

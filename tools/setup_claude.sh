#!/usr/bin/env bash
# Brings the agent toolchain up on a fresh clone.
#
#   bash tools/setup_claude.sh
#
# Idempotent: run it as often as you like. It installs the two pieces that are
# cheap and unambiguous — the gdtoolkit venv and the godot-mcp Node server —
# and for the two it must not install behind your back (Godot, Aseprite) it
# checks, reports, and prints the exact thing to do.
#
# The addons themselves are committed, so nothing here touches addons/.
#
# Honoured environment variables, all optional:
#   GODOT / GODOT_CLI   pin the Godot binary instead of discovering one
#   GODOT_DIR           where the standalone lives (default C:/tools/godot)
#   GODOT_MCP_DIR       where to clone/build godot-mcp (default C:/tools/godot-mcp)
#   ASEPRITE            pin the Aseprite binary
set -uo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
source tools/lib/find_godot.sh

GODOT_MCP_DIR="${GODOT_MCP_DIR:-C:/tools/godot-mcp}"
missing=0

say()  { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  MISS  %s\n' "$1"; missing=1; }
note() { printf '        %s\n' "$1"; }

# The venv puts its executables in Scripts/ on Windows and bin/ everywhere else.
venv_bin() {
	if [ -d "${PROJECT_DIR}/.venv/Scripts" ]; then
		printf '%s\n' "${PROJECT_DIR}/.venv/Scripts"
	else
		printf '%s\n' "${PROJECT_DIR}/.venv/bin"
	fi
}

# ---------------------------------------------------------------- prerequisites

say "prerequisites"
for tool in python node git; do
	if command -v "$tool" >/dev/null 2>&1; then
		ok "$tool $("$tool" --version 2>&1 | head -1)"
	else
		warn "$tool is not on PATH"
	fi
done

# ------------------------------------------------------------- gdtoolkit venv

say "gdtoolkit (gdlint, gdformat)"
if [ ! -d .venv ]; then
	printf '  creating .venv\n'
	python -m venv .venv || warn "python -m venv .venv failed"
fi
VENV_BIN="$(venv_bin)"
if [ -d .venv ]; then
	if ! "${VENV_BIN}/python" -c "import gdtoolkit" >/dev/null 2>&1; then
		printf '  installing gdtoolkit\n'
		"${VENV_BIN}/python" -m pip install --quiet --upgrade pip
		"${VENV_BIN}/python" -m pip install --quiet "gdtoolkit==4.*"
	fi
	if "${VENV_BIN}/gdlint" --version >/dev/null 2>&1; then
		ok "gdlint $("${VENV_BIN}/gdlint" --version 2>&1)"
	else
		warn "gdlint did not install"
	fi
else
	warn ".venv is missing"
fi

# ------------------------------------------------------------------- godot-mcp

say "godot-mcp server (the bridge into a running editor)"
if [ ! -d "${GODOT_MCP_DIR}/.git" ]; then
	printf '  cloning into %s\n' "${GODOT_MCP_DIR}"
	git clone --depth 1 https://github.com/mkdevkit/godot-mcp.git "${GODOT_MCP_DIR}" 2>&1 | tail -1
fi
if [ -d "${GODOT_MCP_DIR}/server" ]; then
	if [ ! -f "${GODOT_MCP_DIR}/server/build/index.js" ]; then
		printf '  building\n'
		(cd "${GODOT_MCP_DIR}/server" && npm install --silent && npm run build) 2>&1 | tail -3
	fi
	if [ -f "${GODOT_MCP_DIR}/server/build/index.js" ]; then
		ok "${GODOT_MCP_DIR}/server/build/index.js"
		if [ "${GODOT_MCP_DIR}" != "C:/tools/godot-mcp" ]; then
			note "not the default path — export GODOT_MCP_SERVER=${GODOT_MCP_DIR}/server/build/index.js"
			note "(.mcp.json reads it as \${GODOT_MCP_SERVER:-C:/tools/godot-mcp/...})"
		fi
	else
		warn "godot-mcp did not build"
	fi
else
	warn "godot-mcp was not cloned to ${GODOT_MCP_DIR}"
fi

# ----------------------------------------------------------------------- godot

say "godot"
if GODOT_FOUND="$(find_godot)"; then
	ok "${GODOT_FOUND}"
	printf '        %s\n' "$("${GODOT_FOUND}" --version 2>&1 | tail -1)"
	case "${GODOT_FOUND}" in
		*console*) ;;
		*)
			note "this is not the console build; headless output only survives a redirect."
			note "Get Godot_v<version>-stable_win64.exe.zip from godotengine.org/download/windows,"
			note "unpack into ${GODOT_DIR:-C:/tools/godot}, and the _console.exe wins next run."
			;;
	esac
else
	warn "no Godot binary found"
	note "Unpack the standalone into ${GODOT_DIR:-C:/tools/godot}, or export GODOT=<path>."
	note "The version must match whatever opens the project by hand."
fi

# -------------------------------------------------------------------- aseprite

say "aseprite"
ASEPRITE_FOUND="${ASEPRITE:-}"
if [ -z "${ASEPRITE_FOUND}" ]; then
	for candidate in \
		"C:/Program Files (x86)/Steam/steamapps/common/Aseprite/Aseprite.exe" \
		"C:/Program Files/Aseprite/Aseprite.exe" \
		"/Applications/Aseprite.app/Contents/MacOS/aseprite"; do
		[ -x "${candidate}" ] && ASEPRITE_FOUND="${candidate}" && break
	done
	[ -z "${ASEPRITE_FOUND}" ] && command -v aseprite >/dev/null 2>&1 && ASEPRITE_FOUND="$(command -v aseprite)"
fi

if [ -n "${ASEPRITE_FOUND}" ]; then
	ok "${ASEPRITE_FOUND}"
	# The Wizard reads this from EDITOR settings, not from project.godot, and a
	# self-contained install (the Steam one has a ._sc_ marker) keeps its own
	# copy next to the executable. Missing it is why the plugin "does nothing".
	found_setting=0
	for settings in \
		"C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/editor_data/editor_settings-4.7.tres" \
		"${APPDATA:-$HOME/.config}/Godot/editor_settings-4.7.tres" \
		"$HOME/.config/godot/editor_settings-4.7.tres"; do
		[ -f "${settings}" ] || continue
		if grep -q '^aseprite/general/command_path' "${settings}" 2>/dev/null; then
			ok "aseprite path is set in ${settings}"
			found_setting=1
		else
			warn "aseprite path is NOT set in ${settings}"
			note "Close the editor, then append this line to that file:"
			note "aseprite/general/command_path = \"${ASEPRITE_FOUND//\\//}\""
		fi
	done
	[ "${found_setting}" -eq 0 ] && note "Or set it in the editor: Project Settings > Plugins > Aseprite Wizard."
else
	warn "no Aseprite binary found"
	note "Sprites are authored there; nothing else in this repo generates image data."
fi

# ------------------------------------------------------------------- pixel-mcp

say "pixel-mcp config (Aseprite over MCP, from the pixel-plugin Claude plugin)"
PIXEL_CFG="${APPDATA:-$HOME/.config}/pixel-mcp/config.json"
if [ -f "${PIXEL_CFG}" ]; then
	ok "${PIXEL_CFG}"
elif [ -n "${ASEPRITE_FOUND}" ]; then
	mkdir -p "$(dirname "${PIXEL_CFG}")"
	printf '{\n  "aseprite_path": "%s",\n  "timeout": 60,\n  "log_level": "info"\n}\n' \
		"$(printf '%s' "${ASEPRITE_FOUND}" | sed 's#/#\\\\#g')" > "${PIXEL_CFG}"
	ok "wrote ${PIXEL_CFG}"
else
	note "skipped — no Aseprite to point it at"
fi

# --------------------------------------------------------------------- summary

say "summary"
if [ "${missing}" -ne 0 ]; then
	printf 'Some pieces are missing — see MISS above.\n'
	printf 'The repo still works without them; you lose the feedback loop they carry.\n'
	exit 1
fi
printf 'Everything is in place. Verify with: bash tools/run_tests.sh\n'

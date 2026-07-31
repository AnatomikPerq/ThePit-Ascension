#!/usr/bin/env bash
# Locates a Godot binary. Source it, then call find_godot; it echoes the path
# and returns non-zero if nothing was found.
#
#   source tools/lib/find_godot.sh
#   GODOT="$(find_godot)" || { echo "no godot"; exit 1; }
#
# Order, most explicit first:
#   $GODOT / $GODOT_CLI   pin it and nothing here guesses
#   $GODOT_DIR            the standalone unpack, default C:/tools/godot
#   PATH                  how it looks on Linux and macOS
#   Steam                 last resort, and the reason it is last is below
#
# Prefer the console build on Windows. The Steam exe is linked as a GUI
# subsystem app: run it from a terminal and it attaches to no console, so it
# prints nothing unless the handle happens to be redirected. Everything in
# run_tests.sh pipes into grep, which is a redirect, which is the only reason
# that ever looked like it worked.

find_godot() {
	if [ -n "${GODOT:-}" ] && [ -x "${GODOT}" ]; then
		printf '%s\n' "${GODOT}"
		return 0
	fi
	if [ -n "${GODOT_CLI:-}" ] && [ -x "${GODOT_CLI}" ]; then
		printf '%s\n' "${GODOT_CLI}"
		return 0
	fi

	# Newest by name, so keeping an old build around does not pin the version.
	local dir="${GODOT_DIR:-C:/tools/godot}"
	local candidate
	candidate="$(ls -1 "${dir}"/*console*.exe 2>/dev/null | sort | tail -1)"
	if [ -n "${candidate}" ]; then
		printf '%s\n' "${candidate}"
		return 0
	fi

	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return 0
	fi

	local steam="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
	if [ -x "${steam}" ]; then
		printf '%s\n' "${steam}"
		return 0
	fi

	return 1
}

extends SceneTree
## One-shot generator: writes data/net/protocol_stamp.tres.
##
##   godot --headless --path . -s tools/build_protocol_stamp.gd
##
## Like the other `build_*.gd` in this folder it is not part of the build — it
## exists so the number it produces is traceable to something rather than typed
## by hand. `tools/run_tests.sh` runs it every time and says out loud when the
## result moved, because a commit that moves it is a commit that obliges you to
## rebuild and redeploy the dedicated server.
##
## **What "the game changed" is defined to mean.** Everything below is a file the
## simulation is a function of: the entity and world code, every scene the server
## instantiates, and the tuning resources those read. Cosmetics are deliberately
## out — `scenes/ui`, `scenes/fx`, `data/fx`, `data/audio`, the sprite assets and
## the audio bank never cross the wire and never change where anything is, so a
## new particle preset must not force every player to download a new client.
##
## `src/server` and `src/directory` are out for the same reason from the other
## side: a client never runs a line of either, so it cannot be out of step with
## them. (Neither is in ROOTS at all, which is why neither appears in the skip
## list below.) The server directory is doubly out — it is metadata ABOUT
## servers, never part of one. What the two builds must agree about is the
## simulation and the wire, and `src/net`, which is the wire, is very much in.
## Without these exclusions, fixing a typo in a server log message would change
## the fingerprint and oblige every player to update.
##
## Two things that are NOT files are folded in at the end: the handful of project
## settings the simulation actually depends on (physics rate, collision layer
## names) and NetProtocol.VERSION. A physics tick rate that differs between two
## builds desyncs every moving platform in the pit, and it lives in
## project.godot rather than in any of the directories above.

## Walked recursively. Order within a directory does not matter — the file list
## is sorted before hashing, so the same tree hashes the same on any filesystem.
const ROOTS: Array[String] = [
	"res://src/core", "res://src/defs", "res://src/entities", "res://src/net",
	"res://src/world",
	"res://scripts", "res://scenes",
	"res://data/characters", "res://data/enemies", "res://data/upgrades",
	"res://data/worlds", "res://data/animations",
]

## Paths that start with any of these are skipped. Everything here is local
## presentation: it can differ between two builds without either of them being
## wrong about where a platform is.
const SKIP_PREFIXES: Array[String] = [
	"res://scenes/ui/", "res://scenes/fx/", "res://src/ui/",
	"res://scripts/fx.gd", "res://scripts/ui_input.gd",
	# The menus. They are presentation exactly as much as `scenes/ui` is, and
	# they sat inside the fingerprint only because they happen to be at the top
	# of `scenes/` rather than under it — so moving a button used to oblige every
	# server on earth to redeploy.
	"res://scenes/MainMenu.tscn", "res://scenes/Lobby.tscn",
	"res://scripts/main_menu.gd",
	# The console programs' own scenes, for the same reason `src/server` is out of
	# ROOTS entirely: a client never loads a line of either.
	"res://scenes/server/",
	# Circular by construction: the stamp cannot contain its own hash. Also where
	# `directory.tres` lives — the list a copy of the game reads has nothing to do
	# with whether it can simulate the same pit as a server.
	"res://data/net/",
]

## Extensions worth hashing. `.uid` is derived, `.import` describes how an asset
## was converted for this machine, and neither says anything about the pit.
const KEEP_EXTENSIONS: Array[String] = [
	"gd", "tscn", "tres",
]

## Project settings the simulation depends on. Named one by one rather than
## hashing project.godot whole, because that file also carries the editor plugin
## list and the input map — things that move without changing the game.
const SETTINGS: Array[String] = [
	"application/config/name",
	"physics/common/physics_ticks_per_second",
	"layer_names/2d_physics/layer_1", "layer_names/2d_physics/layer_2",
	"layer_names/2d_physics/layer_3", "layer_names/2d_physics/layer_4",
	"layer_names/2d_physics/layer_5", "layer_names/2d_physics/layer_6",
]

const OUT_PATH := "res://data/net/protocol_stamp.tres"


func _initialize() -> void:
	var files := _collect()
	files.sort()

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for path in files:
		var bytes := FileAccess.get_file_as_bytes(path)
		# The path and the length go in as well as the content: without them two
		# files could be swapped, or one split in two, without moving the hash.
		ctx.update(("%s:%d\n" % [path, bytes.size()]).to_utf8_buffer())
		ctx.update(bytes)
	for key in SETTINGS:
		ctx.update(("%s=%s\n" % [key, ProjectSettings.get_setting(key, "")]).to_utf8_buffer())
	ctx.update(("protocol=%d\n" % NetProtocol.VERSION).to_utf8_buffer())

	var stamp := ProtocolStamp.new()
	stamp.content_hash = ctx.finish().hex_encode()
	stamp.file_count = files.size()
	stamp.generated_at = Time.get_datetime_string_from_system(true)
	stamp.sources = PackedStringArray(ROOTS)

	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var err := ResourceSaver.save(stamp, OUT_PATH)
	if err != OK:
		printerr("could not write %s: %d" % [OUT_PATH, err])
		quit(1)
		return
	print("protocol stamp: %s  (%d files, protocol %d)" % [
		stamp.content_hash, stamp.file_count, NetProtocol.VERSION])
	quit(0)


func _collect() -> PackedStringArray:
	var out := PackedStringArray()
	for root in ROOTS:
		_walk(root, out)
	return out


func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return # a root that does not exist yet is not an error, it is a stage
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, out)
		elif KEEP_EXTENSIONS.has(entry.get_extension()) and not _skipped(full):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _skipped(path: String) -> bool:
	for prefix in SKIP_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false

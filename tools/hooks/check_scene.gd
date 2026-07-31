extends Node
## Loads one scene and instantiates it, so a broken `ext_resource`, a dead UID,
## a node path that no longer resolves or a script that no longer compiles is
## reported now rather than the next time somebody opens the editor.
##
##   godot --headless --path . tools/hooks/check_scene.tscn -- res://scenes/X.tscn
##
## Called by tools/hooks/claude_hook.mjs after Claude edits a .tscn.
##
## This is a scene and not a `-s` script on purpose. Under `-s` the main loop is
## replaced and the autoloads are never registered, so every script that names
## Fx, Audio, Game, Net fails to compile and the probe reports a wall of errors
## about a scene that is fine.
##
## Instantiate is safe here: it runs _init but not _ready, because the instance
## never enters a tree.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("no scene path given")
		return

	var path := args[0]
	if not ResourceLoader.exists(path):
		_fail("no such resource: " + path)
		return

	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if scene == null:
		_fail("failed to load " + path)
		return

	if not (scene is PackedScene):
		_fail("not a PackedScene: " + path)
		return

	var instance := (scene as PackedScene).instantiate()
	if instance == null:
		_fail("failed to instantiate " + path)
		return

	instance.free()
	print("check_scene ok: " + path)
	get_tree().quit(0)


func _fail(message: String) -> void:
	printerr("check_scene FAILED: " + message)
	get_tree().quit(1)

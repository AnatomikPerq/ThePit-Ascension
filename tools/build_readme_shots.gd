extends Node
## One-shot generator for the images in README.md.
##
##   godot --path . tools/build_readme_shots.tscn
##
## Like every tools/build_* script this is NOT part of the build: it writes into
## docs/images/ and re-running it overwrites what is there. It exists so the
## README's pictures have a traceable origin — every one of them is this
## project's own scenes rendered by this project's own renderer, at a fixed
## seed, rather than something cropped out of a video by hand.
##
## Not headless: it needs a real renderer to produce an image.
##
## docs/images/ carries a .gdignore so Godot does not import its own output
## back into the project as game assets.

const OUT_DIR := "res://docs/images"
const SEED: int = 20260728

## The lineup: everything that moves, in the order the docs talk about it.
const CAST: Array[String] = [
	"res://scenes/Player.tscn",
	"res://scenes/Golem.tscn",
	"res://scenes/Slime.tscn",
	"res://scenes/Pursuer.tscn",
	"res://scenes/Bat.tscn",
	"res://scenes/Spitter.tscn",
	"res://scenes/Trampoline.tscn",
]
const CAST_SCALE: float = 3.0
const CAST_STEP: float = 240.0
const CAST_FIRST_X: float = 180.0
const CAST_Y: float = 300.0
const CAST_CROP := Rect2i(40, 130, 1740, 340)
## The lobby before anyone has connected is mostly empty screen; trim to the
## part that has something on it.
const LOBBY_CROP := Rect2i(0, 200, 1920, 680)

## Where Cyn stands for the gameplay shot: deep enough for the molten palette,
## below the first upgrade milestone at 75% so the shot is a climb and not a
## menu. Health is padded because she is standing still under a rain of drone
## heads for eight seconds and dying would spoil the picture.
const SHOT_DEPTH_FRACTION: float = 0.8
const SPAWN_FRAMES: int = 1200


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	seed(SEED)
	await _shoot_cast()
	await _shoot_control("res://scenes/MainMenu.tscn", "menu.png", 30)
	await _shoot_control("res://scenes/Lobby.tscn", "lobby.png", 10, LOBBY_CROP)
	await _shoot_run()
	print("build_readme_shots: wrote 5 images to ", OUT_DIR)
	get_tree().quit(0)


## Every entity in a row, frozen the moment its _ready() has run — the same
## discipline visual_check uses, for the same reason: a tween or a particle
## mid-flight makes the picture a matter of timing.
func _shoot_cast() -> void:
	RenderingServer.set_default_clear_color(Color(0.09, 0.02, 0.03))
	var root := Node2D.new()
	add_child(root)

	var player: Node2D = null
	var x := CAST_FIRST_X
	for path in CAST:
		var node: Node2D = load(path).instantiate()
		root.add_child(node)
		node.global_position = Vector2(x, CAST_Y)
		node.scale = Vector2(CAST_SCALE, CAST_SCALE)
		if player == null:
			player = node
		x += CAST_STEP

	for child in root.get_children():
		if child != player and child.has_method("set_player_ref"):
			child.set_player_ref(player)
		child.process_mode = Node.PROCESS_MODE_DISABLED
		_freeze(child)

	await _frames(3)
	await _save("cast.png", CAST_CROP)
	root.free()


func _shoot_control(scene_path: String, file_name: String, settle: int,
		crop: Rect2i = Rect2i()) -> void:
	var ui: Node = load(scene_path).instantiate()
	get_tree().root.add_child(ui)
	await _frames(settle)
	await _save(file_name, crop)
	ui.free()


## A live run: the world built from a fixed seed, Cyn partway up, and long
## enough on the clock for the spawner to fill the shaft above her.
func _shoot_run() -> void:
	var world: Node = load("res://scenes/World.tscn").instantiate()
	world.world_seed = SEED
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _frames(2)

	var cyn: CharacterBody2D = world.player
	cyn.global_position.y = world.max_depth * SHOT_DEPTH_FRACTION
	cyn.health = 999
	# The HUD's ability icons only exist for abilities you own.
	cyn.max_jumps = 2
	cyn.has_attack = true
	cyn.has_shockwave = true

	await _frames(SPAWN_FRAMES)
	await _save("gameplay.png")

	world._show_upgrade_menu()
	await _frames(5)
	await _save("upgrades.png")
	get_tree().paused = false
	world.free()


## Stop every AnimatedSprite2D on frame 0 and every AnimationPlayer, so the
## invincibility blink cannot catch a sprite mid-hide.
func _freeze(node: Node) -> void:
	var animated := node as AnimatedSprite2D
	if animated:
		animated.stop()
		animated.frame = 0
		animated.visible = true
	var anim_player := node as AnimationPlayer
	if anim_player:
		anim_player.stop()
	for child in node.get_children():
		_freeze(child)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## `crop` of zero size means the whole viewport.
func _save(file_name: String, crop: Rect2i = Rect2i()) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if crop.size != Vector2i.ZERO:
		img = img.get_region(crop)
	var err := img.save_png(OUT_DIR.path_join(file_name))
	if err != OK:
		push_error("build_readme_shots: could not write %s (error %d)" % [file_name, err])
		get_tree().quit(1)

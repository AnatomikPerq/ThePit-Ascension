extends Node2D
## Visual regression harness: lays every entity out at fixed positions, freezes
## them, screenshots the viewport and quits.
##
##   godot --path . --fixed-fps 60 tools/visual_check.tscn -- <output.png>
##
## Run it on two commits and diff the PNGs to prove a refactor did not change
## how anything looks.
##
## Determinism is the whole point, so every entity is switched to
## PROCESS_MODE_DISABLED immediately after it enters the tree. Its _ready() has
## already run (which is what puts a texture on the old procedurally-drawn
## enemies), but no AI, physics, animation advance, tween or particle emission
## follows. Without this the harness is useless: an earlier version left the
## entities running and two captures of the SAME commit differed by 8.6% of
## pixels, purely from tween and particle timing.
##
## Not headless — it needs a real renderer to produce an image.

const SEED: int = 20260728

const ENTITIES: Array = [
	["res://scenes/Player.tscn", Vector2(200, 260)],
	["res://scenes/Golem.tscn", Vector2(440, 260)],
	["res://scenes/Slime.tscn", Vector2(680, 260)],
	["res://scenes/Pursuer.tscn", Vector2(920, 260)],
	["res://scenes/Bat.tscn", Vector2(1160, 260)],
	["res://scenes/Spitter.tscn", Vector2(1400, 260)],
	["res://scenes/Trampoline.tscn", Vector2(1640, 260)],
	["res://scenes/Platform.tscn", Vector2(260, 520)],
	["res://scenes/MovingPlatform.tscn", Vector2(700, 520)],
	["res://scenes/Projectile.tscn", Vector2(1100, 520)],
	["res://scenes/Strike.tscn", Vector2(1300, 520)],
	["res://scenes/Shockwave.tscn", Vector2(960, 820)],
]

var _out_path: String = "user://visual_check.png"
var _player: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]

	seed(SEED)
	RenderingServer.set_default_clear_color(Color(0.14, 0.02, 0.02))
	_spawn_all()
	_capture.call_deferred()


func _spawn_all() -> void:
	var spawned: Array[Node] = []
	for entry: Array in ENTITIES:
		var packed: PackedScene = load(entry[0])
		if packed == null:
			push_error("visual_check: cannot load " + String(entry[0]))
			continue
		var node: Node = packed.instantiate()
		add_child(node)
		(node as Node2D).global_position = entry[1]
		spawned.append(node)
		if String(entry[0]).ends_with("Player.tscn"):
			_player = node

	for node in spawned:
		if node != _player and node.has_method("set_player_ref"):
			node.set_player_ref(_player)
		# Freeze: _ready() has run, nothing else will.
		node.process_mode = Node.PROCESS_MODE_DISABLED
		_freeze_animations(node)


## Stop every AnimatedSprite2D so the capture always shows frame 0, and every
## AnimationPlayer so the invincibility blink cannot hide a sprite.
func _freeze_animations(node: Node) -> void:
	var animated := node as AnimatedSprite2D
	if animated:
		animated.stop()
		animated.frame = 0
		animated.visible = true
	var anim_player := node as AnimationPlayer
	if anim_player:
		anim_player.stop()
	for child in node.get_children():
		_freeze_animations(child)


func _capture() -> void:
	# Two frames is enough for the tree to be laid out and drawn once.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_path)
	if err != OK:
		push_error("visual_check: could not write %s (error %d)" % [_out_path, err])
		get_tree().quit(1)
		return
	print("visual_check: wrote ", _out_path)
	get_tree().quit(0)

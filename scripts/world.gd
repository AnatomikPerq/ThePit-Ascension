extends Node2D
## World — main game controller.
## Handles procedural level generation, enemy spawning, HUD, and game state.
## All coordinates are ×2 scaled from the legacy Pygame FINAL.py.

# ── Constants (×2) ──────────────────────────────────────────────────────────
const WORLD_WIDTH: int = 2000 # 1000 * 2
const WORLD_HEIGHT: int = 8000 # 4000 * 2
const WALL_THICK: int = 128 # 64 * 2

# ── Scenes ──────────────────────────────────────────────────────────────────
const PLATFORM_SCENE: PackedScene = preload("res://scenes/Platform.tscn")
const MOVING_PLAT_SCENE: PackedScene = preload("res://scenes/MovingPlatform.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/Golem.tscn")
const SLIME_SCENE: PackedScene = preload("res://scenes/Slime.tscn")
const PURSUER_SCENE: PackedScene = preload("res://scenes/Pursuer.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const TRAMPOLINE_SCENE: PackedScene = preload("res://scenes/Trampoline.tscn")

# ── State ───────────────────────────────────────────────────────────────────
enum GameState {PLAYING, UPGRADE_MENU, GAME_OVER, VICTORY}
var state: int = GameState.PLAYING

var player: CharacterBody2D
var spawn_rate: float = 2.0
var upgrade_milestones: Array[int] = [6000, 2000] # 3000*2, 1000*2
var notification_timer: float = 0.0

# Background color cycling
var bg_colors: Array[Color] = [
	Color(0.059, 0.0, 0.0),
	Color(0.251, 0.0, 0.0),
	Color(0.059, 0.0, 0.0),
	Color(0.290, 0.220, 0.0),
	Color(0.059, 0.0, 0.0),
]
const BG_TRANSITION_TIME: float = 15.0
var bg_time: float = 0.0

# ── Node references ─────────────────────────────────────────────────────────
@onready var camera: Camera2D = $Camera2D
@onready var platforms_node: Node2D = $Platforms
@onready var enemies_node: Node2D = $Enemies
@onready var trampolines_node: Node2D = $Trampolines
@onready var hud: Control = $CanvasLayer/HUD
@onready var hp_bar: HBoxContainer = $CanvasLayer/HUD/HPBar
@onready var depth_label: Label = $CanvasLayer/HUD/DepthLabel
@onready var skills_label: Label = $CanvasLayer/HUD/SkillsLabel
@onready var flight_label: Label = $CanvasLayer/HUD/FlightLabel
@onready var notif_label: Label = $CanvasLayer/HUD/NotificationLabel
@onready var upgrade_menu: Panel = $CanvasLayer/UpgradeMenu
@onready var game_over_screen: ColorRect = $CanvasLayer/GameOverScreen
@onready var victory_screen: ColorRect = $CanvasLayer/VictoryScreen
@onready var enemy_timer: Timer = $EnemySpawnTimer
@onready var dim_overlay: ColorRect = $CanvasLayer/DimOverlay


func _ready() -> void:
	_generate_map()
	_spawn_player()
	_build_hp_bar()

	# Camera limits — keep within world bounds
	camera.limit_left = - WALL_THICK
	camera.limit_right = WORLD_WIDTH + WALL_THICK
	camera.limit_top = -384
	camera.limit_bottom = WORLD_HEIGHT + 120
	# Offset player slightly below center so we see more above
	camera.offset = Vector2(0, -120)

	enemy_timer.timeout.connect(_on_enemy_timer)
	$CanvasLayer/UpgradeMenu/DoubleJumpBtn.pressed.connect(_on_double_jump_chosen)
	$CanvasLayer/UpgradeMenu/StrikeBtn.pressed.connect(_on_strike_chosen)

	# Make upgrade menu work while paused
	$CanvasLayer/UpgradeMenu.process_mode = Node.PROCESS_MODE_ALWAYS
	$CanvasLayer/UpgradeMenu/DoubleJumpBtn.process_mode = Node.PROCESS_MODE_ALWAYS
	$CanvasLayer/UpgradeMenu/StrikeBtn.process_mode = Node.PROCESS_MODE_ALWAYS

	# Set background
	RenderingServer.set_default_clear_color(bg_colors[0])


func _process(delta: float) -> void:
	# Background color cycling
	if state != GameState.VICTORY:
		bg_time += delta
		var progress: float = fmod(bg_time, BG_TRANSITION_TIME) / BG_TRANSITION_TIME
		var color_index: float = progress * (bg_colors.size() - 1)
		var idx1: int = int(color_index)
		var idx2: int = mini(idx1 + 1, bg_colors.size() - 1)
		var local_p: float = color_index - idx1
		var c: Color = bg_colors[idx1].lerp(bg_colors[idx2], local_p)
		RenderingServer.set_default_clear_color(c)

	if not is_instance_valid(player):
		return

	# Update camera to follow player
	camera.global_position = player.global_position

	# HUD updates
	depth_label.text = "DEPTH: %d" % int(player.global_position.y)
	var skills_text := "Skills: "
	if player.has_double_jump:
		skills_text += "[WING] "
	if player.has_strike:
		skills_text += "[STRIKE] "
	if player.flying:
		skills_text += "[FLIGHT] "
	skills_label.text = skills_text
	flight_label.text = "FLIGHT MODE ACTIVE" if player.flying else ""

	# Notification fade
	if notification_timer > 0.0:
		notification_timer -= delta
		if notification_timer <= 0.0:
			notif_label.text = ""

	# Game logic
	if state == GameState.PLAYING:
		_check_milestones()
		_check_victory()

	if state == GameState.GAME_OVER:
		if Input.is_action_just_pressed("jump"):
			_restart()


func _unhandled_input(event: InputEvent) -> void:
	# Reset on R
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		_restart()


func _check_milestones() -> void:
	for i in range(upgrade_milestones.size() - 1, -1, -1):
		if player.global_position.y < upgrade_milestones[i]:
			upgrade_milestones.remove_at(i)
			_show_upgrade_menu()
			break


func _check_victory() -> void:
	if player.global_position.y < 200.0:
		state = GameState.VICTORY
		player.can_input = false
		victory_screen.visible = true
		get_tree().paused = true


func _show_upgrade_menu() -> void:
	state = GameState.UPGRADE_MENU
	get_tree().paused = true
	upgrade_menu.visible = true


func _on_double_jump_chosen() -> void:
	if not player.has_double_jump:
		player.has_double_jump = true
		_show_notification("UNLOCKED: DOUBLE JUMP")
	else:
		_show_notification("ALREADY OWNED (XP BONUS)")
	_close_upgrade_menu()


func _on_strike_chosen() -> void:
	if not player.has_strike:
		player.has_strike = true
		_show_notification("UNLOCKED: SIDEWAYS STRIKE")
	else:
		_show_notification("ALREADY OWNED (XP BONUS)")
	_close_upgrade_menu()


func _close_upgrade_menu() -> void:
	upgrade_menu.visible = false
	state = GameState.PLAYING
	get_tree().paused = false


func _show_notification(text: String) -> void:
	notif_label.text = text
	notification_timer = 3.0


# ── Player ──────────────────────────────────────────────────────────────────
func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.global_position = Vector2(WORLD_WIDTH / 2.0, WORLD_HEIGHT - 300.0)
	add_child(player)
	player.player_died.connect(_on_player_died)
	player.player_damaged.connect(_on_player_damaged)


func _on_player_died() -> void:
	state = GameState.GAME_OVER
	game_over_screen.visible = true


func _on_player_damaged(_new_health: int) -> void:
	_update_hp_display()


func _build_hp_bar() -> void:
	for child in hp_bar.get_children():
		child.queue_free()
	for i in range(player.max_health):
		var heart := ColorRect.new()
		heart.custom_minimum_size = Vector2(30, 16)
		heart.color = Color(0.8, 0.2, 0.2) if i < player.health else Color(0.2, 0.0, 0.0)
		hp_bar.add_child(heart)


func _update_hp_display() -> void:
	var hearts := hp_bar.get_children()
	for i in range(hearts.size()):
		if i < player.health:
			hearts[i].color = Color(0.8, 0.2, 0.2)
		else:
			hearts[i].color = Color(0.2, 0.0, 0.0)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ── Enemy Spawning ──────────────────────────────────────────────────────────
func _on_enemy_timer() -> void:
	if state != GameState.PLAYING or not is_instance_valid(player):
		return
	_spawn_enemy()

	# Gradually decrease spawn interval
	if spawn_rate > 0.6:
		spawn_rate -= 0.05
		enemy_timer.wait_time = spawn_rate


func _spawn_enemy() -> void:
	var pursuer_count := 0
	for e in enemies_node.get_children():
		if e.is_in_group("pursuer_group"):
			pursuer_count += 1
	if pursuer_count >= 20:
		return

	var spawn_y: float = player.global_position.y - 1200.0
	if spawn_y < 400.0:
		spawn_y = 400.0

	var depth: float = player.global_position.y
	var choices: Array[String] = []

	if depth > 6000.0:
		choices = ["golem", "slime"]
	elif depth > 4000.0:
		choices = ["golem", "slime", "slime", "pursuer"]
	elif depth > 2000.0:
		choices = ["slime", "pursuer", "pursuer"]
	else:
		choices = ["pursuer", "pursuer", "slime"]

	var type_name: String = choices[randi() % choices.size()]
	var x: float

	if type_name == "pursuer":
		x = 128.0 if randf() < 0.5 else WORLD_WIDTH - 192.0
		spawn_y = player.global_position.y - 800.0
	else:
		x = randf_range(200.0, WORLD_WIDTH - 200.0)

	var enemy: Node
	match type_name:
		"golem":
			enemy = GOLEM_SCENE.instantiate()
		"slime":
			enemy = SLIME_SCENE.instantiate()
		"pursuer":
			enemy = PURSUER_SCENE.instantiate()
			enemy.add_to_group("pursuer_group")

	enemy.global_position = Vector2(x, spawn_y)
	enemy.set_player_ref(player)
	enemies_node.add_child(enemy)


# ── Map Generation ──────────────────────────────────────────────────────────
func _generate_map() -> void:
	# Multiply walls vertically upwards from the placed base segment
	# Base walls are placed at y=7744, which goes up to y=7488 (height 512)
	# So we continue adding up from 7232 up to 0 and beyond.
	var y_pos := 7232.0
	while y_pos > -3000.0:
		_create_wall(Vector2(-128, y_pos), Vector2(128, 512))
		_create_wall(Vector2(WORLD_WIDTH, y_pos), Vector2(128, 512))
		y_pos -= 512.0

	# Procedural platforms
	_generate_platforms()
	# Moving platforms
	_add_moving_platforms()

func _create_wall(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	# Size is 128 wide, 512 tall. Center it relative to pos.
	body.position = pos + size / 2.0
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)

	var tex: Texture2D = preload("res://assets/sprites/wall_map.png")
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	spr.scale = Vector2(2, 2)
	spr.region_enabled = true
	spr.region_rect = Rect2(0, 0, size.x / 2.0, size.y / 2.0)
	body.add_child(spr)

	platforms_node.add_child(body)

func _create_static_platform(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos + size / 2.0
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)

	var tex: Texture2D = preload("res://assets/sprites/platform_part.png")
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	spr.scale = Vector2(2, 2)
	spr.region_enabled = true
	spr.region_rect = Rect2(0, 0, size.x / 2.0, 16)
	
	body.add_child(spr)
	platforms_node.add_child(body)


func _generate_platforms() -> void:
	# All values ×2 from legacy
	var PLAT_MIN_W: int = 160 # 80 * 2
	var PLAT_MAX_W: int = 512 # 256 * 2
	var PLAT_H: int = 32 # 16 * 2

	var forbidden_zones: Array[Rect2] = []
	for level_y in [2000, 4000, 6000]:
		forbidden_zones.append(Rect2(600, level_y - 200, 800, 400))

	var levels: Array[Dictionary] = [
		{"start_y": 7000, "end_y": 2000, "density": 0.7, "min_sp": 160, "max_sp": 300},
		{"start_y": 5800, "end_y": 4000, "density": 0.6, "min_sp": 180, "max_sp": 360},
		{"start_y": 3800, "end_y": 6000, "density": 0.5, "min_sp": 200, "max_sp": 400},
		{"start_y": 1800, "end_y": 800, "density": 0.4, "min_sp": 240, "max_sp": 500},
	]

	for level in levels:
		_gen_level_platforms(level, forbidden_zones, PLAT_MIN_W, PLAT_MAX_W, PLAT_H)

	# Special platforms
	var special: Array[Array] = [
		[4400, 2], [6400, 2], [3000, 3], [5000, 2], [7000, 2]
	]
	for sp in special:
		var y_pos: int = sp[0]
		var count: int = sp[1]
		for i in range(count):
			var x_range: Vector2 = Vector2(200, 800) if i % 2 == 0 else Vector2(1200, 1800)
			var x: int = randi_range(int(x_range.x), int(x_range.y))
			var w: int = randi_range(PLAT_MIN_W, PLAT_MAX_W)
			if not _too_close_to_divider(Rect2(x, y_pos, w, PLAT_H)):
				_create_static_platform(Vector2(x, y_pos), Vector2(w, PLAT_H))


func _gen_level_platforms(params: Dictionary, forbidden: Array[Rect2], min_w: int, max_w: int, h: int) -> void:
	var y: float = params["start_y"]
	var density: float = params["density"]
	var min_sp: int = params["min_sp"]
	var max_sp: int = params["max_sp"]

	while y > params["end_y"]:
		if randf() < density:
			var gen_count: int = 2 if randf() < 0.3 else 1
			var generated: Array[Rect2] = []

			for _i in range(gen_count):
				var zone_r: float = randf()
				var x_range: Vector2
				if zone_r < 0.1:
					x_range = Vector2(700, 1300) # center
				elif zone_r < 0.55:
					x_range = Vector2(100, 500) # left
				else:
					x_range = Vector2(1500, 1900) # right

				var x: int = randi_range(int(x_range.x), int(x_range.y))
				var w: int = randi_range(min_w, max_w)
				w = (w / 64) * 64 # Snap to 64px grid

				var r := Rect2(x, y, w, h)
				var valid := true

				for fz in forbidden:
					if r.intersects(fz):
						valid = false
						break

				if valid and _too_close_to_divider(r):
					valid = false

				if valid:
					for existing in generated:
						if abs(r.get_center().x - existing.get_center().x) < min_sp or r.intersects(existing):
							valid = false
							break

				if valid:
					_create_static_platform(Vector2(x, y), Vector2(w, h))
					generated.append(r)

		y -= randi_range(min_sp, max_sp)


func _too_close_to_divider(r: Rect2, min_dist: float = 100.0) -> bool:
	for dy in [2000, 4000, 6000]:
		if abs(r.get_center().y - dy) < min_dist:
			return true
	return false


func _add_moving_platforms() -> void:
	# All coords ×2 from legacy
	var positions: Array[Array] = [
		# [x, y, range, speed, delay, type]
		# Level 1 (bottom)
		[600, 6800, 500, 35, 0, "horizontal"],
		[1200, 6600, 400, 40, 30, "horizontal"],
		[400, 6400, 600, 25, 60, "horizontal"],
		[1000, 5800, 480, 40, 90, "horizontal"],
		[700, 5600, 800, 30, 60, "horizontal"],
		[1300, 5400, 640, 35, 30, "horizontal"],
		# Level 2
		[500, 4800, 560, 40, 0, "horizontal"],
		[1100, 4600, 640, 25, 60, "horizontal"],
		[1500, 4400, 480, 35, 30, "horizontal"],
		[1200, 3800, 560, 35, 45, "horizontal"],
		[600, 3600, 800, 25, 60, "horizontal"],
		[1400, 3400, 640, 30, 30, "horizontal"],
		# Level 3
		[800, 2800, 700, 35, 0, "horizontal"],
		[400, 2600, 560, 40, 60, "horizontal"],
		[1200, 2400, 600, 25, 30, "horizontal"],
		[1400, 1800, 720, 40, 45, "horizontal"],
		[700, 1600, 480, 25, 60, "horizontal"],
		[1300, 1400, 800, 30, 30, "horizontal"],
		# Level 4 (top)
		[500, 1200, 640, 35, 0, "horizontal"],
		[1100, 1000, 560, 40, 30, "horizontal"],
		[900, 400, 480, 35, 45, "horizontal"],
		[1200, 200, 640, 40, 30, "horizontal"],
		# Vertical
		[300, 6400, 400, 20, 0, "vertical"],
		[1700, 6200, 360, 25, 45, "vertical"],
		[360, 5000, 440, 30, 60, "vertical"],
		[1760, 3000, 400, 25, 90, "vertical"],
		[200, 1600, 560, 30, 60, "vertical"],
		[1800, 1400, 440, 40, 30, "vertical"],
		# Extra
		[400, 2400, 800, 25, 30, "vertical"],
		[1200, 3600, 900, 30, 60, "horizontal"],
	]

	for p in positions:
		var plat_w: int = randi_range(160, 512)
		if not _too_close_to_divider(Rect2(p[0], p[1], plat_w, 32), 120.0):
			var mp := MOVING_PLAT_SCENE.instantiate()
			mp.global_position = Vector2(p[0], p[1])
			mp.move_range = p[2]
			mp.move_speed = p[3]
			mp.move_delay = p[4]
			mp.move_type = p[5]
			# Resize collision to match random width
			var col_shape: CollisionShape2D = mp.get_node("CollisionShape2D")
			col_shape.shape = col_shape.shape.duplicate()
			col_shape.shape.size = Vector2(plat_w, 32)
			# Resize sprite to tile across full width
			# Resize sprite to tile across full width
			var spr: Sprite2D = mp.get_node("Sprite2D")
			spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			spr.region_enabled = true
			spr.region_rect = Rect2(0, 0, plat_w / 2.0, spr.texture.get_height())
			platforms_node.add_child(mp)

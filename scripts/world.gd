extends Node2D
## World — main game controller.
## Handles procedural level generation, enemy spawning, HUD, and game state.
## All coordinates are ×2 scaled from the legacy Pygame FINAL.py.

# ── Constants (×2) ──────────────────────────────────────────────────────────
const WORLD_WIDTH: int = 2000 # 1000 * 2
const WALL_THICK: int = 128 # 64 * 2

@export var level_count: int = 4
@export var level_height: int = 2000
var max_depth: float = 8000.0

# ── Scenes ──────────────────────────────────────────────────────────────────
const PLATFORM_SCENE: PackedScene = preload("res://scenes/Platform.tscn")
const MOVING_PLAT_SCENE: PackedScene = preload("res://scenes/MovingPlatform.tscn")
const GOLEM_SCENE: PackedScene = preload("res://scenes/Golem.tscn")
const SLIME_SCENE: PackedScene = preload("res://scenes/Slime.tscn")
const PURSUER_SCENE: PackedScene = preload("res://scenes/Pursuer.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const TRAMPOLINE_SCENE: PackedScene = preload("res://scenes/Trampoline.tscn")

# ── State ───────────────────────────────────────────────────────────────────
enum GameState {PLAYING, UPGRADE_MENU, GAME_OVER, VICTORY, PAUSED}
var state: int = GameState.PLAYING

var player: CharacterBody2D
var spawn_timer: float = 0.0
var current_spawn_interval: float = 2.0
var upgrade_milestones: Array[float] = []
var notification_timer: float = 0.0

var show_debug: bool = false
var debug_free_zones: Array[Rect2] = []

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


func _ready() -> void:
	max_depth = float(level_count * level_height)
	upgrade_milestones = [max_depth * 0.75, max_depth * 0.25]
	
	_generate_map()
	_spawn_player()
	_build_hp_bar()

	# Create FPS Label dynamically
	var fps_label := Label.new()
	fps_label.name = "FPSLabel"
	fps_label.position = Vector2(1780, 20) # Top right corner roughly
	fps_label.add_theme_font_size_override("font_size", 20)
	hud.add_child(fps_label)

	# Camera limits — keep within world bounds
	camera.limit_left = - WALL_THICK
	camera.limit_right = WORLD_WIDTH + WALL_THICK
	camera.limit_top = -384
	camera.limit_bottom = int(max_depth) + 120
	# Offset player slightly below center so we see more above
	camera.offset = Vector2(0, -120)

	$CanvasLayer/UpgradeMenu/DoubleJumpBtn.pressed.connect(_on_double_jump_chosen)
	$CanvasLayer/UpgradeMenu/StrikeBtn.pressed.connect(_on_strike_chosen)

	# World should pause normally.
	self.process_mode = Node.PROCESS_MODE_INHERIT

	# Let the CanvasLayer (or a specific control) process while paused for menus
	$CanvasLayer.process_mode = Node.PROCESS_MODE_ALWAYS

	# Set background
	RenderingServer.set_default_clear_color(bg_colors[0])
	
	# Load and attach UI input handler script manually
	var ui_script: Script = load("res://scripts/ui_input.gd")
	if ui_script:
		var input_node := Node.new()
		input_node.name = "UIInputHandler"
		input_node.set_script(ui_script)
		input_node.process_mode = Node.PROCESS_MODE_ALWAYS
		$CanvasLayer.add_child(input_node)


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

	if state == GameState.GAME_OVER:
		if Input.is_action_just_pressed("jump"):
			_restart()
		return

	if not is_instance_valid(player):
		return

	# Time-based enemy spawner
	if state == GameState.PLAYING:
		spawn_timer += delta
		if spawn_timer >= current_spawn_interval:
			spawn_timer = 0.0
			_spawn_enemy()
			# Increase difficulty gradually (lower interval allowed)
			if current_spawn_interval > 0.4:
				current_spawn_interval -= 0.05

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

	# Update FPS
	var fps_node: Label = hud.get_node_or_null("FPSLabel")
	if fps_node:
		fps_node.text = "FPS: %d" % Engine.get_frames_per_second()

	# Game logic
	if state == GameState.PLAYING:
		_check_milestones()
		_check_victory()

	if show_debug:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Reset on R
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		_restart()

	# Toggle Debug Hitboxes on U
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_U:
		show_debug = not show_debug
		queue_redraw()


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


func _pause_game() -> void:
	state = GameState.PAUSED
	get_tree().paused = true
	var pause_label = hud.get_node_or_null("PauseLabel")
	if not pause_label:
		pause_label = Label.new()
		pause_label.name = "PauseLabel"
		pause_label.text = "PAUSED (Press ESC to Resume)"
		pause_label.add_theme_font_size_override("font_size", 48)
		pause_label.set_anchors_preset(Control.PRESET_CENTER)
		pause_label.position = Vector2(WORLD_WIDTH / 2 - 1350, 300) # Roughly center
		hud.add_child(pause_label)
	pause_label.visible = true

func _resume_game() -> void:
	state = GameState.PLAYING
	get_tree().paused = false
	var pause_label = hud.get_node_or_null("PauseLabel")
	if pause_label:
		pause_label.visible = false

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
	player.global_position = Vector2(WORLD_WIDTH / 2.0, max_depth - 300.0)
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

func _spawn_enemy() -> void:
	# Calculate depth progress (0.0 at top, 1.0 at bottom)
	var current_depth := maxf(0.0, minf(max_depth, player.global_position.y))
	# We want t=0 at the start (highest depth number) and t=1 at the end (lowest depth number)
	var progress := 1.0 - (current_depth / max_depth)

	# Calculate probabilities based on progress
	# Start (progress 0.0): Golem 100, Slime 90, Pursuer 1
	# End (progress 1.0): Golem 60, Slime 25, Pursuer 80
	var w_golem: float = lerp(100.0, 60.0, progress)
	var w_slime: float = lerp(90.0, 25.0, progress)
	var w_pursuer: float = lerp(1.0, 80.0, progress)
	
	var total_weight: float = w_golem + w_slime + w_pursuer
	var roll: float = randf() * total_weight

	var type_name := ""
	if roll < w_golem:
		type_name = "golem"
	elif roll < w_golem + w_slime:
		type_name = "slime"
	else:
		type_name = "pursuer"

	# Limit Pursuers
	if type_name == "pursuer":
		var pursuer_count := 0
		for e in enemies_node.get_children():
			if e.is_in_group("pursuer_group"):
				pursuer_count += 1
		if pursuer_count >= 20:
			return # Re-roll essentially negated, wait for next timer tick

	var spawn_y: float = player.global_position.y - 1200.0
	if spawn_y < -800.0:
		spawn_y = -800.0

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
	# Base walls scale from bottom to top
	var y_pos := max_depth - 512.0
	while y_pos > -3000.0:
		_create_wall(Vector2(-128, y_pos), Vector2(128, 512))
		_create_wall(Vector2(WORLD_WIDTH, y_pos), Vector2(128, 512))
		y_pos -= 512.0

	_generate_platforms()


func _create_wall(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos + size / 2.0
	body.collision_layer = 33
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
	# Keep user's preset layout for dividers conceptually,
	# but we must calculate the positions dynamically so it works with ANY level_count / max_depth.
	var dividers_y: Array[float] = []
	for i in range(1, level_count):
		dividers_y.append(max_depth - i * float(level_height))
	
	# Start generating platforms from the bottom up
	var current_y := max_depth - 800.0
	var plat_h := 32.0

	while current_y > -400.0:
		var progress := 1.0 - (maxf(current_y, 0.0) / max_depth)
		var step_y: float = lerp(80.0, 180.0, progress)
		
		# Skip spawning if too close to an existing divider from World.tscn
		var near_divider := false
		for div_y in dividers_y:
			if abs(current_y - div_y) < 250.0:
				near_divider = true
				break
				
		if near_divider:
			current_y -= step_y
			debug_free_zones.append(Rect2(0, current_y, WORLD_WIDTH, step_y))
			continue
			
		var chance: float = lerp(0.95, 0.6, progress)
		if randf() < chance:
			# Spawn 1 to 4 platforms per height step to increase density
			var max_plats := int(lerp(4.0, 1.0, progress))
			var plat_count := randi_range(1, maxi(1, max_plats))
			
			for i in range(plat_count):
				var max_b := int(lerp(8.0, 3.0, progress))
				var min_b := 2
				var blocks := randi_range(min_b, maxi(min_b, max_b))
				var w := float(blocks * 64)
				
				var x := randf_range(128.0, WORLD_WIDTH - 128.0 - w)
				var type_roll := randf()
				var p_y := current_y + randf_range(-30.0, 30.0)
				
				if type_roll < 0.6: # Static
					_create_static_platform(Vector2(x, p_y), Vector2(w, plat_h))
				else: # Moving
					var mp := MOVING_PLAT_SCENE.instantiate()
					mp.global_position = Vector2(x, p_y)
					mp.move_speed = randf_range(20.0, 50.0)
					mp.move_delay = randf_range(0.0, 90.0)
					if type_roll < 0.8:
						mp.move_type = "horizontal"
						mp.move_range = randf_range(300.0, 800.0)
					else:
						mp.move_type = "vertical"
						mp.move_range = randf_range(300.0, 600.0)
					
					var col_shape: CollisionShape2D = mp.get_node("CollisionShape2D")
					col_shape.shape = col_shape.shape.duplicate()
					col_shape.shape.size = Vector2(w, plat_h)
					var spr: Sprite2D = mp.get_node("Sprite2D")
					spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
					spr.region_enabled = true
					spr.region_rect = Rect2(0, 0, w / 2.0, spr.texture.get_height())
					platforms_node.add_child(mp)
				
		current_y -= step_y
		debug_free_zones.append(Rect2(0, current_y, WORLD_WIDTH, step_y))

# ── Debug Draw ──────────────────────────────────────────────────────────────
func _process_debug_draw() -> void:
	if not show_debug: return
	queue_redraw()

func _draw() -> void:
	if not show_debug: return
	
	# Draw Free Zones
	var fzone_color := Color(1.0, 0.0, 1.0, 0.15) # Light purple
	for fz in debug_free_zones:
		draw_rect(fz, fzone_color)
		
	# Draw Platform Hitboxes
	var plat_color := Color(0.0, 1.0, 0.0, 0.4) # Green
	for p in platforms_node.get_children():
		if p is CollisionObject2D:
			for child in p.get_children():
				if child is CollisionShape2D and child.shape is RectangleShape2D:
					var shape := child.shape as RectangleShape2D
					var shape_tf: Transform2D = child.global_transform
					var r := Rect2(shape_tf.origin - shape.size / 2.0, shape.size)
					draw_rect(r, plat_color)
						
	# Draw Mobs Hitboxes
	var mob_color := Color(1.0, 0.0, 0.0, 0.4) # Red
	for e in enemies_node.get_children():
		# Try Area2Ds or CharacterBody2D
		for child in e.get_children():
			if child is CollisionShape2D and child.shape is RectangleShape2D:
				var r := Rect2(child.global_position - child.shape.size / 2.0, child.shape.size)
				draw_rect(r, mob_color)
			elif child is Area2D or child is StaticBody2D or child is AnimatableBody2D:
				for gc in child.get_children():
					if gc is CollisionShape2D and gc.shape is RectangleShape2D:
						var shape := gc.shape as RectangleShape2D
						var r := Rect2(gc.global_position - shape.size / 2.0, shape.size)
						draw_rect(r, mob_color)
			elif child is StaticBody2D or child is AnimatableBody2D:
				for gc in child.get_children():
					if gc is CollisionShape2D and gc.shape is RectangleShape2D:
						var r := Rect2(gc.global_position - gc.shape.size / 2.0, gc.shape.size)
						draw_rect(r, mob_color)
						
	# Player Hitbox
	if is_instance_valid(player):
		var p_color := Color(0.0, 0.0, 1.0, 0.4)
		for child in player.get_children():
			if child is CollisionShape2D and child.shape is RectangleShape2D:
				var r := Rect2(child.global_position - child.shape.size / 2.0, child.shape.size)
				draw_rect(r, p_color)

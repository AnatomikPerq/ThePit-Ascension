extends Node2D
## World — main game controller.
## Builds the level from a WorldProfile + seed, spawns enemies, runs the HUD
## and the in-run state machine. All coordinates are ×2 scaled from the legacy
## Pygame FINAL.py.

const CAMERA_BASE_OFFSET := Vector2(0, -120)
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const CONFETTI_BURST: BurstPreset = preload("res://data/fx/confetti.tres")

## Every number the world is built and paced from. One .tres per world.
@export var profile: WorldProfile
## 0 = roll a fresh seed. Setting a value before add_child reproduces a world
## exactly — the fingerprint harness does, and the multiplayer host will.
@export var world_seed: int = 0

var max_depth: float = 8000.0

# ── State ───────────────────────────────────────────────────────────────────
enum GameState {PLAYING, UPGRADE_MENU, GAME_OVER, VICTORY, PAUSED}
var state: int = GameState.PLAYING

var player: CharacterBody2D
var spawn_timer: float = 0.0
var current_spawn_interval: float = 2.0
var upgrade_milestones: Array[float] = []
var zone_milestones: Array[float] = []
var notification_timer: float = 0.0

var show_debug: bool = false
var debug_free_zones: Array[Rect2] = []

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

# HUD nodes built in code
var score_label: Label
var combo_label: Label
var progress_bar: ProgressBar
var ability_icons: Dictionary = {} # name -> Panel
var pause_overlay: ColorRect
const HEART_FULL_TEX: Texture2D = preload("res://assets/sprites/heart_full.png")
const HEART_EMPTY_TEX: Texture2D = preload("res://assets/sprites/heart_empty.png")
var _combo_tween: Tween


func _ready() -> void:
	max_depth = profile.max_depth()
	current_spawn_interval = profile.spawn_interval_start
	# Milestones trigger the upgrade menu once each as the player ascends past.
	upgrade_milestones.clear()
	for fraction in profile.upgrade_fractions:
		upgrade_milestones.append(max_depth * fraction)
	zone_milestones = profile.divider_ys()

	Game.new_run()
	Game.score_changed.connect(_on_score_changed)

	# World-space effects (bursts, popups, ghosts) spawn under this scene
	# and die with it.
	Fx.effects_root = self

	while world_seed == 0:
		world_seed = randi()
	var plan := WorldGenerator.generate(profile, world_seed)
	WorldBuilder.build(plan, profile.theme, platforms_node)
	debug_free_zones = plan.free_zones

	_spawn_player()
	_build_hp_bar()
	_build_hud_extras()
	_style_screens()
	_style_upgrade_menu()

	# Camera limits — keep within world bounds
	camera.limit_left = int(-profile.wall_thickness)
	camera.limit_right = int(profile.world_width + profile.wall_thickness)
	camera.limit_top = int(profile.camera_top_limit)
	camera.limit_bottom = int(max_depth + profile.camera_bottom_margin)
	# Offset player slightly below center so we see more above
	camera.offset = CAMERA_BASE_OFFSET
	_build_embers()

	$CanvasLayer/UpgradeMenu/DoubleJumpBtn.pressed.connect(_on_double_jump_chosen)
	$CanvasLayer/UpgradeMenu/StrikeBtn.pressed.connect(_on_strike_chosen)
	$CanvasLayer/UpgradeMenu/ShockwaveBtn.pressed.connect(_on_shockwave_chosen)

	# World should pause normally.
	self.process_mode = Node.PROCESS_MODE_INHERIT

	# Let the CanvasLayer (or a specific control) process while paused for menus
	$CanvasLayer.process_mode = Node.PROCESS_MODE_ALWAYS

	# Set background
	RenderingServer.set_default_clear_color(profile.theme.background_by_ascent.sample(0.0))


func _exit_tree() -> void:
	if Fx.effects_root == self:
		Fx.effects_root = null


func _process(delta: float) -> void:
	bg_time += delta
	_update_background()

	if state == GameState.GAME_OVER:
		if Input.is_action_just_pressed("jump"):
			restart()
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

	# Update camera to follow player (+ screen shake)
	camera.global_position = player.global_position
	camera.offset = CAMERA_BASE_OFFSET + Fx.get_shake_offset()

	_update_hud(delta)

	# Game logic
	if state == GameState.PLAYING:
		_check_milestones()
		_check_zones()
		_check_victory()

	if show_debug:
		queue_redraw()


# ── Background & atmosphere ─────────────────────────────────────────────────
func _update_background() -> void:
	if state == GameState.VICTORY:
		return
	var ascent := 0.0
	if is_instance_valid(player):
		ascent = clampf(1.0 - player.global_position.y / max_depth, 0.0, 1.0)
	# Sample the theme's palette by ascent progress.
	var c := profile.theme.background_by_ascent.sample(ascent)
	# Subtle slow "breathing" of the depths.
	c = c.lightened(0.04 * (0.5 + 0.5 * sin(bg_time * 0.35)))
	RenderingServer.set_default_clear_color(c)


func _build_embers() -> void:
	var p := CPUParticles2D.new()
	p.name = "Embers"
	p.amount = 70
	p.lifetime = 7.0
	p.preprocess = 6.0
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1150, 720)
	p.direction = Vector2.UP
	p.spread = 25.0
	p.gravity = Vector2(0, -25)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 45.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.55, 0.25, 0.0),
		Color(1.0, 0.55, 0.25, 0.30),
		Color(1.0, 0.4, 0.2, 0.22),
		Color(1.0, 0.4, 0.2, 0.0),
	])
	p.color_ramp = ramp
	camera.add_child(p)


# ── HUD ─────────────────────────────────────────────────────────────────────
func _build_hp_bar() -> void:
	for child in hp_bar.get_children():
		hp_bar.remove_child(child)
		child.queue_free()
	hp_bar.add_theme_constant_override("separation", 8)
	for i in range(player.max_health):
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(42, 36)
		heart.stretch_mode = TextureRect.STRETCH_SCALE
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.texture = HEART_FULL_TEX if i < player.health else HEART_EMPTY_TEX
		hp_bar.add_child(heart)


func _update_hp_display() -> void:
	var hearts := hp_bar.get_children()
	for i in range(hearts.size()):
		hearts[i].texture = HEART_FULL_TEX if i < player.health else HEART_EMPTY_TEX


func _build_hud_extras() -> void:
	# Vignette (behind all HUD text).
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.45),
	])
	var vtex := GradientTexture2D.new()
	vtex.gradient = grad
	vtex.fill = GradientTexture2D.FILL_RADIAL
	vtex.fill_from = Vector2(0.5, 0.5)
	vtex.fill_to = Vector2(0.5, 0.0)
	vtex.width = 512
	vtex.height = 512
	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = vtex
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(vignette)
	hud.move_child(vignette, 0)

	# Score / combo (top-left, under hearts).
	score_label = Label.new()
	score_label.name = "ScoreLabel"
	score_label.position = Vector2(20, 64)
	score_label.add_theme_font_size_override("font_size", 26)
	score_label.text = "SCORE 000000"
	hud.add_child(score_label)

	combo_label = Label.new()
	combo_label.name = "ComboLabel"
	combo_label.position = Vector2(20, 96)
	combo_label.size = Vector2(200, 34)
	combo_label.pivot_offset = Vector2(0, 17)
	combo_label.add_theme_font_size_override("font_size", 28)
	combo_label.visible = false
	hud.add_child(combo_label)

	# Ascent progress bar (right edge).
	progress_bar = ProgressBar.new()
	progress_bar.name = "AscentBar"
	progress_bar.anchor_left = 1.0
	progress_bar.anchor_right = 1.0
	progress_bar.anchor_top = 0.5
	progress_bar.anchor_bottom = 0.5
	progress_bar.offset_left = -44.0
	progress_bar.offset_right = -26.0
	progress_bar.offset_top = -300.0
	progress_bar.offset_bottom = 300.0
	progress_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.show_percentage = false
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.05, 0.03, 0.05, 0.7)
	sb_bg.set_border_width_all(2)
	sb_bg.border_color = Color(0.9, 0.6, 0.25, 0.5)
	sb_bg.set_corner_radius_all(4)
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = Color(0.95, 0.62, 0.2)
	sb_fill.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("background", sb_bg)
	progress_bar.add_theme_stylebox_override("fill", sb_fill)
	hud.add_child(progress_bar)

	var surface_label := Label.new()
	surface_label.text = "SURFACE"
	surface_label.anchor_left = 1.0
	surface_label.anchor_right = 1.0
	surface_label.anchor_top = 0.5
	surface_label.anchor_bottom = 0.5
	surface_label.offset_left = -110.0
	surface_label.offset_right = -10.0
	surface_label.offset_top = -336.0
	surface_label.offset_bottom = -308.0
	surface_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	surface_label.add_theme_font_size_override("font_size", 18)
	surface_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.35))
	hud.add_child(surface_label)

	# Ability icons (bottom-left).
	var icons := HBoxContainer.new()
	icons.name = "AbilityIcons"
	icons.anchor_top = 1.0
	icons.anchor_bottom = 1.0
	icons.offset_left = 20.0
	icons.offset_top = -92.0
	icons.offset_bottom = -20.0
	icons.add_theme_constant_override("separation", 12)
	hud.add_child(icons)
	for def in [["strike", "Z"], ["shockwave", "C"]]:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(72, 72)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.05, 0.08, 0.85)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.9, 0.6, 0.25, 0.8)
		sb.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", sb)
		var key_label := Label.new()
		key_label.text = def[1]
		key_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 34)
		panel.add_child(key_label)
		panel.visible = false
		icons.add_child(panel)
		ability_icons[def[0]] = panel

	# Pause overlay.
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	$CanvasLayer.add_child(pause_overlay)
	var pv := VBoxContainer.new()
	pv.anchor_left = 0.5
	pv.anchor_right = 0.5
	pv.anchor_top = 0.5
	pv.anchor_bottom = 0.5
	pv.offset_left = -400.0
	pv.offset_right = 400.0
	pv.offset_top = -80.0
	pv.offset_bottom = 80.0
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 16)
	pause_overlay.add_child(pv)
	var pt := Label.new()
	pt.text = "PAUSED"
	pt.add_theme_font_size_override("font_size", 72)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pt)
	var ph := Label.new()
	ph.text = "ESC — resume      R — restart      M — music"
	ph.add_theme_font_size_override("font_size", 24)
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.modulate = Color(1, 1, 1, 0.7)
	pv.add_child(ph)

	# FPS label (top right, under depth).
	var fps_label := Label.new()
	fps_label.name = "FPSLabel"
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.offset_left = -250.0
	fps_label.offset_right = -20.0
	fps_label.offset_top = 52.0
	fps_label.offset_bottom = 78.0
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.modulate = Color(1, 1, 1, 0.6)
	hud.add_child(fps_label)

	# Existing label styling.
	depth_label.add_theme_font_size_override("font_size", 26)
	depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skills_label.add_theme_font_size_override("font_size", 20)
	skills_label.position.y = 136.0
	notif_label.add_theme_font_size_override("font_size", 34)
	notif_label.add_theme_color_override("font_color", Color(0.98, 0.8, 0.3))
	notif_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	notif_label.add_theme_constant_override("outline_size", 8)
	flight_label.add_theme_font_size_override("font_size", 22)
	flight_label.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))


func _update_hud(delta: float) -> void:
	depth_label.text = "DEPTH: %d" % int(player.global_position.y)

	var skills_text := "Skills: "
	if player.has_double_jump:
		skills_text += "[WING] "
	if player.has_strike:
		skills_text += "[STRIKE] "
	if player.has_shockwave:
		skills_text += "[SHOCKWAVE] "
	if player.flying:
		skills_text += "[FLIGHT] "
	skills_label.text = skills_text
	flight_label.text = "FLIGHT MODE ACTIVE" if player.flying else ""

	# Ascent progress.
	var ascent := clampf(1.0 - player.global_position.y / max_depth, 0.0, 1.0)
	progress_bar.value = ascent * 100.0

	# Ability cooldown icons.
	if ability_icons.has("strike"):
		var icon: Panel = ability_icons["strike"]
		icon.visible = player.has_strike
		icon.modulate.a = 0.35 if not player.strike_cd_timer.is_stopped() else 1.0
	if ability_icons.has("shockwave"):
		var icon2: Panel = ability_icons["shockwave"]
		icon2.visible = player.has_shockwave
		icon2.modulate.a = 0.35 if not player.shockwave_cd_timer.is_stopped() else 1.0

	# Notification fade
	if notification_timer > 0.0:
		notification_timer -= delta
		if notification_timer <= 0.0:
			notif_label.text = ""

	var fps_node: Label = hud.get_node_or_null("FPSLabel")
	if fps_node:
		fps_node.text = "FPS: %d" % Engine.get_frames_per_second()


func _on_score_changed(score: int, combo: int) -> void:
	if score_label:
		score_label.text = "SCORE %06d" % score
	if combo_label == null:
		return
	if combo >= 2:
		combo_label.visible = true
		combo_label.text = "COMBO x%d" % combo
		var heat := clampf((combo - 2) / 8.0, 0.0, 1.0)
		combo_label.add_theme_color_override(
			"font_color", Color(1.0, lerpf(1.0, 0.45, heat), lerpf(1.0, 0.1, heat)))
		if _combo_tween and _combo_tween.is_valid():
			_combo_tween.kill()
		combo_label.scale = Vector2(1.35, 1.35)
		_combo_tween = create_tween()
		_combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.2)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		combo_label.visible = false


# ── Public API (used by UIInputHandler and the UI scenes) ───────────────────
## ESC. What it means depends on the state, and every state has an answer.
func cancel_pressed() -> void:
	match state:
		GameState.PLAYING:
			_pause_game()
		GameState.PAUSED:
			_resume_game()
		GameState.GAME_OVER, GameState.VICTORY:
			go_to_menu()


func toggle_debug() -> void:
	show_debug = not show_debug
	queue_redraw()


func is_choosing_upgrade() -> bool:
	return state == GameState.UPGRADE_MENU


## Index into the upgrade menu's four buttons, left to right.
func choose_upgrade(index: int) -> void:
	match index:
		0: _on_double_jump_chosen()
		1: _on_strike_chosen()
		2: _on_shockwave_chosen()
		3: _on_heal_chosen()


func show_notification(text: String) -> void:
	notif_label.text = text
	notification_timer = 3.0


func _check_milestones() -> void:
	for i in range(upgrade_milestones.size() - 1, -1, -1):
		if player.global_position.y < upgrade_milestones[i]:
			upgrade_milestones.remove_at(i)
			Game.add_score(500, player.global_position, Color(0.98, 0.8, 0.3))
			_show_upgrade_menu()
			break


func _check_zones() -> void:
	for i in range(zone_milestones.size() - 1, -1, -1):
		if player.global_position.y < zone_milestones[i]:
			zone_milestones.remove_at(i)
			var level := clampi(
				int((max_depth - player.global_position.y) / profile.level_height) + 1,
				1, profile.level_count)
			show_notification("LEVEL %d / %d" % [level, profile.level_count])
			Game.add_score(250)
			Audio.play(&"zone")
			break


func _check_victory() -> void:
	if player.global_position.y < profile.victory_y:
		state = GameState.VICTORY
		player.can_input = false
		_show_victory()


func _pause_game() -> void:
	state = GameState.PAUSED
	get_tree().paused = true
	pause_overlay.visible = true


func _resume_game() -> void:
	state = GameState.PLAYING
	get_tree().paused = false
	pause_overlay.visible = false


func _show_upgrade_menu() -> void:
	state = GameState.UPGRADE_MENU
	get_tree().paused = true
	upgrade_menu.visible = true
	Audio.play(&"upgrade")


func _on_double_jump_chosen() -> void:
	if not player.has_double_jump:
		player.has_double_jump = true
		show_notification("UNLOCKED: DOUBLE JUMP")
	else:
		show_notification("ALREADY OWNED (XP BONUS)")
		Game.add_score(300)
	_close_upgrade_menu()


func _on_strike_chosen() -> void:
	if not player.has_strike:
		player.has_strike = true
		show_notification("UNLOCKED: SIDEWAYS STRIKE")
	else:
		show_notification("ALREADY OWNED (XP BONUS)")
		Game.add_score(300)
	_close_upgrade_menu()


func _on_shockwave_chosen() -> void:
	if not player.has_shockwave:
		player.has_shockwave = true
		show_notification("UNLOCKED: SHOCKWAVE BLAST")
	else:
		show_notification("ALREADY OWNED (XP BONUS)")
		Game.add_score(300)
	_close_upgrade_menu()


func _on_heal_chosen() -> void:
	player.max_health += 1
	player.health = player.max_health
	_build_hp_bar()
	Audio.play(&"heal")
	show_notification("MAX HP +1, FULLY HEALED")
	_close_upgrade_menu()


func _close_upgrade_menu() -> void:
	upgrade_menu.visible = false
	state = GameState.PLAYING
	get_tree().paused = false
	Audio.play(&"ui_click")


# ── Menus & screens styling ─────────────────────────────────────────────────
func _style_upgrade_menu() -> void:
	# Panel look.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.04, 0.07, 0.96)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.95, 0.62, 0.2)
	sb.set_corner_radius_all(12)
	upgrade_menu.add_theme_stylebox_override("panel", sb)

	# Widen for a 4th option.
	upgrade_menu.offset_left = -570.0
	upgrade_menu.offset_right = 570.0

	var title: Label = upgrade_menu.get_node("Title")
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.8, 0.3))

	var heal_btn := Button.new()
	heal_btn.name = "HealBtn"
	heal_btn.text = "+1 MAX HP\nFULL HEAL\n(V)"
	upgrade_menu.add_child(heal_btn)
	heal_btn.pressed.connect(_on_heal_chosen)

	var buttons: Array[Button] = [
		upgrade_menu.get_node("DoubleJumpBtn") as Button,
		upgrade_menu.get_node("StrikeBtn") as Button,
		upgrade_menu.get_node("ShockwaveBtn") as Button,
		heal_btn,
	]
	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.12, 0.08, 0.12)
	btn_sb.set_border_width_all(2)
	btn_sb.border_color = Color(0.9, 0.6, 0.25, 0.6)
	btn_sb.set_corner_radius_all(10)
	var btn_hover: StyleBoxFlat = btn_sb.duplicate()
	btn_hover.bg_color = Color(0.22, 0.13, 0.10)
	btn_hover.border_color = Color(0.98, 0.8, 0.3)
	var btn_pressed: StyleBoxFlat = btn_sb.duplicate()
	btn_pressed.bg_color = Color(0.30, 0.18, 0.10)
	for i in buttons.size():
		var b := buttons[i]
		b.set_anchors_preset(Control.PRESET_TOP_LEFT)
		b.position = Vector2(40.0 + i * 270.0, 110.0)
		b.size = Vector2(250.0, 200.0)
		b.add_theme_stylebox_override("normal", btn_sb)
		b.add_theme_stylebox_override("hover", btn_hover)
		b.add_theme_stylebox_override("pressed", btn_pressed)
		b.add_theme_font_size_override("font_size", 22)

	var help: Label = upgrade_menu.get_node("HelpLabel")
	help.text = "Click to select or press Z, X, C, V"
	help.modulate = Color(1, 1, 1, 0.65)


func _style_screens() -> void:
	for screen: Control in [game_over_screen, victory_screen]:
		var title: Label = screen.get_node("Title") if screen.has_node("Title") else screen.get_node("GG")
		title.add_theme_font_size_override("font_size", 96)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.anchor_left = 0.5
		title.anchor_right = 0.5
		title.anchor_top = 0.5
		title.anchor_bottom = 0.5
		title.offset_left = -500.0
		title.offset_right = 500.0
		title.offset_top = -260.0
		title.offset_bottom = -140.0
		title.grow_horizontal = Control.GROW_DIRECTION_BOTH

		var sub: Label = screen.get_node("SubTitle")
		sub.add_theme_font_size_override("font_size", 26)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub.anchor_left = 0.5
		sub.anchor_right = 0.5
		sub.anchor_top = 0.5
		sub.anchor_bottom = 0.5
		sub.offset_left = -400.0
		sub.offset_right = 400.0
		sub.offset_top = -125.0
		sub.offset_bottom = -85.0
	var go_title: Label = game_over_screen.get_node("Title")
	go_title.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
	var gg: Label = victory_screen.get_node("GG")
	gg.add_theme_color_override("font_color", Color(0.98, 0.8, 0.3))

	# Stats label on both screens, filled when shown.
	for screen: Control in [game_over_screen, victory_screen]:
		var stats := Label.new()
		stats.name = "Stats"
		stats.anchor_left = 0.5
		stats.anchor_right = 0.5
		stats.anchor_top = 0.5
		stats.anchor_bottom = 0.5
		stats.offset_left = -350.0
		stats.offset_right = 350.0
		stats.offset_top = 70.0
		stats.offset_bottom = 220.0
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats.add_theme_font_size_override("font_size", 24)
		stats.modulate = Color(1, 1, 1, 0.85)
		screen.add_child(stats)


func _stats_text(new_record: bool) -> String:
	var depth_now := 0
	if is_instance_valid(player):
		depth_now = int(player.global_position.y)
	var text := "SCORE %d\nKILLS %d      MAX COMBO x%d\nDEPTH %d      TIME %s\n" % [
		Game.score, Game.kills, Game.max_combo, depth_now, Game.run_time_text(),
	]
	if new_record:
		text += "NEW RECORD!\n"
	else:
		text += "BEST %d\n" % Game.best_score
	return text + "\nESC — main menu"


func _show_victory() -> void:
	Game.add_score(2000)
	victory_screen.visible = true
	victory_screen.get_node("Stats").text = _stats_text(Game.finish_run())
	Audio.play(&"win")
	# Confetti around the player.
	for i in 10:
		var t := get_tree().create_timer(0.15 * i)
		t.timeout.connect(func() -> void:
			if is_instance_valid(player):
				var pos := player.global_position + Vector2(randf_range(-500, 500), randf_range(-450, 150))
				Fx.burst(pos, CONFETTI_BURST, Color.from_hsv(randf(), 0.8, 1.0))
		)


# ── Player ──────────────────────────────────────────────────────────────────
func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.global_position = Vector2(
		profile.world_width / 2.0, max_depth - profile.player_spawn_height)
	add_child(player)
	player.player_died.connect(_on_player_died)
	player.player_damaged.connect(_on_player_damaged)


func _on_player_died() -> void:
	state = GameState.GAME_OVER
	game_over_screen.visible = true
	game_over_screen.get_node("Stats").text = _stats_text(Game.finish_run())


func _on_player_damaged(_new_health: int) -> void:
	_update_hp_display()


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func go_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# ── Enemy Spawning ──────────────────────────────────────────────────────────

func _spawn_enemy() -> void:
	# Ascent progress: 0.0 at the bottom of the pit, 1.0 at the surface.
	var current_depth := maxf(0.0, minf(max_depth, player.global_position.y))
	var progress := 1.0 - (current_depth / max_depth)

	# Weighted roll over the profile's spawn table.
	var weights: Array[float] = []
	var total := 0.0
	for entry in profile.spawn_table:
		var w := lerpf(entry.weight_start, entry.weight_end, progress)
		weights.append(w)
		total += w
	if total <= 0.0:
		return

	var roll := randf() * total
	var chosen: SpawnEntry = profile.spawn_table.back()
	for i in profile.spawn_table.size():
		roll -= weights[i]
		if roll < 0.0:
			chosen = profile.spawn_table[i]
			break

	if chosen.max_alive > 0:
		var alive := 0
		for e in enemies_node.get_children():
			if e.is_in_group(chosen.group):
				alive += 1
		if alive >= chosen.max_alive:
			return # wait for the next timer tick

	var enemy: Node2D = chosen.scene.instantiate()
	if chosen.group != &"":
		enemy.add_to_group(chosen.group)
	enemies_node.add_child(enemy)
	enemy.global_position = _spawn_position(chosen)
	enemy.set_player_ref(player)


func _spawn_position(entry: SpawnEntry) -> Vector2:
	var player_y := player.global_position.y
	match entry.placement:
		SpawnEntry.Placement.WALL:
			var x := profile.wall_spawn_inset_left if randf() < 0.5 \
					else profile.world_width - profile.wall_spawn_inset_right
			return Vector2(x, player_y - entry.above_player_min)
		SpawnEntry.Placement.PLATFORM_BAND:
			# Needs solid ground: appear in the platform band near the player's
			# altitude instead of falling in from far above.
			return Vector2(
				randf_range(profile.spawn_margin_x, profile.world_width - profile.spawn_margin_x),
				player_y - randf_range(entry.above_player_min, entry.above_player_max))
		_: # SKY
			var y := maxf(player_y - entry.above_player_min, profile.spawn_ceiling_y)
			return Vector2(
				randf_range(profile.spawn_margin_x, profile.world_width - profile.spawn_margin_x),
				y)


# ── Debug Draw ──────────────────────────────────────────────────────────────
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

	# Player Hitbox
	if is_instance_valid(player):
		var p_color := Color(0.0, 0.0, 1.0, 0.4)
		for child in player.get_children():
			if child is CollisionShape2D and child.shape is RectangleShape2D:
				var r := Rect2(child.global_position - child.shape.size / 2.0, child.shape.size)
				draw_rect(r, p_color)

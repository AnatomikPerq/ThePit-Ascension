extends Node2D
## World — main game controller.
## Builds the level from a WorldProfile + seed, spawns enemies, drives the
## in-run state machine and feeds the HUD. All layout lives in scenes; all
## tuning numbers live in the profile. Coordinates are ×2 scaled from the
## legacy Pygame FINAL.py.

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

## peer_id -> avatar. The "player" group is how enemies discover targets;
## this dictionary is the authority for identity. Solo play is one entry.
var players: Dictionary[int, CharacterBody2D] = {}
## The avatar this machine steers: camera, HUD, input, end screens.
var player: CharacterBody2D

var spawn_timer: float = 0.0
var current_spawn_interval: float = 2.0
## Remaining milestone depths, per peer — each avatar earns its own upgrades
## and its own zone crossings.
var _upgrade_milestones: Dictionary[int, Array] = {}
var _zone_milestones: Dictionary[int, Array] = {}

var show_debug: bool = false
var debug_free_zones: Array[Rect2] = []

var bg_time: float = 0.0

# ── Node references ─────────────────────────────────────────────────────────
@onready var camera: Camera2D = $Camera2D
@onready var platforms_node: Node2D = $Platforms
@onready var enemies_node: Node2D = $Enemies
@onready var trampolines_node: Node2D = $Trampolines
@onready var hud: RunHud = $CanvasLayer/HUD
@onready var upgrade_menu: UpgradeMenu = $CanvasLayer/UpgradeMenu
@onready var pause_overlay: ColorRect = $CanvasLayer/PauseOverlay
@onready var game_over_screen: EndScreen = $CanvasLayer/GameOverScreen
@onready var victory_screen: EndScreen = $CanvasLayer/VictoryScreen


func _ready() -> void:
	max_depth = profile.max_depth()
	current_spawn_interval = profile.spawn_interval_start

	Game.new_run()
	Game.score_changed.connect(hud.on_score_changed)
	upgrade_menu.chosen.connect(choose_upgrade)

	# World-space effects (bursts, popups, ghosts) spawn under this scene
	# and die with it.
	Fx.effects_root = self

	while world_seed == 0:
		world_seed = randi()
	var plan := WorldGenerator.generate(profile, world_seed)
	WorldBuilder.build(plan, profile.theme, platforms_node)
	debug_free_zones = plan.free_zones

	_spawn_player()
	hud.build_hp_bar(player.max_health, player.health)

	# Camera limits — keep within world bounds
	camera.limit_left = int(-profile.wall_thickness)
	camera.limit_right = int(profile.world_width + profile.wall_thickness)
	camera.limit_top = int(profile.camera_top_limit)
	camera.limit_bottom = int(max_depth + profile.camera_bottom_margin)
	# Offset player slightly below center so we see more above
	camera.offset = CAMERA_BASE_OFFSET

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
			if current_spawn_interval > profile.spawn_interval_min:
				current_spawn_interval -= profile.spawn_interval_step

	# Update camera to follow player (+ screen shake)
	camera.global_position = player.global_position
	camera.offset = CAMERA_BASE_OFFSET + Fx.get_shake_offset()

	hud.update(player, max_depth, delta)

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
	hud.show_notification(text)


func _check_milestones() -> void:
	for peer_id in players:
		var avatar := players[peer_id]
		if not is_instance_valid(avatar):
			continue
		var milestones: Array = _upgrade_milestones[peer_id]
		for i in range(milestones.size() - 1, -1, -1):
			if avatar.global_position.y < milestones[i]:
				milestones.remove_at(i)
				Game.add_score(500, avatar.global_position, Color(0.98, 0.8, 0.3), peer_id)
				# The choice is each player's own input; only the local
				# player's milestone opens this machine's menu.
				if peer_id == Game.local_peer_id:
					_show_upgrade_menu()
				break


func _check_zones() -> void:
	for peer_id in players:
		var avatar := players[peer_id]
		if not is_instance_valid(avatar):
			continue
		var milestones: Array = _zone_milestones[peer_id]
		for i in range(milestones.size() - 1, -1, -1):
			if avatar.global_position.y < milestones[i]:
				milestones.remove_at(i)
				Game.add_score(250, Vector2.INF, Color.WHITE, peer_id)
				if peer_id == Game.local_peer_id:
					var level := clampi(
						int((max_depth - avatar.global_position.y) / profile.level_height) + 1,
						1, profile.level_count)
					show_notification("LEVEL %d / %d" % [level, profile.level_count])
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
	hud.build_hp_bar(player.max_health, player.health)
	Audio.play(&"heal")
	show_notification("MAX HP +1, FULLY HEALED")
	_close_upgrade_menu()


func _close_upgrade_menu() -> void:
	upgrade_menu.visible = false
	state = GameState.PLAYING
	get_tree().paused = false
	Audio.play(&"ui_click")


# ── End of run ──────────────────────────────────────────────────────────────
func _stats_text(new_record: bool) -> String:
	var depth_now := 0
	if is_instance_valid(player):
		depth_now = int(player.global_position.y)
	var run := Game.local_run()
	var text := "SCORE %d\nKILLS %d      MAX COMBO x%d\nDEPTH %d      TIME %s\n" % [
		run.score, run.kills, run.max_combo, depth_now, Game.run_time_text(),
	]
	if new_record:
		text += "NEW RECORD!\n"
	else:
		text += "BEST %d\n" % Game.best_score
	return text + "\nESC — main menu"


func _show_victory() -> void:
	Game.add_score(2000)
	victory_screen.show_with(_stats_text(Game.finish_run()))
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
	player = _spawn_avatar(Game.local_peer_id)
	player.player_died.connect(_on_player_died)
	player.player_damaged.connect(_on_player_damaged)


## One avatar, its identity and its personal milestone ladders. Multiplayer
## calls this once per peer; solo calls it once.
func _spawn_avatar(peer_id: int) -> CharacterBody2D:
	var avatar: CharacterBody2D = PLAYER_SCENE.instantiate()
	avatar.peer_id = peer_id
	avatar.global_position = Vector2(
		profile.world_width / 2.0, max_depth - profile.player_spawn_height)
	add_child(avatar)
	players[peer_id] = avatar

	var upgrades: Array[float] = []
	for fraction in profile.upgrade_fractions:
		upgrades.append(max_depth * fraction)
	_upgrade_milestones[peer_id] = upgrades
	_zone_milestones[peer_id] = profile.divider_ys()
	return avatar


func _on_player_died() -> void:
	state = GameState.GAME_OVER
	game_over_screen.show_with(_stats_text(Game.finish_run()))


func _on_player_damaged(new_health: int) -> void:
	hud.update_hp(new_health)


func restart() -> void:
	Router.restart_run()


func go_to_menu() -> void:
	Router.to_menu()


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

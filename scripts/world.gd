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
## Set on every machine when the session's run ends (someone reached the
## surface). Stops the host simulation and further milestones.
var _session_over: bool = false

# ── Node references ─────────────────────────────────────────────────────────
@onready var camera: Camera2D = $Camera2D
@onready var platforms_node: Node2D = $Platforms
@onready var enemies_node: Node2D = $Enemies
@onready var trampolines_node: Node2D = $Trampolines
@onready var hud: RunHud = $CanvasLayer/HUD
@onready var upgrade_menu: UpgradeMenu = $CanvasLayer/UpgradeMenu
@onready var pause_overlay: PauseOverlay = $CanvasLayer/PauseOverlay
@onready var game_over_screen: EndScreen = $CanvasLayer/GameOverScreen
@onready var victory_screen: EndScreen = $CanvasLayer/VictoryScreen


func _ready() -> void:
	max_depth = profile.max_depth()
	current_spawn_interval = profile.spawn_interval_start

	Game.new_run(Net.session_peers)
	Game.score_changed.connect(hud.on_score_changed)
	upgrade_menu.chosen.connect(choose_upgrade)
	# Every way out of a run, from every screen that offers one, lands on the
	# same three methods.
	pause_overlay.resume_pressed.connect(_resume_game)
	pause_overlay.restart_pressed.connect(restart)
	pause_overlay.menu_pressed.connect(go_to_menu)
	for screen: EndScreen in [game_over_screen, victory_screen]:
		screen.restart_pressed.connect(restart)
		screen.menu_pressed.connect(go_to_menu)
	if Net.active:
		Net.peers_changed.connect(_prune_disconnected)
		Net.session_closed.connect(_on_session_closed)
		# "Press SPACE to Restart" is a solo promise; in a session the end
		# screen's own hint line says who may do what.
		game_over_screen.get_node(^"SubTitle").text = ""

	# World-space effects (bursts, popups, ghosts) spawn under this scene
	# and die with it.
	Fx.effects_root = self

	while world_seed == 0:
		world_seed = randi()
	var plan := WorldGenerator.generate(profile, world_seed)
	WorldBuilder.build(plan, profile.theme, platforms_node)
	debug_free_zones = plan.free_zones

	_spawn_players()
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

	# World simulation: spawning, milestones, victory. On the host this keeps
	# running even when the local avatar is dead — the other players are not.
	if _should_simulate():
		spawn_timer += delta
		if spawn_timer >= current_spawn_interval:
			spawn_timer = 0.0
			_spawn_enemy()
			# Increase difficulty gradually (lower interval allowed)
			if current_spawn_interval > profile.spawn_interval_min:
				current_spawn_interval -= profile.spawn_interval_step
		_check_milestones()
		_check_zones()
		_check_victory()

	if state == GameState.GAME_OVER:
		if not Net.active and Input.is_action_just_pressed("jump"):
			restart()
		return

	if not is_instance_valid(player):
		return

	# Update camera to follow player (+ screen shake)
	camera.global_position = player.global_position
	camera.offset = CAMERA_BASE_OFFSET + Fx.get_shake_offset()

	hud.update(player, max_depth, delta)

	if show_debug:
		queue_redraw()


## Solo: the run state machine gates everything. Session: the host simulates
## as long as anyone is still climbing and nobody has won yet.
func _should_simulate() -> bool:
	if not Net.is_sim_authority():
		return false
	if Net.active:
		return not _session_over and _any_avatar_alive()
	return state == GameState.PLAYING


func _any_avatar_alive() -> bool:
	for avatar in players.values():
		if is_instance_valid(avatar):
			return true
	return false


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


## Is this avatar's position something to judge progress by? A puppet reports
## where it is from its own machine, and its node path is the same in every run,
## so right after a restart the host can still be hearing about the run that
## just ended. Anything that awards or ends must ask this first.
func _reports_this_run(avatar: CharacterBody2D) -> bool:
	return is_instance_valid(avatar) and avatar.run_seed == world_seed


func _check_milestones() -> void:
	for peer_id in players:
		var avatar := players[peer_id]
		if not _reports_this_run(avatar):
			continue
		var milestones: Array = _upgrade_milestones[peer_id]
		for i in range(milestones.size() - 1, -1, -1):
			if avatar.global_position.y < milestones[i]:
				milestones.remove_at(i)
				Game.add_score(500, avatar.global_position, Color(0.98, 0.8, 0.3), peer_id)
				# The choice is each player's own input; the menu opens on the
				# machine of whoever earned it.
				if peer_id == Game.local_peer_id:
					_show_upgrade_menu()
				elif Net.active:
					_offer_upgrade.rpc_id(peer_id)
				break


@rpc("authority", "call_remote", "reliable")
func _offer_upgrade() -> void:
	_show_upgrade_menu()


func _check_zones() -> void:
	for peer_id in players:
		var avatar := players[peer_id]
		if not _reports_this_run(avatar):
			continue
		var milestones: Array = _zone_milestones[peer_id]
		for i in range(milestones.size() - 1, -1, -1):
			if avatar.global_position.y < milestones[i]:
				milestones.remove_at(i)
				Game.add_score(250, Vector2.INF, Color.WHITE, peer_id)
				var level := clampi(
					int((max_depth - avatar.global_position.y) / profile.level_height) + 1,
					1, profile.level_count)
				if peer_id == Game.local_peer_id:
					_zone_notice(level)
				elif Net.active:
					_zone_notice.rpc_id(peer_id, level)
				break


@rpc("authority", "call_remote", "reliable")
func _zone_notice(level: int) -> void:
	show_notification("LEVEL %d / %d" % [level, profile.level_count])
	Audio.play(&"zone")


func _check_victory() -> void:
	if Net.active:
		for peer_id in players:
			var avatar := players[peer_id]
			if _reports_this_run(avatar) and avatar.global_position.y < profile.victory_y:
				# Host-authoritative: the surface bonus lands before the
				# broadcast so every end screen shows the final number.
				Game.add_score(2000, Vector2.INF, Color.WHITE, peer_id)
				_end_session.rpc(peer_id)
				return
		return
	if player.global_position.y < profile.victory_y:
		state = GameState.VICTORY
		player.can_input = false
		_show_victory()


## The shared run is over: somebody reached the surface. In co-op that is a
## win for the team; in a race it is a win for exactly one machine.
@rpc("authority", "call_local", "reliable")
func _end_session(winner_peer: int) -> void:
	_session_over = true
	if is_instance_valid(player):
		player.can_input = false
	var won := winner_peer == Game.local_peer_id
	if Net.mode == Net.Mode.RACE and not won:
		state = GameState.GAME_OVER
		game_over_screen.get_node(^"Title").text = "RACE OVER"
		game_over_screen.show_with(
			"PLAYER %d WON THE RACE\n\n" % winner_peer + _stats_text(Game.finish_run()))
	else:
		state = GameState.VICTORY
		var text := _stats_text(Game.finish_run())
		if not won:
			text = "PLAYER %d REACHED THE SURFACE FIRST\n\n" % winner_peer + text
		victory_screen.show_with(text)
		Audio.play(&"win")
		_confetti()


## In a session one machine's menu must never freeze the others, so the tree
## only actually pauses solo. The overlay still shows, and the local avatar
## stops listening to input while it is up.
func _pause_game() -> void:
	state = GameState.PAUSED
	if Net.active:
		if is_instance_valid(player):
			player.can_input = false
	else:
		get_tree().paused = true
	pause_overlay.visible = true


func _resume_game() -> void:
	state = GameState.PLAYING
	if Net.active:
		if is_instance_valid(player) and not _session_over:
			player.can_input = true
	else:
		get_tree().paused = false
	pause_overlay.visible = false


func _show_upgrade_menu() -> void:
	state = GameState.UPGRADE_MENU
	if not Net.active:
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
	if not Net.active:
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
		text += "NEW RECORD!"
	else:
		text += "BEST %d" % Game.best_score
	# The way out used to be spelled out here; the end screen's own buttons and
	# hint line carry it now, for every mode.
	return text


func _show_victory() -> void:
	Game.add_score(2000)
	victory_screen.show_with(_stats_text(Game.finish_run()))
	Audio.play(&"win")
	_confetti()


## Confetti around the local player. Cosmetic, so it never replicates.
## Connected as a method, not a lambda: a SceneTreeTimer outliving this world
## drops a method connection safely, while a lambda would call into a freed
## instance.
func _confetti() -> void:
	for i in 10:
		get_tree().create_timer(0.15 * i).timeout.connect(_confetti_burst)


func _confetti_burst() -> void:
	if is_instance_valid(player):
		var pos := player.global_position + Vector2(randf_range(-500, 500), randf_range(-450, 150))
		Fx.burst(pos, CONFETTI_BURST, Color.from_hsv(randf(), 0.8, 1.0))


# ── Player ──────────────────────────────────────────────────────────────────
## Every machine builds the same avatar set from the session roster (solo:
## just the local player), spread around the spawn point. Deterministic, so
## node paths agree on every peer and the synchronizers line up.
func _spawn_players() -> void:
	var roster := Net.session_peers if Net.active else ([Game.local_peer_id] as Array[int])
	for i in roster.size():
		var avatar := _spawn_avatar(roster[i], i - (roster.size() - 1) * 0.5)
		if roster[i] == Game.local_peer_id:
			player = avatar
			player.player_died.connect(_on_player_died)
			player.player_damaged.connect(_on_player_damaged)


## One avatar, its identity and its personal milestone ladders.
func _spawn_avatar(peer_id: int, slot_offset: float = 0.0) -> CharacterBody2D:
	var avatar: CharacterBody2D = PLAYER_SCENE.instantiate()
	avatar.name = "Avatar%d" % peer_id
	avatar.peer_id = peer_id
	avatar.set_multiplayer_authority(peer_id)
	# Only for the avatar this machine steers. A puppet keeps -1 until its owner
	# says which run it is reporting from — see Player.run_seed.
	if peer_id == Game.local_peer_id:
		avatar.run_seed = world_seed
	avatar.global_position = Vector2(
		profile.world_width / 2.0 + slot_offset * 90.0,
		max_depth - profile.player_spawn_height)
	add_child(avatar)
	players[peer_id] = avatar

	var upgrades: Array[float] = []
	for fraction in profile.upgrade_fractions:
		upgrades.append(max_depth * fraction)
	_upgrade_milestones[peer_id] = upgrades
	_zone_milestones[peer_id] = profile.divider_ys()
	return avatar


## A peer dropped mid-run: remove its avatar everywhere.
func _prune_disconnected() -> void:
	if not Net.active:
		return
	for peer_id in players.keys():
		if peer_id == Game.local_peer_id or peer_id in Net.session_peers:
			continue
		var avatar: CharacterBody2D = players[peer_id]
		if is_instance_valid(avatar):
			avatar.queue_free()
		players.erase(peer_id)


func _on_session_closed(_reason: String) -> void:
	Router.to_menu()


func _on_player_died() -> void:
	state = GameState.GAME_OVER
	game_over_screen.show_with(_stats_text(Game.finish_run()))


func _on_player_damaged(new_health: int) -> void:
	hud.update_hp(new_health)


## R, the pause menu button and the end screens all end here. In a session
## there is one shared run, so a restart is the host putting everyone back at
## the bottom of a fresh pit — it used to be silently ignored, which left
## rejoining as the only way to play a second round.
func restart() -> void:
	if not Net.active:
		Router.restart_run()
		return
	if Net.is_host():
		Net.restart_session()
	else:
		show_notification("ONLY THE HOST CAN RESTART")


func go_to_menu() -> void:
	if Net.active:
		Net.leave()
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
	# Position before add_child so the spawn packet carries it, and readable
	# names (add_child(_, true)) so the MultiplayerSpawner can mirror it.
	enemy.position = _spawn_position(chosen)
	enemies_node.add_child(enemy, true)
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

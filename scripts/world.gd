extends Node2D
## World — main game controller.
## Builds the level from a WorldProfile + seed, spawns enemies, drives the
## in-run state machine and feeds the HUD. All layout lives in scenes; all
## tuning numbers live in the profile. Coordinates are ×2 scaled from the
## legacy Pygame FINAL.py.

## The shared run is over — somebody reached the surface, or everybody went down.
## Emitted on every machine, but only a dedicated server listens: its room manager
## needs to know to stop calling the room RUNNING and to put it back in its lobby
## after `rooms/end_to_lobby_seconds`. Without it a finished room would stay
## "running" for the rest of the server's life.
signal run_ended

## How far above the avatar the camera looks. The climb is upward, so the useful
## half of the screen is the half above you.
const CAMERA_BASE_OFFSET := Vector2(0, -180)
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const CONFETTI_BURST: BurstPreset = preload("res://data/fx/confetti.tres")

## How close a climber has to be to a body before the pick-up is offered. The
## host allows some slack on top when it checks, because it is judging two
## replicated positions rather than the two the presser could see.
const REVIVE_RANGE: float = 260.0
const REVIVE_HOST_SLACK: float = 1.6
## What a milestone pays once there is nothing left to unlock.
const SPENT_MILESTONE_BONUS: int = 500

## Every number the world is built and paced from. One .tres per world.
@export var profile: WorldProfile
## 0 = roll a fresh seed. Setting a value before add_child reproduces a world
## exactly — the fingerprint harness does, and the multiplayer host will.
@export var world_seed: int = 0

## The room this world is: who is in it, what each of them picked, which mode.
## Set BEFORE add_child, exactly like world_seed — by Router from Net on a
## player's machine, by the room manager on a dedicated server.
##
## Nothing below reads the session fields off the Net autoload any more. Net
## describes THIS MACHINE's connection, and a machine can be in one room; a
## server is in none and hosts several, so "the" session is a question only a
## world can answer.
var session: NetSession = NetSession.new()

## A world with nobody looking at it. A dedicated server sets this before
## add_child, and it turns off exactly one thing: presentation. No camera, no
## HUD, no upgrade menu, no particles, no positional audio, no ledger registered
## with Game. The simulation underneath is untouched — the server runs the same
## world the players do, which is the whole reason the server is a build of this
## project rather than a reimplementation of it.
var simulation_only: bool = false

var max_depth: float = 16000.0

# ── State ───────────────────────────────────────────────────────────────────
enum GameState {PLAYING, UPGRADE_MENU, GAME_OVER, VICTORY, PAUSED}
var state: int = GameState.PLAYING

## peer_id -> avatar. The "player" group is how enemies discover targets;
## this dictionary is the authority for identity. Solo play is one entry.
var players: Dictionary[int, CharacterBody2D] = {}
## The avatar this machine steers: camera, HUD, input, end screens. Null for a
## peer that joined to watch rather than climb.
var player: CharacterBody2D

var spawn_timer: float = 0.0
var current_spawn_interval: float = 2.0
## Remaining milestone depths, per peer — each avatar earns its own upgrades
## and its own zone crossings.
var _upgrade_milestones: Dictionary[int, Array] = {}
var _zone_milestones: Dictionary[int, Array] = {}
## What the LOCAL climber has not taken yet, in menu order. Each upgrade leaves
## the pool when it is taken, so the menu never offers the same thing twice; one
## left is granted without asking and none left pays score instead.
##
## Only the local pool exists here. The host detects the milestone and tells the
## peer that earned it; what that peer is still missing is that peer's business.
var _my_upgrades: Array[UpgradeDef] = []
## Host only: bodies a revive has already been granted for, waiting for the
## owning machine to say it stood up. See _resolve_revive.
var _revive_granted: Dictionary[int, bool] = {}

var show_debug: bool = false
var debug_free_zones: Array[Rect2] = []

var bg_time: float = 0.0
## Set on every machine when the session's run ends (someone reached the
## surface, or everybody went down). Stops the host simulation and further
## milestones.
var _session_over: bool = false

# ── Node references ─────────────────────────────────────────────────────────
## This room's score, kills and combo. One per world — see RunLedger for why it
## is not on the Game autoload any more.
@onready var run: RunLedger = $Run
@onready var camera: Camera2D = $Camera2D
@onready var platforms_node: Node2D = $Platforms
@onready var enemies_node: Node2D = $Enemies
@onready var trampolines_node: Node2D = $Trampolines
@onready var spectator: SpectatorCam = $Spectator
@onready var hud: RunHud = $CanvasLayer/HUD
@onready var upgrade_menu: UpgradeMenu = $CanvasLayer/UpgradeMenu
@onready var pause_overlay: PauseOverlay = $CanvasLayer/PauseOverlay
@onready var game_over_screen: EndScreen = $CanvasLayer/GameOverScreen
@onready var victory_screen: EndScreen = $CanvasLayer/VictoryScreen
## The server administration panel, on its own layer above everything. It refuses
## to open unless this machine is on a dedicated server and holds the right, so
## it costs a hidden node and nothing else in solo play. A moderator should not
## have to leave the pit to deal with somebody who is in it.
@onready var admin_panel: CanvasLayer = $AdminPanel


func _ready() -> void:
	max_depth = profile.max_depth()
	current_spawn_interval = profile.spawn_interval_start

	run.new_run(_playing_peers())
	upgrade_menu.chosen.connect(choose_upgrade)
	# Every way out of a run, from every screen that offers one, lands on the
	# same three methods.
	pause_overlay.resume_pressed.connect(_resume_game)
	pause_overlay.restart_pressed.connect(restart)
	pause_overlay.menu_pressed.connect(go_to_menu)
	for screen: EndScreen in [game_over_screen, victory_screen]:
		screen.restart_pressed.connect(restart)
		screen.menu_pressed.connect(go_to_menu)
	if session.active and not simulation_only:
		Net.peers_changed.connect(prune_disconnected)
		Net.session_closed.connect(_on_session_closed)
		# "Press SPACE to Restart" is a solo promise; in a session the end
		# screen's own hint line says who may do what.
		game_over_screen.get_node(^"SubTitle").text = ""

	if not simulation_only:
		run.score_changed.connect(hud.on_score_changed)
		# The facade the rest of the machine asks "how is the run going": this
		# world's ledger while this world is the one being looked at.
		Game.ledger = run
		# World-space effects (bursts, popups, ghosts, rubble, fireballs) spawn
		# under this scene and die with it — and so do positional sounds, which
		# need to be in the 2D world for distance to mean anything.
		Fx.effects_root = self
		Audio.world_root = self

	while world_seed == 0:
		world_seed = randi()
	var plan := WorldGenerator.generate(profile, world_seed)
	WorldBuilder.build(plan, profile.theme, platforms_node)
	debug_free_zones = plan.free_zones

	_spawn_players()
	if simulation_only:
		_strip_presentation()
		return

	if is_instance_valid(player):
		hud.build_hp_bar(player.max_health, player.health)
	else:
		# Nobody to climb with: this peer joined to watch.
		_enter_spectator(Vector2(profile.world_width / 2.0, max_depth - 400.0))
	# Before the first frame, so anything that goes off on frame one is judged
	# from where the avatar actually is rather than from the world origin.
	Fx.listener_position = _eye_position()

	# Camera limits — keep within world bounds
	camera.limit_left = int(-profile.wall_thickness)
	camera.limit_right = int(profile.world_width + profile.wall_thickness)
	camera.limit_top = int(profile.camera_top_limit)
	camera.limit_bottom = int(max_depth + profile.camera_bottom_margin)
	# Offset player well below centre so most of the screen is the climb ahead
	# rather than the drop behind.
	camera.offset = CAMERA_BASE_OFFSET
	# On the avatar from frame one. Without reset_smoothing() the camera starts
	# at the world origin — the top-left corner of the shaft — and eases across,
	# which reads as spawning off to one side.
	camera.global_position = _eye_position()
	camera.reset_smoothing()

	# Set background
	RenderingServer.set_default_clear_color(profile.theme.background_by_ascent.sample(0.0))


## Everything a room on a dedicated server has no use for. Turned off rather
## than deleted: the node paths under this world are the addresses the
## replication layer uses, and a server whose tree has a different shape from a
## client's is a server whose packets land nowhere.
##
## The camera is the exception that has to stay awake — it is where `Fx` thinks
## this machine's eyes are, and the 2D audio listener. On a server neither is
## consulted, but leaving the node in place keeps `_update_camera` honest rather
## than making it a branch.
func _strip_presentation() -> void:
	var ui := get_node_or_null(^"CanvasLayer") as CanvasLayer
	if ui != null:
		ui.visible = false
		ui.process_mode = Node.PROCESS_MODE_DISABLED
	camera.enabled = false
	spectator.process_mode = Node.PROCESS_MODE_DISABLED
	admin_panel.visible = false
	admin_panel.process_mode = Node.PROCESS_MODE_DISABLED


func _exit_tree() -> void:
	if Fx.effects_root == self:
		Fx.effects_root = null
	if Audio.world_root == self:
		Audio.world_root = null
	Game.release_ledger(run)


func _process(delta: float) -> void:
	if not simulation_only:
		bg_time += delta
		_update_background()

	# World simulation: spawning, milestones, victory. On the authority this
	# keeps running even when the local avatar is dead — the other players are
	# not. It is also the ONLY half of this function a dedicated server runs.
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
	# Outside the block above on purpose: a wipe is exactly the case where
	# nobody is left to simulate for.
	_check_wipe()

	# Below this line is presentation and local input. A server has neither.
	if simulation_only:
		return

	_update_camera(delta)
	_update_revive_prompts()

	if state == GameState.GAME_OVER:
		if not session.active and Input.is_action_just_pressed("jump"):
			restart()
		return

	if spectator.active:
		hud.update_spectator(spectator.status_text())
		return

	if not is_instance_valid(player):
		return

	if session.active and state == GameState.PLAYING \
			and Input.is_action_just_pressed(&"revive"):
		_try_revive()

	hud.update(player, max_depth, delta)

	if show_debug:
		queue_redraw()


## The camera is also this machine's ear and eye: Fx measures how far away an
## event was from here, and the Camera2D is the 2D audio listener, so both kinds
## of distance come from the same place — whatever this machine is looking at.
func _update_camera(delta: float) -> void:
	if spectator.active:
		spectator.step(delta)
	elif is_instance_valid(player):
		camera.global_position = player.global_position
	camera.offset = CAMERA_BASE_OFFSET + Fx.get_shake_offset()
	Fx.listener_position = camera.global_position


func _eye_position() -> Vector2:
	if is_instance_valid(player):
		return player.global_position
	return camera.global_position


## Solo: the run state machine gates everything. Session: the host simulates
## as long as anyone is still climbing and nobody has won yet.
func _should_simulate() -> bool:
	if not Net.is_sim_authority():
		return false
	if session.active:
		return not _session_over and _any_avatar_alive()
	return state == GameState.PLAYING


## A body lying on a platform is not an avatar that is alive — it is one waiting
## for somebody to spend a heart on it.
func _any_avatar_alive() -> bool:
	for avatar in players.values():
		if is_instance_valid(avatar) and not avatar.is_downed:
			return true
	return false


# ── Background & atmosphere ─────────────────────────────────────────────────
func _update_background() -> void:
	if state == GameState.VICTORY:
		return
	var eye := _eye_position()
	var ascent := clampf(1.0 - eye.y / max_depth, 0.0, 1.0)
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


## F8. Silently does nothing off a dedicated server, or without the right.
func toggle_admin_panel() -> void:
	if admin_panel.visible:
		admin_panel.close()
	else:
		admin_panel.open()


func toggle_debug() -> void:
	show_debug = not show_debug
	queue_redraw()


func is_choosing_upgrade() -> bool:
	return state == GameState.UPGRADE_MENU


## Index into the buttons the upgrade menu is showing, left to right. Those are
## whatever the local climber has not taken yet, so the index means nothing on
## its own — it is only ever read against the same list the menu was built from.
func choose_upgrade(index: int) -> void:
	if index < 0 or index >= _my_upgrades.size():
		return
	_apply_upgrade(_my_upgrades[index])
	_close_upgrade_menu()


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
		if not _reports_this_run(avatar) or avatar.is_downed:
			continue
		var milestones: Array = _upgrade_milestones[peer_id]
		for i in range(milestones.size() - 1, -1, -1):
			if avatar.global_position.y < milestones[i]:
				milestones.remove_at(i)
				run.add_score(500, avatar.global_position, Color(0.98, 0.8, 0.3), peer_id)
				# The choice is each player's own input; the menu opens on the
				# machine of whoever earned it.
				if peer_id == Game.local_peer_id:
					_show_upgrade_menu()
				elif session.active:
					_offer_upgrade.rpc_id(peer_id)
				break


@rpc("authority", "call_remote", "reliable")
func _offer_upgrade() -> void:
	_show_upgrade_menu()


func _check_zones() -> void:
	for peer_id in players:
		var avatar := players[peer_id]
		if not _reports_this_run(avatar) or avatar.is_downed:
			continue
		var milestones: Array = _zone_milestones[peer_id]
		for i in range(milestones.size() - 1, -1, -1):
			if avatar.global_position.y < milestones[i]:
				milestones.remove_at(i)
				run.add_score(250, Vector2.INF, Color.WHITE, peer_id)
				var level := clampi(
					int((max_depth - avatar.global_position.y) / profile.level_height) + 1,
					1, profile.level_count)
				if peer_id == Game.local_peer_id:
					_zone_notice(level)
				elif session.active:
					_zone_notice.rpc_id(peer_id, level)
				break


@rpc("authority", "call_remote", "reliable")
func _zone_notice(level: int) -> void:
	show_notification("LEVEL %d / %d" % [level, profile.level_count])
	Audio.play(&"zone")


func _check_victory() -> void:
	if session.active:
		for peer_id in players:
			var avatar := players[peer_id]
			if _reports_this_run(avatar) and not avatar.is_downed \
					and avatar.global_position.y < profile.victory_y:
				# Host-authoritative: the surface bonus lands before the
				# broadcast so every end screen shows the final number.
				run.add_score(2000, Vector2.INF, Color.WHITE, peer_id)
				session.broadcast(self, &"_end_session", [peer_id])
				return
		return
	if player.global_position.y < profile.victory_y:
		state = GameState.VICTORY
		player.can_input = false
		_show_victory()


## Everybody is on the floor and nobody is left to pick anyone up. The host
## calls it; nothing else can, because nothing else can see every avatar.
func _check_wipe() -> void:
	if not session.active or _session_over or not Net.is_sim_authority():
		return
	if players.is_empty() or _any_avatar_alive():
		return
	session.broadcast(self, &"_end_session_wiped")


@rpc("authority", "call_local", "reliable")
func _end_session_wiped() -> void:
	if _session_over:
		return
	_session_over = true
	run_ended.emit()
	if simulation_only:
		return
	_leave_spectator()
	state = GameState.GAME_OVER
	game_over_screen.get_node(^"Title").text = "EVERYBODY IS DOWN"
	game_over_screen.show_with(_stats_text(Game.finish_run()))


## The shared run is over: somebody reached the surface. In co-op that is a
## win for the team; in a race it is a win for exactly one machine.
@rpc("authority", "call_local", "reliable")
func _end_session(winner_peer: int) -> void:
	_session_over = true
	run_ended.emit()
	if simulation_only:
		return
	_leave_spectator()
	if is_instance_valid(player):
		player.can_input = false
	var won := winner_peer == Game.local_peer_id
	if session.is_versus() and not won:
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
	if session.active:
		if is_instance_valid(player):
			player.can_input = false
	else:
		get_tree().paused = true
	pause_overlay.visible = true


func _resume_game() -> void:
	state = GameState.PLAYING
	if session.active:
		if is_instance_valid(player) and not _session_over and not player.is_downed:
			player.can_input = true
	else:
		get_tree().paused = false
	pause_overlay.visible = false


# ── Upgrades ────────────────────────────────────────────────────────────────
## A milestone was crossed by the local climber. What happens depends on what
## they have left: several to choose from opens the menu, exactly one is granted
## without asking (there is no choice to make), and none pays score.
func _show_upgrade_menu() -> void:
	if not is_instance_valid(player):
		return
	if _my_upgrades.is_empty():
		run.add_score(SPENT_MILESTONE_BONUS, player.global_position, Color(0.98, 0.8, 0.3))
		show_notification("EVERYTHING UNLOCKED  ·  +%d" % SPENT_MILESTONE_BONUS)
		Audio.play(&"upgrade")
		return
	if _my_upgrades.size() == 1:
		# Nothing to choose between. It still gets the sound the menu would have
		# had, so the milestone is not silently swallowed.
		Audio.play(&"upgrade")
		_apply_upgrade(_my_upgrades[0])
		return
	state = GameState.UPGRADE_MENU
	if not session.active:
		get_tree().paused = true
	upgrade_menu.open(_my_upgrades)
	Audio.play(&"upgrade")


func _apply_upgrade(def: UpgradeDef) -> void:
	if def == null or not is_instance_valid(player):
		return
	_my_upgrades.erase(def)
	match def.effect:
		UpgradeDef.Effect.EXTRA_JUMP:
			player.max_jumps += 1
		UpgradeDef.Effect.ATTACK:
			player.has_attack = true
		UpgradeDef.Effect.SHOCKWAVE:
			player.has_shockwave = true
		UpgradeDef.Effect.RANGED:
			player.has_ranged = true
		UpgradeDef.Effect.MAX_HP:
			player.max_health += 1
			player.health = player.max_health
			hud.build_hp_bar(player.max_health, player.health)
			Audio.play(&"heal")
	show_notification("UNLOCKED: %s" % def.title)


func _close_upgrade_menu() -> void:
	upgrade_menu.visible = false
	if state == GameState.UPGRADE_MENU:
		state = GameState.PLAYING
		if not session.active:
			get_tree().paused = false
	Audio.play(&"ui_click")


# ── Reviving (multiplayer) ──────────────────────────────────────────────────
## Every machine decides for itself which bodies its own climber is standing
## close enough to pick up. Nothing about the sign crosses the wire.
func _update_revive_prompts() -> void:
	if not session.active:
		return
	var can_pay: bool = is_instance_valid(player) and not player.is_downed \
			and player.health > 1 and state == GameState.PLAYING
	for peer_id in players:
		var avatar := players[peer_id]
		if not is_instance_valid(avatar):
			continue
		if not avatar.is_downed:
			_revive_granted.erase(peer_id)
		avatar.set_revive_prompt(can_pay and avatar.is_downed \
				and avatar != player \
				and avatar.global_position.distance_to(player.global_position) <= REVIVE_RANGE)


## The nearest body this machine is currently offering to pick up.
func _revive_target() -> CharacterBody2D:
	if not is_instance_valid(player) or player.is_downed or player.health <= 1:
		return null
	var best: CharacterBody2D = null
	var best_distance := REVIVE_RANGE
	for peer_id in players:
		var avatar := players[peer_id]
		if not is_instance_valid(avatar) or not avatar.is_downed or avatar == player:
			continue
		var d := avatar.global_position.distance_to(player.global_position)
		if d <= best_distance:
			best_distance = d
			best = avatar
	return best


func _try_revive() -> void:
	var body := _revive_target()
	if body == null:
		return
	# The host owns consequences, so it is the one that decides a revive
	# happened — otherwise two climbers reaching the same body on the same frame
	# both pay a heart for one pick-up.
	if Net.is_host():
		_resolve_revive(Game.local_peer_id, body.peer_id)
	else:
		_request_revive.rpc_id(1, body.peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_revive(target_peer: int) -> void:
	if not Net.is_host():
		return
	_resolve_revive(multiplayer.get_remote_sender_id(), target_peer)


## Host only. Judged from replicated state, with slack on the distance: the
## presser saw two positions on their own screen and the host is looking at two
## slightly older ones.
func _resolve_revive(reviver_peer: int, target_peer: int) -> void:
	if _session_over:
		return
	var body: CharacterBody2D = players.get(target_peer)
	var reviver: CharacterBody2D = players.get(reviver_peer)
	if not _reports_this_run(body) or not _reports_this_run(reviver):
		return
	if not body.is_downed or reviver.is_downed or reviver.health <= 1:
		return
	if body.global_position.distance_to(reviver.global_position) \
			> REVIVE_RANGE * REVIVE_HOST_SLACK:
		return
	# `is_downed` clears on the body's OWN machine and takes a few frames to
	# arrive back here, so without this latch two climbers reaching the same body
	# on the same frame would both be charged for one pick-up. It is dropped
	# again the moment that avatar is seen standing (or goes down afresh).
	if _revive_granted.get(target_peer, false):
		return
	_revive_granted[target_peer] = true
	_ask_to_revive(body)
	_ask_to_pay(reviver)


## Health belongs to the machine steering the avatar, so both halves of a revive
## are requests to that machine — which the host may itself be.
func _ask_to_revive(body: CharacterBody2D) -> void:
	if body.is_multiplayer_authority():
		session.broadcast(body, &"stand_up")
	else:
		body.rpc_id(body.get_multiplayer_authority(), &"remote_revive")


func _ask_to_pay(reviver: CharacterBody2D) -> void:
	if reviver.is_multiplayer_authority():
		session.broadcast(reviver, &"pay_revive")
	else:
		reviver.rpc_id(reviver.get_multiplayer_authority(), &"remote_pay_revive")


# ── Spectating ──────────────────────────────────────────────────────────────
func _enter_spectator(at: Vector2) -> void:
	if spectator.active:
		return
	spectator.begin(self, camera, at)
	hud.enter_spectator()


func _leave_spectator() -> void:
	if not spectator.active:
		return
	spectator.end()
	hud.exit_spectator()
	if is_instance_valid(player):
		hud.build_hp_bar(player.max_health, player.health)


# ── End of run ──────────────────────────────────────────────────────────────
func _stats_text(new_record: bool) -> String:
	var mine := run.local_run()
	if mine == null:
		# A peer that joined to watch has no run of its own to report.
		return "TIME %s" % run.run_time_text()
	var depth_now := 0
	if is_instance_valid(player):
		depth_now = int(player.global_position.y)
	var text := "SCORE %d\nKILLS %d      MAX COMBO x%d\nDEPTH %d      TIME %s\n" % [
		mine.score, mine.kills, mine.max_combo, depth_now, run.run_time_text(),
	]
	if new_record:
		text += "NEW RECORD!"
	else:
		text += "BEST %d" % Game.best_score
	# The way out used to be spelled out here; the end screen's own buttons and
	# hint line carry it now, for every mode.
	return text


func _show_victory() -> void:
	run.add_score(2000)
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
	var at := _eye_position()
	var pos := at + Vector2(randf_range(-500, 500), randf_range(-450, 150))
	Fx.burst(pos, CONFETTI_BURST, Color.from_hsv(randf(), 0.8, 1.0))


# ── Player ──────────────────────────────────────────────────────────────────
## Which climber a peer picked. Null means "watching", which is a real answer:
## that peer gets no avatar and no run of its own.
func _character_for(peer_id: int) -> CharacterDef:
	if not session.active:
		return Game.character_def()
	var id: StringName = session.characters.get(peer_id, CharacterRoster.SPECTATOR)
	if id == CharacterRoster.SPECTATOR:
		return null
	return Game.roster.resolve(id)


## The session roster minus its spectators, in roster order. Solo is one entry.
func _playing_peers() -> Array[int]:
	if not session.active:
		return [Game.local_peer_id] as Array[int]
	var out: Array[int] = []
	for peer_id in session.peers:
		if _character_for(peer_id) != null:
			out.append(peer_id)
	return out


## Every machine builds the same avatar set from the session roster (solo:
## just the local player), spread around the spawn point. Deterministic, so
## node paths agree on every peer and the synchronizers line up.
func _spawn_players() -> void:
	var roster := _playing_peers()
	for i in roster.size():
		var avatar := _spawn_avatar(roster[i], i - (roster.size() - 1) * 0.5)
		if roster[i] == Game.local_peer_id:
			player = avatar
			player.player_died.connect(_on_player_died)
			player.player_damaged.connect(_on_player_damaged)
			player.player_downed.connect(_on_player_downed)
			player.player_revived.connect(_on_player_revived)


## One avatar, its identity and its personal milestone ladders.
func _spawn_avatar(peer_id: int, slot_offset: float = 0.0) -> CharacterBody2D:
	var avatar: CharacterBody2D = PLAYER_SCENE.instantiate()
	avatar.name = "Avatar%d" % peer_id
	avatar.peer_id = peer_id
	# Before add_child, so the character is in place when _ready() reads it.
	var def := _character_for(peer_id)
	if def != null:
		avatar.character = def
	avatar.set_multiplayer_authority(peer_id)
	# Only for the avatar this machine steers. A puppet keeps -1 until its owner
	# says which run it is reporting from — see Player.run_seed.
	if peer_id == Game.local_peer_id:
		avatar.run_seed = world_seed
		_my_upgrades.clear()
		if def != null:
			_my_upgrades.assign(def.upgrades)
	avatar.global_position = Vector2(
		profile.world_width / 2.0 + slot_offset * 90.0,
		max_depth - profile.player_spawn_height)
	# Before add_child, so the very first packet about this avatar is already
	# addressed to this room and to nobody else. See NetSession.scope().
	session.scope(avatar)
	add_child(avatar)
	players[peer_id] = avatar

	var upgrades: Array[float] = []
	for fraction in profile.upgrade_fractions:
		upgrades.append(max_depth * fraction)
	_upgrade_milestones[peer_id] = upgrades
	_zone_milestones[peer_id] = profile.divider_ys()
	return avatar


## A peer dropped mid-run: remove its avatar. Driven by `Net` on a player's
## machine and called directly by the room manager on a dedicated server, which
## is why it is public — a server watches its own socket, not this world's idea
## of one.
func prune_disconnected() -> void:
	if not session.active:
		return
	for peer_id in players.keys():
		if peer_id == Game.local_peer_id or peer_id in session.peers:
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


## Out of hearts in a session. The run is not over — the body is lying on a
## platform waiting for a teammate — so the camera comes off it and this machine
## watches the pit until somebody spends a heart.
func _on_player_downed() -> void:
	_enter_spectator(player.global_position)
	show_notification("YOU ARE DOWN — SOMEONE CAN STILL PICK YOU UP")


func _on_player_revived() -> void:
	_leave_spectator()
	show_notification("BACK ON YOUR FEET")


func _on_player_damaged(new_health: int) -> void:
	hud.update_hp(new_health)


## R, the pause menu button and the end screens all end here. In a session
## there is one shared run, so a restart is the host putting everyone back at
## the bottom of a fresh pit — it used to be silently ignored, which left
## rejoining as the only way to play a second round.
func restart() -> void:
	if not session.active:
		Router.restart_run()
		return
	if Hub.on_server():
		# On a dedicated server it is the room's decision, and who may make it is
		# `rooms/who_may_restart`. The server answers with a notice if not.
		Hub.ask(&"request_restart")
		return
	if Net.is_host():
		Net.restart_session()
	else:
		show_notification("ONLY THE HOST CAN RESTART")


## The way out of a run. On a dedicated server that means leaving the ROOM and
## going back to the browser — the connection, the account and the chat all
## survive it. Everywhere else it means ending the session.
func go_to_menu() -> void:
	if Hub.on_server():
		Hub.ask(&"request_leave")
		Router.to_server_lobby()
		return
	if session.active:
		Net.leave()
	Router.to_menu()


# ── Enemy Spawning ──────────────────────────────────────────────────────────
## Whose altitude the spawner works from. The local avatar whenever there is
## one, which is every case that existed before spectators did; a host that
## joined to watch has to pick somebody, and the climber nearest the surface is
## the one the pit should be keeping busy.
func _spawn_reference() -> CharacterBody2D:
	if is_instance_valid(player) and not player.is_downed:
		return player
	var best: CharacterBody2D = null
	for avatar in players.values():
		if not is_instance_valid(avatar) or avatar.is_downed:
			continue
		if best == null or avatar.global_position.y < best.global_position.y:
			best = avatar
	return best


func _spawn_enemy() -> void:
	var reference := _spawn_reference()
	if reference == null:
		return
	# Ascent progress: 0.0 at the bottom of the pit, 1.0 at the surface.
	var current_depth := maxf(0.0, minf(max_depth, reference.global_position.y))
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
	enemy.position = _spawn_position(chosen, reference.global_position.y)
	session.scope(enemy)
	enemies_node.add_child(enemy, true)
	enemy.set_player_ref(reference)


func _spawn_position(entry: SpawnEntry, player_y: float) -> Vector2:
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

extends Node
## Screenshots every UI surface into a directory, for eyeballing:
##
##   godot --path . tools/ui_check.tscn -- <out_dir>
##
## NOT a gate and NOT deterministic: embers drift, the title pulses, the world
## behind the HUD depends on the seed's platforms being on screen. Use it to
## see that a layout change did what you meant, not to diff pixels.
##
## It deliberately avoids _show_victory()/_on_player_died(): those call
## Game.finish_run(), which can overwrite the developer's real best score.

var _out_dir: String = "user://ui_check"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# Shoot the same climber every time, whoever this machine last played.
	Game.selected_character = &"cyn"

	var menu: Node = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _frames(20)
	await _shot("menu.png")
	# The same panel serves the menu and the lobby, so it is shot once, here.
	menu.get_node(^"CharacterSelect").open()
	await _frames(20)
	await _shot("characters.png")
	menu.free()

	# The one door out of the main menu. Given long enough for both discovery
	# paths to answer — the LAN scan alone runs for two and a half seconds — so
	# that running this with a directory and a server up shows the populated
	# list, and running it with neither shows the empty state honestly.
	var browser: Node = load("res://scenes/ui/MultiplayerMenu.tscn").instantiate()
	get_tree().root.add_child(browser)
	await _frames(200)
	await _shot("multiplayer.png")
	browser.free()

	var lobby: Node = load("res://scenes/Lobby.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await _frames(10)
	await _shot("lobby.png")
	lobby.free()

	# The dedicated server's two client surfaces. The lobby is shot with nobody
	# connected, which is the state it is in for the half-second before the room
	# list lands — and the state that is hardest to notice looking wrong.
	var connect_screen: Node = load("res://scenes/ui/ServerConnect.tscn").instantiate()
	get_tree().root.add_child(connect_screen)
	await _frames(10)
	await _shot("server_connect.png")
	connect_screen.free()

	var server_lobby: Node = load("res://scenes/ui/ServerLobby.tscn").instantiate()
	get_tree().root.add_child(server_lobby)
	await _frames(10)
	await _shot("server_lobby.png")
	server_lobby.free()

	var world: Node = load("res://scenes/World.tscn").instantiate()
	world.world_seed = 20260728
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _frames(30)
	await _shot("hud.png")

	world.cancel_pressed()
	await _frames(5)
	await _shot("pause.png")
	world.cancel_pressed()
	await _frames(2)

	world._show_upgrade_menu()
	await _frames(5)
	await _shot("upgrade.png")
	world.choose_upgrade(3) # heal: also exercises the button flow + HP rebuild
	await _frames(5)
	# One taken, three left: the menu only ever offers what is still missing.
	world._show_upgrade_menu()
	await _frames(5)
	await _shot("upgrade_partial.png")
	world.choose_upgrade(0)
	await _frames(5)

	# Cyn's strike, three moments apart. It is one drawing spun and scaled by an
	# AnimationPlayer, so a still of it says nothing — the strip is the point.
	world.player.has_attack = true
	world.player._try_strike()
	await _frames(3)
	await _shot("strike_1.png")
	await _frames(5)
	await _shot("strike_2.png")
	await _frames(6)
	await _shot("strike_3.png")
	await _frames(20)

	# What a downed player sees while they wait to be picked up. The prompt over
	# the body is shot with it, because that sign is the whole interaction, and
	# after its appear animation has settled rather than halfway through it.
	world.player.set_revive_prompt(true)
	world._enter_spectator(world.player.global_position + Vector2(0, -300))
	world.hud.update_spectator(world.spectator.status_text())
	await _frames(45)
	await _shot("spectator.png")
	world._leave_spectator()
	world.player.set_revive_prompt(false)
	await _frames(5)

	world.game_over_screen.show_with(world._stats_text(false))
	await _frames(5)
	await _shot("game_over.png")
	world.game_over_screen.visible = false

	world.victory_screen.show_with(world._stats_text(true))
	await _frames(5)
	await _shot("victory.png")
	world.free()

	await _shoot_tessa()

	print("ui_check: wrote 16 captures to ", _out_dir)
	get_tree().quit(0)


## A second run as Tessa, for the two things only she does: the blade, and the
## pistol. Both are spawned by hand rather than pressed, because a headless-ish
## harness has no hands.
func _shoot_tessa() -> void:
	Game.selected_character = &"tessa"
	var world: Node = load("res://scenes/World.tscn").instantiate()
	world.world_seed = 20260728
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _frames(20)

	var tessa: CharacterBody2D = world.player
	tessa.has_attack = true
	tessa.has_ranged = true
	await _shot("tessa_hud.png")

	tessa._try_strike()
	await _frames(3)
	await _shot("tessa_sword_1.png")
	await _frames(4)
	await _shot("tessa_sword_2.png")
	await _frames(20)

	tessa._try_shoot()
	await _frames(2)
	await _shot("tessa_shot_1.png")
	await _frames(8)
	await _shot("tessa_shot_2.png")
	world.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_dir.path_join(file_name))
	if err != OK:
		push_error("ui_check: could not write %s (error %d)" % [file_name, err])
		get_tree().quit(1)

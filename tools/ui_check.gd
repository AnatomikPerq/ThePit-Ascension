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

	var menu: Node = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _frames(20)
	await _shot("menu.png")
	menu.free()

	var lobby: Node = load("res://scenes/Lobby.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await _frames(10)
	await _shot("lobby.png")
	lobby.free()

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

	world.game_over_screen.show_with(world._stats_text(false))
	await _frames(5)
	await _shot("game_over.png")
	world.game_over_screen.visible = false

	world.victory_screen.show_with(world._stats_text(true))
	await _frames(5)
	await _shot("victory.png")

	print("ui_check: wrote 7 captures to ", _out_dir)
	get_tree().quit(0)


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

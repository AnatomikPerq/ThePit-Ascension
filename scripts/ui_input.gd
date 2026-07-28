extends Node
## UIInputHandler — global hotkeys that must work even while the tree is
## paused (menus). Attached under World/CanvasLayer with PROCESS_MODE_ALWAYS.

var world: Node2D


func _ready() -> void:
	world = get_parent().get_parent() # Parent is CanvasLayer, its parent is World
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Music toggle
		if event.physical_keycode == KEY_M:
			var enabled: bool = Audio.toggle_music()
			if world.state == world.GameState.PLAYING:
				world._show_notification("MUSIC ON" if enabled else "MUSIC OFF")
			get_viewport().set_input_as_handled()

		# Pause Menu Toggle / back to main menu from end screens
		if event.physical_keycode == KEY_ESCAPE:
			if world.state == world.GameState.PLAYING:
				world._pause_game()
				get_viewport().set_input_as_handled()
			elif world.state == world.GameState.PAUSED:
				world._resume_game()
				get_viewport().set_input_as_handled()
			elif world.state in [world.GameState.GAME_OVER, world.GameState.VICTORY]:
				world.go_to_menu()
				get_viewport().set_input_as_handled()

		# Upgrade Menu Hotkeys
		if world.state == world.GameState.UPGRADE_MENU:
			if event.physical_keycode == KEY_Z:
				world._on_double_jump_chosen()
				get_viewport().set_input_as_handled()
			elif event.physical_keycode == KEY_X:
				world._on_strike_chosen()
				get_viewport().set_input_as_handled()
			elif event.physical_keycode == KEY_C:
				world._on_shockwave_chosen()
				get_viewport().set_input_as_handled()
			elif event.physical_keycode == KEY_V:
				world._on_heal_chosen()
				get_viewport().set_input_as_handled()

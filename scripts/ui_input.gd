extends Node

var world: Node2D

func _ready() -> void:
	world = get_parent().get_parent() # Parent is CanvasLayer, its parent is World
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Pause Menu Toggle
		if event.physical_keycode == KEY_ESCAPE:
			if world.state == world.GameState.PLAYING:
				world._pause_game()
				get_viewport().set_input_as_handled()
			elif world.state == world.GameState.PAUSED:
				world._resume_game()
				get_viewport().set_input_as_handled()

		# Upgrade Menu Hotkeys
		if world.state == world.GameState.UPGRADE_MENU:
			if event.physical_keycode == KEY_Z:
				world._on_double_jump_chosen()
				get_viewport().set_input_as_handled()
			elif event.physical_keycode == KEY_X:
				world._on_strike_chosen()
				get_viewport().set_input_as_handled()

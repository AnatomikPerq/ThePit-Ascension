extends Control
## Main menu behavior. The whole layout — embers, title, buttons, help — is
## authored in MainMenu.tscn; this script wires the buttons, fills in the best
## score and pulses the title.

@onready var title: Label = $UI/Title
@onready var best_label: Label = $UI/BestScore
@onready var character_btn: Button = $UI/CharacterBtn
@onready var character_select: CharacterSelect = $CharacterSelect


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.07, 0.02, 0.03))
	if Game.best_score > 0:
		best_label.text = "BEST SCORE  %d" % Game.best_score
		best_label.visible = true
	$UI/StartBtn.pressed.connect(_start_game)
	character_btn.pressed.connect(character_select.open)
	character_select.closed.connect(_refresh_character)
	$UI/MultiplayerBtn.pressed.connect(Router.to_lobby)
	$UI/QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	_refresh_character()
	_pulse_title()


func _refresh_character() -> void:
	character_btn.text = "CHARACTER: %s" % Game.character_def().display_name


func _pulse_title() -> void:
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(title, "modulate", Color(1.25, 1.1, 1.0), 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title, "modulate", Color.WHITE, 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _unhandled_input(event: InputEvent) -> void:
	# Named actions, not raw physical keycodes. The menu used to match
	# event.physical_keycode directly, which meant these keys could not be
	# rebound and could not be driven by anything outside a real keyboard —
	# the end-to-end suite could boot the menu and then had no way to leave it.
	# ui_accept and ui_cancel are Godot's built-ins, so a gamepad works too.
	if event.is_echo() or character_select.visible:
		return
	if event.is_action_pressed(&"ui_accept"):
		_start_game()
	elif event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
	elif event.is_action_pressed(&"music_toggle"):
		Audio.toggle_music()
	else:
		return
	get_viewport().set_input_as_handled()


func _start_game() -> void:
	Audio.play(&"ui_confirm")
	Router.start_run()

extends Control
## Main menu — title screen with rising embers, best score and start/quit.
## The whole layout is built in code; MainMenu.tscn is just the root Control.

var _title: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.07, 0.02, 0.03))
	_build_embers()
	_build_ui()
	_pulse_title()


func _build_embers() -> void:
	var p := CPUParticles2D.new()
	p.amount = 90
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1000, 40)
	p.position = Vector2(960, 1120)
	p.direction = Vector2.UP
	p.spread = 15.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 140.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.75, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.6, 0.25, 0.0),
		Color(1.0, 0.6, 0.25, 0.5),
		Color(0.9, 0.3, 0.15, 0.3),
		Color(0.9, 0.3, 0.15, 0.0),
	])
	p.color_ramp = ramp
	add_child(p)


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -320.0
	box.offset_right = 320.0
	box.offset_top = -330.0
	box.offset_bottom = 330.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	_title = Label.new()
	_title.text = "THE PIT"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 130)
	_title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.2))
	_title.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.02))
	_title.add_theme_constant_override("outline_size", 16)
	box.add_child(_title)

	var subtitle := Label.new()
	subtitle.text = "A S C E N S I O N"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 40)
	subtitle.add_theme_color_override("font_color", Color(0.98, 0.8, 0.3))
	box.add_child(subtitle)

	if Game.best_score > 0:
		var best := Label.new()
		best.text = "BEST SCORE  %d" % Game.best_score
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		best.add_theme_font_size_override("font_size", 26)
		best.modulate = Color(1, 1, 1, 0.8)
		box.add_child(best)

	box.add_child(_spacer(30))

	var start_btn := _make_button("START  (SPACE)")
	start_btn.pressed.connect(_start_game)
	box.add_child(start_btn)

	var quit_btn := _make_button("QUIT  (ESC)")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit_btn)

	box.add_child(_spacer(24))

	var help := Label.new()
	help.text = "A/D — move      SPACE — jump      S — dash down\nZ — strike      C — shockwave      M — music"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 22)
	help.modulate = Color(1, 1, 1, 0.55)
	box.add_child(help)

	var flavor := Label.new()
	flavor.text = "You start at depth 8000. The surface does not expect you."
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.add_theme_font_size_override("font_size", 18)
	flavor.modulate = Color(1, 1, 1, 0.35)
	box.add_child(flavor)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 64)
	b.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.06, 0.08)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.9, 0.5, 0.2, 0.7)
	sb.set_corner_radius_all(10)
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = Color(0.25, 0.10, 0.08)
	sb_hover.border_color = Color(0.98, 0.8, 0.3)
	var sb_pressed: StyleBoxFlat = sb.duplicate()
	sb_pressed.bg_color = Color(0.35, 0.15, 0.08)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	return b


func _pulse_title() -> void:
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_title, "modulate", Color(1.25, 1.1, 1.0), 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_title, "modulate", Color.WHITE, 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_SPACE, KEY_ENTER:
				_start_game()
			KEY_ESCAPE:
				get_tree().quit()
			KEY_M:
				Audio.toggle_music()


func _start_game() -> void:
	Audio.play(&"ui_confirm")
	get_tree().change_scene_to_file("res://scenes/World.tscn")

extends Node2D
## One floating score popup ("+300  x3"). The rise, the fade and the
## self-free all live in the scene's AnimationPlayer; the script only
## fills in the text.


func setup(text: String, color: Color, font_size: int) -> void:
	var label: Label = $Label
	label.text = text
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_font_size_override(&"font_size", font_size)

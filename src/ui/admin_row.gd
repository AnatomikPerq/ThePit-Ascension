extends HBoxContainer
## One line in the admin panel: two labels and up to three buttons.
##
## Deliberately generic. Players, rooms, bans and accounts are four lists of
## "something, some detail about it, and two or three things you can do to it",
## and four row scenes would be four places to change when the theme moves. The
## buttons are authored and then hidden — nothing is constructed at runtime.

@onready var primary: Label = $Primary
@onready var secondary: Label = $Secondary
@onready var buttons: Array[Button] = [$Actions/A, $Actions/B, $Actions/C]


## `actions` is an array of [label, callable] pairs, at most three. Anything past
## what is given is hidden, so a row with one button looks like a row with one
## button rather than a row with two empty ones.
func show_row(left: String, right: String, actions: Array) -> void:
	primary.text = left
	secondary.text = right
	for i in buttons.size():
		var button := buttons[i]
		if i >= actions.size():
			button.visible = false
			continue
		var pair: Array = actions[i]
		button.visible = true
		button.text = pair[0]
		button.pressed.connect(pair[1])


## Colour the row without every caller reaching into the label. Used for what is
## worth noticing at a glance: a muted player, a running room, a permanent ban.
func tint(colour: Color) -> void:
	primary.add_theme_color_override(&"font_color", colour)

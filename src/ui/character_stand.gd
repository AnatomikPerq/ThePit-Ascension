class_name CharacterStand
extends Button
## One plinth in the character-select screen: the climber standing on it, their
## name, and the numbers that make them different from the one next to them.
##
## Everything about how it looks is authored in CharacterStand.tscn. This pours
## a CharacterDef into it and answers whether it is the one currently picked.

var def: CharacterDef

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var name_label: Label = $Name
@onready var blurb_label: Label = $Blurb
@onready var stat_values: Label = $StatValues
@onready var unlocks_label: Label = $Unlocks
@onready var selected_frame: Panel = $Selected


func fill(character: CharacterDef) -> void:
	def = character
	name_label.text = character.display_name
	name_label.add_theme_color_override(&"font_color", character.accent)
	blurb_label.text = character.blurb
	stat_values.text = _values_text(character)
	unlocks_label.text = _unlocks_text(character)
	sprite.sprite_frames = character.frames
	# Held on the first standing frame rather than played: a menu is for reading.
	sprite.animation = &"standing"
	sprite.frame = 0
	sprite.stop()


func set_selected(on: bool) -> void:
	selected_frame.visible = on
	# The unpicked stand stands back rather than disappearing: you are choosing
	# between two climbers, not looking at one.
	modulate = Color.WHITE if on else Color(0.62, 0.62, 0.68)


## The right-hand column, lined up against the fixed labels authored in the
## scene. Jump height is relative to Cyn, who is the 100%.
func _values_text(character: CharacterDef) -> String:
	var jumps := str(character.base_jumps)
	var upgraded := character.base_jumps + _extra_jumps(character)
	if upgraded > character.base_jumps:
		jumps += "  →  %d" % upgraded
	return "%d\n%s\n%d%%" % [character.max_health, jumps, roundi(character.jump_scale * 100.0)]


## What the climb will hand this character, one per line, in the order the
## upgrade menu will offer them.
func _unlocks_text(character: CharacterDef) -> String:
	var lines: Array[String] = []
	for upgrade in character.upgrades:
		if upgrade != null:
			lines.append(upgrade.title)
	return "\n".join(lines) if not lines.is_empty() else "—"


func _extra_jumps(character: CharacterDef) -> int:
	var n := 0
	for upgrade in character.upgrades:
		if upgrade != null and upgrade.effect == UpgradeDef.Effect.EXTRA_JUMP:
			n += 1
	return n

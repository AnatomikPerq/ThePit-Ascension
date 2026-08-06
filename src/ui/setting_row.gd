extends VBoxContainer
## One server setting in the admin panel, with the editor its type deserves.
##
## Three editors are authored in the scene and one is shown: a toggle for a
## boolean, a dropdown for a setting with a fixed set of choices, a text field
## for everything else. Which one appears is decided by the schema the server
## sent, not by a list here — so a setting added to `ServerSettings` appears in
## this panel with the right control and no UI change at all.

@onready var key_label: Label = $Head/KeyLabel
@onready var restart_label: Label = $Head/RestartLabel
@onready var description: Label = $Description
@onready var text_edit: LineEdit = $Editor/TextEdit
@onready var choice_edit: OptionButton = $Editor/ChoiceEdit
@onready var toggle_edit: Button = $Editor/ToggleEdit
@onready var apply_btn: Button = $Editor/ApplyBtn

var _key: String = ""
var _on_apply: Callable


func show_setting(row: Dictionary, writable: bool, on_apply: Callable) -> void:
	_key = str(row.get("key", ""))
	_on_apply = on_apply

	key_label.text = _key
	description.text = str(row.get("description", ""))
	description.visible = description.text != ""
	restart_label.visible = bool(row.get("restart", false))

	var choices: Array = row.get("choices", [])
	var is_bool := int(row.get("type", TYPE_STRING)) == TYPE_BOOL
	var secret := bool(row.get("secret", false))
	text_edit.visible = not is_bool and choices.is_empty()
	choice_edit.visible = not is_bool and not choices.is_empty()
	toggle_edit.visible = is_bool

	if is_bool:
		toggle_edit.button_pressed = str(row.get("raw", "false")) == "true"
		_label_toggle()
		toggle_edit.toggled.connect(func(_on: bool) -> void: _label_toggle())
	elif not choices.is_empty():
		for choice: Variant in choices:
			choice_edit.add_item(str(choice))
		var current := choices.find(str(row.get("raw", "")))
		if current >= 0:
			choice_edit.select(current)
	else:
		# A secret's value is never sent, so the field starts empty and says so:
		# typing nothing changes nothing, typing something replaces it.
		text_edit.text = "" if secret else str(row.get("raw", ""))
		text_edit.placeholder_text = "(set — type to replace)" if secret \
				else str(row.get("default", ""))
		text_edit.secret = secret

	apply_btn.disabled = not writable
	if writable:
		apply_btn.pressed.connect(_apply)


func _label_toggle() -> void:
	toggle_edit.text = "ON" if toggle_edit.button_pressed else "OFF"


func _apply() -> void:
	if not _on_apply.is_valid():
		return
	var value := ""
	if toggle_edit.visible:
		value = "true" if toggle_edit.button_pressed else "false"
	elif choice_edit.visible:
		value = choice_edit.get_item_text(choice_edit.selected)
	else:
		value = text_edit.text
		if value == "":
			return # a secret left alone
	_on_apply.call(_key, value)

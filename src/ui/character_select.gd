class_name CharacterSelect
extends Control
## The character-select screen: one plinth per climber, the standing animation
## playing on each.
##
## It is a panel rather than a scene of its own, instanced into both the main
## menu and the lobby, because those are the two places the question comes up
## and the answer is the same in both. It writes the choice to Game, which
## remembers it between runs; the lobby is what tells the other machines.

signal picked(id: StringName)
signal closed

const STAND_SCENE: PackedScene = preload("res://scenes/ui/CharacterStand.tscn")

var _stands: Array[CharacterStand] = []
var _index: int = 0

@onready var row: HBoxContainer = $Row
@onready var confirm_btn: Button = $Buttons/ConfirmBtn


func _ready() -> void:
	confirm_btn.pressed.connect(_confirm)
	_build()


func _build() -> void:
	for character in Game.roster.characters:
		if character == null:
			continue
		var stand: CharacterStand = STAND_SCENE.instantiate()
		row.add_child(stand)
		stand.fill(character)
		stand.pressed.connect(_on_stand_pressed.bind(stand))
		_stands.append(stand)


## Show, with the cursor already on whatever this machine last picked.
func open() -> void:
	var current := Game.selected_character
	for i in _stands.size():
		if _stands[i].def.id == current:
			_index = i
	_refresh()
	visible = true
	confirm_btn.grab_focus()


func _refresh() -> void:
	for i in _stands.size():
		_stands[i].set_selected(i == _index)


func _on_stand_pressed(stand: CharacterStand) -> void:
	var at := _stands.find(stand)
	if at < 0:
		return
	Audio.play(&"ui_click")
	# A second click on the stand you are already on confirms it, so picking a
	# climber is one gesture for anyone reaching for the mouse.
	if at == _index:
		_confirm()
		return
	_index = at
	_refresh()


func _confirm() -> void:
	if _stands.is_empty():
		close()
		return
	Audio.play(&"ui_confirm")
	var id: StringName = _stands[_index].def.id
	Game.select_character(id)
	picked.emit(id)
	close()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or event.is_echo() or _stands.is_empty():
		return
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		_index = posmod(_index + 1, _stands.size())
		Audio.play(&"ui_click")
		_refresh()
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_index = posmod(_index - 1, _stands.size())
		Audio.play(&"ui_click")
		_refresh()
	elif event.is_action_pressed(&"ui_accept"):
		_confirm()
	elif event.is_action_pressed(&"ui_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()

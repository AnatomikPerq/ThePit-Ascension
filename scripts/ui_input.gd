extends Node
## Global UI hotkeys.
##
## Authored as a node under World/CanvasLayer with process_mode = Always, so it
## keeps receiving input while the tree is paused. That is the fix for the
## owner's headline complaint: R (restart) and U (debug hitboxes) used to be
## handled in World._unhandled_input, and World is PROCESS_MODE_INHERIT, so it
## stopped receiving input the instant the game paused — while the pause overlay
## itself advertised "R — restart". Godot only delivers input to nodes that can
## process, so the key was dead exactly where it was promised.
##
## Everything here goes through named InputMap actions and World's public API.
## No raw keycodes, no reaching into private methods, no get_parent() walking.

## The World this drives. Wired in World.tscn; the default is the historical
## layout (this node sits under World/CanvasLayer).
@export var world_path: NodePath = NodePath("../..")

const UPGRADE_ACTIONS: Array[StringName] = [
	&"upgrade_1", &"upgrade_2", &"upgrade_3", &"upgrade_4",
]

@onready var world: Node = get_node_or_null(world_path)


func _ready() -> void:
	if world == null:
		push_error("UIInputHandler: world_path '%s' does not resolve" % world_path)


func _unhandled_input(event: InputEvent) -> void:
	if world == null or event.is_echo():
		return

	var handler := _resolve(event)
	if handler.is_null():
		return

	# Consume the event BEFORE acting on it. `restart` reloads the scene, which
	# frees this node mid-call; touching get_viewport() afterwards then fails on
	# a null viewport.
	get_viewport().set_input_as_handled()
	handler.call()


## Returns the action to run for this event, or an empty Callable if we do not
## handle it.
func _resolve(event: InputEvent) -> Callable:
	if event.is_action_pressed(&"restart"):
		return world.restart
	if event.is_action_pressed(&"pause"):
		return world.cancel_pressed
	if event.is_action_pressed(&"music_toggle"):
		return _toggle_music
	if event.is_action_pressed(&"debug_toggle"):
		return world.toggle_debug

	if world.is_choosing_upgrade():
		for i in UPGRADE_ACTIONS.size():
			if event.is_action_pressed(UPGRADE_ACTIONS[i]):
				# NOTE: upgrade_1..3 share their keys with the `attack` and
				# `shockwave` gameplay actions (Z and C). set_input_as_handled()
				# does not retract the Input singleton's action state, so the
				# same press can still be seen by the player on the frame the
				# menu closes. Pre-existing; left alone deliberately, because
				# changing it means changing the keys printed on the buttons.
				return world.choose_upgrade.bind(i)

	return Callable()


func _toggle_music() -> void:
	var enabled: bool = Audio.toggle_music()
	world.show_notification("MUSIC ON" if enabled else "MUSIC OFF")

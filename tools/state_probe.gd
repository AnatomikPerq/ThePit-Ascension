extends Node
## Headless probe for pause, input reachability and restart.
##
##   godot --headless --path . tools/state_probe.tscn
##
## Exits non-zero if any assertion fails. This exists because the owner's
## headline bug — "while paused you cannot reload the world" — is invisible to
## every other check in the harness: the scene loads, nothing errors, and the key
## simply does nothing. The only way to catch it is to press the key.
##
## It drives real InputEventKey objects through Input.parse_input_event() rather
## than calling World's methods directly, so it tests the actual path: physical
## key -> InputMap action -> a node that can still process while paused.

var _world: Node
var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _ok(what: String) -> void:
	_checks += 1
	print("  . ", what)


func _expect(condition: bool, what: String) -> void:
	_checks += 1
	if condition:
		print("  . ", what)
	else:
		print("  x ", what)
		_failures.append(what)


func _run() -> void:
	# Install World as the current scene so reload_current_scene() has something
	# to reload, while this probe survives as a plain child of root.
	var packed: PackedScene = load("res://scenes/World.tscn")
	_world = packed.instantiate()
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	await _idle(10)

	print("initial state")
	_expect(not get_tree().paused, "tree starts unpaused")
	_expect(_world.state == _world.GameState.PLAYING, "world starts PLAYING")

	var handler := _world.get_node_or_null("CanvasLayer/UIInputHandler")
	_expect(handler != null, "UIInputHandler is a node in World.tscn, not built at runtime")
	if handler == null:
		return _finish()
	_expect(handler.process_mode == Node.PROCESS_MODE_ALWAYS,
		"UIInputHandler is PROCESS_MODE_ALWAYS")

	print("pause")
	await _press(&"pause")
	_expect(get_tree().paused, "ESC pauses the tree")
	_expect(_world.state == _world.GameState.PAUSED, "world state is PAUSED")

	print("input reachability while paused")
	# This is the crux. Godot only delivers input to nodes that can process, so
	# before the fix World stopped seeing keys the moment it paused — which is
	# where R lived.
	_expect(not _world.can_process(), "World itself cannot process while paused (by design)")
	_expect(handler.can_process(), "UIInputHandler CAN process while paused")

	var music_before: bool = Audio.music_enabled
	await _press(&"music_toggle")
	_expect(Audio.music_enabled != music_before,
		"a key handled by UIInputHandler still fires while paused")

	print("restart while paused")
	var old_world := _world
	await _press(&"restart")
	await _idle(10)
	_expect(not is_instance_valid(old_world), "R while paused actually reloaded the world")
	_expect(not get_tree().paused, "restart leaves the tree unpaused")

	_world = get_tree().current_scene
	_expect(is_instance_valid(_world) and _world.state == _world.GameState.PLAYING,
		"the reloaded world is PLAYING")

	print("no global time scale left behind")
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Engine.time_scale is 1.0")

	_finish()


func _press(action: StringName) -> void:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		_failures.append("InputMap has no events for action '%s'" % action)
		return
	var key := (events[0] as InputEventKey).duplicate() as InputEventKey
	key.pressed = true
	Input.parse_input_event(key)
	await _idle(2)
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _idle(2)


func _idle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("state probe PASSED — %d checks" % _checks)
		get_tree().quit(0)
		return
	print("state probe FAILED — %d of %d checks" % [_failures.size(), _checks])
	for f in _failures:
		print("  x ", f)
	get_tree().quit(1)

class_name SpectatorCam
extends Node
## Watching the pit instead of climbing it.
##
## Two modes, one key apart: FOLLOW rides a chosen climber, FREE flies the camera
## anywhere inside the shaft. Both zoom out, which is the point — a pit eight
## levels deep is not readable at the climbing camera's framing.
##
## It drives World's Camera2D rather than owning one. That keeps a single camera
## in the scene, so screen shake, the 2D audio listener and Fx.listener_position
## all still come from the same node they always did — a spectator hears the pit
## from where they are looking.
##
## Nothing here is replicated. Where somebody's camera is pointing is their own
## business, and a spectator changes nothing about the run.

## How fast the free camera flies, at normal zoom. Zoomed out it covers more
## ground per second, so the screen moves at roughly one speed either way.
const FREE_SPEED: float = 1500.0
## Zoom is a Camera2D factor: 1.0 is the climbing framing, smaller sees more.
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 1.0
const ZOOM_STEP: float = 0.12
## How fast a zoom press is followed, in e-folds per second.
const ZOOM_LERP: float = 9.0

var active: bool = false
var free_cam: bool = false
## Who is being followed. Null in free cam, and null when nobody is left.
var target: CharacterBody2D = null

var _world: Node = null
var _camera: Camera2D = null
var _position: Vector2 = Vector2.ZERO
var _zoom: float = ZOOM_MAX
var _zoom_wanted: float = ZOOM_MAX


## Take the camera. `at` is where the view starts — the body you just left, or
## the spawn point for somebody who never had one.
func begin(world: Node, camera: Camera2D, at: Vector2) -> void:
	if active:
		return
	_world = world
	_camera = camera
	_position = at
	_zoom = ZOOM_MAX
	_zoom_wanted = ZOOM_MAX
	free_cam = false
	active = true
	# Straight away, not on the next _process: World reads the camera as this
	# machine's ear on the very frame it hands it over.
	camera.global_position = at
	_retarget()


## Hand it back. The zoom goes with it — a revived player gets their own framing.
func end() -> void:
	if not active:
		return
	active = false
	target = null
	if is_instance_valid(_camera):
		_camera.zoom = Vector2.ONE
	_camera = null
	_world = null


## Called from World's _process, before the shake offset is applied.
func step(delta: float) -> void:
	if not active or not is_instance_valid(_camera):
		return
	if free_cam:
		var dir := Vector2(
			Input.get_axis(&"move_left", &"move_right"),
			Input.get_axis(&"move_up", &"move_down"))
		if dir != Vector2.ZERO:
			_position += dir.normalized() * FREE_SPEED * delta / _zoom
	else:
		if not _is_watchable(target):
			_retarget()
		if is_instance_valid(target):
			_position = target.global_position
	_zoom = lerpf(_zoom, _zoom_wanted, clampf(ZOOM_LERP * delta, 0.0, 1.0))
	_camera.global_position = _position
	_camera.zoom = Vector2(_zoom, _zoom)


## The line along the bottom of a spectator's screen.
func status_text() -> String:
	if free_cam:
		return "FREE CAM   ·   WASD move   ·   TAB follow a character   ·   Q/E wheel zoom"
	if is_instance_valid(target):
		return "WATCHING PLAYER %d   ·   A/D switch   ·   TAB free cam   ·   Q/E wheel zoom" \
			% int(target.get("peer_id"))
	return "NOBODY LEFT TO WATCH   ·   TAB free cam   ·   Q/E wheel zoom"


func _unhandled_input(event: InputEvent) -> void:
	if not active or event.is_echo():
		return
	if event.is_action_pressed(&"spectate_toggle"):
		free_cam = not free_cam
		if not free_cam:
			_retarget()
	elif event.is_action_pressed(&"spectate_zoom_in"):
		_zoom_wanted = minf(_zoom_wanted + ZOOM_STEP, ZOOM_MAX)
	elif event.is_action_pressed(&"spectate_zoom_out"):
		_zoom_wanted = maxf(_zoom_wanted - ZOOM_STEP, ZOOM_MIN)
	elif not free_cam and event.is_action_pressed(&"move_right"):
		_cycle(1)
	elif not free_cam and event.is_action_pressed(&"move_left"):
		_cycle(-1)
	else:
		return
	get_viewport().set_input_as_handled()


## Everyone still climbing, in peer order, so "next" means the same thing on
## every machine and does not jump around as the dictionary rehashes.
func _watchable() -> Array:
	var out: Array = []
	if _world == null or not is_instance_valid(_world):
		return out
	var peers: Array = _world.players.keys()
	peers.sort()
	for peer_id in peers:
		var avatar: Node = _world.players[peer_id]
		if _is_watchable(avatar):
			out.append(avatar)
	return out


func _is_watchable(avatar: Node) -> bool:
	return is_instance_valid(avatar) and avatar.get("is_downed") != true


func _cycle(step_by: int) -> void:
	var list := _watchable()
	if list.is_empty():
		target = null
		return
	var at := list.find(target)
	target = list[posmod(at + step_by, list.size())] if at >= 0 else list[0]


func _retarget() -> void:
	var list := _watchable()
	target = list[0] if not list.is_empty() else null

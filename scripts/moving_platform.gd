class_name MovingPlatform
extends AnimatableBody2D
## Oscillates around its start position along one axis. Position is a pure
## function of ticks-since-ready, so with a fixed physics rate two peers that
## build the same world see the same trajectory.

enum Axis {HORIZONTAL, VERTICAL}

@export var axis: Axis = Axis.HORIZONTAL
## Total travel in pixels (already ×2 scaled).
@export var move_range: float = 500.0
## Speed multiplier for the sine oscillation.
@export var move_speed: float = 35.0
## Physics ticks to wait before moving, so rows don't oscillate in lockstep.
@export var move_delay: int = 0

var _start_pos: Vector2
var _ticks: int = 0


func _ready() -> void:
	_start_pos = global_position


## Where the platform was authored: the point its travel oscillates around, and
## the only thing about its position that is the same on every peer at every
## moment. Anything hashing or comparing world layout wants this, not the live
## position, which depends on how many ticks that machine has run.
func start_position() -> Vector2:
	return _start_pos


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks <= move_delay:
		return
	var t := float(_ticks - move_delay) / float(Engine.physics_ticks_per_second)
	var progress := (sin(t * move_speed * 0.01) + 1.0) * 0.5
	var offset := progress * move_range - move_range / 2.0
	var new_pos := _start_pos
	if axis == Axis.HORIZONTAL:
		new_pos.x += offset
	else:
		new_pos.y += offset
	global_position = new_pos

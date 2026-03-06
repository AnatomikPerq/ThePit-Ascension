extends AnimatableBody2D

## Movement type: "horizontal" or "vertical"
@export var move_type: String = "horizontal"
## Total range of movement in pixels (already ×2 scaled)
@export var move_range: float = 500.0
## Speed multiplier for sine oscillation
@export var move_speed: float = 35.0
## Delay in frames before movement starts
@export var move_delay: int = 0

var _start_pos: Vector2
var _timer: float = 0.0
var _delay_counter: int = 0


func _ready() -> void:
	_start_pos = global_position


func _physics_process(delta: float) -> void:
	if _delay_counter < move_delay:
		_delay_counter += 1
		return

	_timer += delta
	var progress: float = (sin(_timer * move_speed * 0.01) + 1.0) * 0.5
	var new_pos: Vector2 = _start_pos

	if move_type == "horizontal":
		new_pos.x = _start_pos.x + (progress * move_range - move_range / 2.0)
	elif move_type == "vertical":
		new_pos.y = _start_pos.y + (progress * move_range - move_range / 2.0)

	global_position = new_pos

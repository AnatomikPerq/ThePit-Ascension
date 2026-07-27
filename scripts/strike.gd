extends Area2D
## Strike attack — spawned by Player, lasts 0.35s, snaps to player side.

const LIFETIME: float = 0.35
const ANIM_DELAY: float = 0.1 # seconds between frames

var _player: Node2D
var _facing_right: bool = true
var _life_timer: float = LIFETIME
var _frame_idx: int = 0
var _anim_timer: float = 0.0

var _frames: Array[Texture2D] = []

@onready var sprite: Sprite2D = $Sprite2D


func setup(player: Node2D, facing: bool) -> void:
	_player = player
	_facing_right = facing


func _ready() -> void:
	_frames = [
		preload("res://assets/sprites/punch_1.png"),
		preload("res://assets/sprites/punch_2.png"),
		preload("res://assets/sprites/punch_3.png"),
	]
	sprite.texture = _frames[0]
	sprite.flip_h = not _facing_right


func _physics_process(delta: float) -> void:
	_life_timer -= delta
	_anim_timer += delta

	if _anim_timer >= ANIM_DELAY:
		_anim_timer = 0.0
		_frame_idx = mini(_frame_idx + 1, _frames.size() - 1)
		sprite.texture = _frames[_frame_idx]
		sprite.flip_h = not _facing_right

	if _life_timer <= 0.0:
		if is_instance_valid(_player) and _player.current_strike == self:
			_player.current_strike = null
		queue_free()

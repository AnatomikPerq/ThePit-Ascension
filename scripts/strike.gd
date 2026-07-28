extends Area2D
## Strike attack — spawned by Player, lasts 0.35s, snaps to player side.

const LIFETIME: float = 0.35

var _player: Node2D
var _facing_right: bool = true
var _life_timer: float = LIFETIME

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func setup(player: Node2D, facing: bool) -> void:
	_player = player
	_facing_right = facing


func _ready() -> void:
	# The "punch" clip does not loop, so it holds on the last frame by itself —
	# which is what the old hand-written frame counter emulated by clamping.
	sprite.flip_h = not _facing_right
	# Enemies find this hitbox through the "strike" group and credit the kill
	# to whoever owns it.
	set_meta(&"owner_peer", _player.get("peer_id") if is_instance_valid(_player) else 0)


func _physics_process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		if is_instance_valid(_player) and _player.current_strike == self:
			_player.current_strike = null
		queue_free()

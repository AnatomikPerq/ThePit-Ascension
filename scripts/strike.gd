extends Area2D
## A sideways attack hitbox: spawned by Player, it snaps to its owner's side for
## a moment and then frees itself.
##
## One script, one scene per weapon. Cyn's fist is scenes/Strike.tscn and Tessa's
## blade is scenes/SwordStrike.tscn; everything that differs between them — how
## long it lasts, how far out it sits, how far it reaches from its own centre,
## the collision shape and the frames — is authored in those scenes rather than
## branched on here. A third weapon is a third .tscn.

## How long the hitbox lives, in seconds. The frames in the scene should finish
## inside this.
@export var lifetime: float = 0.35
## How far from the owner's centre the hitbox sits.
@export var side_offset: float = 52.0
## How far this hitbox reaches from its own centre — the half-diagonal of its
## collision box. Anything that wants to know how squarely it was hit reads this
## off the hitbox; the bomb throws further for a centred punch.
@export var hit_reach: float = 51.0

var _player: Node2D
var _facing_right: bool = true
var _life_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func setup(player: Node2D, facing: bool) -> void:
	_player = player
	_facing_right = facing


func _ready() -> void:
	_life_timer = lifetime
	# The "punch" clip does not loop, so it holds on the last frame by itself —
	# which is what the old hand-written frame counter emulated by clamping.
	sprite.flip_h = not _facing_right
	# Enemies find this hitbox through the "strike" group and credit the kill
	# to whoever owns it.
	set_meta(&"owner_peer", _player.get("peer_id") if is_instance_valid(_player) else 0)
	set_meta(&"hit_reach", hit_reach)


func _physics_process(delta: float) -> void:
	# Snap to the owner's side every frame. This lives here rather than in
	# player.gd so it also works for remote avatars, whose player scripts run
	# only the puppet branch.
	if is_instance_valid(_player):
		var side_x: float = side_offset if _player.facing_right else -side_offset
		global_position = _player.global_position + Vector2(side_x, 0)
		sprite.flip_h = not _player.facing_right

	_life_timer -= delta
	if _life_timer <= 0.0:
		if is_instance_valid(_player) and _player.current_strike == self:
			_player.current_strike = null
		queue_free()

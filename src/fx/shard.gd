class_name FxShard
extends Sprite2D
## One piece of a broken drawing.
##
## It is a plain `Sprite2D` showing a rectangle of the original texture through
## the node's own `region_rect` — no texture is built, sliced or drawn anywhere,
## the sprite simply looks at part of what it already had. Motion is integrated
## here because every piece needs its own trajectory and spin; the fade is the
## `tumble` clip, stretched to the preset's lifetime.

var _velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _gravity: float = 0.0

@onready var anim: AnimationPlayer = $AnimationPlayer


func setup(source: Texture2D, cell: Rect2, velocity: Vector2, spin: float,
		gravity_px: float, life: float, tint: Color) -> void:
	texture = source
	region_rect = cell
	_velocity = velocity
	_spin = spin
	_gravity = gravity_px
	modulate = tint
	# One authored second of fading, stretched to whatever the preset asked for.
	anim.speed_scale = 1.0 / maxf(life, 0.05)
	anim.play(&"tumble")


func _physics_process(delta: float) -> void:
	_velocity.y += _gravity * delta
	global_position += _velocity * delta
	rotation += _spin * delta


## Method track at the end of the clip.
func _done() -> void:
	queue_free()

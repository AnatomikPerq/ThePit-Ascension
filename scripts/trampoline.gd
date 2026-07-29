extends Area2D
## Trampoline — what a stomped slime leaves behind. Launches a falling player
## straight back up and refills their double jump, which is how a good run
## chains from one bounce to the next without ever touching the ground.
##
## The squash used to be an integer counted down per physics tick; it is an
## AnimationPlayer clip now.

const LAUNCH_VELOCITY: float = -2760.0 # -23 * 60 * 2
const BOUNCE_BURST: BurstPreset = preload("res://data/fx/trampoline_bounce.tres")

@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	# Only launch someone on the way down; walking off the side does nothing.
	if body.velocity.y <= 0.0:
		return

	anim.stop()
	anim.play(&"squash")
	body.velocity.y = LAUNCH_VELOCITY
	body.jump_count = 0
	body.dashing_down = false
	Audio.play(&"bounce")
	Fx.burst(global_position + Vector2(0, -10), BOUNCE_BURST)

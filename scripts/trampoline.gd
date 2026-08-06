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
	# A remote avatar's velocity is replicated, so this reads true there too.
	if body.velocity.y <= 0.0:
		return

	# Every machine sees the pad flex and puff — that is world scenery, and it is
	# how you can tell from a distance that a teammate found a bounce.
	anim.stop()
	anim.play(&"squash")
	Fx.burst(global_position + Vector2(0, -10), BOUNCE_BURST)

	# The launch and the sound belong to the machine steering the player who
	# landed. Writing the velocity on a puppet only ever did nothing — its
	# owner's next packet overwrote it — but the sound was real, and it meant a
	# lobby heard every bounce anybody made.
	if NetSession.of(self).active and int(body.get("peer_id")) != Game.local_peer_id:
		return
	body.velocity.y = LAUNCH_VELOCITY
	body.jump_count = 0
	body.dashing_down = false
	Audio.play(&"bounce")

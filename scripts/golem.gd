extends Node2D
## Golem — a broken drone head falling out of the pit's upper reaches.
## Struck or landed on, it petrifies into a solid platform instead of vanishing,
## which is what makes it the game's improvised staircase.
##
## Contact resolution lives in the Combat child (EnemyCombat); this script keeps
## only the fall and the petrification.

const FALL_SPEED: float = 360.0 # term_vel 3 * 60 * 2
const PLATFORM_SIZE := Vector2(64, 64)

@onready var combat: EnemyCombat = $Combat
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var destructible: Destructible = $Destructible


func _ready() -> void:
	combat.killed.connect(_on_killed)


## A golem is a mirror to a railgun beam in BOTH states, across the whole of
## itself — the owner asked for a falling one to reflect like a platform rather
## than be passed through, and for it to be set off by the same shot.
##
## It has to be said out loud because the shape a beam would otherwise find is
## the wrong one. `CrushBody` is 54×38 and sits low, while the drawing is 64×64:
## the top third of a golem is solid to nothing, so a beam aimed at its head
## went through a golem that was plainly in the way. Claiming this node makes its
## damage and stomp areas mirrors too, and between them they cover the drawing.
##
## Reflecting is all this does. Setting the golem off is the beam's HITBOX, in
## the `"strike"` group like every other thing that can hurt an enemy — which is
## why there is nothing here about being activated.
func beam_response() -> int:
	return RailBeam.Response.REFLECT


func set_player_ref(player: CharacterBody2D) -> void:
	# $Combat, not the @onready reference: the spawner calls this before
	# the enemy is added to the tree, when @onready values are still null.
	($Combat as EnemyCombat).player = player


func _physics_process(delta: float) -> void:
	if not Net.is_sim_authority():
		return # movement is mirrored from the host
	if combat.is_dead:
		return
	position.y += FALL_SPEED * delta


func _on_killed(_by_strike: bool) -> void:
	Fx.dust(global_position, 14)
	Audio.play_at(&"thud", global_position)
	_petrify.call_deferred()


## Becomes scenery: sheds every hitbox and grows a solid body to stand on.
## Deferred because it restructures the node while the physics server is
## iterating it.
func _petrify() -> void:
	sprite.play(&"petrified")
	# The Combat component stays: it already returns early once is_dead is set,
	# and _physics_process below still reads that flag every frame. Freeing it
	# left this script talking to a deleted object.
	for node in [get_node_or_null("DamageArea"), get_node_or_null("StompArea"),
			get_node_or_null("CrushBody")]:
		if node:
			node.queue_free()

	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = PLATFORM_SIZE
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

	# From here it is furniture, and furniture can be blown up. While it was
	# still falling it was an enemy and died as one — a blast kills it down the
	# same path a punch does, and the corpse it leaves is this platform.
	destructible.enabled = true

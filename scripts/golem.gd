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


func _ready() -> void:
	combat.killed.connect(_on_killed)


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
	Audio.play(&"thud")
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

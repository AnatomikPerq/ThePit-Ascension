class_name EnemyCombat
extends Node
## The half of an enemy that every enemy shares: how it dies, how it hurts the
## player, and when it despawns.
##
## This was copy-pasted across golem.gd, slime.gd, pursuer.gd, bat.gd and
## spitter.gd — the same twenty-five line ladder five times, with small
## divergences that were impossible to see side by side and easy to break.
##
## It is a component rather than a base class on purpose. Enemies do not share a
## root type: golem, slime and bat are Node2D, pursuer and spitter are
## CharacterBody2D. Composition also makes the extension story honest — a future
## enemy drops this node in, points it at its two Area2Ds and assigns a stats
## resource, and inherits the whole contact matrix without inheriting a movement
## model it does not want.
##
## The owner keeps only its movement and its death reaction, which it hooks up
## through the `killed` signal.

## Emitted once, when this enemy is defeated. `by_strike` distinguishes a strike
## or shockwave from a stomp, for owners that care.
signal killed(by_strike: bool)

## Emitted when the enemy has fallen out of the play area.
signal despawned

@export var stats: EnemyStats

## The thin strip on top that the player lands on. The default matches the node
## every existing enemy already uses, so a scene only overrides this if its
## layout differs. Typed node exports (@export var x: Area2D) were tried first
## and did not survive the round trip through .tscn — they loaded as null.
@export var stomp_area_path: NodePath = NodePath("../StompArea")

## The body volume that hurts the player on contact. Optional.
@export var damage_area_path: NodePath = NodePath("../DamageArea")

## Set through the owner's set_player_ref(). Kept here so the shared despawn and
## contact logic does not have to reach back into the owner.
var player: CharacterBody2D

## True from the moment the enemy is defeated. The owner checks this to stop
## moving; it stays true even for enemies that survive as scenery (the golem
## becomes a platform rather than freeing itself).
var is_dead: bool = false

@onready var _owner_2d: Node2D = get_parent()
@onready var stomp_area: Area2D = get_node_or_null(stomp_area_path)
@onready var damage_area: Area2D = get_node_or_null(damage_area_path)


func _ready() -> void:
	if player == null:
		# Nobody assigned one, so fall back to the player in the scene. This is
		# the single place that will become a nearest-living-avatar lookup when
		# multiplayer lands, instead of five copies of a stored reference.
		player = get_tree().get_first_node_in_group(&"player") as CharacterBody2D


func _physics_process(_delta: float) -> void:
	if is_dead or stats == null or not is_instance_valid(player):
		return
	if _owner_2d.global_position.y > player.global_position.y + stats.despawn_below:
		despawned.emit()
		_owner_2d.queue_free()
		return
	_resolve_contacts()


## Priority order, unchanged from the five originals: a strike beats everything,
## then a stomp, then plain contact damage.
func _resolve_contacts() -> void:
	if stomp_area == null:
		return

	# 1. Strike or shockwave. Both add their hitbox to the "strike" group, so
	#    neither this component nor any enemy knows those scenes exist.
	var areas: Array[Area2D] = stomp_area.get_overlapping_areas()
	if damage_area:
		areas.append_array(damage_area.get_overlapping_areas())
	for area in areas:
		if area.is_in_group(&"strike"):
			_kill(true)
			return

	# 2. Stomp from above.
	for body in stomp_area.get_overlapping_bodies():
		if not body.is_in_group(&"player") or body.velocity.y < 0.0:
			continue
		if stats.requires_dash_to_stomp and body.get("dashing_down") != true:
			# Landing on this one without a dash is a mistake, not an attack.
			body.take_damage()
			return
		body.velocity.y = stats.stomp_rebound
		body.dashing_down = false
		if stats.stomp_sound != &"":
			Audio.play(stats.stomp_sound)
		_kill(false)
		return

	# 3. Contact damage.
	if damage_area == null:
		return
	for body in damage_area.get_overlapping_bodies():
		if not body.is_in_group(&"player"):
			continue
		# A player dashing down from above is mid-stomp. Without this the
		# outcome depends on which Area2D the engine reports first: damage_area
		# covers the whole body while stomp_area is a thin strip on top, so a
		# legitimate dash-kill was frequently turned into the player taking a
		# hit — and the knockback then failed the stomp check's velocity guard on
		# the following frame.
		if body.get("dashing_down") == true \
				and body.global_position.y < _owner_2d.global_position.y:
			continue
		body.take_damage()
		return


func _kill(by_strike: bool) -> void:
	is_dead = true
	Game.enemy_killed(_owner_2d.global_position, stats.score, stats.score_color)
	killed.emit(by_strike)

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

## Whether a dead enemy removes itself. True for everything that simply dies;
## the two enemies that leave something behind — the golem petrifies into a
## platform, the slime is replaced by a trampoline — turn it off in their scene
## and dispose of themselves from `killed`.
##
## It defaults to ON because "the corpse disappears" is what an enemy does
## unless it is special, and the three that are not special (pursuer, bat,
## spitter) had no `killed` handler at all: their sprites stayed in the world
## forever, frozen where they died.
@export var frees_on_death: bool = true

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
		# Nobody assigned one, so fall back to a player in the scene. The sim
		# authority re-targets to the nearest living avatar every frame anyway;
		# this only seeds the reference.
		player = get_tree().get_first_node_in_group(&"player") as CharacterBody2D


func _physics_process(_delta: float) -> void:
	if is_dead or stats == null:
		return

	if Net.is_sim_authority():
		# Chase the nearest living avatar. Solo, that is simply the player —
		# this is the one retargeting seam instead of five stored references.
		var nearest := _nearest_target()
		if nearest != null:
			player = nearest
		if not is_instance_valid(player):
			return
		if _owner_2d.global_position.y > player.global_position.y + stats.despawn_below:
			despawned.emit()
			_owner_2d.queue_free()
			return
		_resolve_kills()

	# A stomp kill and a body overlap happen on the same frame; the old single
	# ladder returned before the damage check, so a legal stomp never hurt.
	# The split ladder must keep that: no contact damage from a corpse.
	if not is_dead:
		_resolve_local_damage()


func _nearest_target() -> CharacterBody2D:
	var best: CharacterBody2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"player"):
		var avatar := node as CharacterBody2D
		if avatar == null or not is_instance_valid(avatar) or avatar.get("health") <= 0:
			continue
		var d := _owner_2d.global_position.distance_squared_to(avatar.global_position)
		if d < best_distance:
			best_distance = d
			best = avatar
	return best


## Kill resolution — strikes beat stomps, unchanged from the five originals.
## Runs only where the world simulation lives: solo, or the host.
func _resolve_kills() -> void:
	if stomp_area == null:
		return

	# 1. Strike or shockwave. Both add their hitbox to the "strike" group, so
	#    neither this component nor any enemy knows those scenes exist. The
	#    hitbox carries its owner's peer id as metadata for kill credit.
	var areas: Array[Area2D] = stomp_area.get_overlapping_areas()
	if damage_area:
		areas.append_array(damage_area.get_overlapping_areas())
	for area in areas:
		if area.is_in_group(&"strike"):
			_kill(true, area.get_meta(&"owner_peer", 0))
			return

	# 2. Stomp from above.
	for body in stomp_area.get_overlapping_bodies():
		if not body.is_in_group(&"player") or body.velocity.y < 0.0:
			continue
		if stats.requires_dash_to_stomp and body.get("dashing_down") != true:
			# Landing on this one without a dash is a mistake, not an attack.
			_hurt(body)
			return
		# The rebound and the sound both belong to the avatar's own machine. The
		# sound used to play right here, which meant the host heard every client's
		# boots: a stomp is a sound your own avatar makes, not an event in the pit
		# that the lobby overhears.
		if not Net.active or body.is_multiplayer_authority():
			body.velocity.y = stats.stomp_rebound
			body.dashing_down = false
			if stats.stomp_sound != &"":
				Audio.play(stats.stomp_sound)
		else:
			# The invincibility window on that machine absorbs the duplicate if
			# its damage path also fired.
			body.rpc_id(body.get_multiplayer_authority(), &"remote_stomp",
				stats.stomp_rebound, stats.stomp_sound)
		_kill(false, body.get("peer_id"))
		return


## Contact damage. Every machine runs this, but each hurts only ITS OWN
## avatar: health belongs to the machine steering the player, so nobody
## takes damage decided by somebody else's overlap test.
func _resolve_local_damage() -> void:
	if damage_area == null:
		return
	for body in damage_area.get_overlapping_bodies():
		if not body.is_in_group(&"player"):
			continue
		if body.get("peer_id") != Game.local_peer_id:
			continue
		# A player coming down from above is mid-stomp, dashing or not. Without
		# this the outcome depends on which Area2D the engine reports first:
		# damage_area covers the whole body while stomp_area is a thin strip on
		# top, so a legitimate kill was frequently turned into the player taking
		# a hit — and the knockback then failed the stomp check's velocity guard
		# on the following frame.
		#
		# It used to test `dashing_down`, which was enough while only a dash
		# could kill a pursuer or a bat. Now that a plain landing does, the
		# descent itself is what matters. A landing that is NOT allowed to kill
		# still punishes the player — that is the spitter, and it happens on the
		# stomp ladder above, not here.
		if body.velocity.y > 0.0 \
				and body.global_position.y < _owner_2d.global_position.y:
			continue
		body.take_damage()
		return


func _hurt(body: Node) -> void:
	if not Net.active or body.is_multiplayer_authority():
		body.take_damage()
	else:
		body.rpc_id(body.get_multiplayer_authority(), &"remote_hurt")


func _kill(by_strike: bool, killer_peer: Variant = 0) -> void:
	var peer: int = killer_peer if killer_peer is int else 0
	if Net.active:
		_kill_everywhere.rpc(by_strike, peer)
	else:
		_kill_everywhere(by_strike, peer)


## The death happens on every machine — golems must petrify into platforms
## locally, slimes must vanish — but only the sim authority scores it.
@rpc("authority", "call_local", "reliable")
func _kill_everywhere(by_strike: bool, killer_peer: int) -> void:
	if is_dead:
		return
	is_dead = true
	if Net.is_sim_authority():
		Game.enemy_killed(_owner_2d.global_position, stats.score, stats.score_color, killer_peer)
	killed.emit(by_strike)
	# The owner may have disposed of itself already (the slime becomes a
	# trampoline). Only the sim authority frees: the MultiplayerSpawner mirrors
	# the removal to every client, and a client that frees the node itself
	# leaves the spawner despawning something that is no longer there.
	if frees_on_death and Net.is_sim_authority() \
			and is_instance_valid(_owner_2d) and not _owner_2d.is_queued_for_deletion():
		_owner_2d.queue_free()

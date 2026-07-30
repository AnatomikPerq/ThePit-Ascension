class_name Blast
extends Object
## One explosion, start to finish. Nothing else in the game knows how an
## explosion works: the bomb only says "go off, here", and the next thing that
## explodes will say the same.
##
## It is deliberately TWO steps, because an explosion is the one event in this
## game that changes the world itself:
##
##   targets()  — the sim authority alone decides what breaks, and answers in
##                node paths.
##   detonate() — every machine runs this off one replicated event: the same
##                fireball, the same rubble, the same sound from the same place,
##                and each machine's own avatar taking its own heart off.
##
## Why the split. Every peer builds identical geometry from the shared seed, so
## it is tempting to let each recompute the destruction and skip the packet. It
## does not hold: a moving platform's live position is a function of how many
## physics ticks that machine has run, so a mover at the edge of a wave breaks
## here and survives there — and a platform that exists on one screen and not
## another is a desync you climb into. The host therefore decides once and names
## the casualties. Node paths are absolute, and the world builder gives every
## piece a name derived from its place in the plan, so a path means the same
## thing on every machine.
##
## Everything else follows the rules the rest of the game already runs on: the
## host owns consequences (kills, breakage, score), victims own their pain (each
## machine damages only the avatar it steers), and cosmetics are local.

const EXPLOSION_SCENE: PackedScene = preload("res://scenes/fx/Explosion.tscn")


## What this wave would break, as absolute paths to the Destructible components.
## Sim-authority side only; the answer travels.
static func targets(from: Node, epicentre: Vector2, def: BlastDef) -> PackedStringArray:
	var doomed := PackedStringArray()
	if def == null or from == null or not from.is_inside_tree():
		return doomed
	for node in from.get_tree().get_nodes_in_group(Destructible.GROUP):
		var breakable := node as Destructible
		if breakable == null or not breakable.breakable():
			continue
		if def.force_at(breakable.distance_from(epicentre)) > breakable.strength:
			doomed.append(String(breakable.get_path()))
	return doomed


## The event, run on every machine. `credited_peer` is whoever caused it, or -1
## for a blast nobody gets the credit — or the points — for.
##
## `point_blank_peer` is the player who set it off with their own body, or -1.
## That one machine gets a different event entirely: two hearts, thrown much
## further, a deeper sound, the screen filled. Every other machine plays the
## ordinary blast and simply watches that avatar leave at speed — its position is
## already replicated, so nothing about the spectacle has to travel.
static func detonate(from: Node, epicentre: Vector2, def: BlastDef,
		credited_peer: int, doomed: PackedStringArray,
		point_blank_peer: int = -1) -> void:
	if def == null or from == null or not from.is_inside_tree():
		return
	var tree := from.get_tree()
	var point_blank := point_blank_peer > 0 and point_blank_peer == Game.local_peer_id
	_show(epicentre, def, credited_peer, point_blank)
	_break(tree, epicentre, doomed)
	_hurt(tree, epicentre, def, point_blank)
	# Score is the sim authority's call, exactly like a kill; add_score
	# broadcasts the resulting number, so the popup lands everywhere.
	if Net.is_sim_authority() and credited_peer > 0 and def.score > 0:
		Game.add_score(def.score, epicentre, def.score_color, credited_peer)


## Fireball, noise, and the two pieces of feedback that fade with distance —
## which is what stops a bomb on the far side of the pit from shaking a screen
## it is nowhere near. Unless it went off against us, in which case distance is
## not a thing that applies.
static func _show(epicentre: Vector2, def: BlastDef, credited_peer: int,
		point_blank: bool) -> void:
	if point_blank:
		if def.point_blank_sound != &"":
			Audio.play(def.point_blank_sound)
		Fx.shake(def.point_blank_shake)
		Fx.screen_flash(def.point_blank_flash, true)
	else:
		if def.sound != &"":
			Audio.play_at(def.sound, epicentre)
		Fx.shake_from(epicentre, def.shake, def.feedback_range)
		Fx.screen_flash(def.flash * Fx.loudness_at(epicentre, def.feedback_range))
	for preset in def.bursts:
		Fx.burst(epicentre, preset)

	# The hitbox lives in the scene rather than being assembled here, and it
	# joins the "strike" group — so every enemy in the blast dies through the
	# same path a punch kills them by, and the acid blobs fizzle, and neither
	# EnemyCombat nor any enemy scene has to learn that bombs exist.
	var root := Fx.effects_root
	if not is_instance_valid(root):
		return
	var boom: FxExplosion = EXPLOSION_SCENE.instantiate()
	root.add_child(boom)
	boom.global_position = epicentre
	boom.fire(def, credited_peer)


static func _break(tree: SceneTree, epicentre: Vector2, doomed: PackedStringArray) -> void:
	for path in doomed:
		var breakable := tree.root.get_node_or_null(NodePath(path)) as Destructible
		if breakable != null:
			breakable.shatter(epicentre)


## What it does to this machine's own avatar. No damage packet is needed for
## that: the event says where the blast went off, and every victim answers for
## itself — the same rule that keeps somebody else's lag off your health bar
## everywhere else in the game.
##
## The shove reaches further than the damage does, so a bomb going off nearby
## moves you even when it did not hurt you, and it is applied whether the heart
## came off or not — being invincible does not make you heavy.
static func _hurt(tree: SceneTree, epicentre: Vector2, def: BlastDef,
		point_blank: bool) -> void:
	for node in tree.get_nodes_in_group(&"player"):
		var avatar := node as CharacterBody2D
		if avatar == null or int(avatar.get("peer_id")) != Game.local_peer_id:
			continue
		if point_blank:
			avatar.take_damage(def.point_blank_damage)
			avatar.shove(epicentre, def.point_blank_push)
			return
		var distance := avatar.global_position.distance_to(epicentre)
		if distance <= def.radius:
			avatar.take_damage()
		avatar.shove(epicentre, def.push_at(distance))
		return

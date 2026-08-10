class_name RailBeam
extends Object
## Where a railgun beam goes. A pure function of (origin, direction, geometry) —
## no node, no state, no frame.
##
## That purity is the whole design, and it is what the owner asked for when he
## said the mechanic has to scale up to a beam you can HOLD with the reflections
## moving instantly. A held beam is this function called again; a swept beam is
## this function called with a different angle; the six-bounce shot is this
## function called once. There is no path object being nudged from frame to
## frame that could get out of step with the aim.
##
## ## Why there are no special cases in here
##
## The rules the owner set out read like a table of exceptions — bombs go off,
## a falling golem sets and reflects, an activated golem reflects, slimes are
## passed through in any state, enemies are passed through and killed, platforms
## and walls reflect. Almost all of it is already true of the collision layers,
## and writing it out as branches would have been writing it down twice:
##
## - **Walls, floors, dividers, platforms and moving platforms** are all on
##   layer WORLD (`src/world/world_builder.gd:57`, and the two platform scenes'
##   default layer). The ray masks WORLD, so it reflects off every one of them.
## - **A falling golem** is on WORLD too — its `CrushBody` is an AnimatableBody2D
##   on layer 1. So it reflects like a platform without being asked to, which is
##   exactly what was wanted. An **activated** golem is a StaticBody2D on WORLD
##   as well. Neither state needs a test; both reflect.
## - **Slimes** have no physics body at all, in any state — a Slime is a Node2D
##   with two Area2Ds on layer ENEMY, and the trampoline it leaves is on layer
##   TRAMPOLINE. **Bats** have no body either, **pursuers** and **spitters** are
##   on ENEMY, and a **bomb** is on no layer whatsoever. A WORLD-masked ray with
##   `collide_with_areas` off passes through the lot of them for nothing.
##
## Areas ARE queried, and the default keeps them harmless: the rule is decided
## by LAYER, so a slime's hurt box, a bomb's contact area and a trampoline are
## all passed through without any of them knowing a railgun exists. They are
## queried at all for one reason — a golem's solid `CrushBody` is smaller than a
## golem, so its hurt boxes have to be mirrors too or the top third of the
## drawing is see-through. That is the single `beam_response()` in the game.
##
## What actually kills and detonates is not this function at all — it is the
## hitbox `RailShot` lays along these segments, in group `&"strike"` like every
## other thing in the game that can hurt an enemy. That is why a beam kills a
## bat, which the ray cannot even see.
##
## ## The one hook
##
## `beam_response()` on a collider overrides the default. It exists for the
## breakable furniture the map is going to grow: something on the WORLD layer
## that a beam should go through rather than bounce off is one method, not an
## edit here.

enum Response {
	REFLECT, ## a mirror: the beam turns and spends one of its bounces
	PASS, ## the beam carries straight on, and this thing is not touched again
}

## How many straight runs one beam can have, and therefore how many collision
## shapes `RailShot.tscn` authors. `RailgunStats.bounces` is clamped to one less
## than this, out loud.
const MAX_SEGMENTS: int = 8

## Nudge off a surface after reflecting, so the next ray does not immediately
## find the wall it just left. Half a pixel at this scale is invisible and the
## physics server is comfortably more precise than that.
const SURFACE_BIAS: float = 0.5


## The answer: the corners, in order.
##
## `points[0]` is the muzzle, `points[-1]` is where it stopped, and everything
## between is a reflection — so the caller draws it as one polyline, throws a
## spark at each interior point, and puts the impact at the last one.
class Path extends RefCounted:
	var points := PackedVector2Array()
	## False when the last segment ran out of range in open air rather than
	## meeting anything. The difference is a burst and a bang, or nothing.
	var landed: bool = false

	func segment_count() -> int:
		return maxi(points.size() - 1, 0)


## Trace a beam. `from` is any node in the world being fired in — it is used for
## the physics space and nothing else.
static func trace(from: Node2D, origin: Vector2, direction: Vector2,
		stats: RailgunStats) -> Path:
	var path := Path.new()
	path.points.append(origin)
	if from == null or stats == null or not from.is_inside_tree():
		return path

	var world := from.get_world_2d()
	if world == null:
		return path
	var space := world.direct_space_state

	# ENEMY is in the mask so that a GOLEM can be a mirror across the whole of
	# itself. Its `CrushBody` is 54×38 and sits low, while the drawing is 64×64 —
	# so the top third of a golem you can plainly see has no solid collider at
	# all, and a beam aimed at its head went straight through. Its damage and
	# stomp areas cover the rest, and `golem.gd` claims them with
	# `beam_response()`. Everything else on ENEMY defaults to PASS; see below.
	var mask := Layers.WORLD | Layers.ENEMY
	if stats.stops_on_players:
		mask |= Layers.PLAYER

	var heading := direction.normalized()
	if heading == Vector2.ZERO:
		heading = Vector2.RIGHT

	# One less than MAX_SEGMENTS, because n reflections is n+1 straight runs.
	var budget := mini(stats.bounces, MAX_SEGMENTS - 1)
	var here := origin
	# Colliders already passed through on THIS run. Cleared at every reflection,
	# so a beam that comes back through the same thing passes it again.
	var ignore: Array[RID] = []
	# Distance already covered on this run. A pass-through must not buy the beam
	# a fresh full-length ray, or a row of them would reach forever.
	var covered := 0.0

	while true:
		var reach := stats.segment_length - covered
		if reach <= 0.0:
			path.points.append(here)
			return path

		var query := PhysicsRayQueryParameters2D.create(here, here + heading * reach, mask)
		query.exclude = ignore
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)

		if hit.is_empty():
			path.points.append(here + heading * reach)
			return path

		var point: Vector2 = hit.position

		if _response_of(hit.get("collider")) == Response.PASS:
			covered += here.distance_to(point) + SURFACE_BIAS
			here = point + heading * SURFACE_BIAS
			ignore.append(hit.rid)
			continue

		path.points.append(point)
		if budget <= 0:
			path.landed = true
			return path

		budget -= 1
		heading = heading.bounce(hit.normal)
		here = point + hit.normal * SURFACE_BIAS
		ignore.clear()
		covered = 0.0

	return path


## What a surface does to a beam.
##
## The default is decided by LAYER, not by node kind, and that is what keeps the
## table of interactions out of this file: **anything on WORLD is a mirror,
## anything else is transparent.** The pit is made of walls, and everything a
## climber cannot stand on — enemy hurt boxes, a bomb's contact area, a slime,
## a trampoline — is something a beam should be going through.
##
## `beam_response()` overrides it, on the collider or on the thing that owns it.
## Exactly one entity uses it today (the golem, claiming its own hurt boxes as
## mirror so that its whole drawing reflects rather than only its crush box) and
## it is the seam for the breakable furniture the map is going to grow.
static func _response_of(collider: Variant) -> Response:
	var node := collider as Node
	if node == null:
		return Response.REFLECT
	if node.has_method(&"beam_response"):
		return node.call(&"beam_response") as Response
	# The collider is usually a child — a golem's DamageArea, a room's wall body
	# — so the owner gets a say without every shape needing a script.
	var owner_node := node.get_parent()
	if owner_node != null and owner_node.has_method(&"beam_response"):
		return owner_node.call(&"beam_response") as Response
	var layers := int(node.get(&"collision_layer"))
	return Response.REFLECT if (layers & Layers.WORLD) != 0 else Response.PASS

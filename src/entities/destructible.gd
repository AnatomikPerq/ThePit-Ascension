class_name Destructible
extends Node
## Makes its parent breakable by a blast. Drop it in, give it a strength, done.
##
## `strength` IS the durability: the wave breaks this object when the force
## reaching it exceeds this number. Because a blast's force falls off with
## distance (BlastDef.force_at), a tougher object simply has to be closer — one
## explosion sorts everything it covers, and no code anywhere holds a table of
## "platforms die within N px". Damage never accumulates: a wave too weak to
## break something leaves no mark at all, so two near misses are still two near
## misses.
##
## It is a component rather than a base class for the same reason EnemyCombat is
## one — the things that break do not share a root type. A static platform is a
## StaticBody2D, a mover an AnimatableBody2D, a trampoline an Area2D, and a
## petrified golem a Node2D with a body bolted on afterwards.
##
## *Seam:* a new piece of world furniture that should be breakable is this node
## plus one number. Nothing in Blast, the bomb, or the world builder has to
## learn about it.

## Emitted on the machine where this object breaks, just before it goes.
signal destroyed

## Every destructible finds itself here. The component joins the group itself
## rather than the scene declaring it: forgetting the group would make an
## object silently indestructible, which is exactly the kind of bug nobody
## notices for a month.
const GROUP := &"destructible"

## Durability, in BlastDef.peak_force units. Higher is tougher. The pit's
## ladder, loosest first: a slime's trampoline, a petrified golem, a moving
## platform, a static platform.
@export var strength: float = 50.0

## Off means "not breakable yet". The golem carries this node switched off while
## it is still falling — a falling golem is an enemy and dies as one; it only
## becomes furniture once it has petrified into a platform.
@export var enabled: bool = true

## Locally-built geometry is freed by every machine, because every machine built
## its own copy from the shared seed. A node born from a MultiplayerSpawner —
## a slime's trampoline, a petrified golem — is mirrored instead, so only the
## sim authority may free it and everyone else just takes it out of the world.
## Freeing it locally would leave the host announcing the loss of something the
## client had already thrown away.
@export var frees_locally: bool = true

@export_group("Breaking up")
## Two ways to come apart, and which one is right depends on what the object
## looks like. Set exactly one; `shards` wins if both are filled in.
##
## `debris` throws copies of the object's own texture around. Correct for things
## visibly built from one repeating part — a platform is a row of identical
## blocks, so loose blocks are what it should leave.
##
## `shards` cuts the sprite into a grid and throws the pieces. Correct for
## everything that is a single drawing: a trampoline, a petrified golem. Copies of
## those read as the thing multiplying rather than breaking, which is exactly what
## the first version of this looked like.
@export var debris: BurstPreset
@export var shards: ShardPreset
@export var dust_count: int = 10
@export var break_sound: StringName = &"rubble"

var _spent: bool = false
var _shape: CollisionShape2D


func _ready() -> void:
	add_to_group(GROUP)


## The node that actually goes away. Everything about a destructible is really
## about its parent; this component is only the label.
func target() -> Node:
	return get_parent()


func breakable() -> bool:
	if not enabled or _spent:
		return false
	var body := get_parent()
	return body != null and is_instance_valid(body) and not body.is_queued_for_deletion()


## How far this object is from `point`, measured from its nearest edge.
##
## Not from its centre: a platform eight blocks wide is not a dot. Measured
## centre-to-centre, a bomb going off against one end reads as far away, and the
## plank you are standing on survives a blast that visibly engulfed it.
func distance_from(point: Vector2) -> float:
	var box := footprint()
	if box.size == Vector2.ZERO:
		return box.position.distance_to(point)
	return Vector2(
		clampf(point.x, box.position.x, box.end.x),
		clampf(point.y, box.position.y, box.end.y)
	).distance_to(point)


## The object's own box in world space, from its first rectangular collision
## shape. Anything with no such shape counts as a point at its origin.
func footprint() -> Rect2:
	var body := get_parent() as Node2D
	if body == null:
		return Rect2()
	var shape := _rect_shape()
	if shape == null:
		return Rect2(body.global_position, Vector2.ZERO)
	var rect := shape.shape as RectangleShape2D
	var size: Vector2 = rect.size * shape.global_scale
	return Rect2(shape.global_position - size * 0.5, size)


## Break. Cosmetics run on every machine that gets here; the removal follows
## `frees_locally`.
func shatter(epicentre: Vector2) -> void:
	if _spent:
		return
	_spent = true
	var box := footprint()
	var centre := box.get_center()
	var away := centre - epicentre
	if away.length_squared() < 1.0:
		away = Vector2.UP
	away = away.normalized()
	var drawing := _sprite()
	if shards != null:
		Fx.shards(drawing, shards, away)
	elif debris != null:
		Fx.debris(centre, Fx.texture_of(drawing), box.size * 0.5, away, debris)
	Fx.dust(centre, dust_count)
	if break_sound != &"":
		Audio.play_at(break_sound, centre)
	destroyed.emit()
	_remove()


func _remove() -> void:
	var body := get_parent()
	if frees_locally or Net.is_sim_authority():
		body.queue_free()
		return
	deactivate(body)


## Out of the world without being freed: invisible, on no layer, watching
## nothing. What a client does with a spawner-owned object until the despawn
## packet arrives. Recursive, because what makes a petrified golem solid is a
## body it grew at runtime, not the node this component hangs off.
static func deactivate(node: Node) -> void:
	var item := node as CanvasItem
	if item != null:
		item.visible = false
	var area := node as Area2D
	if area != null:
		area.monitoring = false
		area.monitorable = false
	var collider := node as CollisionObject2D
	if collider != null:
		collider.collision_layer = Layers.NONE
		collider.collision_mask = Layers.NONE
	for child in node.get_children():
		deactivate(child)


## Looked up lazily and re-looked-up if it goes stale, because a golem grows its
## collision shape at the moment it petrifies, long after this node was ready.
func _rect_shape() -> CollisionShape2D:
	if is_instance_valid(_shape) and _shape.shape is RectangleShape2D \
			and not _shape.is_queued_for_deletion():
		return _shape
	_shape = _find_rect_shape(get_parent())
	return _shape


static func _find_rect_shape(node: Node) -> CollisionShape2D:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		var shape := child as CollisionShape2D
		if shape != null and shape.shape is RectangleShape2D:
			return shape
		var deeper := _find_rect_shape(child)
		if deeper != null:
			return deeper
	return null


func _sprite() -> Node2D:
	for child in get_parent().get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return child
	return null

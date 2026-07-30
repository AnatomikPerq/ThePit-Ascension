class_name WorldBuilder
extends Object
## Turns WorldPlan records into nodes under one parent. Every layout decision
## was already made by WorldGenerator — nothing here draws a random number.
##
## Each piece is NAMED after its place in the plan, and that is load-bearing
## rather than tidiness. The world never travels: every peer builds its own copy
## from the shared seed. So when a blast destroys a platform, the only thing the
## host can send is "that one" — and a name derived from the plan means the same
## node on every machine. Left to Godot's own duplicate-name handling the pieces
## would be @Platform@7-style names off a per-instance counter, which agree
## between peers only by luck.

const PLATFORM_SCENE: PackedScene = preload("res://scenes/Platform.tscn")
const MOVING_PLATFORM_SCENE: PackedScene = preload("res://scenes/MovingPlatform.tscn")

## Node name prefix per record kind. Readable, so a destroyed-platform path in a
## log still says what it was.
const KIND_NAMES: Dictionary = {
	WorldPlan.Kind.WALL: "Wall",
	WorldPlan.Kind.FLOOR: "Floor",
	WorldPlan.Kind.DIVIDER: "Div",
	WorldPlan.Kind.PLATFORM: "Plat",
}


static func build(plan: WorldPlan, theme: WorldTheme, parent: Node2D) -> void:
	for i in plan.statics.size():
		var piece := plan.statics[i]
		var body := _platform(piece.rect, theme) if piece.kind == WorldPlan.Kind.PLATFORM \
				else _shaft_body(piece, theme)
		body.name = "%s%d" % [KIND_NAMES.get(piece.kind, "Piece"), i]
		parent.add_child(body)
	for i in plan.movers.size():
		var mover := _moving_platform(plan.movers[i], theme)
		mover.name = "Mover%d" % i
		parent.add_child(mover)


## Static platforms come from the authored scene, resized to the plan.
static func _platform(rect: Rect2, theme: WorldTheme) -> StaticBody2D:
	var body: StaticBody2D = PLATFORM_SCENE.instantiate()
	body.position = rect.position + rect.size / 2.0
	var col: CollisionShape2D = body.get_node("CollisionShape2D")
	col.shape = col.shape.duplicate() # scenes share the sub-resource
	col.shape.size = rect.size
	var spr: Sprite2D = body.get_node("Sprite2D")
	spr.region_rect = Rect2(Vector2.ZERO, rect.size / theme.pixel_scale)
	return body


## Bulk shaft geometry — walls, floor, dividers — is assembled here from the
## theme's textures, the way a TileMap would emit its colliders.
static func _shaft_body(piece: WorldPlan.StaticPiece, theme: WorldTheme) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = piece.rect.position + piece.rect.size / 2.0
	body.collision_layer = Layers.WORLD

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = piece.rect.size
	col.shape = shape
	body.add_child(col)

	var spr := Sprite2D.new()
	spr.texture = theme.texture_for(piece.kind)
	spr.scale = Vector2.ONE * theme.pixel_scale
	if piece.kind != WorldPlan.Kind.FLOOR:
		# Tile the texture across the piece. The floor texture is authored at
		# exactly floor size, so it needs no region.
		spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		spr.region_enabled = true
		spr.region_rect = Rect2(Vector2.ZERO, piece.rect.size / theme.pixel_scale)
	body.add_child(spr)
	return body


static func _moving_platform(mover: WorldPlan.MoverPiece, theme: WorldTheme) -> MovingPlatform:
	var mp: MovingPlatform = MOVING_PLATFORM_SCENE.instantiate()
	mp.position = mover.position
	mp.axis = mover.axis
	mp.move_speed = mover.speed
	mp.move_delay = mover.delay
	mp.move_range = mover.travel
	var col: CollisionShape2D = mp.get_node("CollisionShape2D")
	col.shape = col.shape.duplicate() # scenes share the sub-resource
	col.shape.size = mover.size
	var spr: Sprite2D = mp.get_node("Sprite2D")
	spr.region_rect = Rect2(0.0, 0.0, mover.size.x / theme.pixel_scale, spr.texture.get_height())
	return mp

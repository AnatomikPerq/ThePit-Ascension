extends GdUnitTestSuite
## World generation has to be a pure function of its seed. That matters twice
## over: it is what makes a refactor of the generator provable, and it is what
## lets every peer in a multiplayer session build an identical world from a
## seed the host sends.

const SEEDS: Array[int] = [1, 20260728, 999999]

var _worlds: Array[Node] = []


func after_test() -> void:
	for w in _worlds:
		if is_instance_valid(w):
			w.free()
	_worlds.clear()


## Generation runs synchronously inside add_child(), so the geometry is readable
## with no frames elapsed. Waiting frames would let MovingPlatform start
## oscillating and make the sample time-dependent.
func _build(world_seed: int) -> Node:
	var world: Node = load("res://scenes/World.tscn").instantiate()
	world.world_seed = world_seed
	add_child(world)
	_worlds.append(world)
	return world


func _collision_rects(world: Node) -> Array[String]:
	var out: Array[String] = []
	for shape in _shapes(world.get_node("Platforms")):
		var rect := shape.shape as RectangleShape2D
		if rect == null:
			continue
		var origin := shape.global_transform.origin - rect.size * 0.5
		out.append("%.4f,%.4f,%.4f,%.4f" % [origin.x, origin.y, rect.size.x, rect.size.y])
	out.sort()
	return out


func _shapes(root: Node) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	for child in root.get_children():
		var shape := child as CollisionShape2D
		if shape:
			out.append(shape)
		out.append_array(_shapes(child))
	return out


func test_same_seed_produces_identical_geometry() -> void:
	for s in SEEDS:
		var first := _collision_rects(_build(s))
		var second := _collision_rects(_build(s))
		assert_array(second) \
			.override_failure_message("seed %d generated different geometry on a second run" % s) \
			.is_equal(first)


## The generator itself, without a scene: two plans from the same seed must be
## record-for-record identical. This is the cheap fast check; the scene-level
## tests above prove the builder faithfully transfers the plan into nodes.
func test_generator_is_a_pure_function_of_the_seed() -> void:
	var profile: WorldProfile = load("res://data/worlds/pit.tres")
	for s in SEEDS:
		var a := _plan_lines(WorldGenerator.generate(profile, s))
		var b := _plan_lines(WorldGenerator.generate(profile, s))
		assert_array(b) \
			.override_failure_message("WorldGenerator is not pure for seed %d" % s) \
			.is_equal(a)
		assert_array(a).is_not_empty()


func _plan_lines(plan: WorldPlan) -> Array[String]:
	var out: Array[String] = []
	for piece in plan.statics:
		out.append("%d %s" % [piece.kind, piece.rect])
	for m in plan.movers:
		out.append("mover %s %s %d %f %d %f" % [m.position, m.size, m.axis, m.speed, m.delay, m.travel])
	return out


func test_different_seeds_produce_different_geometry() -> void:
	var a := _collision_rects(_build(SEEDS[0]))
	var b := _collision_rects(_build(SEEDS[1]))
	assert_array(a).is_not_equal(b)


## Regression: World.tscn used to hand-place a wall segment that the generator
## then re-created at the same coordinates, leaving two identical colliders
## stacked on top of each other.
func test_no_duplicate_colliders() -> void:
	for s in SEEDS:
		var rects := _collision_rects(_build(s))
		var seen := {}
		var duplicates: Array[String] = []
		for r in rects:
			if seen.has(r):
				duplicates.append(r)
			seen[r] = true
		assert_array(duplicates) \
			.override_failure_message("seed %d stacks identical colliders at: %s" % [s, str(duplicates)]) \
			.is_empty()


func test_walls_span_the_full_climb() -> void:
	var world := _build(SEEDS[0])
	var max_depth: float = world.max_depth
	var bounds := Rect2()
	var first := true
	for shape in _shapes(world.get_node("Platforms")):
		var rect := shape.shape as RectangleShape2D
		if rect == null:
			continue
		var r := Rect2(shape.global_transform.origin - rect.size * 0.5, rect.size)
		bounds = r if first else bounds.merge(r)
		first = false
	# The floor sits at the bottom of the climb and the walls run past the top.
	assert_float(bounds.end.y).is_greater_equal(max_depth)
	assert_float(bounds.position.y).is_less(0.0)


func test_trampolines_container_is_used_not_the_enemies_one() -> void:
	var world := _build(SEEDS[0])
	var container := world.get_node_or_null("Trampolines")
	assert_object(container) \
		.override_failure_message("World.tscn lost its Trampolines container").is_not_null()
	assert_bool(container.is_in_group(&"trampoline_container")) \
		.override_failure_message("Trampolines is not discoverable, so slimes will fall back to the Enemies container") \
		.is_true()

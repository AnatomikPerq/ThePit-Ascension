extends GdUnitTestSuite
## Destroying the world: which pieces of it can go, and by what rule.
##
## The rule is one comparison. A blast's force falls off with distance from the
## epicentre; an object breaks when that force beats its own strength. So
## toughness is a single number per object, nothing anywhere holds a table of
## "platforms die within N px", and the map can grow new kinds of furniture that
## only have to say how strong they are.
##
## What must NEVER break is the shaft itself — walls, floor and the level
## dividers. That is not a strength value, it is the absence of the component:
## WorldBuilder assembles those from the theme's textures and only platforms and
## movers come from scenes that carry a Destructible. The test below asserts it
## against a real generated world, because that is the version that matters.

const PLATFORM := "res://scenes/Platform.tscn"
const MOVING_PLATFORM := "res://scenes/MovingPlatform.tscn"
const TRAMPOLINE := "res://scenes/Trampoline.tscn"
const GOLEM := "res://scenes/Golem.tscn"

var root: Node2D
var def: BlastDef


func before_test() -> void:
	Game.new_run()
	def = load("res://data/fx/blast.tres")
	root = Node2D.new()
	add_child(root)
	Fx.effects_root = root
	Audio.world_root = root
	Fx.listener_position = Vector2.ZERO


func after_test() -> void:
	Fx.effects_root = null
	Audio.world_root = null
	# Cases here build real Worlds, which point the listener at their own avatar
	# deep in the pit. Left there it silences every distance-scaled assertion in
	# whatever suite runs next.
	Fx.listener_position = Vector2.ZERO
	if is_instance_valid(root):
		root.free()


func _step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## Position BEFORE add_child, the way World spawns everything: a body moved
## after entering the tree leaves the physics server holding its origin overlap
## for a step.
func _spawn(path: String, at: Vector2) -> Node2D:
	var node: Node2D = load(path).instantiate()
	node.position = at
	root.add_child(node)
	return node


func _blast(at: Vector2) -> void:
	Blast.detonate(root, at, def, -1, Blast.targets(root, at, def))


## Variant, not Node: GDScript refuses to bind an already-freed object to a
## typed parameter, and "already freed" is exactly the answer being asked for.
func _gone(node: Variant) -> bool:
	return not is_instance_valid(node) or (node as Node).is_queued_for_deletion()


func _strength_of(path: String) -> float:
	var node: Node2D = load(path).instantiate()
	var d: Destructible = node.get_node("Destructible")
	var s := d.strength
	node.free()
	return s


# ── The rule ────────────────────────────────────────────────────────────────
## Point blank breaks it; a whole radius away does not. The two ends of the
## falloff, on the object the whole climb is made of.
func test_a_blast_breaks_a_platform_it_is_sitting_on() -> void:
	var platform := _spawn(PLATFORM, Vector2.ZERO)
	_blast(Vector2.ZERO)
	await _step(4)
	assert_bool(_gone(platform)) \
		.override_failure_message("a platform survived a blast centred on it").is_true()


func test_a_blast_leaves_a_platform_beyond_its_reach() -> void:
	var reach := def.reach_for(_strength_of(PLATFORM))
	var platform := _spawn(PLATFORM, Vector2(reach + 200.0, 0))
	_blast(Vector2.ZERO)
	await _step(4)
	assert_bool(_gone(platform)) \
		.override_failure_message("a platform %.0f px away broke, past its %.0f px reach" \
			% [reach + 200.0, reach]) \
		.is_false()


## Cracks do not accumulate. Two waves that are each too weak leave the thing
## standing, however many of them there are — which is what keeps the pit from
## dissolving over a long run of near misses.
func test_durability_does_not_accumulate() -> void:
	var reach := def.reach_for(_strength_of(PLATFORM))
	var platform := _spawn(PLATFORM, Vector2(reach + 120.0, 0))
	for i in 5:
		_blast(Vector2.ZERO)
		await _step(3)
	assert_bool(_gone(platform)) \
		.override_failure_message("five near misses added up and broke a platform") \
		.is_false()


## Measured from the nearest edge, not from the centre. A platform eight blocks
## wide is not a dot: centre-to-centre, a bomb going off against one end reads as
## far away and the plank you are standing on survives a blast that visibly
## engulfed it.
func test_distance_is_measured_from_the_nearest_edge() -> void:
	var wide: StaticBody2D = load(PLATFORM).instantiate()
	root.add_child(wide)
	var col: CollisionShape2D = wide.get_node("CollisionShape2D")
	col.shape = col.shape.duplicate()
	col.shape.size = Vector2(1200, 32)
	wide.global_position = Vector2.ZERO

	# Against the left end. The centre is 600 px away — well past any reach —
	# but the edge we are touching is not.
	var epicentre := Vector2(-600.0, 0.0)
	var breakable: Destructible = wide.get_node("Destructible")
	assert_float(breakable.distance_from(epicentre)) \
		.override_failure_message("a 1200 px platform measured itself as a point") \
		.is_less(20.0)
	_blast(epicentre)
	await _step(4)
	assert_bool(_gone(wide)) \
		.override_failure_message("a blast against one end of a long platform did nothing") \
		.is_true()


# ── The ladder ──────────────────────────────────────────────────────────────
## The owner's ordering, pinned as data rather than prose: an ordinary platform
## is tougher than what an activated golem leaves, which is tougher than what an
## activated slime leaves.
func test_platforms_are_tougher_than_golems_which_are_tougher_than_slimes() -> void:
	var platform := _strength_of(PLATFORM)
	var mover := _strength_of(MOVING_PLATFORM)
	var golem := _strength_of(GOLEM)
	var trampoline := _strength_of(TRAMPOLINE)
	assert_float(platform).override_failure_message(
		"a static platform (%.0f) is not tougher than a petrified golem (%.0f)" \
		% [platform, golem]).is_greater(golem)
	assert_float(mover).override_failure_message(
		"a moving platform (%.0f) is not tougher than a petrified golem (%.0f)" \
		% [mover, golem]).is_greater(golem)
	assert_float(golem).override_failure_message(
		"a petrified golem (%.0f) is not tougher than a slime's trampoline (%.0f)" \
		% [golem, trampoline]).is_greater(trampoline)


## The ladder has to be visible as distance, not just as numbers: at the same
## remove, the weaker thing goes and the stronger one does not.
func test_the_ladder_shows_up_as_reach() -> void:
	var between := (def.reach_for(_strength_of(PLATFORM)) \
		+ def.reach_for(_strength_of(TRAMPOLINE))) * 0.5
	var platform := _spawn(PLATFORM, Vector2(between, 0))
	var trampoline := _spawn(TRAMPOLINE, Vector2(between, 200))
	_blast(Vector2.ZERO)
	await _step(4)
	assert_bool(_gone(trampoline)) \
		.override_failure_message("a trampoline %.0f px out survived a wave that should beat it" \
			% between).is_true()
	assert_bool(_gone(platform)) \
		.override_failure_message("a platform %.0f px out broke to the same wave" % between) \
		.is_false()


# ── The golem's two lives ───────────────────────────────────────────────────
## A falling golem is an enemy and dies as one; only the platform it petrifies
## into is furniture. Without the switch, a blast would list a live golem as
## rubble and break it before its own death reaction ever ran.
func test_a_falling_golem_is_not_furniture() -> void:
	var golem := _spawn(GOLEM, Vector2.ZERO)
	var breakable: Destructible = golem.get_node("Destructible")
	assert_bool(breakable.breakable()) \
		.override_failure_message("a golem is destructible while still falling") \
		.is_false()
	assert_array(Blast.targets(root, Vector2.ZERO, def)) \
		.override_failure_message("a blast listed a live golem among the rubble") \
		.is_empty()


func test_a_petrified_golem_is_furniture_and_can_be_blown_up() -> void:
	var golem := _spawn(GOLEM, Vector2.ZERO)
	# Level with it and far to the side: an enemy despawns once it is far enough
	# below the avatar it tracks, and this one has to stay put to be blown up.
	var player := _spawn("res://scenes/Player.tscn", Vector2(4000, 0)) as CharacterBody2D
	player.can_input = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	golem.set_player_ref(player)

	# Kill it the way the game does, then let the deferred petrification land.
	(golem.get_node("Combat") as EnemyCombat).killed.emit(true)
	await _step(6)
	var breakable: Destructible = golem.get_node("Destructible")
	assert_bool(breakable.breakable()) \
		.override_failure_message("a petrified golem is still not destructible") \
		.is_true()

	_blast(Vector2.ZERO)
	await _step(6)
	assert_bool(_gone(golem)) \
		.override_failure_message("a petrified golem shrugged off a point-blank blast") \
		.is_true()


# ── How things look coming apart ────────────────────────────────────────────
## Two ways to break, and picking the wrong one is a visible bug rather than a
## subtle one.
##
## A platform is a row of identical blocks, so loose blocks are exactly what it
## should leave — that is `Fx.debris`, copies of its own texture.
##
## A trampoline and a petrified golem are each a single drawing. Throwing copies
## of THOSE around does not read as breaking, it reads as the thing multiplying,
## which is precisely what the first version of this did. They get `Fx.shards`
## instead: the sprite cut into a grid, every piece leaving on its own.
func test_a_platform_leaves_blocks_of_itself() -> void:
	_spawn(PLATFORM, Vector2.ZERO)
	_blast(Vector2.ZERO)
	await _step(2)
	assert_int(_count_of("FxDebris")) \
		.override_failure_message("a broken platform left no rubble").is_greater(0)
	assert_int(_count_of("FxShard")) \
		.override_failure_message("a platform was cut up instead of shedding blocks") \
		.is_equal(0)


func test_a_trampoline_is_cut_into_pieces_of_itself() -> void:
	_spawn(TRAMPOLINE, Vector2.ZERO)
	_blast(Vector2.ZERO)
	await _step(2)
	assert_int(_count_of("FxShard")) \
		.override_failure_message("a broken trampoline did not come apart into shards") \
		.is_greater(1)
	assert_int(_count_of("FxDebris")) \
		.override_failure_message("a trampoline threw whole copies of itself around") \
		.is_equal(0)


## The grid comes from a target piece size rather than fixed rows and columns, so
## one preset gives sensible shards for a 32×16 trampoline and a 39×36 bomb alike
## — and never more pieces than it is allowed.
func test_the_shard_grid_adapts_to_the_sprite_and_respects_its_cap() -> void:
	var preset: ShardPreset = load("res://data/fx/shards.tres")
	for size in [Vector2(32, 16), Vector2(39, 36), Vector2(8, 8), Vector2(512, 32)]:
		var grid := preset.grid_for(size)
		assert_int(grid.x).override_failure_message(
			"%s produced %d columns" % [size, grid.x]).is_greater(0)
		assert_int(grid.y).override_failure_message(
			"%s produced %d rows" % [size, grid.y]).is_greater(0)
		assert_int(grid.x * grid.y).override_failure_message(
			"%s produced %d pieces, over the cap of %d" \
			% [size, grid.x * grid.y, preset.max_pieces]) \
			.is_less_equal(preset.max_pieces)


func _count_of(class_name_wanted: String) -> int:
	var n := 0
	for child in root.get_children():
		if child.get_script() != null \
				and child.get_script().get_global_name() == class_name_wanted:
			n += 1
	return n


# ── Who is allowed to free what ─────────────────────────────────────────────
## Breaking something has two removals, chosen by `frees_locally`.
##
## Locally-built geometry — platforms, movers — is freed by every machine,
## because every machine built its own copy from the seed. That is the branch the
## cases above and the net probe exercise. A trampoline or a petrified golem is
## born from a `MultiplayerSpawner`, so its removal is mirrored and only the
## authority may free it; a client that freed one itself would leave the host
## announcing the loss of a node the client had already thrown away — the
## `ERR_UNAUTHORIZED … on_despawn_receive` line NETWORKING.md documents for
## restarts. So the client takes it out of the world instead, and this pins what
## that means: present, but invisible, on no layer, and watching nothing.
##
## A petrified golem is used because it is the recursive case — what makes it
## solid is a body it grew at runtime, not the node the component hangs off.
## (`Net.active = true` does not fake a client here: with no peer open
## `multiplayer.is_server()` is true, so the authority branch would run anyway.)
func test_a_piece_can_be_taken_out_of_the_world_without_being_freed() -> void:
	var golem := _spawn(GOLEM, Vector2.ZERO)
	var player := _spawn("res://scenes/Player.tscn", Vector2(4000, 0)) as CharacterBody2D
	player.can_input = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	golem.set_player_ref(player)
	(golem.get_node("Combat") as EnemyCombat).killed.emit(true)
	await _step(6)

	Destructible.deactivate(golem)

	assert_bool(_gone(golem)) \
		.override_failure_message("deactivate() freed the node instead of parking it") \
		.is_false()
	assert_bool(golem.visible) \
		.override_failure_message("the broken golem is still on screen").is_false()
	var solid: Array[String] = []
	_collect_solid(golem, solid)
	assert_array(solid) \
		.override_failure_message("still on a collision layer after being taken out: %s" % str(solid)) \
		.is_empty()


func _collect_solid(node: Node, out: Array[String]) -> void:
	var collider := node as CollisionObject2D
	if collider != null and (collider.collision_layer != 0 or collider.collision_mask != 0):
		out.append(String(node.name))
	for child in node.get_children():
		_collect_solid(child, out)


# ── The shaft ───────────────────────────────────────────────────────────────
## Against a real generated world: whatever a blast reaches down there, it may
## never be the walls, the floor or a level divider. The names come from
## WorldBuilder, which derives them from the plan so that a destroyed-piece path
## means the same node on every peer.
func test_the_shaft_itself_is_indestructible() -> void:
	var world: Node = load("res://scenes/World.tscn").instantiate()
	world.world_seed = 20260728
	add_child(world)

	var floor_y: float = world.max_depth - 32.0
	var doomed := Blast.targets(world, Vector2(1000.0, floor_y), def)
	var offenders: Array[String] = []
	for path in doomed:
		for forbidden in ["Wall", "Floor", "Div"]:
			if String(path).contains("/" + forbidden):
				offenders.append(String(path))
	world.free()

	assert_array(offenders) \
		.override_failure_message("a blast on the pit floor listed shaft geometry: %s" \
			% str(offenders)) \
		.is_empty()


## …and the platforms in a real world ARE listed, so the test above is not
## passing because nothing is destructible at all.
func test_a_real_world_has_breakable_platforms() -> void:
	var world: Node = load("res://scenes/World.tscn").instantiate()
	world.world_seed = 20260728
	add_child(world)

	# The platform band sits above the floor; sweep it until a blast finds
	# something, so the assertion does not depend on one seed's exact layout.
	var found := PackedStringArray()
	var y: float = world.max_depth - 400.0
	while y > 0.0 and found.is_empty():
		found = Blast.targets(world, Vector2(1000.0, y), def)
		y -= 200.0
	world.free()

	assert_array(found) \
		.override_failure_message("no platform anywhere in a generated world is breakable") \
		.is_not_empty()


## Every path a blast names has to resolve back to a Destructible on the machine
## that receives it. That is the entire multiplayer contract for destruction: the
## host sends names, and a name that does not resolve is a platform that silently
## survives on one screen and not another.
func test_every_named_target_resolves_to_a_destructible() -> void:
	var world: Node = load("res://scenes/World.tscn").instantiate()
	world.world_seed = 20260728
	add_child(world)

	var found := PackedStringArray()
	var y: float = world.max_depth - 400.0
	while y > 0.0 and found.is_empty():
		found = Blast.targets(world, Vector2(1000.0, y), def)
		y -= 200.0

	var unresolved: Array[String] = []
	for path in found:
		if get_tree().root.get_node_or_null(NodePath(path)) as Destructible == null:
			unresolved.append(String(path))
	world.free()

	assert_array(unresolved) \
		.override_failure_message("blast targets that no peer could find again: %s" \
			% str(unresolved)) \
		.is_empty()

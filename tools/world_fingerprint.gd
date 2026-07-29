extends Node
## Dumps a stable fingerprint of the generated level geometry.
##
##   godot --headless --path . tools/world_fingerprint.tscn -- [seed ...]
##
## For each seed it prints the number of collision rects, their bounding box,
## the count of exact-duplicate rects, and a SHA256 over the whole sorted set.
## Two runs with the same seed must print the same hash.
##
## This is the oracle for the world-generation work: it proves that a
## restructured generator emits the same geometry, and it is what caught the
## walls being defined twice (once by hand in World.tscn, once by the generator
## at the same coordinates).
##
## It also matters for multiplayer, where every peer has to build an identical
## world from a shared seed.

const DEFAULT_SEEDS: Array[int] = [1, 20260728, 999999]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var seeds: Array[int] = DEFAULT_SEEDS.duplicate()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		seeds.clear()
		for a: String in args:
			seeds.append(int(a))

	var any_duplicates := false
	for s: int in seeds:
		var report := await _fingerprint(s)
		print("seed %-10d rects=%-5d duplicates=%-3d bounds=%s" % [
			s, report["count"], report["duplicates"], report["bounds"]])
		print("            sha256=%s" % report["hash"])
		if report["duplicates"] > 0:
			any_duplicates = true

	if any_duplicates:
		print("\nWARNING: identical colliders stacked at the same position.")
		get_tree().quit(1)
		return
	get_tree().quit(0)


func _fingerprint(world_seed: int) -> Dictionary:
	var packed: PackedScene = load("res://scenes/World.tscn")
	var world: Node = packed.instantiate()
	# Exactly what a multiplayer client will do with the host's seed.
	world.world_seed = world_seed
	# No awaits. _ready() — and therefore the whole generation — runs
	# synchronously inside add_child(), so the geometry is readable immediately.
	# Waiting frames made this unstable: MovingPlatform starts oscillating on its
	# first _physics_process, so the sampled positions depended on how many
	# physics ticks the host machine happened to fit into those frames, and the
	# same seed produced different hashes across runs.
	get_tree().root.add_child(world)

	var rects: Array[String] = []
	var bounds := Rect2()
	var first := true
	for shape: CollisionShape2D in _collision_shapes(world.get_node("Platforms")):
		var rect := shape.shape as RectangleShape2D
		if rect == null:
			continue
		var origin := shape.global_transform.origin - rect.size * 0.5
		var r := Rect2(origin, rect.size)
		rects.append("%.4f,%.4f,%.4f,%.4f" % [r.position.x, r.position.y, r.size.x, r.size.y])
		bounds = r if first else bounds.merge(r)
		first = false

	rects.sort()
	var duplicates := 0
	for i in range(1, rects.size()):
		if rects[i] == rects[i - 1]:
			duplicates += 1

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for line: String in rects:
		ctx.update(line.to_utf8_buffer())
	var digest := ctx.finish().hex_encode()

	world.free()
	return {
		"count": rects.size(),
		"duplicates": duplicates,
		"bounds": str(bounds),
		"hash": digest,
	}


func _collision_shapes(root: Node) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	for child in root.get_children():
		var shape := child as CollisionShape2D
		if shape:
			out.append(shape)
		out.append_array(_collision_shapes(child))
	return out

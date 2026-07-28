extends GdUnitTestSuite
## Fx spawns every world-space effect under an explicit effects_root that the
## active scene registers — there is no fallback to current_scene. Bursts are
## pooled and returned on their `finished` signal; popups and ghosts free
## themselves from their scene's AnimationPlayer.

var root: Node2D


func before_test() -> void:
	root = Node2D.new()
	add_child(root)
	Fx.effects_root = root


func after_test() -> void:
	Fx.effects_root = null
	if is_instance_valid(root):
		root.free()


func test_without_a_root_nothing_spawns_and_nothing_crashes() -> void:
	Fx.effects_root = null
	Fx.burst(Vector2.ZERO, load("res://data/fx/dust.tres"))
	Fx.popup(Vector2.ZERO, "nope")
	assert_int(root.get_child_count()) \
		.override_failure_message("effects appeared without a registered effects_root") \
		.is_equal(0)


func test_burst_is_pooled_and_reused_after_finishing() -> void:
	var preset: BurstPreset = load("res://data/fx/dust.tres")
	Fx.burst(Vector2(100, 100), preset)
	assert_int(root.get_child_count()).is_equal(1)
	var first := root.get_child(0)

	var done := [false]
	(first as CPUParticles2D).finished.connect(func() -> void: done[0] = true)
	for i in 600: # dust lives 0.45 s; physics runs at 120 Hz
		await get_tree().physics_frame
		if done[0]:
			break
	assert_bool(done[0]) \
		.override_failure_message("one-shot burst never emitted `finished`") \
		.is_true()

	# The next burst must reuse the pooled node, not grow the tree.
	Fx.burst(Vector2(200, 200), preset)
	assert_int(root.get_child_count()).is_equal(1)
	assert_object(root.get_child(0)).is_same(first)


func test_popup_fills_its_label_and_frees_itself() -> void:
	Fx.popup(Vector2(50, 50), "+300  x3", Color.RED, 24)
	assert_int(root.get_child_count()).is_equal(1)
	var popup := root.get_child(0)
	var label: Label = popup.get_node("Label")
	assert_str(label.text).is_equal("+300  x3")

	for i in 600: # the float_up clip is 1.05 s, then a method track frees it
		await get_tree().physics_frame
		if not is_instance_valid(popup):
			break
	assert_bool(is_instance_valid(popup)) \
		.override_failure_message("popup did not free itself after its animation") \
		.is_false()


func test_the_pool_dies_with_its_root_and_recovers() -> void:
	var preset: BurstPreset = load("res://data/fx/dust.tres")
	Fx.burst(Vector2.ZERO, preset)
	assert_int(root.get_child_count()).is_equal(1)

	# The scene hosting the effects goes away (restart does this)…
	root.free()
	root = Node2D.new()
	add_child(root)
	Fx.effects_root = root

	# …and Fx must keep working against the new root without touching
	# freed pool entries.
	Fx.burst(Vector2.ZERO, preset)
	assert_int(root.get_child_count()).is_equal(1)

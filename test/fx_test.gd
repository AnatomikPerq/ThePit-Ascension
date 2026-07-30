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
	# Fx.listener_position is global and any suite that builds a World leaves it
	# wherever that world's avatar stood — 7700 px down the pit. Every
	# distance-scaled assertion below would then be measuring a kill on the far
	# side of the map.
	Fx.listener_position = Vector2.ZERO


func after_test() -> void:
	Fx.effects_root = null
	Fx.listener_position = Vector2.ZERO
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


## Shake is the only feedback a kill has left since the hitstop was removed, so
## it has to actually reach the screen — and be big enough to see. The old
## amplitude put a hit at ±3.7 px, which is what "the camera shake is gone"
## turned out to mean.
func test_shake_produces_a_visible_offset_and_decays_to_nothing() -> void:
	Fx.shake(1.0)
	# Each read is a fresh random sample inside the trauma envelope, so a
	# single one can land near zero. The amplitude is what is being asserted.
	var peak := 0.0
	for i in 10:
		peak = maxf(peak, Fx.get_shake_offset().length())
	assert_float(peak) \
		.override_failure_message("full trauma shifted the camera by %.1f px at most" % peak) \
		.is_greater(20.0)

	# Trauma bleeds off in _process, and the offset with it.
	for i in 300:
		await get_tree().process_frame
		if Fx.get_shake_offset() == Vector2.ZERO:
			break
	assert_vector(Fx.get_shake_offset()) \
		.override_failure_message("shake never settled back to zero").is_equal(Vector2.ZERO)


func test_a_kill_shakes_the_camera() -> void:
	Game.new_run()
	# Trauma is global state; start from rest whatever ran before this.
	for i in 300:
		if Fx.get_shake_offset() == Vector2.ZERO:
			break
		await get_tree().process_frame
	assert_vector(Fx.get_shake_offset()).is_equal(Vector2.ZERO)
	Game.enemy_killed(Vector2(100, 100), 100, Color.WHITE)
	assert_vector(Fx.get_shake_offset()) \
		.override_failure_message("killing something did not move the camera at all") \
		.is_not_equal(Vector2.ZERO)


## Distance-scaled feedback. Kills, blasts and shockwaves all fire on every
## machine in a session, so their kick has to fade with distance — otherwise
## every player's camera jumps for everybody else's fights, anywhere in the pit.
func test_loudness_falls_off_from_the_listener_and_never_goes_negative() -> void:
	Fx.listener_position = Vector2.ZERO
	assert_float(Fx.loudness_at(Vector2.ZERO, 1000.0)).is_equal_approx(1.0, 0.001)
	assert_float(Fx.loudness_at(Vector2(500, 0), 1000.0)).is_equal_approx(0.5, 0.001)
	assert_float(Fx.loudness_at(Vector2(4000, 0), 1000.0)) \
		.override_failure_message("something far away produced negative loudness") \
		.is_equal_approx(0.0, 0.001)
	# A range of zero means "distance does not apply", not "silent".
	assert_float(Fx.loudness_at(Vector2(9999, 0), 0.0)).is_equal_approx(1.0, 0.001)


func test_a_distant_event_does_not_shake_the_camera() -> void:
	for i in 300:
		if Fx.get_shake_offset() == Vector2.ZERO:
			break
		await get_tree().process_frame
	Fx.shake_from(Vector2(20000, 0), 1.0, 2600.0)
	assert_vector(Fx.get_shake_offset()) \
		.override_failure_message("an event 20000 px away still shook the screen") \
		.is_equal(Vector2.ZERO)


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

extends GdUnitTestSuite
## Getting squeezed between two platforms.
##
## The penalty used to be a heart and then two seconds of drifting downward at
## a fifth of gravity with the controls dead — long enough to read as the game
## having broken rather than having hit you. It is now a heart, a pop clear of
## the squeeze, and half a second of falling through the level at normal speed.
##
## The case that made the timer alone insufficient: handing collision back
## while still inside the wall is an instant re-crush and another heart, so
## recovery waits for the geometry as well as the clock.

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")

var _root: Node2D
var _player: CharacterBody2D


func before_test() -> void:
	Game.new_run()
	_root = Node2D.new()
	add_child(_root)


func after_test() -> void:
	if is_instance_valid(_root):
		_root.free()


## A solid slab of level geometry.
func _slab(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	_root.add_child(body)
	body.global_position = center


## The player, wedged: its 48×64 body spans -32..32 and both slabs reach 12 px
## into it, which is the diagonal-squeeze case the crush check exists for.
func _wedge() -> void:
	_slab(Vector2(0, -52), Vector2(600, 64))
	_slab(Vector2(0, 52), Vector2(600, 64))
	_player = PLAYER_SCENE.instantiate()
	_root.add_child(_player)
	_player.global_position = Vector2.ZERO


func test_a_squeeze_costs_a_heart_and_pops_the_player_out() -> void:
	_wedge()
	for i in 4:
		await get_tree().physics_frame

	assert_bool(_player.is_crushed) \
		.override_failure_message("wedged between two slabs and never registered a crush") \
		.is_true()
	assert_int(_player.health).is_equal(4)
	assert_float(_player.velocity.y) \
		.override_failure_message("the crush did not pop the player upward (v.y=%.1f)" \
			% _player.velocity.y) \
		.is_less(0.0)
	assert_bool(_player.get_collision_mask_value(Layers.BIT_WORLD)) \
		.override_failure_message("the player should fall through the level while crushed") \
		.is_false()


## Normal gravity, not the old fifth of it: half a second has to actually carry
## the player somewhere.
func test_the_fall_is_at_normal_speed() -> void:
	_wedge()
	for i in 60: # 0.5 s at 120 Hz
		await get_tree().physics_frame
	assert_float(_player.global_position.y) \
		.override_failure_message("after half a second the player had moved %.0f px" \
			% _player.global_position.y) \
		.is_greater(150.0)


func test_collision_and_control_come_back_after_the_window() -> void:
	_wedge()
	for i in 90: # 0.75 s: the 0.5 s timer plus room to clear the slabs
		await get_tree().physics_frame

	assert_bool(_player.is_crushed) \
		.override_failure_message("still crushed well past the recovery window").is_false()
	assert_bool(_player.can_input) \
		.override_failure_message("the controls never came back").is_true()
	assert_bool(_player.get_collision_mask_value(Layers.BIT_WORLD)).is_true()
	assert_int(_player.health) \
		.override_failure_message("one squeeze cost %d hearts" % (5 - _player.health)) \
		.is_equal(4)


## The re-crush loop. Recovery on a timer alone hands collision back wherever
## the player happens to be, and inside the same squeeze that is another heart
## immediately. Asked to recover while still wedged, it must decline.
func test_recovery_declines_while_the_squeeze_still_holds() -> void:
	_wedge()
	for i in 2:
		await get_tree().physics_frame
	assert_bool(_player.is_crushed).is_true()

	# Two frames in, the pop has barely started: the body still spans both
	# slabs, so this is exactly the moment recovery must refuse.
	_player._end_crush()

	assert_bool(_player.is_crushed) \
		.override_failure_message("recovery handed collision back inside the squeeze") \
		.is_true()
	assert_bool(_player.get_collision_mask_value(Layers.BIT_WORLD)).is_false()
	assert_int(_player.health) \
		.override_failure_message("the squeeze cost %d hearts" % (5 - _player.health)) \
		.is_equal(4)

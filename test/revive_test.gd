extends GdUnitTestSuite
## Going down, and being picked back up.
##
## In a session running out of hearts is not the end of you: the body drops
## where it fell and anyone still climbing can spend a heart on it. Solo is
## untouched, and that is half of what this suite is for — the other half is the
## arithmetic nobody should be able to cheat, which is that a pick-up costs
## exactly one heart and cannot be paid for by somebody down to their last.
##
## `Net.active` is set directly rather than by hosting: none of this needs a
## socket, and single-player must never open one.

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const ROSTER: CharacterRoster = preload("res://data/characters/roster.tres")

var _root: Node2D


func before_test() -> void:
	Game.new_run()
	_root = Node2D.new()
	add_child(_root)


func after_test() -> void:
	Net.active = false
	Net.mode = Net.Mode.COOP
	if is_instance_valid(_root):
		_root.free()


func _avatar(peer_id: int) -> CharacterBody2D:
	var avatar: CharacterBody2D = PLAYER_SCENE.instantiate()
	avatar.name = "Avatar%d" % peer_id
	avatar.peer_id = peer_id
	avatar.character = ROSTER.by_id(&"cyn")
	_root.add_child(avatar)
	avatar.global_position = Vector2(0, -4000) # clear of everything
	return avatar


func _down(avatar: CharacterBody2D) -> void:
	avatar.health = 0
	avatar._go_down()


# ── Solo is unchanged ───────────────────────────────────────────────────────
func test_solo_death_is_still_death() -> void:
	var avatar := _avatar(1)
	var died := [false]
	avatar.player_died.connect(func() -> void: died[0] = true)
	avatar.health = 1
	avatar.take_damage()
	assert_bool(avatar.is_downed) \
		.override_failure_message("solo has no downed state to be in").is_false()
	# The death tween runs a second before it frees and emits; what matters here
	# is that the avatar took the solo path at all.
	assert_bool(avatar.can_input).is_false()


# ── The body ────────────────────────────────────────────────────────────────
func test_running_out_of_hearts_in_a_session_leaves_a_body() -> void:
	Net.active = true
	var avatar := _avatar(1)
	var downed := [false]
	avatar.player_downed.connect(func() -> void: downed[0] = true)
	avatar.health = 1
	avatar.take_damage()

	assert_bool(avatar.is_downed) \
		.override_failure_message("a session death should leave a body, not nothing").is_true()
	assert_bool(downed[0]).is_true()
	assert_bool(is_instance_valid(avatar)).is_true()
	assert_int(avatar.health).is_equal(0)
	assert_bool(avatar.can_input).is_false()


func test_a_body_is_invisible_to_everything_but_the_floor() -> void:
	Net.active = true
	var avatar := _avatar(1)
	_down(avatar)
	assert_int(avatar.collision_layer) \
		.override_failure_message("enemies, trampolines and rivals can still see the corpse") \
		.is_equal(Layers.NONE)
	assert_bool(avatar.get_collision_mask_value(Layers.BIT_WORLD)) \
		.override_failure_message("the body has to fall to the nearest floor").is_true()
	assert_bool(avatar.hurt_box.monitoring).is_false()


func test_a_body_shows_the_died_frame_lying_down() -> void:
	Net.active = true
	var avatar := _avatar(1)
	_down(avatar)
	assert_str(String(avatar.sprite.animation)).is_equal("died")
	assert_float(avatar.sprite.rotation_degrees) \
		.override_failure_message("a body should be on its back, not standing up dead") \
		.is_equal(-90.0)


func test_a_body_cannot_be_hurt_again() -> void:
	Net.active = true
	var avatar := _avatar(1)
	_down(avatar)
	assert_bool(avatar.take_damage()) \
		.override_failure_message("something took a heart off a corpse").is_false()
	assert_int(avatar.health).is_equal(0)


func test_a_body_still_falls() -> void:
	Net.active = true
	var avatar := _avatar(1)
	var start := avatar.global_position.y
	_down(avatar)
	for i in 30:
		await get_tree().physics_frame
	assert_float(avatar.global_position.y) \
		.override_failure_message("a body has to drop to the ground, not hang in the air") \
		.is_greater(start)


# ── The pick-up ─────────────────────────────────────────────────────────────
func test_standing_up_costs_the_reviver_one_heart() -> void:
	Net.active = true
	var body := _avatar(1)
	var reviver := _avatar(2)
	_down(body)

	body.stand_up()
	reviver.pay_revive()

	assert_bool(body.is_downed).is_false()
	assert_int(body.health) \
		.override_failure_message("a revived climber comes back on one heart").is_equal(1)
	assert_bool(body.can_input).is_true()
	assert_int(reviver.health) \
		.override_failure_message("the pick-up should have cost exactly one heart").is_equal(4)


func test_a_revived_climber_is_solid_again() -> void:
	Net.active = true
	var body := _avatar(1)
	_down(body)
	body.stand_up()
	assert_int(body.collision_layer).is_equal(Layers.PLAYER)
	assert_bool(body.get_collision_mask_value(Layers.BIT_WORLD)).is_true()


func test_a_revived_climber_gets_a_moment_of_grace() -> void:
	Net.active = true
	var body := _avatar(1)
	_down(body)
	body.stand_up()
	assert_bool(body.invincible) \
		.override_failure_message("standing up under an enemy would be instant death again") \
		.is_true()


## The rule the whole cost hangs on. pay_revive() is only ever reached through
## World._resolve_revive, which refuses a reviver on one heart — but the floor
## here is the backstop, because a revive must never be able to kill the person
## paying for it.
func test_paying_can_never_take_the_last_heart() -> void:
	Net.active = true
	var reviver := _avatar(2)
	reviver.health = 1
	reviver.pay_revive()
	assert_int(reviver.health) \
		.override_failure_message("paying for a revive killed the reviver").is_equal(1)


func test_standing_up_twice_changes_nothing() -> void:
	Net.active = true
	var body := _avatar(1)
	_down(body)
	body.stand_up()
	body.health = 3
	body.stand_up() # already up: must not reset the hearts it has earned since
	assert_int(body.health).is_equal(3)

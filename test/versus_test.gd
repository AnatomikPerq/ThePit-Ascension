extends GdUnitTestSuite
## Race mode turns the other climbers into obstacles and targets. Co-op does
## not, and solo cannot: one predicate, Net.is_versus(), gates all of it, and
## everything below is a check that nothing leaks across that line.
##
## `Net.active` is set directly here rather than by hosting. is_versus() is a
## pure function of two variables and no socket is needed to ask it — which is
## also the property that keeps single-player from ever opening one.

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")

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


func _session(mode: Net.Mode) -> void:
	Net.active = true
	Net.mode = mode


## peer_id, and the position it stands at.
func _avatar(peer_id: int, at: Vector2) -> CharacterBody2D:
	var avatar: CharacterBody2D = PLAYER_SCENE.instantiate()
	avatar.name = "Avatar%d" % peer_id
	avatar.peer_id = peer_id
	_root.add_child(avatar)
	avatar.global_position = at
	return avatar


# ── The predicate ───────────────────────────────────────────────────────────
func test_solo_is_never_versus() -> void:
	Net.mode = Net.Mode.RACE # left over from a previous session
	assert_bool(Net.is_versus()) \
		.override_failure_message("solo play must never be versus").is_false()


func test_coop_is_not_versus_and_race_is() -> void:
	_session(Net.Mode.COOP)
	assert_bool(Net.is_versus()).is_false()
	_session(Net.Mode.RACE)
	assert_bool(Net.is_versus()).is_true()


# ── Bodies ──────────────────────────────────────────────────────────────────
func test_racers_are_solid_to_each_other() -> void:
	_session(Net.Mode.RACE)
	var avatar := _avatar(1, Vector2.ZERO)
	assert_bool(avatar.get_collision_mask_value(Layers.BIT_PLAYER)) \
		.override_failure_message("racers should be able to stand on each other").is_true()


func test_coop_players_pass_through_each_other() -> void:
	_session(Net.Mode.COOP)
	var avatar := _avatar(1, Vector2.ZERO)
	assert_bool(avatar.get_collision_mask_value(Layers.BIT_PLAYER)) \
		.override_failure_message("co-op players must not block each other").is_false()


func test_solo_player_is_unchanged() -> void:
	var avatar := _avatar(1, Vector2.ZERO)
	assert_bool(avatar.get_collision_mask_value(Layers.BIT_PLAYER)).is_false()
	assert_bool(avatar.hurt_box.monitoring) \
		.override_failure_message("solo play should not even watch for hostile hitboxes") \
		.is_false()


# ── Attacks ─────────────────────────────────────────────────────────────────
func test_a_rivals_strike_hurts_the_rival_and_not_its_owner() -> void:
	_session(Net.Mode.RACE)
	var attacker := _avatar(1, Vector2.ZERO)
	var victim := _avatar(2, Vector2.ZERO)

	var strike: Area2D = load("res://scenes/Strike.tscn").instantiate()
	strike.setup(attacker, true)
	_root.add_child(strike)
	strike.global_position = Vector2.ZERO

	# Areas need a step or two before an overlap is reported.
	for i in 6:
		await get_tree().physics_frame

	assert_int(victim.health) \
		.override_failure_message("a rival's strike did no damage in a race").is_equal(4)
	assert_int(attacker.health) \
		.override_failure_message("the striker hurt itself").is_equal(5)


func test_the_same_strike_is_harmless_in_coop() -> void:
	_session(Net.Mode.COOP)
	var attacker := _avatar(1, Vector2.ZERO)
	var teammate := _avatar(2, Vector2.ZERO)

	var strike: Area2D = load("res://scenes/Strike.tscn").instantiate()
	strike.setup(attacker, true)
	_root.add_child(strike)
	strike.global_position = Vector2.ZERO

	for i in 6:
		await get_tree().physics_frame

	assert_int(teammate.health) \
		.override_failure_message("co-op players hurt each other").is_equal(5)


## Damage resolved on another machine arrives as remote_hurt. It used to accept
## the host only, which is right for world hazards and wrong for a race, where
## the peer landing the hit is the rival rather than peer 1.
func test_remote_hurt_takes_a_rivals_word_only_in_a_race() -> void:
	_session(Net.Mode.COOP)
	var avatar := _avatar(2, Vector2.ZERO)
	avatar.remote_hurt() # sender id is 0 here: not the host
	assert_int(avatar.health) \
		.override_failure_message("co-op: only the host may resolve harm").is_equal(5)

	_session(Net.Mode.RACE)
	avatar.remote_hurt()
	assert_int(avatar.health) \
		.override_failure_message("race: a rival's hit never landed").is_equal(4)

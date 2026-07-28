extends GdUnitTestSuite
## The contact matrix: for every enemy, what happens when the player strikes it,
## stomps it with a downward dash, or lands on it without one.
##
## This is the oracle for collapsing the five near-identical enemy scripts onto a
## shared base. The five ladders are NOT interchangeable and a naive merge would
## silently change how the game plays:
##
##   enemy    plain landing        dash stomp        strike     leaves behind
##   golem    converts             converts          converts   a platform
##   slime    converts             converts          converts   a trampoline
##   pursuer  hurts the player     dies              dies       nothing
##   bat      hurts the player     dies              dies       nothing
##   spitter  hurts the player     dies              dies       nothing
##
## Each case runs in its own container which is freed immediately afterwards.
## That is not ceremony: the first version of this suite reused the tree, and a
## golem petrified in one case became a StaticBody2D at the same coordinates in
## the next, so the player landed on it, `is_on_floor()` cleared `dashing_down`,
## and three enemies "mysteriously" refused to die.

const CASES := {
	"golem": {
		"scene": "res://scenes/Golem.tscn",
		"needs_dash": false, "rebound": -600.0, "score": 50, "leaves": "",
	},
	"slime": {
		"scene": "res://scenes/Slime.tscn",
		"needs_dash": false, "rebound": -700.0, "score": 75, "leaves": "Trampoline.tscn",
	},
	"pursuer": {
		"scene": "res://scenes/Pursuer.tscn",
		"needs_dash": true, "rebound": -900.0, "score": 150, "leaves": "",
	},
	"bat": {
		"scene": "res://scenes/Bat.tscn",
		"needs_dash": true, "rebound": -900.0, "score": 125, "leaves": "",
	},
	"spitter": {
		"scene": "res://scenes/Spitter.tscn",
		"needs_dash": true, "rebound": -900.0, "score": 150, "leaves": "",
	},
}

## Result of one scripted contact.
class Outcome:
	var enemy_died: bool
	var enemy_freed: bool
	var player_health: int
	var player_velocity_y: float
	var player_dashing: bool
	var score: int
	var kills: int
	var spawned: Array[String] = []


func _run_contact(key: String, dashing: bool, use_strike: bool) -> Outcome:
	Game.new_run()
	var spec: Dictionary = CASES[key]

	var root := Node2D.new()
	add_child(root)

	var enemy: Node2D = load(spec["scene"]).instantiate()
	var player: CharacterBody2D = load("res://scenes/Player.tscn").instantiate()
	root.add_child(enemy)
	root.add_child(player)
	enemy.global_position = Vector2.ZERO
	if enemy.has_method("set_player_ref"):
		enemy.set_player_ref(player)

	var strike: Area2D = null
	if use_strike:
		# Park the player out of reach so only the strike touches the enemy.
		player.global_position = Vector2(0, -4000)
		strike = load("res://scenes/Strike.tscn").instantiate()
		strike.setup(player, true)
		root.add_child(strike)
		strike.global_position = Vector2.ZERO
	else:
		# Falling onto the enemy from just above.
		player.global_position = Vector2(0, -40)
		player.velocity = Vector2(0, 200.0)
		player.dashing_down = dashing

	# Count physics frames, never wall-clock. Areas need a step or two before
	# get_overlapping_bodies() reports anything, and an earlier version waited
	# 50ms instead: the first case in a run spent that budget loading scenes off
	# disk, so it saw fewer physics steps than the rest and failed at random.
	# Six frames is enough to register the overlap and short enough (50ms) that
	# gravity has not carried the player past the enemy.
	for i in 6:
		await get_tree().physics_frame

	var out := Outcome.new()
	out.enemy_freed = not is_instance_valid(enemy) or enemy.is_queued_for_deletion()
	if out.enemy_freed:
		out.enemy_died = true
	else:
		var combat := enemy.get_node_or_null("Combat")
		out.enemy_died = combat != null and combat.is_dead
	out.player_health = player.health
	out.player_velocity_y = player.velocity.y
	out.player_dashing = player.dashing_down
	out.score = Game.local_run().score
	out.kills = Game.local_run().kills
	for child in root.get_children():
		if child != enemy and child != player and child != strike:
			out.spawned.append(child.scene_file_path.get_file())

	root.free()
	return out


func test_dash_stomp_kills_every_enemy() -> void:
	for key in CASES:
		var r := await _run_contact(key, true, false)
		assert_bool(r.enemy_died) \
			.override_failure_message("%s survived a dash stomp" % key).is_true()
		assert_int(r.kills) \
			.override_failure_message("%s registered %d kills, expected 1" % [key, r.kills]) \
			.is_equal(1)


func test_dash_stomp_rebounds_the_player_and_ends_the_dash() -> void:
	for key in CASES:
		var r := await _run_contact(key, true, false)
		assert_float(r.player_velocity_y) \
			.override_failure_message("%s did not bounce the player upward (v.y=%.1f)" % [key, r.player_velocity_y]) \
			.is_less(0.0)
		assert_bool(r.player_dashing) \
			.override_failure_message("%s left the player still dashing" % key).is_false()


func test_dash_stomp_awards_the_documented_score() -> void:
	for key in CASES:
		var r := await _run_contact(key, true, false)
		assert_int(r.score) \
			.override_failure_message("%s awarded %d, expected %d" % [key, r.score, CASES[key]["score"]]) \
			.is_equal(int(CASES[key]["score"]))


## The load-bearing asymmetry. Golem and slime convert under any downward
## contact; the other three demand a dash and punish a plain landing.
func test_plain_landing_respects_the_dash_requirement() -> void:
	for key in CASES:
		var needs_dash: bool = CASES[key]["needs_dash"]
		var r := await _run_contact(key, false, false)

		if needs_dash:
			assert_bool(r.enemy_died) \
				.override_failure_message("%s died to a plain landing; it should require a dash" % key) \
				.is_false()
			assert_int(r.player_health) \
				.override_failure_message("%s did not hurt the player on a plain landing" % key) \
				.is_less(5)
		else:
			assert_bool(r.enemy_died) \
				.override_failure_message("%s survived a plain landing; it should convert" % key) \
				.is_true()
			assert_int(r.player_health) \
				.override_failure_message("%s hurt the player on a legal stomp" % key) \
				.is_equal(5)


func test_strike_kills_every_enemy() -> void:
	for key in CASES:
		var r := await _run_contact(key, false, true)
		assert_bool(r.enemy_died) \
			.override_failure_message("%s survived a strike" % key).is_true()
		assert_int(r.player_health) \
			.override_failure_message("%s hurt the player who struck it from range" % key) \
			.is_equal(5)


## Golem petrifies into a platform in place rather than freeing itself; slime is
## replaced by a trampoline. Both are the point of those enemies.
func test_conversions_leave_the_right_thing_behind() -> void:
	for key in CASES:
		var leaves: String = CASES[key]["leaves"]
		var r := await _run_contact(key, true, false)
		if leaves.is_empty():
			continue
		assert_array(r.spawned) \
			.override_failure_message("%s should leave a %s, spawned: %s" % [key, leaves, str(r.spawned)]) \
			.contains([leaves])


func test_golem_stays_in_the_tree_as_a_platform() -> void:
	var r := await _run_contact("golem", true, false)
	assert_bool(r.enemy_freed) \
		.override_failure_message("the golem freed itself instead of becoming a platform") \
		.is_false()
	assert_bool(r.enemy_died).is_true()


func test_slime_removes_itself() -> void:
	var r := await _run_contact("slime", true, false)
	assert_bool(r.enemy_freed) \
		.override_failure_message("the slime should be replaced by its trampoline") \
		.is_true()

extends GdUnitTestSuite
## Run state is per player. Game holds one PlayerRun per peer; kills carry the
## killer's peer id; combo chains never bleed between players. This is the
## contract multiplayer stands on — and solo play is just the single-entry
## case of the same structure.


func after_test() -> void:
	# Leave the default solo run behind for whatever runs next.
	Game.new_run()


func test_solo_run_is_the_single_local_entry() -> void:
	Game.new_run()
	assert_int(Game.runs.size()).is_equal(1)
	assert_object(Game.local_run()).is_not_null()
	assert_int(Game.local_run().peer_id).is_equal(Game.local_peer_id)


func test_kills_are_credited_to_the_killer_only() -> void:
	Game.new_run([1, 2] as Array[int])
	Game.enemy_killed(Vector2.ZERO, 100, Color.WHITE, 2)
	Game.enemy_killed(Vector2.ZERO, 100, Color.WHITE, 2)

	var second := Game.run_of(2)
	assert_int(second.kills).is_equal(2)
	assert_int(second.score).is_equal(100 + 200) # combo doubles the second kill
	assert_int(second.combo).is_equal(2)

	var first := Game.run_of(1)
	assert_int(first.kills).is_equal(0)
	assert_int(first.score).is_equal(0)
	assert_int(first.combo).is_equal(0)


func test_killer_peer_zero_means_the_local_player() -> void:
	Game.new_run([1, 2] as Array[int])
	Game.enemy_killed(Vector2.ZERO, 100, Color.WHITE)
	assert_int(Game.local_run().kills).is_equal(1)
	assert_int(Game.run_of(2).kills).is_equal(0)


func test_flat_score_lands_on_the_right_run() -> void:
	Game.new_run([1, 2] as Array[int])
	Game.add_score(500, Vector2.INF, Color.WHITE, 2)
	Game.add_score(250) # local default
	assert_int(Game.run_of(2).score).is_equal(500)
	assert_int(Game.local_run().score).is_equal(250)


func test_score_changed_reports_the_peer_it_belongs_to() -> void:
	Game.new_run([1, 2] as Array[int])
	var seen: Array = []
	var handler := func(peer_id: int, score: int, _combo: int) -> void:
		seen.append([peer_id, score])
	Game.score_changed.connect(handler)
	Game.add_score(100, Vector2.INF, Color.WHITE, 2)
	Game.score_changed.disconnect(handler)
	assert_array(seen).contains([[2, 100]])

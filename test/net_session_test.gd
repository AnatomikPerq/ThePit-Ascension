extends GdUnitTestSuite
## Mode semantics of the shared-run ending. The two-instance net probe
## (tools/run_net_probe.sh) proves the transport — same world, mirrored
## enemies, replicated score; this suite pins what the ending MEANS:
## co-op is a shared victory, a race has exactly one winner.

var _w: Node


func before_test() -> void:
	# Pin the climber: these assertions are about hearts and upgrade pools, and
	# the character is otherwise whatever this machine last played.
	Game.selected_character = &"cyn"
	_w = load("res://scenes/World.tscn").instantiate()
	_w.world_seed = 1
	add_child(_w)


func after_test() -> void:
	Net.mode = Net.Mode.COOP
	if is_instance_valid(_w):
		_w.free()
	Game.new_run()


func test_coop_end_is_a_shared_victory() -> void:
	Net.mode = Net.Mode.COOP
	_w._end_session(999) # somebody else reached the surface
	assert_bool(_w.victory_screen.visible) \
		.override_failure_message("co-op: everyone should see the victory screen").is_true()
	assert_bool(_w.game_over_screen.visible).is_false()
	assert_str(_w.victory_screen.get_node("Stats").text) \
		.contains("PLAYER 999 REACHED THE SURFACE FIRST")


func test_race_loss_shows_race_over_not_victory() -> void:
	Net.mode = Net.Mode.RACE
	_w._end_session(999)
	assert_bool(_w.game_over_screen.visible) \
		.override_failure_message("race: a loser must not see the victory screen").is_true()
	assert_bool(_w.victory_screen.visible).is_false()
	assert_str(_w.game_over_screen.get_node("Title").text).is_equal("RACE OVER")
	assert_str(_w.game_over_screen.get_node("Stats").text).contains("PLAYER 999 WON THE RACE")


func test_race_winner_sees_victory() -> void:
	Net.mode = Net.Mode.RACE
	_w._end_session(Game.local_peer_id)
	assert_bool(_w.victory_screen.visible).is_true()
	assert_bool(_w.game_over_screen.visible).is_false()


func test_session_end_stops_the_simulation() -> void:
	_w._end_session(999)
	assert_bool(_w._should_simulate()) \
		.override_failure_message("enemies must stop spawning once the run is decided").is_false()

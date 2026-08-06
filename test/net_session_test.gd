extends GdUnitTestSuite
## Mode semantics of the shared-run ending. The two-instance net probe
## (tools/run_net_probe.sh) proves the transport — same world, mirrored
## enemies, replicated score; this suite pins what the ending MEANS:
## co-op is a shared victory, a race has exactly one winner.
##
## The mode is set on the WORLD's session rather than on `Net`, and that is the
## contract, not a detail of the test. A dedicated server runs a race in one room
## and a co-op climb in the next out of one process, so "which mode is this" stopped
## being a fact about the machine the moment rooms existed — a world that asked the
## Net autoload would give both rooms whichever answer was written last.

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


## Put the world in a live session of the given mode. Applied after _ready() on
## purpose: the roster these tests want is the solo one an inactive session
## builds, and only the ending is under test.
func _in_session(mode: int) -> void:
	_w.session.active = true
	_w.session.mode = mode


func test_coop_end_is_a_shared_victory() -> void:
	_in_session(Net.Mode.COOP)
	_w._end_session(999) # somebody else reached the surface
	assert_bool(_w.victory_screen.visible) \
		.override_failure_message("co-op: everyone should see the victory screen").is_true()
	assert_bool(_w.game_over_screen.visible).is_false()
	assert_str(_w.victory_screen.get_node("Stats").text) \
		.contains("PLAYER 999 REACHED THE SURFACE FIRST")


func test_race_loss_shows_race_over_not_victory() -> void:
	_in_session(Net.Mode.RACE)
	_w._end_session(999)
	assert_bool(_w.game_over_screen.visible) \
		.override_failure_message("race: a loser must not see the victory screen").is_true()
	assert_bool(_w.victory_screen.visible).is_false()
	assert_str(_w.game_over_screen.get_node("Title").text).is_equal("RACE OVER")
	assert_str(_w.game_over_screen.get_node("Stats").text).contains("PLAYER 999 WON THE RACE")


func test_race_winner_sees_victory() -> void:
	_in_session(Net.Mode.RACE)
	_w._end_session(Game.local_peer_id)
	assert_bool(_w.victory_screen.visible).is_true()
	assert_bool(_w.game_over_screen.visible).is_false()


## A dedicated server's room manager listens for this and nothing else. Without
## it a finished room stays "running" for the rest of the server's life: it never
## returns to its lobby, and nobody in it can start another climb.
func test_the_end_of_a_run_is_announced() -> void:
	var heard := [0]
	_w.run_ended.connect(func() -> void: heard[0] += 1)
	_in_session(Net.Mode.COOP)
	_w._end_session(999)
	assert_int(heard[0]) \
		.override_failure_message("nothing told the room that its run had ended") \
		.is_equal(1)


func test_a_wipe_is_announced_the_same_way() -> void:
	var heard := [0]
	_w.run_ended.connect(func() -> void: heard[0] += 1)
	_in_session(Net.Mode.COOP)
	_w._end_session_wiped()
	assert_int(heard[0]).is_equal(1)
	# Twice must not announce twice — the room would return to its lobby, and
	# then be told to again.
	_w._end_session_wiped()
	assert_int(heard[0]).is_equal(1)


func test_session_end_stops_the_simulation() -> void:
	_w._end_session(999)
	assert_bool(_w._should_simulate()) \
		.override_failure_message("enemies must stop spawning once the run is decided").is_false()

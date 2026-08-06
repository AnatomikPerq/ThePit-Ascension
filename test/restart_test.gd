extends GdUnitTestSuite
## What a host restart must not carry over.
##
## An avatar's node path is identical in every run, so for the frames between a
## restart and a client finishing its own world swap, the host is still
## receiving where that player was in the run that just ended. Read as progress,
## that position handed the client a free upgrade at the bottom of the new pit —
## and one platform higher it would have ended the fresh run on the spot.
##
## Every avatar therefore reports the seed of the run it is climbing, in the
## same replicated packet as its position, and nothing awards or ends without
## checking it.

var _w: Node


func before_test() -> void:
	# Pin the climber: these assertions are about hearts and upgrade pools, and
	# the character is otherwise whatever this machine last played.
	Game.selected_character = &"cyn"
	Game.new_run()
	_w = load("res://scenes/World.tscn").instantiate()
	_w.world_seed = 1
	add_child(_w)


func after_test() -> void:
	# _show_upgrade_menu() pauses the tree in solo. Never leave it paused: the
	# next case would run inside it.
	get_tree().paused = false
	Net.active = false
	Net.mode = Net.Mode.COOP
	if is_instance_valid(_w):
		_w.free()
	Game.new_run()


func test_the_local_avatar_always_reports_its_own_run() -> void:
	assert_bool(_w._reports_this_run(_w.player)) \
		.override_failure_message("the avatar this machine steers is always in this run") \
		.is_true()
	assert_int(_w.player.run_seed).is_equal(_w.world_seed)


func test_an_avatar_reporting_another_run_is_not_making_progress() -> void:
	_w.player.run_seed = _w.world_seed + 1
	assert_bool(_w._reports_this_run(_w.player)).is_false()


## The reported bug, in one case.
func test_a_stale_position_earns_no_upgrade() -> void:
	var avatar: CharacterBody2D = _w.player
	var first_milestone: float = _w._upgrade_milestones[avatar.peer_id][0]
	avatar.global_position.y = first_milestone - 1000.0
	avatar.run_seed = 4242 # where we were in the run that just ended

	_w._check_milestones()
	assert_bool(_w.upgrade_menu.visible) \
		.override_failure_message("a position from another run opened the upgrade menu") \
		.is_false()
	assert_int(Game.local_run().score) \
		.override_failure_message("a position from another run paid out %d points" \
			% Game.local_run().score) \
		.is_equal(0)

	# The same climb, reported by the run it belongs to, does count.
	avatar.run_seed = _w.world_seed
	_w._check_milestones()
	assert_bool(_w.upgrade_menu.visible) \
		.override_failure_message("a real climb past the first milestone offered nothing") \
		.is_true()


func test_a_stale_position_does_not_cross_a_zone() -> void:
	var avatar: CharacterBody2D = _w.player
	var first_divider: float = _w._zone_milestones[avatar.peer_id][0]
	avatar.global_position.y = first_divider - 100.0
	avatar.run_seed = 4242

	_w._check_zones()
	assert_int(Game.local_run().score) \
		.override_failure_message("a position from another run crossed a zone").is_equal(0)


func test_a_stale_position_cannot_reach_the_surface() -> void:
	Net.active = true
	_w.player.global_position.y = _w.profile.victory_y - 100.0
	_w.player.run_seed = 4242

	_w._check_victory()
	assert_bool(_w._session_over) \
		.override_failure_message("a position from another run ended the fresh run") \
		.is_false()

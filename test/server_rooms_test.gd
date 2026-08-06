extends GdUnitTestSuite
## Rooms, and the addressing that keeps several of them on one socket apart.
##
## The three-process probe (tools/run_server_probe.sh) proves the whole thing end
## to end. This pins the pieces it stands on, which are the ones that would break
## silently: a world name derived from a room id, a message addressed to a room's
## members, and a roster locked with the seed.


# ── Addressing ──────────────────────────────────────────────────────────────
## Node paths are how the replication layer addresses everything, so two rooms
## on one socket must not share one — and both sides have to derive the same name
## from the same id without a handshake.
func test_a_room_gets_its_own_world_node_name() -> void:
	assert_str(NetSession.world_name_for(1)).is_equal("World1")
	assert_str(NetSession.world_name_for(7)).is_equal("World7")
	assert_str(NetSession.world_name_for(1)).is_not_equal(NetSession.world_name_for(2))


## Room 0 is solo play and a peer-to-peer host: one unnamed room, and the plain
## `World` the game has always used. Nothing about the existing addressing may
## move when a dedicated server is not involved.
func test_room_zero_keeps_the_name_the_game_has_always_had() -> void:
	assert_str(NetSession.world_name_for(0)).is_equal("World")
	var session := NetSession.new()
	assert_str(session.world_name()).is_equal("World")


## Scoping is off for room 0 by construction. Turning visibility filtering on for
## solo play could only ever be a way to get it wrong.
func test_scoping_does_nothing_solo() -> void:
	var session := NetSession.new()
	var sync: MultiplayerSynchronizer = auto_free(MultiplayerSynchronizer.new())
	session.scope(sync)
	assert_bool(sync.public_visibility) \
		.override_failure_message("solo play must not touch visibility").is_true()


func test_scoping_a_room_restricts_visibility_to_its_members() -> void:
	var session := NetSession.new()
	session.active = true
	session.room_id = 3
	session.peers = [11, 22]
	var carrier: Node2D = auto_free(Node2D.new())
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	carrier.add_child(sync)

	session.scope(carrier)
	assert_bool(sync.public_visibility) \
		.override_failure_message("a scoped node must not be visible to everybody") \
		.is_false()
	assert_bool(sync.get_visibility_for(11)).is_true()
	assert_bool(sync.get_visibility_for(22)).is_true()
	assert_bool(sync.get_visibility_for(33)) \
		.override_failure_message("somebody in another room could see into this one") \
		.is_false()


# ── The room itself ─────────────────────────────────────────────────────────
func test_a_password_is_kept_as_a_hash_and_never_as_itself() -> void:
	var room := Room.make(1, "somewhere")
	assert_bool(room.locked()).is_false()
	assert_bool(room.password_matches("anything")) \
		.override_failure_message("an open room lets anybody in").is_true()

	room.set_password("open sesame")
	assert_bool(room.locked()).is_true()
	assert_str(room.password_hash) \
		.override_failure_message("the password itself must not be kept") \
		.not_contains("open sesame")
	assert_bool(room.password_matches("open sesame")).is_true()
	assert_bool(room.password_matches("open sesamé")).is_false()
	room.set_password("")
	assert_bool(room.locked()).is_false()


func test_spectators_are_members_without_being_climbers() -> void:
	var room := Room.make(1, "somewhere")
	room.add_member(10, &"cyn")
	room.add_member(20, CharacterRoster.SPECTATOR)
	assert_int(room.members.size()).is_equal(2)
	assert_array(room.climbers()).contains_exactly([10])
	assert_int(room.spectators()).is_equal(1)


## Whether watching takes a seat is a setting, because a room set up for people
## to watch a race should not fill up with them.
func test_whether_a_spectator_takes_a_seat_is_a_choice() -> void:
	var room := Room.make(1, "somewhere")
	room.max_players = 1
	room.add_member(10, &"cyn")
	assert_bool(room.has_room_for(false, true)).is_false()
	assert_bool(room.has_room_for(true, true)) \
		.override_failure_message("counting spectators should have filled the room") \
		.is_false()
	assert_bool(room.has_room_for(true, false)) \
		.override_failure_message("not counting them, a watcher should still fit") \
		.is_true()


## The picks travel WITH the seed, so every machine builds the same avatars in
## the same order before its first frame. This is the same contract the
## peer-to-peer roster has, and the reason a run cannot be joined half-way.
func test_locking_the_roster_carries_the_picks_with_the_seed() -> void:
	var room := Room.make(4, "somewhere")
	room.mode = NetSession.MODE_RACE
	room.add_member(10, &"cyn")
	room.add_member(20, &"tessa")
	room.add_member(30, CharacterRoster.SPECTATOR)
	room.lock_roster(12345)

	assert_int(room.run_seed).is_equal(12345)
	assert_array(room.session.peers).contains_exactly([10, 20, 30])
	assert_str(String(room.session.characters[10])).is_equal("cyn")
	assert_str(String(room.session.characters[20])).is_equal("tessa")
	assert_str(String(room.session.characters[30])) \
		.is_equal(String(CharacterRoster.SPECTATOR))
	assert_int(room.session.room_id).is_equal(4)
	assert_bool(room.session.is_versus()).is_true()


func test_leaving_removes_a_member_from_the_roster_as_well() -> void:
	var room := Room.make(1, "somewhere")
	room.add_member(10, &"cyn")
	room.add_member(20, &"tessa")
	room.lock_roster(1)
	room.remove_member(20)
	assert_array(room.members).contains_exactly([10])
	assert_array(room.session.peers) \
		.override_failure_message("a departed peer stayed in the run's roster") \
		.contains_exactly([10])


## Control characters in a room name make one room look like two in every list
## that prints it. The oldest trick there is.
func test_room_names_are_cleaned_and_cut() -> void:
	assert_str(RoomManager.sanitise_name("  a room  ")).is_equal("a room")
	assert_str(RoomManager.sanitise_name("two\nlines")).is_equal("twolines")
	assert_str(RoomManager.sanitise_name("")).is_equal("")
	assert_int(RoomManager.sanitise_name("x".repeat(200)).length()) \
		.is_equal(RoomManager.MAX_NAME)


## A room list goes to everybody connected, including people who have not been
## let into that room. It must carry nothing a stranger should not have.
func test_the_public_room_listing_carries_no_secrets() -> void:
	var room := Room.make(2, "private")
	room.set_password("hunter2")
	room.owner_id = "somebody"
	room.lock_roster(999)
	var info := room.info()
	assert_bool(info.has("locked")).is_true()
	assert_bool(bool(info["locked"])).is_true()
	for forbidden in ["password_hash", "password", "seed", "run_seed", "members"]:
		assert_bool(info.has(forbidden)) \
			.override_failure_message("the room list leaks '%s'" % forbidden).is_false()

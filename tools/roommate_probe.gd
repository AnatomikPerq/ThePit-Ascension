extends Node
## One of two CLIENTS in the SAME room on a real dedicated server.
##
## `tools/run_roommate_probe.sh` starts the server and two of these. The server
## probe puts its two clients in different rooms on purpose, which is exactly why
## it could not see this: on a dedicated server clients have no connection to each
## other, and `network/relay_between_clients` is off, so anything one client sends
## "to the room" reaches the server and stops there. For a while that meant every
## player in a room saw every other player frozen on the spawn pad, never moving
## and never swinging, while the server — which did receive everything — resolved
## the climb correctly.
##
## Each side proves it sees the other one:
##
##   moved   the other avatar has left its spawn point on THIS screen. Each side
##           walks its own avatar a few hundred pixels; a puppet that never moves
##           means the avatar's state never got from its owner to us.
##   strike  a swing the other side threw was spawned on THIS screen. A missing
##           one means a broadcast from a client stopped at the server.
##
##   host   registers first, opens a co-op room, waits for the mate, starts it.
##   mate   registers second and joins that room.

const PASSWORD := "probe-password-1"
## How far each side walks. Far enough that no amount of spawn jitter explains it.
const WALK: float = 300.0
## Less than the walk, more than any spawn offset (slots are 90 px apart).
const MOVED_AT_LEAST: float = 150.0

var role: String = "host"
var port: int = 25911
var failures: int = 0
var _notices: Array[String] = []
var _strikes_seen: int = 0


func _ready() -> void:
	_begin.call_deferred()


func _begin() -> void:
	# The Router frees current_scene on every swap; see tools/server_probe.gd.
	var placeholder := Node.new()
	placeholder.name = "ProbePlaceholder"
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	if args.size() > 1:
		port = int(args[1])
	Game.selected_character = &"cyn"
	Hub.notice.connect(func(text: String) -> void: _notices.append(text))
	_run()


func _run() -> void:
	if role == "mate":
		await _wait(3.0)
	if not await _connect():
		_finish()
		return
	var entered: bool
	if role == "host":
		entered = await _host_room()
	else:
		entered = await _join_room()
	if not entered:
		_finish()
		return
	await _check_each_other()
	_finish()


func _connect() -> bool:
	var err := Net.connect_to_server("127.0.0.1", port, NetProtocol.INTENT_REGISTER,
		role, PASSWORD)
	if err != OK:
		_fail("connect", "could not dial: %d" % err)
		return false
	if not await _await_signal(Hub.welcomed, 25.0):
		_fail("welcome", "never got past the handshake")
		return false
	return true


func _host_room() -> bool:
	Hub.ask(&"request_create", ["shared room", NetSession.MODE_COOP, 4, "",
		String(Game.selected_character)])
	if not await _await_signal(Hub.room_changed, 12.0):
		_fail("room", "never got into a room: %s" % ", ".join(_notices))
		return false
	# Wait for the mate rather than for a clock.
	var joined := await _await_condition(func() -> bool:
		return (Hub.current_room.get("members", []) as Array).size() >= 2, 20.0)
	if not joined:
		_fail("mate", "nobody joined the room")
		return false
	Hub.ask(&"request_start")
	return await _await_world()


func _join_room() -> bool:
	Hub.ask(&"request_rooms")
	var listed := await _await_condition(func() -> bool:
		return not Hub.room_listing.is_empty(), 15.0)
	if not listed:
		_fail("listing", "the host's room never appeared")
		return false
	var room_id := int((Hub.room_listing[0] as Dictionary).get("id", 0))
	Hub.ask(&"request_join", [room_id, "", String(Game.selected_character)])
	return await _await_world()


func _await_world() -> bool:
	if not await _await_condition(func() -> bool: return _world() != null, 20.0):
		_fail("start", "the run never began: %s" % ", ".join(_notices))
		return false
	return true


func _check_each_other() -> void:
	var world := _world()
	# Let both machines build their worlds and settle on the pad.
	await _wait(2.0)
	_expect("two_avatars", world.players.size(), 2)
	var mine: CharacterBody2D = world.players.get(Game.local_peer_id)
	var theirs: CharacterBody2D = null
	for peer_id: int in world.players:
		if peer_id != Game.local_peer_id:
			theirs = world.players[peer_id]
	if mine == null or theirs == null:
		_fail("avatars", "missing an avatar")
		return
	var their_start := theirs.global_position
	var my_start := mine.global_position
	var attack_path: String = theirs.character.attack_scene.resource_path
	world.child_entered_tree.connect(func(node: Node) -> void:
		if node.scene_file_path == attack_path and node.get(&"_player") == theirs:
			_strikes_seen += 1)

	# Walk, honestly — in hops the movement guard accepts — and swing on the way.
	mine.has_attack = true
	mine.flying = true
	var walked := 0.0
	while walked < WALK:
		mine.global_position += Vector2(30.0, -30.0)
		mine.velocity = Vector2.ZERO
		walked += 30.0
		if mine.strike_cd_timer.is_stopped():
			mine._try_strike()
		await _wait(0.1)
	# And hold still long enough for the other side's last packets to arrive.
	await _wait(3.0)
	# Our own avatar is ours alone. The echo goes to everyone BUT its owner; if it
	# ever reached us too, the server's copy — a few packets behind — would keep
	# dragging us back to where we were.
	var mine_moved := mine.global_position.distance_to(my_start)
	mine.flying = false

	var moved := theirs.global_position.distance_to(their_start)
	_say("their_avatar_moved", "%.0f px" % moved)
	_say("their_strikes_seen", str(_strikes_seen))
	_expect("sees_the_other_climber_move", moved >= MOVED_AT_LEAST, true)
	_expect("sees_the_other_climber_swing", _strikes_seen >= 1, true)
	_say("own_avatar_moved", "%.0f px" % mine_moved)
	_expect("own_avatar_not_echoed_back", absf(mine_moved - WALK * sqrt(2.0)) < 5.0, true)


func _world() -> Node:
	for child in get_tree().root.get_children():
		if child.is_in_group(NetSession.HOST_GROUP):
			return child
	return null


func _await_signal(sig: Signal, timeout: float) -> bool:
	var fired := [false]
	var on_fire := func(_a: Variant = null) -> void: fired[0] = true
	sig.connect(on_fire, CONNECT_ONE_SHOT)
	var ok := await _await_condition(func() -> bool: return fired[0], timeout)
	if sig.is_connected(on_fire):
		sig.disconnect(on_fire)
	return ok


## Counted in physics frames, never wall-clock — see CLAUDE.md §5.
func _await_condition(test: Callable, timeout: float) -> bool:
	for i in int(timeout * Engine.physics_ticks_per_second):
		if test.call():
			return true
		await get_tree().physics_frame
	return test.call()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _say(what: String, value: String) -> void:
	print("PROBE %s %s" % [what, value])


func _expect(what: String, got: Variant, wanted: Variant) -> void:
	if got == wanted:
		_say(what, "ok")
	else:
		_fail(what, "got %s, wanted %s" % [str(got), str(wanted)])


func _fail(what: String, why: String) -> void:
	failures += 1
	print("PROBE FAIL %s — %s" % [what, why])


func _finish() -> void:
	print("PROBE %s %s" % [role, "PASSED" if failures == 0 else "FAILED"])
	get_tree().quit(0 if failures == 0 else 1)

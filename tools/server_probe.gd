extends Node
## One CLIENT of a real dedicated server, over a real socket.
##
## `tools/run_server_probe.sh` starts the actual server binary and two of these.
## Nothing here is stubbed: the handshake is the handshake, the rooms are rooms,
## and the two clients end up in DIFFERENT rooms on the same port — which is the
## property the whole single-socket design rests on and the one thing no
## single-process test can check, because one process always agrees with itself.
##
## What each side proves, in order:
##
##   alpha  registers first, so the server makes it the owner. Opens a co-op
##          room, starts it, and later uses the ADMIN path — the same command
##          set the console has — to look at the player list and close a room.
##   beta   registers second as an ordinary player. Opens a RACE room, starts
##          it, and must be refused when it asks the server to stop.
##
## And between them: each client must end up with exactly ONE world in its tree,
## holding exactly its own avatar, with no packet from the other room ever
## landing. The shell script greps both logs for the replication errors that
## would prove otherwise.

const PASSWORD := "probe-password-1"
## Long enough for a run to spawn enemies and for the two rooms to diverge.
const RUN_SECONDS: float = 6.0

var role: String = "alpha"
var port: int = 25901
var failures: int = 0
var _room_id: int = 0
var _chat_seen: Array[String] = []
var _notices: Array[String] = []
var _command_output: String = ""


func _ready() -> void:
	# Deferred: the root is mid-_ready() while ours runs, and add_child on it
	# fails outright until the next frame.
	_begin.call_deferred()


func _begin() -> void:
	# The Router frees current_scene on every swap, and running as the main
	# scene makes that this probe — so entering a room's world would kill the
	# probe mid-await, which reads as a hang rather than a failure. Hand the
	# Router a placeholder and survive as a plain child of root. Same trick as
	# tools/net_probe.gd, for the same reason.
	var placeholder := Node.new()
	placeholder.name = "ProbePlaceholder"
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	if args.size() > 1:
		port = int(args[1])
	# Two different climbers, so a roster that stopped travelling with the seed
	# would show up as both machines building the same one.
	Game.selected_character = &"cyn" if role == "alpha" else &"tessa"
	Hub.chat_received.connect(func(entry: Dictionary) -> void:
		_chat_seen.append(str(entry.get("text", ""))))
	Hub.notice.connect(func(text: String) -> void: _notices.append(text))
	Hub.command_answered.connect(func(text: String, _ok: bool) -> void:
		_command_output = text)
	_run()


func _run() -> void:
	# beta waits, so that alpha is reliably the first account and therefore the
	# owner. Registration order is the only thing that decides it.
	if role == "beta":
		await _wait(3.0)
	if not await _connect():
		_finish()
		return
	if not await _open_and_start_room():
		_finish()
		return
	await _wait(RUN_SECONDS)
	_check_world()
	await _check_role_specific()
	_finish()


# ── Connecting ──────────────────────────────────────────────────────────────
func _connect() -> bool:
	var err := Net.connect_to_server("127.0.0.1", port, NetProtocol.INTENT_REGISTER,
		role, PASSWORD)
	if err != OK:
		_fail("connect", "could not dial: %d" % err)
		return false
	var welcomed := await _await_signal(Hub.welcomed, 25.0)
	if not welcomed:
		_say("link_state", "%d %s" % [Net.link.state, Net.link.message])
		_fail("welcome", "never got past the handshake")
		return false
	_say("account", Hub.account_name)
	_say("role", Hub.role)
	_expect("registered_as_self", Hub.account_name, role)
	if role == "alpha":
		_expect("first_account_is_owner", Hub.role, Permissions.ROLE_OWNER)
	else:
		_expect("second_account_is_player", Hub.role, Permissions.ROLE_PLAYER)
	return true


# ── A room of our own ───────────────────────────────────────────────────────
func _open_and_start_room() -> bool:
	var mode := NetSession.MODE_COOP if role == "alpha" else NetSession.MODE_RACE
	Hub.ask(&"request_create", ["%s room" % role, mode, 4, "",
		String(Game.selected_character)])
	if not await _await_signal(Hub.room_changed, 12.0):
		_fail("room", "never got into a room: %s" % ", ".join(_notices))
		return false
	_room_id = int(Hub.current_room.get("id", 0))
	_say("room_id", str(_room_id))
	# Both clients open a room, so the two rooms must not be the same room.
	_expect("room_is_ours", int(Hub.current_room.get("mode", -1)), mode)

	# Said in ALPHA's room, early, so that beta has every chance to overhear it
	# and must not. Chat is addressed to a room, and this is what proves it.
	if role == "alpha":
		Hub.ask(&"send_chat", ["this is the alpha room"])

	# Give the other client time to open its own room before starting, so that
	# each is genuinely running while the other is.
	await _wait(4.0)
	_expect_at_least("sees_both_rooms", Hub.room_listing.size(), 2)

	Hub.ask(&"request_start")
	if not await _await_condition(func() -> bool: return _world() != null, 12.0):
		_fail("start", "the run never began: %s" % ", ".join(_notices))
		return false
	return true


# ── What the world has to look like ─────────────────────────────────────────
func _check_world() -> void:
	var world := _world()
	if world == null:
		_fail("world", "no world")
		return
	# ONE world. A packet from the other room that had been accepted would have
	# built a second one, or errored trying.
	_expect("exactly_one_world", _worlds().size(), 1)
	_expect("world_named_for_room", world.name, NetSession.world_name_for(_room_id))
	_say("world_seed", str(world.world_seed))
	_say("world_hash", _hash(world))

	# Our avatar, and nobody else's: the other room's climber is on the same
	# socket and must never have been mirrored into this world.
	_expect("only_our_avatar", world.players.size(), 1)
	var mine: CharacterBody2D = world.players.get(Game.local_peer_id)
	if mine == null:
		_fail("avatar", "our own avatar is missing")
		return
	_expect("our_climber", String(mine.character.id), String(Game.selected_character))
	_expect("versus_matches_room", world.session.is_versus(), role == "beta")

	# The server is simulating: enemies it spawned have been mirrored to us.
	var enemies := world.get_node(^"Enemies").get_child_count()
	_say("enemies_mirrored", str(enemies))
	_expect_at_least("server_spawns_enemies", enemies, 1)


func _world() -> Node:
	var found := _worlds()
	return found[0] if not found.is_empty() else null


func _worlds() -> Array[Node]:
	var out: Array[Node] = []
	for child in get_tree().root.get_children():
		if child.is_in_group(NetSession.HOST_GROUP):
			out.append(child)
	return out


## A cheap fingerprint of this room's geometry, for the shell script to compare
## against the OTHER room's. It has to differ: two rooms started from two seeds
## are two different pits, and a probe where they matched would mean one room had
## been built from the other's packet.
##
## Same fold as the net probe: a moving platform's live position is a function of
## how many ticks THIS machine has run, so it is put back where it was authored.
## Hashing the live picture compares clocks, not layouts.
func _hash(world: Node) -> String:
	var rects: Array[String] = []
	for body: Node in world.get_node(^"Platforms").get_children():
		var mover := body as MovingPlatform
		var at: Vector2 = mover.start_position() if mover != null \
				else (body as Node2D).global_position
		rects.append("%.1f,%.1f" % [at.x, at.y])
	rects.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("|".join(rects).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


# ── The parts only one of them does ─────────────────────────────────────────
func _check_role_specific() -> void:
	if role == "alpha":
		await _check_owner_powers()
	else:
		await _check_player_limits()


## The owner drives the ADMIN path: the same commands the console has, arriving
## over the game socket and checked against this account's rights.
func _check_owner_powers() -> void:
	_command_output = ""
	Hub.ask(&"run_command", ["players"])
	await _await_condition(func() -> bool: return _command_output != "", 8.0)
	_say("owner_player_list", _command_output.replace("\n", " / "))
	_expect_contains("owner_sees_both_players", _command_output, "beta")

	_command_output = ""
	Hub.ask(&"run_command", ["rooms"])
	await _await_condition(func() -> bool: return _command_output != "", 8.0)
	_expect_contains("owner_sees_both_rooms", _command_output, "beta room")

	# Structured data for the panel, filtered by rights on the server side.
	#
	# Matched on the KIND, and that is not fussiness: the admin panel instanced
	# into the running world asks for its own feeds, so an unfiltered handler
	# catches whichever answer happens to land first and reports the wrong one
	# missing. It did exactly that.
	var got: Array = []
	var handler := func(kind: String, data: Dictionary) -> void:
		if kind == "settings":
			got.append(data)
	Hub.admin_answered.connect(handler)
	Hub.ask(&"request_admin", ["settings", {}])
	await _await_condition(func() -> bool: return not got.is_empty(), 8.0)
	Hub.admin_answered.disconnect(handler)
	if got.is_empty():
		_fail("admin_feed", "the settings feed never arrived")
		return
	var feed: Dictionary = got[0]
	var settings: Array = feed.get("settings", [])
	_say("settings_offered", str(settings.size()))
	_expect_at_least("panel_gets_the_whole_schema", settings.size(), 60)
	_expect("owner_may_write_settings", bool(feed.get("writable", false)), true)


## An ordinary player must be refused the things they may not do, and must not
## overhear a conversation in a room they are not in.
func _check_player_limits() -> void:
	_command_output = ""
	Hub.ask(&"run_command", ["stop right now"])
	await _await_condition(func() -> bool: return _command_output != "", 8.0)
	_say("player_stop_answer", _command_output)
	_expect_contains("player_may_not_stop", _command_output, "may not")

	_command_output = ""
	Hub.ask(&"run_command", ["kick alpha"])
	await _await_condition(func() -> bool: return _command_output != "", 8.0)
	_expect_contains("player_may_not_kick", _command_output, "may not")

	# alpha is talking in ITS room. We are not in it.
	_expect("chat_did_not_leak", _chat_seen.has("this is the alpha room"), false)


# ── Plumbing ────────────────────────────────────────────────────────────────
func _await_signal(sig: Signal, timeout: float) -> bool:
	var fired := [false]
	var handler := func(_a: Variant = null, _b: Variant = null) -> void: fired[0] = true
	sig.connect(handler)
	var ok := await _await_condition(func() -> bool: return fired[0], timeout)
	if sig.is_connected(handler):
		sig.disconnect(handler)
	return ok


## Frames, never wall-clock deadlines built out of `await get_tree().create_timer`
## alone: a probe that spends its budget loading scenes off disk sees fewer steps
## than one that does not, and fails at random. This counts real elapsed time but
## yields on process frames, so a slow first frame costs nothing.
func _await_condition(test: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if test.call():
			return true
		await get_tree().process_frame
	return test.call()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _say(what: String, value: String) -> void:
	print("PROBE %s %s" % [what, value])


func _expect(what: String, got: Variant, wanted: Variant) -> void:
	if got == wanted:
		_say(what, "ok (%s)" % str(got))
		return
	_fail(what, "got %s, wanted %s" % [str(got), str(wanted)])


func _expect_at_least(what: String, got: int, floor_value: int) -> void:
	if got >= floor_value:
		_say(what, "ok (%d)" % got)
		return
	_fail(what, "got %d, wanted at least %d" % [got, floor_value])


func _expect_contains(what: String, haystack: String, needle: String) -> void:
	if haystack.to_lower().contains(needle.to_lower()):
		_say(what, "ok")
		return
	_fail(what, "'%s' is not in: %s" % [needle, haystack.replace("\n", " / ")])


func _fail(what: String, why: String) -> void:
	failures += 1
	print("PROBE FAIL %s — %s" % [what, why])


func _finish() -> void:
	print("PROBE %s %s" % [role, "PASSED" if failures == 0 else "FAILED"])
	Net.leave()
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)

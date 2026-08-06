extends Node
## Hub — everything a client and a dedicated server say to each other.
##
## One node, one path (`/root/Hub`), present in both builds. That is not tidiness:
## it is the security design. Every message a client can send arrives at exactly
## one place, where the sender is resolved, rate-limited and checked before
## anything else in the server sees it. A server whose clients can address twenty
## different nodes has twenty doors to guard and will eventually leave one
## unguarded.
##
## In-RUN traffic does not come through here. Once a room starts, avatars,
## enemies, blasts and kills replicate through the room's own world at
## `/root/World<id>`, scoped to that room's members — see NetSession.scope(). The
## Hub is the lobby, the browser, the chat and the administration; the world is
## the game.
##
## The same file serves both sides because an RPC is addressed by node path, and
## the two sides must agree on it. Which half runs is decided by whether `server`
## was set at boot: a client's is null, and every server-side method checks it.

# ── Client-side state and signals ───────────────────────────────────────────
signal welcomed(payload: Dictionary)
signal notice(text: String)
signal kicked(reason: String)
signal rooms_changed(listing: Array)
signal room_changed(detail: Dictionary)
signal chat_received(entry: Dictionary)
signal command_answered(text: String, ok: bool)
signal admin_answered(kind: String, data: Dictionary)

## Set only in the server process, by PitServer at boot. Null on a client, and
## every `@rpc("any_peer")` below refuses to do anything while it is.
var server: PitServer = null

## What this client knows about the server it is on. Empty when not on one.
var server_name: String = ""
var motd: String = ""
var account_name: String = ""
var role: String = ""
var is_guest: bool = true
var rights: PackedStringArray = PackedStringArray()
var room_listing: Array = []
var current_room: Dictionary = {}
var chat_enabled: bool = true
var may_create_rooms: bool = false


## True when this machine is a client of a dedicated server, as opposed to solo,
## a peer-to-peer host, or a peer-to-peer guest. The one predicate the UI uses to
## decide whether there is a room browser to go back to.
func on_server() -> bool:
	return server == null and Net.active and not Net.is_host() and account_name != ""


func may(right: String) -> bool:
	return Permissions.allows(rights, right)


func clear() -> void:
	server_name = ""
	motd = ""
	account_name = ""
	role = ""
	rights = PackedStringArray()
	room_listing = []
	current_room = {}
	may_create_rooms = false


# ── Server → client ─────────────────────────────────────────────────────────
@rpc("authority", "call_remote", "reliable")
func server_welcome(payload: Dictionary) -> void:
	server_name = str(payload.get("name", ""))
	motd = str(payload.get("motd", ""))
	account_name = str(payload.get("account", ""))
	role = str(payload.get("role", Permissions.ROLE_PLAYER))
	is_guest = bool(payload.get("guest", true))
	rights = PackedStringArray(payload.get("permissions", []))
	room_listing = payload.get("rooms", [])
	may_create_rooms = bool(payload.get("may_create", false))
	chat_enabled = bool(payload.get("chat", true))
	welcomed.emit(payload)
	rooms_changed.emit(room_listing)


@rpc("authority", "call_remote", "reliable")
func server_notice(text: String) -> void:
	notice.emit(text)


@rpc("authority", "call_remote", "reliable")
func server_kicked(reason: String) -> void:
	kicked.emit(reason)


@rpc("authority", "call_remote", "reliable")
func room_listing_changed(listing: Array) -> void:
	room_listing = listing
	rooms_changed.emit(listing)


@rpc("authority", "call_remote", "reliable")
func room_detail(detail: Dictionary) -> void:
	current_room = detail
	room_changed.emit(detail)


@rpc("authority", "call_remote", "reliable")
func room_left() -> void:
	current_room = {}
	room_changed.emit({})


## The room is starting. This is the dedicated-server equivalent of the
## peer-to-peer host's `_begin_run`, and it carries exactly the same things for
## exactly the same reasons: the picks travel WITH the seed so that every machine
## builds the same avatars in the same order before its first frame.
@rpc("authority", "call_remote", "reliable")
func begin_run(room_id: int, world_seed: int, mode: int, peer_ids: Array,
		picks: Array) -> void:
	Net.enter_room_run(room_id, world_seed, mode, peer_ids, picks)


@rpc("authority", "call_remote", "reliable")
func return_to_room_lobby(room_id: int) -> void:
	Net.leave_room_run(room_id)


@rpc("authority", "call_remote", "reliable")
func chat_message(entry: Dictionary) -> void:
	chat_received.emit(entry)


@rpc("authority", "call_remote", "reliable")
func chat_backlog(entries: Array) -> void:
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			chat_received.emit(entry)


@rpc("authority", "call_remote", "reliable")
func command_result(text: String, ok: bool) -> void:
	command_answered.emit(text, ok)


@rpc("authority", "call_remote", "reliable")
func admin_result(kind: String, data: Dictionary) -> void:
	admin_answered.emit(kind, data)


## Ask the server for something.
##
## The one way a client sends anything, and it is a method rather than a bare
## `rpc_id(1, ...)` at forty call sites because of the case that is easy to
## forget: a surface built while NOT connected. Godot answers an RPC addressed to
## yourself with "RPC on yourself is not allowed by selected mode", which is a
## real error about a harmless thing — the UI screenshot harness builds every
## screen cold and hit exactly that.
func ask(method: StringName, args: Array = []) -> void:
	if server != null or not Net.active or multiplayer.is_server():
		return
	callv(&"rpc_id", [1, method] + args)


# ── Client → server ─────────────────────────────────────────────────────────
## The gate every one of them passes. Returns the sender's record, or null when
## this machine is not a server, the sender is unknown, or it is talking too
## fast. Nothing below does anything before calling it.
func _sender() -> ServerPeer:
	if server == null or not multiplayer.is_server():
		return null
	var id := multiplayer.get_remote_sender_id()
	if id <= 0:
		return null
	var peer: ServerPeer = server.peers.get(id)
	if peer == null or peer.closing:
		return null
	if not server.may_speak(id):
		return null
	peer.touch()
	return peer


@rpc("any_peer", "call_remote", "reliable")
func request_rooms() -> void:
	var peer := _sender()
	if peer == null:
		return
	rpc_id(peer.peer_id, &"room_listing_changed", server.rooms.listing())


@rpc("any_peer", "call_remote", "reliable")
func request_join(room_id: int, password: String, character: String) -> void:
	var peer := _sender()
	if peer == null:
		return
	var refusal := server.rooms.join(peer.peer_id, room_id, password,
		StringName(character))
	if refusal != "":
		server.hub_notice(peer.peer_id, refusal.to_upper())
		return
	server.broadcast_rooms()
	server.chat.send_backlog(peer.peer_id, room_id)


@rpc("any_peer", "call_remote", "reliable")
func request_create(room_name: String, mode: int, seats: int, password: String,
		character: String) -> void:
	var peer := _sender()
	if peer == null:
		return
	var refusal := _may_create(peer)
	if refusal != "":
		server.hub_notice(peer.peer_id, refusal)
		return
	var problem: Array = []
	var room := server.rooms.open(room_name, clampi(mode, 0, 1),
		peer.account.id, seats, password, problem)
	if room == null:
		server.hub_notice(peer.peer_id, str(problem[0]).to_upper() if not problem.is_empty()
			else "COULD NOT OPEN THAT ROOM")
		return
	server.rooms.join(peer.peer_id, room.id, password, StringName(character))
	server.broadcast_rooms()


func _may_create(peer: ServerPeer) -> String:
	if not peer.may(Permissions.ROOM_CREATE):
		return "YOU MAY NOT OPEN ROOMS HERE"
	if not server.settings.get_bool("rooms/players_may_create") \
			and not peer.may(Permissions.ROOM_CONFIGURE_ANY):
		return "ONLY STAFF MAY OPEN ROOMS ON THIS SERVER"
	var owned := 0
	for room_id in server.rooms.rooms:
		if server.rooms.rooms[room_id].owner_id == peer.account.id:
			owned += 1
	if owned >= server.settings.get_int("rooms/rooms_per_player") \
			and not peer.may(Permissions.ROOM_CONFIGURE_ANY):
		return "YOU ALREADY HAVE A ROOM OPEN"
	return ""


@rpc("any_peer", "call_remote", "reliable")
func request_leave() -> void:
	var peer := _sender()
	if peer == null:
		return
	server.rooms.leave(peer.peer_id, "")
	rpc_id(peer.peer_id, &"room_left")
	server.broadcast_rooms()


@rpc("any_peer", "call_remote", "reliable")
func request_character(character: String) -> void:
	var peer := _sender()
	if peer == null:
		return
	var refusal := server.rooms.set_character(peer.peer_id, StringName(character))
	if refusal != "":
		server.hub_notice(peer.peer_id, refusal.to_upper())


@rpc("any_peer", "call_remote", "reliable")
func request_start() -> void:
	var peer := _sender()
	if peer == null:
		return
	var refusal := server.rooms.start(peer.room_id, peer.peer_id)
	if refusal != "":
		server.hub_notice(peer.peer_id, refusal.to_upper())
	else:
		server.broadcast_rooms()


@rpc("any_peer", "call_remote", "reliable")
func request_restart() -> void:
	var peer := _sender()
	if peer == null:
		return
	var refusal := server.rooms.restart(peer.room_id, peer.peer_id)
	if refusal != "":
		server.hub_notice(peer.peer_id, refusal.to_upper())
	else:
		server.broadcast_rooms()


@rpc("any_peer", "call_remote", "reliable")
func send_chat(text: String) -> void:
	var peer := _sender()
	if peer == null:
		return
	server.chat.say(peer, text)


## The admin panel and the in-game console. It is the SAME command set the
## operator has at the keyboard, filtered by what this account may do — see
## CommandRegistry. A player with no rights gets "you may not do that" for
## everything, which is the correct amount of information.
@rpc("any_peer", "call_remote", "reliable")
func run_command(line: String) -> void:
	var peer := _sender()
	if peer == null:
		return
	if line.length() > 400:
		return
	var caller := server.run_command(
		CommandCaller.for_player(peer.account, peer.peer_id), line)
	rpc_id(peer.peer_id, &"command_result", caller.output(), not caller.failed)


## Structured data for the admin panel — the same facts the console prints, in a
## form a table can be built from rather than one that has to be parsed back out
## of text.
@rpc("any_peer", "call_remote", "reliable")
func request_admin(kind: String, args: Dictionary) -> void:
	var peer := _sender()
	if peer == null:
		return
	if not peer.may(Permissions.SERVER_ADMIN_PANEL):
		return
	var data := ServerAdminFeed.build(server, peer, kind, args)
	rpc_id(peer.peer_id, &"admin_result", kind, data)

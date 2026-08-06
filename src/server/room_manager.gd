class_name RoomManager
extends Node
## Every room on the server: opening them, filling them, starting them, and
## tidying them away.
##
## The one thing to understand here is where a running room's world goes. It is
## added at `/root/World<id>` — a sibling of every other room's world, at exactly
## the path a client in that room builds its own copy at. Node paths are how the
## replication layer addresses everything, so that naming is what keeps four
## simultaneous pits from talking over each other on one socket. The other half
## is `_scope_visibility`, which restricts every synchronizer in a room to that
## room's members BEFORE the node enters the tree, so the spawn packet itself is
## already addressed. Both halves were measured before they were written; the
## note in docs/SERVER.md says what the measurement was.

signal rooms_changed

const MAX_NAME := 28

var server: PitServer

var rooms: Dictionary[int, Room] = {}
var _next_id: int = 1


func _ready() -> void:
	# Rooms are stepped by the tree like everything else; this node only keeps
	# the bookkeeping, so it needs no physics.
	set_physics_process(false)


# ── Opening and closing ─────────────────────────────────────────────────────
## Returns the room, or null with the reason written into `problem`.
func open(room_name: String, mode: int, owner_id: String, seats: int,
		password: String, problem: Array) -> Room:
	if rooms.size() >= server.settings.get_int("rooms/max_rooms"):
		problem.append("the server is full of rooms (%d)" % rooms.size())
		return null
	var clean := sanitise_name(room_name)
	if clean == "":
		problem.append("a room needs a name")
		return null
	var ceiling := server.settings.get_int("rooms/max_players_ceiling")
	var room := Room.make(_next_id, clean)
	_next_id += 1
	room.mode = mode
	room.owner_id = owner_id
	room.max_players = clampi(seats, 1, ceiling)
	if server.settings.get_bool("rooms/allow_passwords"):
		room.set_password(password)
	rooms[room.id] = room
	server.logger.info("room", "opened #%d '%s' (%s, %d seats) by %s" % [
		room.id, room.name, Room.mode_name(room.mode), room.max_players,
		owner_id if owner_id != "" else "the server"])
	rooms_changed.emit()
	return room


func close(room_id: int, reason: String) -> bool:
	var room: Room = rooms.get(room_id)
	if room == null:
		return false
	for peer_id in room.members.duplicate():
		leave(peer_id, "the room was closed: %s" % reason)
	_tear_down_world(room)
	rooms.erase(room_id)
	server.logger.info("room", "closed #%d '%s' — %s" % [room_id, room.name, reason])
	rooms_changed.emit()
	return true


func get_room(room_id: int) -> Room:
	return rooms.get(room_id)


func room_of(peer_id: int) -> Room:
	var peer := server.peers.get(peer_id) as ServerPeer
	return rooms.get(peer.room_id) if peer != null else null


func count() -> int:
	return rooms.size()


## Rooms with a climb actually in progress, as opposed to sitting in their lobby.
## Asked by the status line, the status endpoint and the directory announce, all
## of which used to count it themselves.
func running_count() -> int:
	var found := 0
	for room_id in rooms:
		if rooms[room_id].state == Room.State.RUNNING:
			found += 1
	return found


## The browser's view. Every connected peer may ask for it, so it carries only
## what Room.info() considers public.
func listing() -> Array:
	var out: Array = []
	var ids := rooms.keys()
	ids.sort()
	for room_id in ids:
		out.append(rooms[room_id].info())
	return out


# ── Coming and going ────────────────────────────────────────────────────────
## Put a peer in a room. Returns "" or the reason it did not happen.
func join(peer_id: int, room_id: int, password: String, character: StringName) -> String:
	var peer := server.peers.get(peer_id) as ServerPeer
	var room: Room = rooms.get(room_id)
	var refusal := _may_join(peer, room, password, character)
	if refusal != "":
		return refusal

	if peer.room_id != 0:
		leave(peer_id, "")
	room.add_member(peer_id, character)
	peer.room_id = room_id
	peer.stage = ServerPeer.Stage.IN_ROOM
	room.empty_for = 0.0
	server.logger.info("room", "%s joined #%d '%s'" % [peer.name_text(), room.id, room.name])
	_announce(room)
	rooms_changed.emit()
	return ""


## Every reason a join can be refused, in one place, so that `join` itself reads
## as what it does rather than as a wall of guards.
func _may_join(peer: ServerPeer, room: Room, password: String,
		character: StringName) -> String:
	if peer == null or not peer.authenticated():
		return "not connected"
	if room == null:
		return "no such room"
	if peer.room_id == room.id:
		return "you are already in that room"
	if peer.may(Permissions.ROOM_JOIN_LOCKED):
		return "" # staff pass a password and a full room alike
	return _door_refusal(room, password, character == CharacterRoster.SPECTATOR)


## The three things that stop an ordinary player at a room's door.
func _door_refusal(room: Room, password: String, watching: bool) -> String:
	if not room.password_matches(password):
		return "wrong password"
	# A run already going is joinable only to watch. There is no join-in-progress
	# for a climber — every machine built its avatars from the roster before the
	# first frame, and adding one afterwards is a different feature.
	if room.state == Room.State.RUNNING and not watching:
		return "that run has already started — join as a spectator"
	if not room.has_room_for(
			watching, server.settings.get_bool("rooms/spectators_count_to_limit")):
		return "that room is full"
	return ""


func leave(peer_id: int, notice: String) -> void:
	var peer := server.peers.get(peer_id) as ServerPeer
	if peer == null or peer.room_id == 0:
		return
	var room: Room = rooms.get(peer.room_id)
	peer.room_id = 0
	peer.stage = ServerPeer.Stage.LOBBY
	if room == null:
		return
	room.remove_member(peer_id)
	if room.running():
		# The world has to forget the avatar too, and it is the world that owns
		# the roster the enemies chase.
		room.world.prune_disconnected()
		_scope_room(room)
	if notice != "":
		server.hub_notice(peer_id, notice)
	server.logger.info("room", "%s left #%d" % [peer.name_text(), room.id])
	_announce(room)
	rooms_changed.emit()


## A peer disappeared entirely. Same as leaving, minus telling it anything.
func drop(peer_id: int) -> void:
	leave(peer_id, "")


func set_character(peer_id: int, character: StringName) -> String:
	var room := room_of(peer_id)
	if room == null:
		return "you are not in a room"
	if room.state == Room.State.RUNNING:
		return "not while the run is going"
	room.choices[peer_id] = character
	_announce(room)
	return ""


# ── Running ─────────────────────────────────────────────────────────────────
## Start the climb. `by_peer` is 0 for the console and for an automatic restart.
func start(room_id: int, by_peer: int) -> String:
	var room: Room = rooms.get(room_id)
	if room == null:
		return "no such room"
	if room.state == Room.State.RUNNING:
		return "that run is already going"
	if room.climbers().is_empty():
		return "nobody in that room is playing — everyone chose to watch"
	var refusal := _may_control(room, by_peer, "rooms/who_may_start")
	if refusal != "":
		return refusal

	var seed_value := 0
	while seed_value == 0:
		seed_value = randi()
	_begin(room, seed_value)
	return ""


func restart(room_id: int, by_peer: int) -> String:
	var room: Room = rooms.get(room_id)
	if room == null:
		return "no such room"
	var refusal := _may_control(room, by_peer, "rooms/who_may_restart")
	if refusal != "":
		return refusal
	var seed_value := 0
	while seed_value == 0:
		seed_value = randi()
	_begin(room, seed_value)
	return ""


## Build the room's world here and tell its members to build the same one.
##
## The order is the whole trick: the roster is locked first, so the picks travel
## WITH the seed and every machine builds the same avatars in the same order; the
## clients are told before the server builds, because they have further to go;
## and the server's own world is scoped to the room's members the moment it
## exists.
func _begin(room: Room, seed_value: int) -> void:
	_tear_down_world(room)
	room.lock_roster(seed_value)
	room.state = Room.State.RUNNING
	room.ended_for = 0.0

	for peer_id in room.members:
		server.hub().rpc_id(peer_id, &"begin_run", room.id, seed_value, room.mode,
			room.session.peers, _picks_of(room))

	var world: Node = (load(Router.WORLD_SCENE) as PackedScene).instantiate()
	world.name = room.world_name()
	world.world_seed = seed_value
	world.session = room.session
	world.simulation_only = true
	get_tree().root.add_child(world)
	room.world = world
	# The world decides when the climb is over; the room has to hear about it, or
	# it stays "running" for the rest of the server's life and never returns to
	# its lobby.
	world.run_ended.connect(finish.bind(room.id))
	_scope_room(room)

	server.logger.info("room", "#%d '%s' started — %s, seed %d, %d climbing" % [
		room.id, room.name, Room.mode_name(room.mode), seed_value,
		room.climbers().size()])
	rooms_changed.emit()


func _picks_of(room: Room) -> Array:
	var picks: Array = []
	for peer_id in room.session.peers:
		picks.append(String(room.session.characters.get(peer_id, CharacterRoster.SPECTATOR)))
	return picks


## The run is over. The room stays, so the same people can go again without
## finding each other a second time.
func finish(room_id: int) -> void:
	var room: Room = rooms.get(room_id)
	if room == null or room.state != Room.State.RUNNING:
		return
	room.state = Room.State.ENDED
	room.ended_for = 0.0
	server.logger.info("room", "#%d '%s' finished" % [room.id, room.name])
	rooms_changed.emit()


func _tear_down_world(room: Room) -> void:
	if is_instance_valid(room.world):
		room.world.queue_free()
	room.world = null


func _may_control(room: Room, by_peer: int, setting_key: String) -> String:
	if by_peer == 0:
		return "" # the console and an automatic restart answer to nobody
	var peer := server.peers.get(by_peer) as ServerPeer
	if peer == null or peer.room_id != room.id:
		return "you are not in that room"
	if peer.may(Permissions.ROOM_CONFIGURE_ANY):
		return ""
	var rule := server.settings.get_text(setting_key)
	if rule == "anyone":
		return ""
	var owns := peer.account != null and peer.account.id == room.owner_id
	if rule == "owner" and owns:
		return ""
	return "only staff may do that here" if rule == "staff" \
			else "only whoever opened the room may do that"


# ── Keeping the tree tidy ───────────────────────────────────────────────────
func _process(delta: float) -> void:
	var empty_limit := server.settings.get_float("rooms/empty_close_seconds")
	var end_limit := server.settings.get_float("rooms/end_to_lobby_seconds")
	var doomed: Array[int] = []
	for room_id in rooms:
		var room: Room = rooms[room_id]
		_step_room(room, delta, empty_limit, end_limit, doomed)
	for room_id in doomed:
		close(room_id, "nobody left in it")


func _step_room(room: Room, delta: float, empty_limit: float, end_limit: float,
		doomed: Array[int]) -> void:
	if room.members.is_empty():
		room.empty_for += delta
		if not room.persistent and empty_limit > 0.0 and room.empty_for >= empty_limit:
			doomed.append(room.id)
			return
		# A finished run that everybody walked out of goes back to its lobby at
		# once, rather than waiting for the end-screen timer that only advances
		# while somebody is there to watch it. Without this a persistent room —
		# `rooms/empty_close_seconds = 0`, which is the whole point of one — kept
		# a fully built pit in the tree for the rest of the server's life.
		if room.state == Room.State.ENDED:
			_to_lobby(room)
			return
		# An empty room is not simulated at all. With hibernation off it keeps
		# running, which is what an operator wants when they are watching a
		# recording of it and nothing else.
		if is_instance_valid(room.world) \
				and server.settings.get_bool("performance/hibernate_empty_rooms"):
			room.world.process_mode = Node.PROCESS_MODE_DISABLED
		return

	room.empty_for = 0.0
	if is_instance_valid(room.world) and room.world.process_mode != Node.PROCESS_MODE_INHERIT:
		room.world.process_mode = Node.PROCESS_MODE_INHERIT

	if room.state == Room.State.ENDED and end_limit > 0.0:
		room.ended_for += delta
		if room.ended_for >= end_limit:
			_to_lobby(room)


func _to_lobby(room: Room) -> void:
	_tear_down_world(room)
	room.state = Room.State.LOBBY
	room.ended_for = 0.0
	room.session.peers.clear()
	room.session.characters.clear()
	for peer_id in room.members:
		server.hub().rpc_id(peer_id, &"return_to_room_lobby", room.id)
	_announce(room)
	rooms_changed.emit()


# ── Replication scope ───────────────────────────────────────────────────────
## Restrict everything replicated in this room's world to this room's members.
##
## Called after the world is built and again whenever the membership changes.
## Enemies spawned later are scoped as they are created — see `scope_node`, which
## the world calls before `add_child` — because doing it afterwards would send a
## spawn packet to everybody first and take it back a frame later.
func _scope_room(room: Room) -> void:
	# The session's own peer list is what visibility is written from, so it has to
	# be the membership as it is now and not as it was when the run started.
	room.session.peers = room.members.duplicate()
	room.session.rescope(room.world)


func _announce(room: Room) -> void:
	var names: Dictionary[int, String] = {}
	for peer_id in room.members:
		var peer := server.peers.get(peer_id) as ServerPeer
		names[peer_id] = peer.name_text() if peer != null else "?"
	var detail := room.detail(names)
	for peer_id in room.members:
		server.hub().rpc_id(peer_id, &"room_detail", detail)


static func sanitise_name(raw: String) -> String:
	var clean := raw.strip_edges()
	# Control characters and newlines in a name break every list that prints it,
	# and are the oldest trick there is for making a room look like two rooms.
	var out := ""
	for i in clean.length():
		var code := clean.unicode_at(i)
		if code >= 32 and code != 127:
			out += clean[i]
	return out.substr(0, MAX_NAME).strip_edges()

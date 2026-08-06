extends Node
## Net — this MACHINE's connection, and the one room it is in.
##
## Read that first sentence again, because it is the whole division of labour
## with `NetSession`: Net answers "am I connected, am I the server, who am I
## talking to"; a `NetSession` answers "who is in THIS run". A player's machine
## has exactly one of each and they can be conflated — which is what this file
## used to do. A dedicated server has one socket and several runs, cannot
## conflate them, and never reads `Net.session` at all.
##
## Single-player NEVER opens a socket: `active` is false until host(), join() or
## connect_to_server() is called, and every networked code path in the game is
## gated on it. With no session the game is bit-for-bit the solo game.
##
## Authority model ("one-peer mirror"):
##   - each avatar is simulated by the machine of the player steering it and
##     mirrored to everyone else (MultiplayerSynchronizer on Player.tscn);
##   - the world simulation — enemy AI, spawning, kills, score, milestones,
##     victory — runs on the SIM AUTHORITY (solo, the peer-to-peer host, or the
##     dedicated server) and is mirrored through MultiplayerSpawners, per-enemy
##     synchronizers and the events below;
##   - cosmetics never replicate as state. Each machine fires its own shake,
##     particles and popups from replicated EVENTS.

signal peers_changed
signal session_closed(reason: String)
## Somebody in the lobby picked a different climber, or switched to watching.
signal choices_changed

enum Mode {COOP, RACE}

const DEFAULT_PORT: int = NetProtocol.DEFAULT_PORT
## The ceiling for a peer-to-peer host. A dedicated server sets its own, higher,
## from its configuration — this is what one player's machine will carry.
const MAX_PLAYERS: int = 8

## The run this machine is in. One object, mutated in place, handed to the World
## by reference so that a peer dropping out is seen by the world that has to
## remove its avatar.
var session: NetSession = NetSession.new()

## True in the dedicated-server process, set by PitServer at boot. It exists to
## turn OFF the peer-to-peer lobby: a server has no climber to announce, and
## `announce_choice()` broadcasting to every peer would put the server's own
## default pick into every client's lobby list.
var dedicated: bool = false
## True on a machine that is a CLIENT of a dedicated server. The lobby chatter is
## off here too — who you are playing is something you tell the server, which
## tells the room, rather than something you announce to everybody connected.
var on_server: bool = false

## The handshake with a dedicated server. Created here rather than authored in a
## scene because `Net` is an autoload and has none, the same way `Audio` builds
## its players.
var link: ServerLink

## True from host()/join() until leave() or a connection error. Kept as a
## forwarding property rather than a field so that the many `Net.active` reads
## across the game — and the suites that set it directly to fake a session —
## keep working while there is only one place the answer is stored.
var active: bool:
	get:
		return session.active
	set(value):
		session.active = value

var mode: int:
	get:
		return session.mode
	set(value):
		session.mode = value

## The locked roster of the running session, same on every machine in the room.
## Empty while in the lobby or solo. Spectators are in it — they are in the
## session, they just have no avatar.
var session_peers: Array[int]:
	get:
		return session.peers
	set(value):
		session.peers = value

## peer -> the climber it locked in, `CharacterRoster.SPECTATOR` for a peer that
## joined to watch. Identical on every machine in the room, so every peer builds
## the same avatars in the same order without a handshake.
var session_characters: Dictionary[int, StringName]:
	get:
		return session.characters
	set(value):
		session.characters = value

## Lobby only: who has picked what so far. Each peer speaks for itself and
## nobody else, and everyone re-announces whenever the lobby changes, so a peer
## that arrives late still learns the whole picture.
var lobby_choices: Dictionary[int, StringName] = {}
## What this machine has picked. Kept here rather than read back out of
## lobby_choices, which is a view of everybody.
var local_choice: StringName = &"":
	set(value):
		local_choice = value
		announce_choice()


func _ready() -> void:
	link = ServerLink.new()
	link.name = "ServerLink"
	add_child(link)
	# Whatever this machine last played solo. character_def() resolves an empty
	# or unknown saved id to the roster's fallback, so this is never garbage.
	local_choice = Game.character_def().id
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: close_session("CONNECTION FAILED"))
	multiplayer.server_disconnected.connect(func() -> void: close_session("HOST LEFT"))


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	NetProtocol.apply_transport(peer)
	multiplayer.multiplayer_peer = peer
	active = true
	lobby_choices.clear()
	announce_choice()
	peers_changed.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	NetProtocol.apply_transport(peer)
	multiplayer.multiplayer_peer = peer
	active = true
	lobby_choices.clear()
	peers_changed.emit()
	return OK


## The socket is up. Say what we picked — until now there was nobody to tell.
func _on_connected_to_server() -> void:
	announce_choice()
	peers_changed.emit()


func is_host() -> bool:
	return active and multiplayer.is_server()


## True when this machine owns the WORLD simulation: solo play, the peer-to-peer
## host, or a dedicated server. Enemy AI, spawning and scoring run only where
## this is true.
func is_sim_authority() -> bool:
	return not active or multiplayer.is_server()


## True only inside a running RACE.
##
## Deprecated in favour of asking the world — `NetSession.of(node).is_versus()` —
## because a dedicated server runs a race in one room and a co-op climb in the
## next, and this can only describe one of them. It is still correct on a
## player's machine, which is in one room, and that is the only place it is
## still read.
func is_versus() -> bool:
	return session.is_versus()


## Everyone connected right now (the lobby view): this machine plus the rest.
func lobby_peers() -> Array[int]:
	if not active:
		return [1]
	var out: Array[int] = [multiplayer.get_unique_id()]
	for p in multiplayer.get_peers():
		out.append(p)
	out.sort()
	return out


# ── Who is playing whom ─────────────────────────────────────────────────────
## Tell the lobby what this machine picked. A peer may only ever speak for
## itself; the id it sends is checked against the sender.
func announce_choice() -> void:
	if dedicated or on_server:
		return # a room's roster is the server's business, not a broadcast
	if not active:
		lobby_choices[1] = local_choice
		choices_changed.emit()
		return
	_set_choice.rpc(local_choice)


@rpc("any_peer", "call_local", "reliable")
func _set_choice(id: StringName) -> void:
	# call_local reports sender 0; that is us, speaking for ourselves.
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	lobby_choices[sender] = id
	choices_changed.emit()


## What a peer has picked, as something the UI can print.
func choice_of(peer_id: int) -> StringName:
	return lobby_choices.get(peer_id, Game.default_character_id())


## Host only: lock the roster and start an identical run on every machine.
func start_session(run_mode: Mode, world_seed: int) -> void:
	if not is_host():
		return
	var ids: Array[int] = [1]
	for p in multiplayer.get_peers():
		ids.append(p)
	ids.sort()
	# The picks travel WITH the roster rather than being asked for afterwards:
	# every machine has to build the same avatars in the same order before the
	# first frame, and a peer that never announced simply gets the default.
	var picks: Array[StringName] = []
	for id in ids:
		picks.append(lobby_choices.get(id, Game.default_character_id()))
	_begin_run.rpc(run_mode, world_seed, ids, picks)


## Host only: same mode, fresh layout, everyone at the bottom again. It goes
## through start_session, so a restart is not a special case — the roster is
## re-locked from whoever is still connected and every machine enters the new
## run the same way it entered the first one.
func restart_session() -> void:
	if not is_host():
		return
	var fresh_seed := 0
	while fresh_seed == 0:
		fresh_seed = randi()
	start_session(mode as Mode, fresh_seed)


@rpc("authority", "call_local", "reliable")
func _begin_run(run_mode: int, world_seed: int, peer_ids: Array, picks: Array) -> void:
	session.active = true
	session.mode = run_mode
	# A peer-to-peer session is one unnamed room, and room 0 is what makes the
	# world node keep the plain name `World` it has always had — so nothing about
	# the existing addressing moves when a dedicated server is not involved.
	session.room_id = 0
	session.peers.clear()
	session.characters.clear()
	for i in peer_ids.size():
		var id := int(peer_ids[i])
		session.peers.append(id)
		session.characters[id] = StringName(picks[i]) if i < picks.size() \
				else Game.default_character_id()
	Game.local_peer_id = multiplayer.get_unique_id()
	Router.start_run(world_seed, session)


func leave() -> void:
	close_session("")


func close_session(reason: String) -> void:
	if not active:
		return
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session.active = false
	session.peers.clear()
	session.characters.clear()
	session.room_id = 0
	lobby_choices.clear()
	on_server = false
	Hub.clear()
	Game.local_peer_id = 1
	peers_changed.emit()
	choices_changed.emit()
	if reason != "":
		session_closed.emit(reason)


## Somebody arrived. Everyone says again what they picked, rather than the host
## keeping a master copy and forwarding it: each peer is the only authority on
## its own choice, and a lobby of eight re-announcing is a few dozen bytes.
func _on_peer_connected(_id: int) -> void:
	announce_choice()
	peers_changed.emit()


# ── Dedicated server, client side ───────────────────────────────────────────
## Dial a dedicated server. Everything after this — the room browser, the room,
## the run — happens over `Hub`; this only opens the socket and proves who we
## are. `intent` is one of NetProtocol's INTENT_* values.
func connect_to_server(address: String, port: int, intent: StringName,
		player_name: String, password: String, token: String = "") -> Error:
	lobby_choices.clear()
	on_server = true
	var err := link.connect_to(address, port, intent, player_name, password, token)
	if err != OK:
		on_server = false
	return err


## A room this machine is in has started. The mirror of `_begin_run` for a
## peer-to-peer host, and it carries the same things for the same reason: the
## picks travel WITH the seed, so every machine builds the same avatars in the
## same order before its first frame.
func enter_room_run(room_id: int, world_seed: int, run_mode: int, peer_ids: Array,
		picks: Array) -> void:
	session.active = true
	session.mode = run_mode
	session.room_id = room_id
	session.peers.clear()
	session.characters.clear()
	for i in peer_ids.size():
		var id := int(peer_ids[i])
		session.peers.append(id)
		session.characters[id] = StringName(picks[i]) if i < picks.size() \
				else CharacterRoster.SPECTATOR
	Game.local_peer_id = multiplayer.get_unique_id()
	Router.start_run(world_seed, session)


## The run ended and the room went back to its lobby. The session stays active —
## we are still connected and still in the room — but there is no world any more.
func leave_room_run(_room_id: int) -> void:
	session.peers.clear()
	session.characters.clear()
	Router.to_server_lobby()


func _on_peer_disconnected(id: int) -> void:
	session.peers.erase(id)
	session.characters.erase(id)
	lobby_choices.erase(id)
	peers_changed.emit()
	choices_changed.emit()

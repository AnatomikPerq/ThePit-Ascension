extends Node
## Net — connection lifecycle for a hosted session. Plain ENet over an open
## port, no service integration: one player hosts, the rest join by address.
##
## Single-player NEVER opens a socket: `active` is false until host() or
## join() is called from the lobby, and every networked code path in the game
## is gated on it. With no session the game is bit-for-bit the solo game.
##
## Authority model ("one-peer mirror"):
##   - each avatar is simulated by the machine of the player steering it and
##     mirrored to everyone else (MultiplayerSynchronizer on Player.tscn);
##   - the world simulation — enemy AI, spawning, kills, score, milestones,
##     victory — runs on the HOST and is mirrored through MultiplayerSpawners,
##     per-enemy synchronizers and the events below;
##   - cosmetics never replicate as state. Each machine fires its own shake,
##     particles and popups from replicated EVENTS.

signal peers_changed
signal session_closed(reason: String)
## Somebody in the lobby picked a different climber, or switched to watching.
signal choices_changed

enum Mode {COOP, RACE}

const DEFAULT_PORT: int = 24565
const MAX_PLAYERS: int = 8

## True from host()/join() until leave() or a connection error.
var active: bool = false
var mode: int = Mode.COOP
## The locked roster of the running session, host first, same on every
## machine. Empty while in the lobby or solo. Spectators are in it — they are
## in the session, they just have no avatar.
var session_peers: Array[int] = []
## peer -> the climber it locked in, `CharacterRoster.SPECTATOR` for a peer that
## joined to watch. Filled at start_session and identical on every machine, so
## every peer builds the same avatars in the same order without a handshake.
var session_characters: Dictionary[int, StringName] = {}

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


## True when this machine owns the WORLD simulation: solo play, or the host
## of a session. Enemy AI, spawning and scoring run only where this is true.
func is_sim_authority() -> bool:
	return not active or multiplayer.is_server()


## True only inside a running RACE. Rivals are solid to each other and their
## attacks land; in co-op players share a goal, so they pass through each other
## and cannot do each other harm. Solo is never versus — one predicate keeps
## the two modes from leaking into each other anywhere else.
func is_versus() -> bool:
	return active and mode == Mode.RACE


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
	mode = run_mode as Mode
	session_peers.clear()
	session_characters.clear()
	for i in peer_ids.size():
		var id := int(peer_ids[i])
		session_peers.append(id)
		session_characters[id] = StringName(picks[i]) if i < picks.size() \
				else Game.default_character_id()
	Game.local_peer_id = multiplayer.get_unique_id()
	Router.start_run(world_seed)


func leave() -> void:
	close_session("")


func close_session(reason: String) -> void:
	if not active:
		return
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	session_peers.clear()
	session_characters.clear()
	lobby_choices.clear()
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


func _on_peer_disconnected(id: int) -> void:
	session_peers.erase(id)
	session_characters.erase(id)
	lobby_choices.erase(id)
	peers_changed.emit()
	choices_changed.emit()

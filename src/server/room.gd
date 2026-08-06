class_name Room
extends RefCounted
## One room on a dedicated server: a lobby, the run it turns into, and the people
## in it.
##
## A room owns a `NetSession` and, while a run is going, a `World`. The world is
## added at `/root/World<id>` — the same path a client in this room builds it at —
## which is what keeps two rooms' replication apart on one socket. See
## NetSession.world_name() and the note in Router.start_run().
##
## Everything a room can be configured to be is here rather than in the manager,
## because the admin panel edits a room and the console edits a room, and both
## should be editing the same object.

enum State {LOBBY, RUNNING, ENDED}

const STATE_NAMES: Array[String] = ["LOBBY", "RUNNING", "ENDED"]

var id: int = 0
var name: String = ""
var mode: int = NetSession.MODE_COOP
var max_players: int = 8
## SHA-256 of the room's password, or "" for an open room. The password itself is
## never kept: a moderator reading a room's settings has no business seeing it,
## and neither has a crash dump.
var password_hash: String = ""
## The account that opened it. Empty for a room the server itself keeps.
var owner_id: String = ""
## A room from the configuration rather than from a player. It survives being
## empty and cannot be closed by anyone but staff.
var persistent: bool = false

var state: int = State.LOBBY
## Peers in the room, in join order. The order is the order avatars are built in,
## so it has to be the same on every machine — which it is, because it travels
## with the seed when the run starts.
var members: Array[int] = []
## peer -> chosen climber, `CharacterRoster.SPECTATOR` for a watcher.
var choices: Dictionary[int, StringName] = {}

var world: Node = null
var session: NetSession = NetSession.new()
var run_seed: int = 0
var created_at: int = 0
## Seconds this room has been empty, and since a finished run ended. Both drive
## the automatic tidying in RoomManager; neither means anything while somebody
## is in here.
var empty_for: float = 0.0
var ended_for: float = 0.0

## The last messages said here, oldest first. A player joining is shown them, so
## walking into a room mid-conversation is not walking into silence.
var chat: Array[Dictionary] = []


static func make(room_id: int, room_name: String) -> Room:
	var room := Room.new()
	room.id = room_id
	room.name = room_name
	room.created_at = int(Time.get_unix_time_from_system())
	room.session.room_id = room_id
	room.session.active = true
	return room


func set_password(password: String) -> void:
	password_hash = "" if password == "" \
			else NetCrypto.sha256_hex(password.to_utf8_buffer())


func locked() -> bool:
	return password_hash != ""


func password_matches(candidate: String) -> bool:
	if password_hash == "":
		return true
	return NetCrypto.equal(
		password_hash.hex_decode(),
		NetCrypto.sha256_hex(candidate.to_utf8_buffer()).hex_decode())


func is_member(peer_id: int) -> bool:
	return members.has(peer_id)


## Everyone in the room who chose a climber. Spectators are members but never
## get an avatar, which is the same rule the peer-to-peer lobby already had.
func climbers() -> Array[int]:
	var out: Array[int] = []
	for peer_id in members:
		if choices.get(peer_id, CharacterRoster.SPECTATOR) != CharacterRoster.SPECTATOR:
			out.append(peer_id)
	return out


func spectators() -> int:
	return members.size() - climbers().size()


## Whether one more player fits. Spectators may or may not take a seat, which is
## `rooms/spectators_count_to_limit` — a room set up for people to watch a race
## should not fill up with them.
func has_room_for(as_spectator: bool, spectators_count: bool) -> bool:
	var used := members.size() if spectators_count else climbers().size()
	if as_spectator and not spectators_count:
		return true
	return used < max_players


func add_member(peer_id: int, character: StringName) -> void:
	if not members.has(peer_id):
		members.append(peer_id)
	choices[peer_id] = character


func remove_member(peer_id: int) -> void:
	members.erase(peer_id)
	choices.erase(peer_id)
	session.peers.erase(peer_id)
	session.characters.erase(peer_id)


## Lock the roster into the session the world will be built from. The picks
## travel with the seed for the same reason they always have: every machine has
## to build the same avatars in the same order before its first frame.
func lock_roster(seed_value: int) -> void:
	run_seed = seed_value
	session.mode = mode
	session.room_id = id
	session.active = true
	session.peers = members.duplicate()
	session.characters.clear()
	for peer_id in members:
		session.characters[peer_id] = choices.get(peer_id, CharacterRoster.SPECTATOR)


func world_name() -> String:
	return NetSession.world_name_for(id)


func running() -> bool:
	return state == State.RUNNING and is_instance_valid(world)


func remember(entry: Dictionary, keep: int) -> void:
	chat.append(entry)
	while chat.size() > keep and keep >= 0:
		chat.remove_at(0)


## What a client is told about this room, in the browser and while in it.
##
## Note what is NOT here: the password, the seed, the member peer ids. A room
## list is sent to everybody connected, including people who have not been let
## into this room, so it carries only what a stranger may know.
func info() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"mode": mode,
		"state": state,
		"players": climbers().size(),
		"spectators": spectators(),
		"max_players": max_players,
		"locked": locked(),
		"persistent": persistent,
		"owner": owner_id,
	}


## The fuller picture, for the people actually in the room: who is here and what
## each of them is playing.
func detail(names: Dictionary[int, String]) -> Dictionary:
	var out := info()
	var roster: Array = []
	for peer_id in members:
		roster.append({
			"peer": peer_id,
			"name": names.get(peer_id, "player %d" % peer_id),
			"character": String(choices.get(peer_id, CharacterRoster.SPECTATOR)),
		})
	out["members"] = roster
	return out


static func state_name(value: int) -> String:
	return STATE_NAMES[value] if value >= 0 and value < STATE_NAMES.size() else "?"


static func mode_name(value: int) -> String:
	return "RACE" if value == NetSession.MODE_RACE else "CO-OP"


static func mode_from(text: String) -> int:
	return NetSession.MODE_RACE if text.to_lower() == "race" else NetSession.MODE_COOP

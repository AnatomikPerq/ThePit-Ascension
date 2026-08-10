class_name NetSession
extends RefCounted
## Who is in one run, what each of them is playing, and how a message reaches
## exactly them and nobody else.
##
## Before the dedicated server there was no need for this to be an object: a
## machine was in at most one session, so "the session" could be a handful of
## fields on the `Net` autoload and a broadcast could be a plain `.rpc()`. A
## server hosts several runs at once, and both of those stop being true —
## `.rpc()` from room 3 would land on every peer in rooms 1 and 2, on a node path
## they do not have.
##
## So a session is a *value*, one per run, and every message is addressed:
##
## - a player's machine has one, on `Net`, describing the room it is in;
## - a dedicated server has one per room, held by that room's World;
## - solo play has an inert one, where `active` is false and broadcasting is
##   simply calling the method.
##
## `of(node)` is how any node in a world finds the session it belongs to without
## anybody having to thread it through a constructor. It walks up to the World —
## and falls back to `Net`'s own when there is no world above, which is the case
## in every unit test that puts an enemy and a player under a bare Node2D.

## The World carries this group, and that is what makes `of()` work. Adding it to
## anything else would give nodes underneath a different answer than their world.
const HOST_GROUP: StringName = &"net_session"

## Modes are Net.Mode values. Kept as a plain int here so this file does not
## depend on the autoload it is a field of.
const MODE_COOP: int = 0
const MODE_RACE: int = 1

## False solo and in the menus. Every networked code path in the game is gated
## on it, which is what "single-player never opens a socket" means in practice.
var active: bool = false
var mode: int = MODE_COOP
## 0 for solo and for a peer-to-peer host, which is one unnamed room. A dedicated
## server numbers its rooms from 1, and the number is part of the world's node
## name so that two rooms cannot collide in the replication path space.
var room_id: int = 0
## The locked roster: everyone in this run, spectators included. Identical on
## every machine in the room, because it travels with the seed.
var peers: Array[int] = []
## peer -> the climber it locked in, `CharacterRoster.SPECTATOR` for a watcher.
var characters: Dictionary[int, StringName] = {}


## The session a node belongs to: its world's, or the local machine's when the
## node is not under a world at all.
static func of(node: Node) -> NetSession:
	var world := world_of(node)
	if world != null:
		var found: Variant = world.get(&"session")
		if found != null:
			return found
	return Net.session


## The world a node lives in, or null when it lives outside one — a menu, or a
## unit suite that puts an enemy and a player under a bare Node2D.
static func world_of(node: Node) -> Node:
	var walk := node
	while walk != null:
		if walk.is_in_group(HOST_GROUP):
			return walk
		walk = walk.get_parent()
	return null


## Every avatar in this node's room.
##
## The reason this exists rather than `get_tree().get_nodes_in_group(&"player")`:
## a dedicated server hosts several pits in ONE tree, and every one of them is
## built in the same coordinate space starting at the same origin. So the
## tree-wide group answer to "which climber is nearest" can be somebody in
## another room standing at the same height — an enemy would chase a player it
## can never reach, through geometry that is not there. The world's own roster is
## both the correct answer and a shorter list.
##
## With no world above, it falls back to the group: solo play and every unit
## suite are exactly the case where the tree holds one room's worth of nodes.
static func avatars_of(node: Node) -> Array:
	var world := world_of(node)
	if world == null:
		return node.get_tree().get_nodes_in_group(&"player")
	var roster: Variant = world.get(&"players")
	return (roster as Dictionary).values() if roster != null else []


## Nodes in `group` that belong to the same room as `node`. Same reasoning as
## `avatars_of`, for the groups that have no per-world roster to read instead.
static func in_world(node: Node, group: StringName) -> Array:
	var all := node.get_tree().get_nodes_in_group(group)
	var world := world_of(node)
	if world == null:
		return all
	var out: Array[Node] = []
	for n: Node in all:
		if n == world or world.is_ancestor_of(n):
			out.append(n)
	return out


## True only inside a running RACE. The one predicate that decides whether
## rivals are solid to each other and whether their attacks land — see
## docs/NETWORKING.md. Per room now, because a server can run a race in one room
## and a co-op climb in the next.
func is_versus() -> bool:
	return active and mode == MODE_RACE


## The world node name for this room. Node paths are how the replication layer
## addresses everything, so two rooms on one socket must not share one — and
## both sides have to derive the same name from the same room id without a
## handshake, which is why it is a pure function of the id.
func world_name() -> String:
	return "World" if room_id == 0 else "World%d" % room_id


static func world_name_for(id: int) -> String:
	return "World" if id == 0 else "World%d" % id


# ── Addressed messages ──────────────────────────────────────────────────────
## Run `method` here and on every other machine in this room.
##
## The replacement for `node.rpc(...)`, which reaches every peer the socket
## knows about. On a player's machine the two are equivalent — everybody
## connected is in the room. On a dedicated server they are not, and the
## difference is a client trying to apply room 3's explosion to a world it has
## never built.
func broadcast(node: Node, method: StringName, args: Array = []) -> void:
	node.callv(method, args)
	if not active:
		return
	_send(node, method, args, node.multiplayer.get_unique_id())


## The same, without running it here: for events this machine has already
## applied, or must not.
func broadcast_remote(node: Node, method: StringName, args: Array = []) -> void:
	if not active:
		return
	_send(node, method, args, node.multiplayer.get_unique_id())


## A room's audience is its MEMBERS, plus the machine that simulates it.
##
## Those are the same list on a player's machine — `Net._begin_run` builds the
## roster starting with `[1]`, so the host is in it. On a dedicated server they
## are not, and the difference was silent and total: `Room.lock_roster` sets
## `session.peers = members.duplicate()` and the server is a member of no room —
## it has no avatar and no climb — so a CLIENT's broadcast went to the other
## clients and stopped there.
##
## Peer 1 is where every kill is resolved (`EnemyCombat._resolve_kills` runs
## under `Net.is_sim_authority()` and nowhere else), so an attack hitbox that
## never reached it never killed anything. On a dedicated server, no client could
## kill an enemy by punching, swinging, shooting or firing a railgun — only by
## stomping, because a stomp travels by `rpc_id` to a named peer instead. The
## same hole swallowed `_go_down`, `stand_up` and `pay_revive`: the server was
## never told a client had gone down or been picked back up.
##
## The server is added here rather than to `peers` on purpose. `peers` is the
## ROSTER: `World._playing_peers()` builds one avatar per entry and
## `prune_disconnected` deletes anyone missing from it, so putting 1 in it would
## give the server a climber in every room on every client's screen.
func _send(node: Node, method: StringName, args: Array, skip: int) -> void:
	for peer_id in peers:
		if peer_id == skip:
			continue
		node.callv(&"rpc_id", [peer_id, method] + args)
	# `skip != 1` is this machine BEING the server; `not peers.has(1)` is a
	# peer-to-peer host, already covered by the loop above.
	if skip != 1 and not peers.has(1):
		node.callv(&"rpc_id", [1, method] + args)


# ── Replication scope ───────────────────────────────────────────────────────
## Restrict everything replicated inside `node` to this room's members, BEFORE
## it enters the tree.
##
## This is the second half of how one socket carries several rooms — the first
## being that each room's world sits at its own node path. Without it, every
## spawn packet and every sync packet in room 3 is sent to every peer on the
## server, and a client in room 1 tries to instantiate an enemy under a world it
## has never built.
##
## Measured before it was relied on (tools/roomscope_probe.gd, three real
## processes over a real socket): `public_visibility = false` plus an explicit
## `set_visibility_for` per member gates the MultiplayerSpawner's SPAWN packet as
## well as the sync stream. Setting it before `add_child` rather than after is
## what keeps a packet from going out and being retracted a frame later.
##
## Room 0 — solo play and a peer-to-peer host — is left alone: there is exactly
## one room there, everybody connected is in it, and restricting visibility would
## only be a way to get it wrong.
func scope(node: Node) -> void:
	if not active or room_id == 0 or node == null:
		return
	if node is MultiplayerSynchronizer:
		scope_sync(node as MultiplayerSynchronizer, peers)
	for found: Node in node.find_children("*", "MultiplayerSynchronizer", true, false):
		scope_sync(found as MultiplayerSynchronizer, peers)


## Re-apply the scope to a world already in the tree. For a membership change:
## somebody joining mid-run to watch has to start receiving, and somebody leaving
## has to stop.
func rescope(world: Node) -> void:
	if not active or room_id == 0 or not is_instance_valid(world):
		return
	for found: Node in world.find_children("*", "MultiplayerSynchronizer", true, false):
		scope_sync(found as MultiplayerSynchronizer, peers)


## Visible to the room's members — and to peer 1, for the same reason `_send`
## addresses it: on a dedicated server the machine simulating this room is not a
## member of it. Without this a client's avatar never sends its position to the
## server, so the server resolves stomps, blasts and hitbox overlaps against a
## climber it believes is still standing on the spawn pad.
##
## On a peer-to-peer host peer 1 is already in `members`, and Godot's visibility
## set is a set: naming it twice costs nothing.
static func scope_sync(sync: MultiplayerSynchronizer, members: Array[int]) -> void:
	if sync == null:
		return
	sync.public_visibility = false
	sync.set_visibility_for(1, true)
	for peer_id in members:
		sync.set_visibility_for(peer_id, true)

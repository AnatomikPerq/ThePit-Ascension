class_name ServerPeer
extends RefCounted
## One connection, from the handshake to the disconnect.
##
## A peer is not an account and not a player: it is a socket with a story. It
## starts anonymous, acquires an account when the handshake finishes, acquires a
## room when it joins one, and is forgotten when it goes. Keeping those three
## apart is what makes "kick the peer, keep the account, remember the ban"
## expressible.

enum Stage {AUTHENTICATING, LOBBY, IN_ROOM}

var peer_id: int = 0
## As ENet reports it. Used for per-address limits and for a ban that has to
## follow somebody through a name change.
var address: String = ""
var stage: int = Stage.AUTHENTICATING
## Filled by the handshake. Guests get one too, so everything downstream deals
## with accounts and not with two kinds of player.
var account: Account = null
## 0 while in the server lobby — connected, browsing, in no room.
var room_id: int = 0

var connected_at: float = 0.0
var last_activity: float = 0.0
## Violations of the movement guard that have not decayed yet, and when the most
## recent one was, so they can.
var violations: int = 0
var last_violation_at: float = 0.0
## Where this avatar was last seen, for the movement guard's step check. Set from
## the replicated position, never trusted, only compared.
var last_position: Vector2 = Vector2.ZERO
var has_position: bool = false
## Warnings issued by a moderator this session, on top of the account's stored
## total — a guest has nowhere to keep them.
var session_warnings: int = 0

## Set when the server has decided to drop this peer, so a message can be
## delivered before the socket closes and nothing tries to talk to it after.
var closing: bool = false


static func make(id: int, from: String) -> ServerPeer:
	var peer := ServerPeer.new()
	peer.peer_id = id
	peer.address = from
	peer.connected_at = Time.get_ticks_msec() / 1000.0
	peer.last_activity = peer.connected_at
	return peer


func name_text() -> String:
	return account.name if account != null else "peer %d" % peer_id


func authenticated() -> bool:
	return account != null and stage != Stage.AUTHENTICATING


func may(right: String) -> bool:
	return account != null and account.may(right)


func touch() -> void:
	last_activity = Time.get_ticks_msec() / 1000.0


func idle_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0 - last_activity


## Record a movement-guard violation and say whether it has crossed the line.
## Violations decay rather than accumulating forever: a player on a bad
## connection should not be banked against for an hour.
func add_violation(limit: int, decay_seconds: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_violation_at > decay_seconds:
		violations = 0
	violations += 1
	last_violation_at = now
	return violations >= limit


## What the player list and the admin panel show. The address is in here, so
## callers must check `player.inspect` before passing it on — RoomManager and the
## commands both do, and the client is never sent this wholesale.
func info() -> Dictionary:
	return {
		"peer": peer_id,
		"name": name_text(),
		"account": account.id if account != null else "",
		"role": account.role if account != null else Permissions.ROLE_PLAYER,
		"guest": account.guest if account != null else true,
		"room": room_id,
		"stage": stage,
		"address": address,
		"connected_for": int(Time.get_ticks_msec() / 1000.0 - connected_at),
		"muted": account.is_muted() if account != null else false,
		"warnings": session_warnings + (account.warnings if account != null else 0),
	}


## The same, with everything a stranger should not see taken out. This is what
## goes to a client that asked who else is here.
static func redact(entry: Dictionary) -> Dictionary:
	var out := entry.duplicate()
	out.erase("address")
	out.erase("account")
	return out

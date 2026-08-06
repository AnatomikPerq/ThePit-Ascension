class_name Permissions
extends Object
## What anybody is allowed to do, as a flat list of named rights.
##
## Roles are a convenience over these, not the other way round. `op somebody`
## makes them an admin, which is a *bundle* of rights — but the check anywhere in
## the server is always for one right by name, never for a role. That is what
## lets a server owner hand one person the ability to kick without also handing
## them the ability to edit settings, and it is why every command declares the
## right it needs instead of a rank.
##
## Wildcards are matched left to right on dots, so `room.*` covers `room.create`
## and everything added under it later. The owner holds `*`.

# ── The rights ──────────────────────────────────────────────────────────────
const CHAT_SEND := "chat.send"
const CHAT_BROADCAST := "chat.broadcast"      ## an announcement to the whole server
const CHAT_BYPASS_FILTER := "chat.bypass"     ## not rate-limited, not word-filtered

const ROOM_JOIN := "room.join"
const ROOM_CREATE := "room.create"
const ROOM_CONFIGURE := "room.configure"      ## settings of a room you own
const ROOM_CONFIGURE_ANY := "room.configure.any"
const ROOM_START := "room.start"
const ROOM_CLOSE := "room.close"              ## close a room you own
const ROOM_CLOSE_ANY := "room.close.any"
const ROOM_JOIN_LOCKED := "room.join.locked"  ## past a password, and past a full room

const PLAYER_LIST := "player.list"            ## see who is on the server at all
const PLAYER_INSPECT := "player.inspect"      ## address, account, room, warnings
const PLAYER_KICK := "player.kick"
const PLAYER_BAN := "player.ban"
const PLAYER_UNBAN := "player.unban"
const PLAYER_MUTE := "player.mute"
const PLAYER_WARN := "player.warn"
const PLAYER_MOVE := "player.move"            ## move somebody between rooms

const ACCOUNT_LIST := "account.list"
const ACCOUNT_EDIT := "account.edit"          ## rename, reset a password
const ACCOUNT_ROLE := "account.role"          ## op / deop — hand out rights
const ACCOUNT_DELETE := "account.delete"

const SERVER_STATUS := "server.status"        ## uptime, load, room count
const SERVER_SETTINGS_READ := "server.settings.read"
const SERVER_SETTINGS_WRITE := "server.settings.write"
const SERVER_LOG := "server.log"              ## read the live log
const SERVER_STOP := "server.stop"
const SERVER_ADMIN_PANEL := "server.panel"    ## may open the in-game panel at all

const ALL := "*"

# ── The bundles ─────────────────────────────────────────────────────────────
const ROLE_PLAYER := "player"
const ROLE_MODERATOR := "moderator"
const ROLE_ADMIN := "admin"
const ROLE_OWNER := "owner"

## Ordered weakest to strongest. Used for "you cannot act on somebody at or above
## your own rank", which is the rule that stops two admins from deposing each
## other and stops a moderator from kicking the owner.
const ROLES: Array[String] = [ROLE_PLAYER, ROLE_MODERATOR, ROLE_ADMIN, ROLE_OWNER]


## The rights each role carries. A moderator can act on people; an admin can act
## on the server; the owner can do anything including changing who is what.
static func of_role(role: String) -> PackedStringArray:
	match role:
		ROLE_OWNER:
			return PackedStringArray([ALL])
		ROLE_ADMIN:
			return PackedStringArray([
				"chat.*", "room.*", "player.*", "account.list", "account.edit",
				"server.status", "server.settings.read", "server.settings.write",
				"server.log", "server.panel"])
		ROLE_MODERATOR:
			return PackedStringArray([
				CHAT_SEND, CHAT_BROADCAST, CHAT_BYPASS_FILTER,
				ROOM_JOIN, ROOM_CREATE, ROOM_CONFIGURE, ROOM_START,
				ROOM_CLOSE, ROOM_CLOSE_ANY, ROOM_JOIN_LOCKED,
				PLAYER_LIST, PLAYER_INSPECT, PLAYER_KICK, PLAYER_MUTE,
				PLAYER_WARN, PLAYER_BAN, PLAYER_MOVE,
				SERVER_STATUS, SERVER_LOG, SERVER_ADMIN_PANEL])
	return PackedStringArray([CHAT_SEND, ROOM_JOIN, ROOM_CREATE, ROOM_START,
		ROOM_CONFIGURE, ROOM_CLOSE])


static func rank(role: String) -> int:
	var index := ROLES.find(role)
	return index if index >= 0 else 0


static func is_role(name: String) -> bool:
	return ROLES.has(name)


## Does this set of rights include `wanted`?
##
## `held` is the role's bundle plus whatever was granted to the account
## individually, so a plain player can be handed `player.kick` and nothing else.
static func allows(held: PackedStringArray, wanted: String) -> bool:
	for right in held:
		if _matches(right, wanted):
			return true
	return false


## `player.*` matches `player.kick`; `*` matches everything; anything else has
## to be exact. Deliberately not a regex — a permission that can be written
## wrongly in a config file and then match more than intended is a hole.
static func _matches(held: String, wanted: String) -> bool:
	if held == ALL or held == wanted:
		return true
	if not held.ends_with(".*"):
		return false
	return wanted.begins_with(held.substr(0, held.length() - 1))


## Everything a role plus a set of individual grants comes to, with any explicit
## denial removed. Denials win, so a right can be taken back from somebody whose
## role would otherwise carry it.
static func effective(role: String, grants: PackedStringArray,
		denials: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for right in of_role(role):
		out.append(right)
	for right in grants:
		if not out.has(right):
			out.append(right)
	if denials.is_empty():
		return out
	var kept := PackedStringArray()
	for right in out:
		if not denials.has(right):
			kept.append(right)
	return kept


## Every right there is, for `help permissions`, for the admin panel's grant
## list and for `test/server_permissions_test.gd`, which asserts that no role
## carries a right that is not in here — that is what catches a constant added
## above and forgotten below.
static func catalogue() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array([
		CHAT_SEND, CHAT_BROADCAST, CHAT_BYPASS_FILTER,
		ROOM_JOIN, ROOM_CREATE, ROOM_CONFIGURE, ROOM_CONFIGURE_ANY, ROOM_START,
		ROOM_CLOSE, ROOM_CLOSE_ANY, ROOM_JOIN_LOCKED,
		PLAYER_LIST, PLAYER_INSPECT, PLAYER_KICK, PLAYER_BAN, PLAYER_UNBAN,
		PLAYER_MUTE, PLAYER_WARN, PLAYER_MOVE,
		ACCOUNT_LIST, ACCOUNT_EDIT, ACCOUNT_ROLE, ACCOUNT_DELETE,
		SERVER_STATUS, SERVER_SETTINGS_READ, SERVER_SETTINGS_WRITE,
		SERVER_LOG, SERVER_STOP, SERVER_ADMIN_PANEL,
	])
	return out

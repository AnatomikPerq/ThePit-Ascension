class_name NetProtocol
extends Object
## The wire contract between a client and a dedicated server.
##
## Two numbers travel in the first packet either side sends, and a connection
## that disagrees about either is refused before it can become a desync:
##
## - **`VERSION`** — the shape of the conversation. Bump it whenever a message
##   gains, loses or repurposes a field, whenever an `@rpc` signature changes,
##   and whenever authority moves between machines. It is a hand-maintained
##   number because it describes code, and code cannot be hashed out of an
##   exported build.
## - **`content_hash()`** — the pit itself. Generated, not maintained: every file
##   the simulation is a function of goes into it (see ProtocolStamp and
##   `tools/build_protocol_stamp.gd`). A character, an enemy, an upgrade, a
##   tuning number or a level count that moved on one side and not the other
##   changes it, and the mismatch is reported with the two hashes rather than
##   discovered later as "the game is broken".
##
## Why bother, when both sides are built from the same repository: because a
## server is a process that stays up for weeks. The failure this prevents is not
## a developer running the wrong branch, it is an operator who updated the game
## and forgot the server — and the symptom without this check is a client
## rebuilding a *different* pit from the same seed and falling through geometry
## its server does not have.

## The conversation's shape. See the class comment for when to move it.
##
## History:
##   1 — first dedicated-server protocol (hello / ident / challenge / proof).
##   2 — Uzi's railgun. An avatar's sync stream gained `aiming` and `aim_angle`,
##       and Player gained the `_spawn_weapon_shot(from, angle)` RPC — a message
##       gaining a field and a new @rpc signature, both of which this covers.
const VERSION: int = 2

## Refuses a connection from a different game entirely — someone pointing a tool
## at the port, or a fork that kept the port number.
const GAME_ID: StringName = &"thepit.ascension"

const STAMP_PATH := "res://data/net/protocol_stamp.tres"

## The port a peer-to-peer host opens and a dedicated server listens on unless
## told otherwise. It lives here rather than on `Net` because both a client and
## a server need it and neither should be the one that owns it.
const DEFAULT_PORT: int = 24565

## ENet compression. It is HERE, and not a server setting, because it is not
## something two machines can disagree about: compression is negotiated by not
## being negotiated at all, and a server that turned it on while its clients had
## it off simply never completed a connection — no error, no log line, just a
## client stuck on "contacting…". That is precisely what happened the first time
## `network/compression` existed as a knob, and the knob is why.
##
## Changing this value is a protocol change. Bump VERSION with it.
const COMPRESSION: int = ENetConnection.COMPRESS_RANGE_CODER


## Apply the transport settings both ends must share. Every place a peer is
## created — the dedicated server, a peer-to-peer host, and both kinds of client
## — calls this and nothing else touches compression.
static func apply_transport(peer: ENetMultiplayerPeer) -> void:
	var host := peer.get_host()
	if host != null:
		host.compress(COMPRESSION)


## A handshake message is a handful of fields and one 32-byte proof. Anything
## larger is not a client of ours, and decoding it is work an unauthenticated
## stranger should not be able to ask for.
const MAX_AUTH_BYTES: int = 4096

# ── Handshake messages ──────────────────────────────────────────────────────
## Server → client. Who this server is, and the nonce for this connection.
const MSG_HELLO: StringName = &"hello"
## Client → server. Build, intent (guest / login / register) and account name.
const MSG_IDENT: StringName = &"ident"
## Server → client. The account's salt and iteration count. An unknown account
## gets a decoy salt so that names cannot be probed — see NetCrypto.decoy_salt.
const MSG_CHALLENGE: StringName = &"challenge"
## Client → server. HMAC(derived key, nonce), and on registration the derived
## key itself, which is the one thing that has to cross.
const MSG_PROOF: StringName = &"proof"
## Server → client. Accepted, with who you are and what you may do.
const MSG_WELCOME: StringName = &"welcome"
## Server → client. Refused, with a sentence a player can act on.
const MSG_DENY: StringName = &"deny"

# ── How a client may present itself ─────────────────────────────────────────
const INTENT_GUEST: StringName = &"guest"
const INTENT_LOGIN: StringName = &"login"
const INTENT_REGISTER: StringName = &"register"

## What the server will accept, in order of strictness. `open` is a LAN party;
## `account` is a public server. `guest` is the middle: named, remembered for the
## session, owning nothing.
const AUTH_OPEN: StringName = &"open"
const AUTH_GUEST: StringName = &"guest"
const AUTH_ACCOUNT: StringName = &"account"

static var _stamp: ProtocolStamp


## The fingerprint of this build's content. Empty only if the stamp resource is
## missing, which means the build is broken rather than merely old — callers
## treat an empty hash as "cannot verify" and say so.
static func content_hash() -> String:
	if _stamp == null:
		_stamp = load(STAMP_PATH) as ProtocolStamp
	return _stamp.content_hash if _stamp != null else ""


## A one-line build identity for logs and for the server browser.
static func build_id() -> String:
	var hash_text := content_hash()
	return "proto %d / content %s" % [
		VERSION, hash_text.substr(0, 12) if hash_text != "" else "unknown"]


# ── Encoding ────────────────────────────────────────────────────────────────
## Handshake messages are plain dictionaries of built-in types.
##
## `var_to_bytes`, never `var_to_bytes_with_objects`: the decoding side of that
## pair instantiates arbitrary classes named in the payload, which on an
## unauthenticated socket is remote code execution wearing a serialisation
## format. The matching `bytes_to_var` below refuses objects for the same reason,
## and `SceneMultiplayer.allow_object_decoding` is left off everywhere else.
static func encode(message: Dictionary) -> PackedByteArray:
	return var_to_bytes(message)


## Decode a handshake message. Returns an empty dictionary for anything that is
## not one — oversized, truncated, not a dictionary, or carrying no type.
## Callers treat that as "refuse the connection", never as "try harder".
##
## The header is checked BEFORE `bytes_to_var` is allowed near the bytes, and
## that is not belt-and-braces. Godot's decoder pushes an engine error for
## malformed input, and everything that reaches here arrives from a stranger who
## has not authenticated yet — so without this, anybody who can reach the port
## can fill an operator's log by sending noise at it. A leading type field that
## does not say "dictionary" is answered with silence.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < 4 or data.size() > MAX_AUTH_BYTES:
		return {}
	# Godot encodes the variant type in the first four bytes, with flags in the
	# high half. A handshake message is always a dictionary.
	if data.decode_u32(0) & 0xFFFF != TYPE_DICTIONARY:
		return {}
	var value: Variant = bytes_to_var(data)
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var message: Dictionary = value
	if not message.has("t"):
		return {}
	return message


## A byte field out of a decoded message, or empty.
##
## `decode()` establishes that a packet is a dictionary and nothing else: every
## VALUE in it is still whatever a stranger put there. Assigning one straight to
## a `PackedByteArray` variable is a runtime error the moment somebody sends a
## string where the salt should be — which is a thing an unauthenticated peer can
## do, and therefore a thing it will eventually do. This is the only way the
## handshake reads bytes off the wire.
static func bytes_of(message: Dictionary, key: String) -> PackedByteArray:
	var value: Variant = message.get(key)
	if typeof(value) != TYPE_PACKED_BYTE_ARRAY:
		return PackedByteArray()
	return value


# ── Compatibility ───────────────────────────────────────────────────────────
## Why these two builds cannot play together, or "" when they can.
##
## The wording is aimed at whoever reads it in a client's status line or a
## server log, so it always names which side is behind — "the server is older"
## is actionable and "version mismatch" is not.
static func incompatibility(their_protocol: int, their_content: String,
		their_game: StringName, from_server: bool) -> String:
	var them := "server" if from_server else "client"
	var us := "client" if from_server else "server"
	if their_game != GAME_ID:
		return "THAT IS NOT A %s SERVER" % String(GAME_ID).to_upper() if from_server \
				else "THAT CLIENT IS NOT PLAYING THIS GAME"
	if their_protocol != VERSION:
		var older := "The %s" % them if their_protocol < VERSION else "The %s" % us
		return "PROTOCOL MISMATCH — %s IS OLDER (%s speaks %d, %s speaks %d). %s" % [
			older.to_upper(), them, their_protocol, us, VERSION,
			"UPDATE BOTH TO THE SAME BUILD."]
	var ours := content_hash()
	if ours == "" or their_content == "":
		return "THIS BUILD HAS NO CONTENT FINGERPRINT — REBUILD IT"
	if their_content != ours:
		return ("CONTENT MISMATCH — THE %s IS RUNNING A DIFFERENT BUILD OF THE GAME "
			+ "(%s has %s, %s has %s). THE SERVER MUST BE REBUILT AND RESTARTED "
			+ "FROM THE SAME COMMIT AS THE GAME.") % [
			them.to_upper(), them, their_content.substr(0, 12), us, ours.substr(0, 12)]
	return ""

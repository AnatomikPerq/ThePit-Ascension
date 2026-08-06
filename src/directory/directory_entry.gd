class_name DirectoryEntry
extends RefCounted
## One server, as the directory holds it and as a player's browser reads it.
##
## The same class on both sides on purpose. A listing is built by `to_listing()`
## here and read by `from_listing()` here, so the two halves of the format cannot
## drift apart the way they do when a server writes a dictionary and a client
## picks fields out of it by hand.
##
## Nothing an announcing server sends is trusted as-is. `apply_announce()` clamps
## every string to a length, drops what it does not recognise, and — the
## important one — **never lets the announce set `badge`**. A badge is decided by
## the directory from a key it issued; a server that puts `"badge": "official"`
## in its own announce gets exactly nothing for it.

## Source of the row, for the browser. Not part of the wire format: a client
## stamps it on when it merges the three places servers come from.
enum Source {DIRECTORY, LAN, SAVED}

var address: String = ""
var port: int = NetProtocol.DEFAULT_PORT
var name: String = "A PIT SERVER"
var description: String = ""
var tags: PackedStringArray = PackedStringArray()
var region: String = ""

var players: int = 0
var max_players: int = 0
var rooms: int = 0
var rooms_running: int = 0
var auth: String = "guest"
## Whether the server allows new accounts to be created from the game. Shown so
## that "log in" and "register" are not both offered when only one will work.
var registration: bool = false

## The build the server is on. A client with a different fingerprint cannot join
## it, and the browser says so rather than letting the connection fail later.
var protocol: int = 0
var content: String = ""

## Which server this is, as opposed to which ADDRESS it is. One machine usually
## has several — a loopback, a local network card, a public name — and a probe on
## the local network gets an answer from each of them, so keying rows on the
## address alone puts the same server in the browser three times. It is stable
## across restarts and says nothing about the machine: see PitServer.instance_id.
var instance: String = ""

## Decided by the directory, never by the server. "" is an ordinary server.
var badge: String = ""
var badge_note: String = ""

## Unix seconds. `first_seen` is what "listed since" is drawn from; `last_seen`
## is what staleness is measured against.
var first_seen: int = 0
var last_seen: int = 0

## Filled in on a client only.
var source: int = Source.DIRECTORY
var favourite: bool = false


## The key an entry is stored and merged under. Address and port, because that is
## what a player connects to and what makes two entries the same server — a name
## is chosen by whoever runs it and two of them may pick the same one.
static func key_for(host: String, host_port: int) -> String:
	return "%s:%d" % [host.strip_edges().to_lower(), host_port]


func key() -> String:
	return key_for(address, port)


## What two rows have to share to be the same server. The instance when there is
## one, and the address otherwise — a saved row carries no instance, because
## nothing has answered for it.
func merge_key() -> String:
	return instance if instance != "" else key()


func verified() -> bool:
	return badge != ""


## True when this client could actually join. The browser draws the reason
## instead of a CONNECT button, which is the difference between "that server is
## on an older build" and a connection that fails ten seconds later with a
## sentence nobody reads.
func joinable() -> bool:
	if protocol == 0 and content == "":
		return true # an entry from before the build fields existed: let it try
	return protocol == NetProtocol.VERSION and content == NetProtocol.content_hash()


func full() -> bool:
	return max_players > 0 and players >= max_players


# ── Server → directory ──────────────────────────────────────────────────────
## Take what an announcing server said. `sender_address` is where the packet
## actually came from and wins when the server did not name itself — a server
## behind NAT usually does not know its own public address, and the directory
## always does.
func apply_announce(message: Dictionary, sender_address: String, now: int) -> void:
	address = _clamp(str(message.get("address", "")).strip_edges(), 120)
	if address == "":
		address = sender_address
	port = clampi(int(message.get("port", NetProtocol.DEFAULT_PORT)), 1, 65535)
	name = _clamp(str(message.get("name", "")).strip_edges(), DirectoryProtocol.MAX_NAME)
	if name == "":
		name = "A PIT SERVER"
	description = _clamp(str(message.get("description", "")).strip_edges(),
		DirectoryProtocol.MAX_DESCRIPTION)
	region = _clamp(str(message.get("region", "")).strip_edges(),
		DirectoryProtocol.MAX_REGION)
	tags = _clean_tags(message.get("tags", []))

	players = maxi(0, int(message.get("players", 0)))
	max_players = maxi(0, int(message.get("max_players", 0)))
	rooms = maxi(0, int(message.get("rooms", 0)))
	rooms_running = maxi(0, int(message.get("rooms_running", 0)))
	auth = _clamp(str(message.get("auth", "guest")), 16)
	registration = bool(message.get("registration", false))
	protocol = int(message.get("protocol", 0))
	content = _clamp(str(message.get("content", "")), 64)
	instance = _clamp(str(message.get("instance", "")), 32)

	if first_seen == 0:
		first_seen = now
	last_seen = now


static func _clean_tags(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item: Variant in raw as Array:
		var tag := str(item).strip_edges().to_lower()
		if tag == "" or out.has(tag):
			continue
		out.append(tag.substr(0, DirectoryProtocol.MAX_TAG))
		if out.size() >= DirectoryProtocol.MAX_TAGS:
			break
	return out


static func _clamp(text: String, length: int) -> String:
	# Control characters are stripped rather than escaped. A name with a newline
	# in it breaks every list that prints it, and there is no legitimate one.
	var clean := ""
	for i in text.length():
		if text.unicode_at(i) >= 32:
			clean += text[i]
	return clean.substr(0, length)


# ── Directory → client ──────────────────────────────────────────────────────
func to_listing() -> Dictionary:
	return {
		"address": address, "port": port, "name": name,
		"description": description, "tags": Array(tags), "region": region,
		"players": players, "max_players": max_players,
		"rooms": rooms, "rooms_running": rooms_running,
		"auth": auth, "registration": registration,
		"protocol": protocol, "content": content, "instance": instance,
		"badge": badge, "badge_note": badge_note,
		"first_seen": first_seen, "last_seen": last_seen,
	}


static func from_listing(row: Dictionary, from: int = Source.DIRECTORY) -> DirectoryEntry:
	var entry := DirectoryEntry.new()
	entry.address = str(row.get("address", ""))
	entry.port = int(row.get("port", NetProtocol.DEFAULT_PORT))
	entry.name = str(row.get("name", "A PIT SERVER"))
	entry.description = str(row.get("description", ""))
	entry.tags = PackedStringArray(row.get("tags", []))
	entry.region = str(row.get("region", ""))
	entry.players = int(row.get("players", 0))
	entry.max_players = int(row.get("max_players", 0))
	entry.rooms = int(row.get("rooms", 0))
	entry.rooms_running = int(row.get("rooms_running", 0))
	entry.auth = str(row.get("auth", "guest"))
	entry.registration = bool(row.get("registration", false))
	entry.protocol = int(row.get("protocol", 0))
	entry.content = str(row.get("content", ""))
	entry.instance = str(row.get("instance", ""))
	# A badge is only ever what the DIRECTORY said. A LAN answer comes straight
	# from the server being described, so it may not carry one — otherwise a
	# server on your own network could wear the developer's badge by claiming it.
	if from == Source.DIRECTORY:
		entry.badge = str(row.get("badge", ""))
		entry.badge_note = str(row.get("badge_note", ""))
	entry.first_seen = int(row.get("first_seen", 0))
	entry.last_seen = int(row.get("last_seen", 0))
	entry.source = from
	return entry


# ── Persistence ─────────────────────────────────────────────────────────────
## The stored form is the listing plus the two things a listing does not carry:
## which key verified it, so a revoked key takes the badge away on the next
## load as well as the next announce.
var verify_id: String = ""


func to_json() -> Dictionary:
	var out := to_listing()
	out["verify_id"] = verify_id
	return out


static func from_json(row: Dictionary) -> DirectoryEntry:
	var entry := from_listing(row)
	entry.verify_id = str(row.get("verify_id", ""))
	return entry

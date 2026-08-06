class_name ServerFinder
extends Node
## Everywhere a player's copy of the game looks for somewhere to play, merged
## into one list.
##
## Three sources, and they answer different questions:
##
##   - **the directory** — every public server on the internet that chose to be
##     listed, and the only one of the three that can say a server is verified;
##   - **a probe on the local network** — servers and hosts within shouting
##     distance, found with no infrastructure at all, which is what makes a LAN
##     party work on a network with no way out;
##   - **what this player saved** — where they have played before, and what they
##     starred. The only source that still works with nothing connected.
##
## They are merged on what the server says it IS rather than on where it was
## found — see `_merge`. A row that came from more than one source keeps the live
## counts from whichever answered *and* the badge from the directory: a server
## may not claim a badge on its own behalf over the local network, which is why
## `DirectoryEntry.from_listing` drops one that arrives that way.

signal changed(entries: Array)
## Something to put under the list while it fills: which sources have answered,
## and what went wrong with the ones that did not.
signal status_changed(text: String)

## How long the browser listens for LAN answers after shouting. Two and a half
## seconds is long enough for a switch and short enough that a player does not
## think the button is broken.
const SCAN_SECONDS: float = 2.5

var directory_url: String = ""

## Merge key (see DirectoryEntry.merge_key) -> the row shown for it.
var _entries: Dictionary[String, DirectoryEntry] = {}
var _http: HTTPRequest
var _udp: PacketPeerUDP
var _scan_left: float = 0.0
var _http_state: String = ""
## Which servers answered on the local network this refresh — a set rather than a
## count, because one machine answers down every interface it has and "2 ON THIS
## NETWORK" for one server is a lie the player can see through.
var _lan_seen: Dictionary[String, bool] = {}
var _asking: bool = false


## How many distinct servers answered over the local network this refresh. Read
## by the probe in tools/, which has to be able to tell "found it through the
## directory" from "found it on the network" after the two have become one row.
func lan_answers() -> int:
	return _lan_seen.size()


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "Http"
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_listing)
	directory_url = DirectoryDef.resolve(SavedServers.directory_url())


func _exit_tree() -> void:
	_stop_scan()


## Ask everything, again. Cheap enough to call on every REFRESH press: one HTTP
## request and three UDP packets.
func refresh() -> void:
	_entries.clear()
	for entry in SavedServers.entries():
		_entries[entry.merge_key()] = entry
	_lan_seen.clear()
	_start_scan()
	_ask_directory()
	_publish()


func entries() -> Array:
	var out: Array = []
	for key in _entries:
		out.append(_entries[key])
	out.sort_custom(_before)
	return out


## Favourites first, then verified, then whatever has people on it. A player's
## own star outranks the developer's badge on purpose: this is their list.
static func _before(a: DirectoryEntry, b: DirectoryEntry) -> bool:
	if a.favourite != b.favourite:
		return a.favourite
	if a.verified() != b.verified():
		return a.verified()
	if a.players != b.players:
		return a.players > b.players
	return a.name.naturalnocasecmp_to(b.name) < 0


# ── The directory ───────────────────────────────────────────────────────────
func _ask_directory() -> void:
	if not DirectoryDef.shipped().enabled or directory_url == "":
		_http_state = "no server list configured"
		return
	if _asking:
		return
	var err := _http.request(DirectoryDef.url_for(directory_url,
		DirectoryProtocol.PATH_SERVERS))
	if err != OK:
		_http_state = "could not reach the server list"
		return
	_asking = true
	_http_state = "asking %s…" % directory_url


func _on_listing(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_asking = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_http_state = "the server list did not answer"
		_publish()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_http_state = "the server list sent something unreadable"
		_publish()
		return
	var rows: Array = (parsed as Dictionary).get("servers", [])
	for row: Variant in rows:
		if typeof(row) == TYPE_DICTIONARY:
			_merge(DirectoryEntry.from_listing(row, DirectoryEntry.Source.DIRECTORY))
	_http_state = "%d from the server list" % rows.size()
	_publish()


# ── The local network ───────────────────────────────────────────────────────
## Bound to port 0 — whatever the operating system hands out — rather than to the
## discovery port. Two copies of the game on one machine would otherwise fight
## over it, and one of them would silently never find anything.
func _start_scan() -> void:
	_stop_scan()
	_udp = PacketPeerUDP.new()
	if _udp.bind(0) != OK:
		_udp = null
		return
	_udp.set_broadcast_enabled(true)
	_scan_left = SCAN_SECONDS
	var probe := DirectoryProtocol.LAN_PROBE.to_utf8_buffer()
	for offset in DirectoryProtocol.LAN_PORT_SPAN:
		var port := DirectoryProtocol.LAN_PORT + offset
		# Broadcast for the network, loopback for the very common case of a
		# server and a client on one machine — where a broadcast is not
		# guaranteed to come back round.
		for host in ["255.255.255.255", "127.0.0.1"]:
			_udp.set_dest_address(host, port)
			_udp.put_packet(probe)


func _stop_scan() -> void:
	_scan_left = 0.0
	if _udp != null:
		_udp.close()
		_udp = null


func _process(delta: float) -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		_take_reply(_udp.get_packet(), _udp.get_packet_ip())
	_scan_left -= delta
	if _scan_left <= 0.0:
		_stop_scan()
		_publish()


func _take_reply(packet: PackedByteArray, from: String) -> void:
	if packet.size() > DirectoryProtocol.LAN_MAX_BYTES:
		return
	var text := packet.get_string_from_utf8()
	if not DirectoryProtocol.is_lan_reply(text):
		return
	var payload := DirectoryProtocol.lan_payload(text)
	if str(payload.get("game", "")) != String(NetProtocol.GAME_ID):
		return
	# The address comes from the packet, never from the payload. A machine on
	# your network does not get to tell you where it is.
	payload["address"] = from
	var entry := DirectoryEntry.from_listing(payload, DirectoryEntry.Source.LAN)
	_lan_seen[entry.merge_key()] = true
	_merge(entry)
	_publish()


# ── Merging ─────────────────────────────────────────────────────────────────
## One row per SERVER, not per address it can be reached at.
##
## A machine answers a local probe down every interface it has, and then the
## directory lists it under the public name its operator configured — three or
## four answers describing one thing. They are folded together on the instance
## id the server puts in all of them; a saved row has none, so it falls back to
## the address, which is all anybody knows about it.
##
## Which ADDRESS survives is deliberate: the first that answered wins, and on a
## local network that is the local one, which is the address that will actually
## connect from where the player is sitting.
func _merge(entry: DirectoryEntry) -> void:
	var key := entry.merge_key()
	var existing: DirectoryEntry = _entries.get(key)
	if existing != null:
		_fold(existing, entry)
		return
	# A saved row for the same address is here under the address, because nothing
	# had answered for it and so it had no instance to be keyed on. The live
	# answer takes its place and inherits its star.
	var saved: DirectoryEntry = _entries.get(entry.key())
	if saved != null and saved.source == DirectoryEntry.Source.SAVED:
		entry.favourite = entry.favourite or saved.favourite
		_entries.erase(entry.key())
	_entries[key] = entry


## Take from `arriving` what it knows better, leaving `kept` where it is in the
## list. A star is the player's and survives everything; a badge is the
## directory's and is the only thing a LAN answer may not overwrite.
static func _fold(kept: DirectoryEntry, arriving: DirectoryEntry) -> void:
	kept.favourite = kept.favourite or arriving.favourite
	if arriving.source == DirectoryEntry.Source.DIRECTORY and arriving.badge != "":
		kept.badge = arriving.badge
		kept.badge_note = arriving.badge_note
	if arriving.source == DirectoryEntry.Source.SAVED:
		return # nothing live in it
	kept.name = arriving.name
	kept.description = arriving.description
	kept.tags = arriving.tags
	kept.region = arriving.region
	kept.players = arriving.players
	kept.max_players = arriving.max_players
	kept.rooms = arriving.rooms
	kept.rooms_running = arriving.rooms_running
	kept.auth = arriving.auth
	kept.registration = arriving.registration
	kept.protocol = arriving.protocol
	kept.content = arriving.content


func _publish() -> void:
	changed.emit(entries())
	var parts := PackedStringArray()
	if _http_state != "":
		parts.append(_http_state)
	parts.append("%d on this network" % _lan_seen.size() if _scan_left <= 0.0
		else "looking on this network…")
	status_changed.emit("  ·  ".join(parts).to_upper())

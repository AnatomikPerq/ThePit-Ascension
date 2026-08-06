class_name DirectoryStore
extends RefCounted
## The table of servers the directory is currently listing.
##
## Held in memory and written to `servers.json` so that a directory restarted at
## three in the morning does not show an empty browser to everybody until each
## server's next announce. Everything in it is *claimed* by whoever announced it,
## except the badge — see VerifyKeyStore — and everything claimed is clamped by
## DirectoryEntry before it gets this far.
##
## Two numbers do the work of keeping the list honest. A server that has not
## announced for `stale_seconds` stops being listed, which is how a machine that
## was unplugged disappears without anybody telling the directory. One that has
## not announced for `forget_seconds` is dropped from the table entirely, which
## is how the file does not grow forever.

const FILE_NAME := "servers.json"
const FORMAT: int = 1

## key ("address:port") -> DirectoryEntry.
var entries: Dictionary[String, DirectoryEntry] = {}
var path: String = ""
var backups: int = 3

var _dirty: bool = false


func load_from(dir_path: String) -> String:
	path = dir_path.path_join(FILE_NAME)
	entries.clear()
	var problem: Array = []
	var data := JsonFile.read_dictionary(path, problem)
	for row: Variant in data.get("servers", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry := DirectoryEntry.from_json(row)
		if entry.address != "":
			entries[entry.key()] = entry
	return str(problem[0]) if not problem.is_empty() else ""


func save() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	var rows: Array = []
	for key in entries:
		rows.append(entries[key].to_json())
	var err := JsonFile.write_atomically(path,
		JsonFile.envelope(FORMAT, "servers", rows), backups)
	if err == OK:
		_dirty = false
	return err


func tick() -> void:
	if _dirty:
		save()


func count() -> int:
	return entries.size()


func find(address: String, port: int) -> DirectoryEntry:
	return entries.get(DirectoryEntry.key_for(address, port))


## How many listed servers share an address. The limit on it is the cheapest
## defence there is against one machine filling the browser with fifty rows.
func count_from(address: String) -> int:
	var found := 0
	var needle := address.strip_edges().to_lower()
	for key in entries:
		if entries[key].address.to_lower() == needle:
			found += 1
	return found


# ── Announces ───────────────────────────────────────────────────────────────
## Take one announce. `key` is whatever VerifyKeyStore made of its claim — null
## for an ordinary server, and null is also what a *failed* claim leaves, so a
## server whose key was revoked simply stops being badged on its next announce.
func accept(message: Dictionary, sender_address: String, key: VerifyKey,
		now: int) -> DirectoryEntry:
	var probe := DirectoryEntry.new()
	probe.apply_announce(message, sender_address, now)
	var existing: DirectoryEntry = entries.get(probe.key())
	var entry := existing if existing != null else probe
	if existing != null:
		entry.apply_announce(message, sender_address, now)
	_stamp_badge(entry, key)
	entries[entry.key()] = entry
	_dirty = true
	return entry


static func _stamp_badge(entry: DirectoryEntry, key: VerifyKey) -> void:
	if key == null:
		entry.badge = ""
		entry.badge_note = ""
		entry.verify_id = ""
		return
	entry.badge = key.badge
	entry.badge_note = key.hover_text()
	entry.verify_id = key.id


## Take the badge away from every entry whose key is gone or revoked. Called
## after loading the file and after a key is revoked, so that revoking does not
## have to wait for the server in question to announce again — which it might
## never do, having got what it wanted.
func refresh_badges(store: VerifyKeyStore) -> int:
	var changed := 0
	for id in entries:
		var entry: DirectoryEntry = entries[id]
		if entry.verify_id == "":
			continue
		var key := store.find(entry.verify_id)
		if key != null and key.usable():
			entry.badge = key.badge
			entry.badge_note = key.hover_text()
			continue
		_stamp_badge(entry, null)
		changed += 1
	if changed > 0:
		_dirty = true
	return changed


func remove(address: String, port: int) -> bool:
	var key := DirectoryEntry.key_for(address, port)
	if not entries.has(key):
		return false
	entries.erase(key)
	_dirty = true
	return true


## Drop what has been silent too long. Returns how many went.
func forget_stale(now: int, forget_seconds: int) -> int:
	var gone: Array[String] = []
	for key in entries:
		if now - entries[key].last_seen > forget_seconds:
			gone.append(key)
	for key in gone:
		entries.erase(key)
	if not gone.is_empty():
		_dirty = true
	return gone.size()


# ── What a client is given ──────────────────────────────────────────────────
## Verified servers first, then by how many people are on them. Not by name:
## sorting a browser alphabetically is how every server called "AAAAA" happens.
func listing(now: int, stale_seconds: int, verified_only: bool = false) -> Array:
	var live: Array[DirectoryEntry] = []
	for key in entries:
		var entry: DirectoryEntry = entries[key]
		if now - entry.last_seen > stale_seconds:
			continue
		if verified_only and not entry.verified():
			continue
		live.append(entry)
	live.sort_custom(_before)
	var out: Array = []
	for entry in live:
		out.append(entry.to_listing())
	return out


static func _before(a: DirectoryEntry, b: DirectoryEntry) -> bool:
	if a.verified() != b.verified():
		return a.verified()
	if a.players != b.players:
		return a.players > b.players
	return a.name.naturalnocasecmp_to(b.name) < 0

class_name SavedServers
extends Object
## The servers this player knows about personally: the ones they have connected
## to, and the ones they have starred.
##
## The third source in the browser, and the only one that works with no network
## at all. It exists because the other two are somebody else's: a directory can
## be down and a LAN probe only reaches the room you are in, but the server your
## friends play on is a fact about you and belongs on your own disk.
##
## Plain `user://` ConfigFile. Nothing secret goes in it — a password is never
## written down here, exactly as ServerConnect refuses to write one, because the
## whole point of the handshake is that it does not leave the machine.

const PATH := "user://thepit_servers.cfg"
const SECTION := "saved"
## Enough that a player's own list never needs a scrollbar of its own, small
## enough that the file cannot become a log of every server ever touched.
const MAX_SAVED: int = 40


static func _file() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(PATH) # a missing file is an empty one, which is the first-run state
	return cf


## address:port -> {name, favourite, last_played, port, address}
static func all() -> Dictionary:
	var out := {}
	var cf := _file()
	if not cf.has_section(SECTION):
		return out
	for key in cf.get_section_keys(SECTION):
		var row: Variant = cf.get_value(SECTION, key, {})
		if typeof(row) == TYPE_DICTIONARY:
			out[key] = row
	return out


## Called after a connection succeeds. Remembering only what worked is
## deliberate: a list full of addresses somebody mistyped is worse than no list.
static func remember(address: String, port: int, server_name: String) -> void:
	var key := DirectoryEntry.key_for(address, port)
	var cf := _file()
	var row: Dictionary = cf.get_value(SECTION, key, {})
	row["address"] = address
	row["port"] = port
	row["name"] = server_name if server_name != "" else str(row.get("name", address))
	row["last_played"] = int(Time.get_unix_time_from_system())
	row["favourite"] = bool(row.get("favourite", false))
	cf.set_value(SECTION, key, row)
	_trim(cf)
	cf.save(PATH)


static func set_favourite(key: String, on: bool) -> void:
	var cf := _file()
	var row: Dictionary = cf.get_value(SECTION, key, {})
	if row.is_empty():
		return
	row["favourite"] = on
	cf.set_value(SECTION, key, row)
	cf.save(PATH)


## Save a server the player typed in but has not connected to yet — the starring
## of a row in the browser that came from the directory.
static func add(entry: DirectoryEntry, favourite: bool = true) -> void:
	var cf := _file()
	var row: Dictionary = cf.get_value(SECTION, entry.key(), {})
	row["address"] = entry.address
	row["port"] = entry.port
	row["name"] = entry.name
	row["favourite"] = favourite
	row["last_played"] = int(row.get("last_played", 0))
	cf.set_value(SECTION, entry.key(), row)
	_trim(cf)
	cf.save(PATH)


static func forget(key: String) -> void:
	var cf := _file()
	if cf.has_section_key(SECTION, key):
		cf.erase_section_key(SECTION, key)
		cf.save(PATH)


## Drop the least recently played, never a favourite. A star is a decision and
## the housekeeping does not get to overrule it.
static func _trim(cf: ConfigFile) -> void:
	var keys := cf.get_section_keys(SECTION)
	if keys.size() <= MAX_SAVED:
		return
	var droppable: Array = []
	for key in keys:
		var row: Dictionary = cf.get_value(SECTION, key, {})
		if not bool(row.get("favourite", false)):
			droppable.append([int(row.get("last_played", 0)), key])
	droppable.sort()
	var excess := keys.size() - MAX_SAVED
	for index in mini(excess, droppable.size()):
		cf.erase_section_key(SECTION, str(droppable[index][1]))


# ── The directory a player reads ────────────────────────────────────────────
## Overrides what the build ships with, for somebody who runs their own list.
static func directory_url() -> String:
	return str(_file().get_value("directory", "url", ""))


static func set_directory_url(url: String) -> void:
	var cf := _file()
	cf.set_value("directory", "url", url.strip_edges())
	cf.save(PATH)


## The entries the browser shows for servers nothing else reported. They carry no
## live counts, because nothing has been asked — an honest blank rather than a
## stale number from the last time.
static func entries() -> Array[DirectoryEntry]:
	var out: Array[DirectoryEntry] = []
	var rows := all()
	for key in rows:
		var row: Dictionary = rows[key]
		var entry := DirectoryEntry.new()
		entry.address = str(row.get("address", ""))
		entry.port = int(row.get("port", NetProtocol.DEFAULT_PORT))
		entry.name = str(row.get("name", entry.address))
		entry.source = DirectoryEntry.Source.SAVED
		entry.favourite = bool(row.get("favourite", false))
		if entry.address != "":
			out.append(entry)
	return out

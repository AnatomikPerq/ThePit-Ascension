class_name ServerLog
extends RefCounted
## The server's log: one line, three destinations.
##
## Everything the server has to say goes through `write()` and comes out on
## stdout (where a terminal or a service manager picks it up), in a rotating file
## under the storage directory, and in a ring buffer that the in-game admin panel
## and the remote console read back. Three destinations, one call, so a message
## cannot exist in one place and not another — which is the failure mode of every
## server that grows a second logging path later.
##
## Ordering matters more than stream hygiene here, so errors go to stdout with
## everything else rather than to stderr. Interleaving two streams scrambles the
## sequence in every capture, and the sequence is usually the thing being read.

signal line_written(entry: Dictionary)

enum Level {TRACE, DEBUG, INFO, WARN, ERROR}

const LEVEL_NAMES: Array[String] = ["TRACE", "DEBUG", "INFO", "WARN", "ERROR"]
## ANSI colours, dim through red. Written as unicode escapes rather than as the
## raw 0x1B byte: a control character sitting in a source file survives git and
## gdlint but not every editor that will ever open this one. Applied only when
## the operator asks for them — piping colour into a file that is then full of
## escape codes is a standing annoyance, and `log/colour` turns it off.
const LEVEL_COLOURS: Array[String] = ["\u001b[90m", "\u001b[36m", "\u001b[0m",
	"\u001b[33m", "\u001b[31m"]
const RESET := "\u001b[0m"

## How many lines the admin panel and `log tail` can look back over. Deliberately
## modest: this is a live view, and the file is the archive.
const RING_SIZE: int = 600

var level: int = Level.INFO
var colour: bool = true
var to_file: bool = false
var max_bytes: int = 16 * 1024 * 1024
var max_files: int = 10

var _dir: String = ""
var _path: String = ""
var _file: FileAccess
var _ring: Array[Dictionary] = []


func configure(settings: ServerSettings, storage_dir: String) -> void:
	level = LEVEL_NAMES.find(settings.get_text("log/level").to_upper())
	if level < 0:
		level = Level.INFO
	colour = settings.get_bool("log/colour")
	to_file = settings.get_bool("log/to_file")
	max_bytes = int(settings.get_float("log/max_size_mb") * 1024.0 * 1024.0)
	max_files = settings.get_int("log/max_files")
	if to_file:
		_open(storage_dir.path_join("logs"))


func _open(dir_path: String) -> void:
	_dir = dir_path
	DirAccess.make_dir_recursive_absolute(_dir)
	_path = _dir.path_join("server.log")
	_file = FileAccess.open(_path, FileAccess.READ_WRITE)
	if _file == null:
		_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file != null:
		_file.seek_end()


func close() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


func trace(category: String, message: String) -> void:
	write(Level.TRACE, category, message)


func debug(category: String, message: String) -> void:
	write(Level.DEBUG, category, message)


func info(category: String, message: String) -> void:
	write(Level.INFO, category, message)


func warn(category: String, message: String) -> void:
	write(Level.WARN, category, message)


func error(category: String, message: String) -> void:
	write(Level.ERROR, category, message)


## `category` is a short tag — net, auth, room, mod, rcon — so that a log can be
## grepped by subsystem without a structured format nobody wants to read by eye.
func write(entry_level: int, category: String, message: String) -> void:
	if entry_level < level:
		return
	var stamp := Time.get_datetime_string_from_system(false, true)
	var entry := {
		"at": stamp,
		"level": entry_level,
		"category": category,
		"message": message,
	}
	_ring.append(entry)
	if _ring.size() > RING_SIZE:
		_ring.remove_at(0)

	var plain := "%s %-5s [%s] %s" % [stamp, LEVEL_NAMES[entry_level], category, message]
	if colour:
		print("%s%s%s" % [LEVEL_COLOURS[entry_level], plain, RESET])
	else:
		print(plain)
	_append_to_file(plain)
	line_written.emit(entry)


## What the console prints when it is answering a command rather than reporting
## an event: no level, no category, no timestamp. A table of settings should look
## like a table, not like forty log lines.
func reply(text: String) -> void:
	for line in text.split("\n"):
		print(line)
	_append_to_file(text)


func _append_to_file(text: String) -> void:
	if _file == null:
		return
	_file.store_line(text)
	_file.flush()
	if _file.get_length() >= max_bytes:
		_rotate()


## server.log becomes server.1.log, .1 becomes .2, and the oldest falls off.
## Done by renaming rather than copying so a rotation cannot half-finish and
## leave two files claiming the same lines.
## The `*_absolute` statics with full paths — see AccountStore._write_atomically
## for why the instance methods are not used for this.
func _rotate() -> void:
	close()
	var oldest := _dir.path_join("server.%d.log" % max_files)
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for index in range(max_files - 1, 0, -1):
		var from := _dir.path_join("server.%d.log" % index)
		if FileAccess.file_exists(from):
			DirAccess.rename_absolute(from, _dir.path_join("server.%d.log" % (index + 1)))
	if FileAccess.file_exists(_path):
		DirAccess.rename_absolute(_path, _dir.path_join("server.1.log"))
	_open(_dir)


## The last `count` lines, oldest first. For `log tail`, the admin panel and the
## remote console — all three want the same thing.
func tail(count: int = 40, min_level: int = Level.TRACE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_ring.size() - 1, -1, -1):
		if out.size() >= count:
			break
		if _ring[i]["level"] >= min_level:
			out.push_front(_ring[i])
	return out


static func format(entry: Dictionary) -> String:
	return "%s %-5s [%s] %s" % [entry["at"], LEVEL_NAMES[int(entry["level"])],
		entry["category"], entry["message"]]


static func level_from(name: String) -> int:
	var found := LEVEL_NAMES.find(name.to_upper())
	return found if found >= 0 else Level.INFO


## An uptime an operator can read at a glance. Here rather than on either
## program because both of them print one, and a status line that says "4230s"
## on one and "1h10m" on the other is the sort of thing nobody fixes.
static func duration(seconds: float) -> String:
	var total := int(seconds)
	if total < 3600:
		return "%dm" % (total / 60)
	if total < 86400:
		return "%dh%02dm" % [total / 3600, (total % 3600) / 60]
	return "%dd%02dh" % [total / 86400, (total % 86400) / 3600]

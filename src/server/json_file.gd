class_name JsonFile
extends Object
## Reading and writing the small JSON files the operator's side keeps: accounts,
## bans, verification keys, the directory's server table.
##
## It exists because the write is not the obvious three lines. A server killed
## mid-write leaves a truncated file, and a truncated accounts.json is every
## account on the server — so the real version writes a temporary, rotates the
## old one into a numbered backup, and moves the temporary into place. That was
## written once for accounts and NOT for bans, which is exactly how a second
## copy of something like this goes wrong: the copy that was made carefully and
## the copy that was made in a hurry.
##
## Two Godot details are load-bearing here and both cost an afternoon once:
##
##   - **`DirAccess.rename` and `.copy` do not resolve a path against the
##     directory the object was opened at.** A full path is looked for *under*
##     that directory again; a bare name is looked for in the process's working
##     directory. Both were tried, both left an `accounts.json.tmp` next to no
##     accounts file. The `*_absolute` statics take a path and mean it.
##   - **Rename-over-an-existing-file is not portable** — it fails outright on
##     Windows. Hence three steps rather than two, in an order where the worst
##     interruption leaves the backup and the temporary side by side and the live
##     file either whole or absent, never half-written.


## Write `text` to `path` without ever leaving a half-written file there.
## `backups` copies of the previous version are kept as `<path>.1.bak` and so on.
static func write_atomically(path: String, text: String, backups: int = 3) -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp_path := "%s.tmp" % path
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		return FileAccess.get_open_error()
	temp.store_string(text)
	temp.flush()
	temp.close()

	if FileAccess.file_exists(path):
		rotate(path, backups)
		if backups > 0:
			DirAccess.copy_absolute(path, "%s.1.bak" % path)
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path)


## Shuffle `<path>.1.bak` … `<path>.N.bak` up one, dropping the oldest. Also used
## by the log, which rotates whole files rather than backups of one.
static func rotate(path: String, keep: int) -> void:
	if keep <= 0:
		return
	var oldest := "%s.%d.bak" % [path, keep]
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for index in range(keep - 1, 0, -1):
		var from := "%s.%d.bak" % [path, index]
		if FileAccess.file_exists(from):
			DirAccess.rename_absolute(from, "%s.%d.bak" % [path, index + 1])


## Parse a file into a dictionary. A missing file and an empty one are both
## "nothing yet", which is the normal state of a fresh install; only a file with
## content that is not a JSON object is a problem, and the caller is told so in a
## sentence rather than left with an empty store and no idea why.
static func read_dictionary(path: String, problem: Array = []) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		problem.append("%s is not readable — it has been left alone; the newest "
			% path.get_file() + "backup next to it is probably the one you want")
		return {}
	return parsed


## The wrapper every one of these files is written with: a format number so a
## later build can recognise an earlier file, and a human-readable timestamp so
## an operator looking at a backup can tell which one it is.
static func envelope(format: int, key: String, rows: Array) -> String:
	return JSON.stringify({
		"format": format,
		"written_at": Time.get_datetime_string_from_system(true),
		key: rows,
	}, "\t")

class_name BanList
extends RefCounted
## Who is not welcome, by account and by address, with an expiry.
##
## Two kinds on purpose. An **account** ban is the honest one: it names a person
## and survives them changing address. An **address** ban catches the same person
## returning under a new name — and also catches everybody else behind that
## address, which is why it is a separate thing that
## `moderation/ban_evasion_by_ip` decides whether to issue automatically. A
## household, a campus or a phone network is one address.
##
## Every ban carries who issued it, when, and why. A moderation record that
## cannot answer "who did this and what did they say the reason was" is one that
## turns into an argument later.

const FILE_NAME := "bans.json"

const KIND_ACCOUNT := "account"
const KIND_ADDRESS := "address"

## subject -> entry dictionary. Subjects are canonical account ids or plain
## addresses, so one flat table serves both kinds.
var entries: Dictionary[String, Dictionary] = {}
var path: String = ""
## Copies of the previous file kept before each rewrite, from `storage/backups`.
var backups: int = 3

var _dirty: bool = false


## Returns "" or the reason the file could not be read. A ban list that failed
## to load used to be indistinguishable from an empty one, which is the same
## thing as quietly unbanning everybody.
func load_from(dir_path: String) -> String:
	path = dir_path.path_join(FILE_NAME)
	entries.clear()
	var problem: Array = []
	var parsed := JsonFile.read_dictionary(path, problem)
	for row: Variant in parsed.get("bans", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = row
		var subject := str(entry.get("subject", ""))
		if subject != "":
			entries[subject] = entry
	_expire()
	return str(problem[0]) if not problem.is_empty() else ""


## Atomic, like the account file and for the same reason: a server killed
## mid-write left a truncated bans.json, and a truncated bans.json is every ban
## on the server. This one was writing straight over the live file.
func save() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	_expire()
	var rows: Array = []
	for subject in entries:
		rows.append(entries[subject])
	var err := JsonFile.write_atomically(path, JsonFile.envelope(1, "bans", rows), backups)
	if err == OK:
		_dirty = false
	return err


func tick() -> void:
	if _dirty:
		save()


## `minutes` of 0 is permanent. Returns the entry, so a caller can report
## exactly what it just issued rather than describing it a second time.
func add(subject: String, kind: String, reason: String, issued_by: String,
		minutes: float) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var entry := {
		"subject": subject,
		"kind": kind,
		"reason": reason,
		"by": issued_by,
		"at": now,
		"until": 0 if minutes <= 0.0 else now + int(minutes * 60.0),
	}
	entries[subject] = entry
	_dirty = true
	return entry


func remove(subject: String) -> bool:
	if not entries.has(subject):
		return false
	entries.erase(subject)
	_dirty = true
	return true


## The ban that applies to this connection, or an empty dictionary. The account
## is checked first so that the message a banned player sees names their own ban
## rather than an address one that happens to overlap.
func check(account_id: String, address: String) -> Dictionary:
	_expire()
	if account_id != "" and entries.has(account_id):
		return entries[account_id]
	if address != "" and entries.has(address):
		return entries[address]
	return {}


func all() -> Array[Dictionary]:
	_expire()
	var out: Array[Dictionary] = []
	for subject in entries:
		out.append(entries[subject])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("at", 0)) > int(b.get("at", 0)))
	return out


func count() -> int:
	_expire()
	return entries.size()


## A ban that has run out is removed rather than merely ignored, so the list an
## operator reads is the list that is in force.
func _expire() -> void:
	var now := int(Time.get_unix_time_from_system())
	var expired: Array[String] = []
	for subject in entries:
		var until := int(entries[subject].get("until", 0))
		if until > 0 and until <= now:
			expired.append(subject)
	for subject in expired:
		entries.erase(subject)
		_dirty = true


## One line for a console listing, an admin panel row or a log entry.
static func describe(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	var until := int(entry.get("until", 0))
	var when := "permanent" if until == 0 \
			else "until %s" % Time.get_datetime_string_from_unix_time(until, true)
	return "%s (%s) — %s · by %s · %s" % [
		entry.get("subject", "?"), entry.get("kind", "?"),
		entry.get("reason", "no reason given"), entry.get("by", "?"), when]


## What the refused player is told. It names the reason and, when the operator
## filled in `server/contact`, where to argue about it.
static func notice(entry: Dictionary, contact: String) -> String:
	var until := int(entry.get("until", 0))
	var text := "YOU ARE BANNED FROM THIS SERVER.\n%s" % entry.get("reason", "No reason given.")
	if until > 0:
		text += "\nUNTIL %s" % Time.get_datetime_string_from_unix_time(until, true)
	if contact != "":
		text += "\nCONTACT: %s" % contact
	return text

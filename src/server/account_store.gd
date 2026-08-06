class_name AccountStore
extends RefCounted
## Every account the server knows, and the file they live in.
##
## One JSON file, held in memory, written back when something changed and not
## more often than `storage/save_interval_seconds`. That is a deliberate choice
## over a database: a server for a fan game has tens or hundreds of accounts, and
## the operator being able to open the file, read it, and copy it somewhere as a
## backup is worth more than the scaling nobody here needs.
##
## Writes go through a temporary file and a rename, with the previous version
## kept as a numbered backup. The failure this guards against is not exotic — a
## server killed mid-write leaves a truncated JSON, and a truncated JSON is every
## account on the server.

const FILE_NAME := "accounts.json"

## id -> Account. Guests are never in here; they exist only while connected.
var accounts: Dictionary[String, Account] = {}
var path: String = ""
var backups: int = 3

var _dirty: bool = false
var _since_save: float = 0.0


func load_from(dir_path: String) -> String:
	path = dir_path.path_join(FILE_NAME)
	accounts.clear()
	var problem: Array = []
	var data := JsonFile.read_dictionary(path, problem)
	if not problem.is_empty():
		return str(problem[0])
	for entry: Variant in data.get("accounts", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var account := Account.from_dict(entry)
		if account.id != "":
			accounts[account.id] = account
	return ""


func find(display_name: String) -> Account:
	return accounts.get(Account.canonical(display_name))


func exists(display_name: String) -> bool:
	return accounts.has(Account.canonical(display_name))


func count() -> int:
	return accounts.size()


func add(account: Account) -> void:
	accounts[account.id] = account
	touch()


func remove(display_name: String) -> bool:
	var key := Account.canonical(display_name)
	if not accounts.has(key):
		return false
	accounts.erase(key)
	touch()
	return true


## Mark the store as changed. Every mutation goes through it, so nothing can be
## changed and quietly not saved.
func touch() -> void:
	_dirty = true


## Called every frame by the server. Writing on a timer rather than on every
## change keeps a busy lobby from rewriting the file once per chat message.
func tick(delta: float, interval: float) -> void:
	if not _dirty:
		return
	_since_save += delta
	if _since_save >= interval:
		save()


func save() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	var rows: Array = []
	for id in accounts:
		rows.append(accounts[id].to_dict())
	var err := JsonFile.write_atomically(path,
		JsonFile.envelope(1, "accounts", rows), backups)
	if err == OK:
		_dirty = false
		_since_save = 0.0
	return err


# ── Queries the console and the admin panel ask ─────────────────────────────
## Accounts whose name contains `needle`, newest activity first. Empty needle
## lists everybody.
func search(needle: String, limit: int = 50) -> Array[Account]:
	var found: Array[Account] = []
	var lowered := needle.to_lower()
	for id in accounts:
		if lowered == "" or id.contains(lowered):
			found.append(accounts[id])
	found.sort_custom(func(a: Account, b: Account) -> bool:
		return a.last_seen_at > b.last_seen_at)
	return found.slice(0, limit)


func staff() -> Array[Account]:
	var found: Array[Account] = []
	for id in accounts:
		if accounts[id].role != Permissions.ROLE_PLAYER:
			found.append(accounts[id])
	found.sort_custom(func(a: Account, b: Account) -> bool: return a.rank() > b.rank())
	return found


## The leaderboard. Best score first, and only accounts that have actually
## climbed — a fresh account with a zero is not a placing.
func top_scores(limit: int = 10) -> Array[Account]:
	var found: Array[Account] = []
	for id in accounts:
		if accounts[id].best_score > 0:
			found.append(accounts[id])
	found.sort_custom(func(a: Account, b: Account) -> bool:
		return a.best_score > b.best_score)
	return found.slice(0, limit)


## True when nobody has ever registered. `auth/first_account_is_owner` reads it,
## so that a fresh install does not need an operator to op themselves by hand
## from the console before anybody can do anything.
func is_empty() -> bool:
	return accounts.is_empty()

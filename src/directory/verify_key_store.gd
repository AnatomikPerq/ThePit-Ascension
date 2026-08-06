class_name VerifyKeyStore
extends RefCounted
## Every verification key the directory has issued, and the check an announce
## has to pass to wear the badge one confers.
##
## The check is the whole point of the class, so it is worth naming what it
## refuses and why:
##
##   - an unknown or revoked key — the badge is withdrawn the moment the key is,
##     with no wait for anything to expire;
##   - a signature that does not match — see DirectoryProtocol.canonical for what
##     is covered, which includes the name, address and port, so a captured
##     announce cannot be replayed onto a different machine;
##   - an announce more than a few minutes old, or one whose nonce has been seen
##     inside that window — which is what stops a *correct* announce being
##     replayed forever by whoever was listening;
##   - a bound key claiming an address it is not bound to.
##
## Everything else about an announce is clamped rather than refused, and only
## this class can refuse one outright, because only this class is deciding
## something a stranger must not be able to lie about.

const FILE_NAME := "keys.json"

## id -> VerifyKey.
var keys: Dictionary[String, VerifyKey] = {}
var path: String = ""
var backups: int = 3

var _dirty: bool = false
## nonce -> unix seconds, for the replay window only. Pruned on every check, so
## it never holds more than the last few minutes of traffic.
var _seen: Dictionary[String, int] = {}


func load_from(dir_path: String) -> String:
	path = dir_path.path_join(FILE_NAME)
	keys.clear()
	var problem: Array = []
	var data := JsonFile.read_dictionary(path, problem)
	for row: Variant in data.get("keys", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var key := VerifyKey.from_dict(row)
		if key.id != "":
			keys[key.id] = key
	return str(problem[0]) if not problem.is_empty() else ""


func save() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	var rows: Array = []
	for id in keys:
		rows.append(keys[id].to_dict())
	var err := JsonFile.write_atomically(path, JsonFile.envelope(
		VerifyKey.FORMAT, "keys", rows), backups)
	if err == OK:
		_dirty = false
	return err


func tick() -> void:
	if _dirty:
		save()


func count() -> int:
	return keys.size()


func find(id: String) -> VerifyKey:
	return keys.get(id)


func add(key: VerifyKey) -> void:
	keys[key.id] = key
	_dirty = true


func revoke(id: String, reason: String) -> bool:
	var key: VerifyKey = keys.get(id)
	if key == null or key.revoked:
		return false
	key.revoked = true
	key.revoked_reason = reason
	_dirty = true
	return true


func forget(id: String) -> bool:
	if not keys.has(id):
		return false
	keys.erase(id)
	_dirty = true
	return true


func bind(id: String, address: String) -> bool:
	var key: VerifyKey = keys.get(id)
	if key == null:
		return false
	key.bind_address = address.strip_edges().to_lower()
	_dirty = true
	return true


## Keys in issue order, newest last.
func all() -> Array[VerifyKey]:
	var out: Array[VerifyKey] = []
	for id in keys:
		out.append(keys[id])
	out.sort_custom(func(a: VerifyKey, b: VerifyKey) -> bool:
		return a.issued_at < b.issued_at)
	return out


# ── The check ───────────────────────────────────────────────────────────────
## Returns [VerifyKey or null, reason]. A null key with an empty reason means the
## announce did not claim a badge at all, which is the ordinary case and not a
## refusal — an unverified server is still listed.
##
## `bind_on_first_use` is what turns "whoever holds the secret" into "whoever
## holds the secret, on the machine they first used it from". Without it a key
## that leaks — or a host who simply keeps it after moving on — badges any
## address they like, because the secret IS the authority. With it, the first
## successful announce writes the address into the key and every later one has to
## match. It is undone with `key bind <id> -`, and a host who moved house is told
## exactly why the badge stopped: their server hears the refusal in its answer.
func check(message: Dictionary, now: int, bind_on_first_use: bool = false) -> Array:
	var id := str(message.get("verify_id", "")).strip_edges()
	if id == "":
		return [null, ""]
	var key: VerifyKey = keys.get(id)
	if key == null or not key.usable():
		return [null, "unknown or revoked verification key"]
	var refusal := _refusal(message, key, now)
	if refusal != "":
		return [null, refusal]
	_remember(str(message.get("nonce", "")), now)
	var claimed := str(message.get("address", ""))
	if bind_on_first_use and key.bind_address == "" and claimed != "":
		key.bind_address = claimed.to_lower()
	key.uses += 1
	key.last_used = now
	_dirty = true
	return [key, ""]


## Every reason a claim is not honoured, in one place, so that `check` reads as
## what it does rather than as a wall of guards.
func _refusal(message: Dictionary, key: VerifyKey, now: int) -> String:
	var stale := _stale_reason(message, now)
	if stale != "":
		return stale
	if not DirectoryProtocol.verify_announce(message, key.secret):
		return "the signature does not match the key"
	if not key.may_claim(str(message.get("address", ""))):
		return "that key is bound to %s" % key.bind_address
	return ""


## Freshness, kept out of `check` so that one stays readable: an announce has to
## be recent and its nonce has to be new. Both are needed — the timestamp alone
## lets an announce be replayed for five minutes, and the nonce alone would mean
## remembering every nonce forever.
func _stale_reason(message: Dictionary, now: int) -> String:
	var stamp := int(message.get("stamp", 0))
	if absi(now - stamp) > DirectoryProtocol.MAX_CLOCK_SKEW_SECONDS:
		return "the announce is stamped %ds away from now — check the clock" % (now - stamp)
	var nonce := str(message.get("nonce", ""))
	if nonce.length() < 16:
		return "the announce carries no usable nonce"
	if _seen.has(nonce):
		return "that announce has already been seen"
	return ""


func _remember(nonce: String, now: int) -> void:
	_seen[nonce] = now
	var cutoff := now - DirectoryProtocol.MAX_CLOCK_SKEW_SECONDS
	var expired: Array[String] = []
	for seen in _seen:
		if _seen[seen] < cutoff:
			expired.append(seen)
	for seen in expired:
		_seen.erase(seen)

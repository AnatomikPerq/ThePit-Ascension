class_name Account
extends RefCounted
## One registered player, as the server remembers them between sessions.
##
## The password is not here and never was. What is stored is `verifier` — the
## PBKDF2 output of the password and this account's own salt — which is enough to
## check a login and useless for performing one anywhere else. See NetCrypto.

## Lower-cased, and the key in the store. Two accounts differing only in case
## would be two accounts that look identical in every list the game prints.
var id: String = ""
## As the player typed it, and what everyone else sees.
var name: String = ""

var salt: PackedByteArray = PackedByteArray()
var verifier: PackedByteArray = PackedByteArray()
## Kept per account rather than read from the setting: raising the cost must not
## invalidate everyone's password. An account is re-derived at its next
## successful login, when the plain password is briefly provable again.
var iterations: int = NetCrypto.DEFAULT_ITERATIONS

var role: String = Permissions.ROLE_PLAYER
## Rights held on top of the role, and rights taken away despite it. Both are
## why the permission check is by name and not by rank.
var grants: PackedStringArray = PackedStringArray()
var denials: PackedStringArray = PackedStringArray()

var created_at: int = 0
var last_seen_at: int = 0
## The address last connected from. Kept because a ban has to be able to follow
## an evader to their next name, and deleted with the account. It is the one
## piece of personal data here, and `moderation/ban_evasion_by_ip` is the switch
## that decides whether it is ever acted on.
var last_address: String = ""

## Unix time the mute expires; 0 for not muted, -1 for until somebody lifts it.
var muted_until: int = 0
## Warnings that have not decayed. `moderation/warnings_before_kick` reads it.
var warnings: int = 0
## Free text, staff only. Why somebody was warned, usually.
var note: String = ""

# ── What they have done here ────────────────────────────────────────────────
var runs: int = 0
var kills: int = 0
var best_score: int = 0
## Highest point reached, as an ascent from the bottom of the pit, so a bigger
## number is better however deep the pit is set to be.
var best_ascent: int = 0
var play_seconds: float = 0.0

## A reconnect token, so dropping out does not mean typing a password again.
var token: String = ""
var token_expires_at: int = 0

## Never persisted: a guest exists only while connected.
var guest: bool = false


static func make(display_name: String, password: String, iters: int) -> Account:
	var account := Account.new()
	account.name = display_name
	account.id = canonical(display_name)
	account.salt = NetCrypto.new_salt()
	account.iterations = iters
	account.verifier = NetCrypto.derive_key(password, account.salt, iters)
	account.created_at = int(Time.get_unix_time_from_system())
	account.last_seen_at = account.created_at
	return account


## A guest: a name for the session and nothing else. It is an Account so that
## everything downstream — permissions, mutes, chat, the player list — has one
## kind of thing to deal with instead of two.
static func guest_for(display_name: String) -> Account:
	var account := Account.new()
	account.name = display_name
	account.id = canonical(display_name)
	account.guest = true
	account.created_at = int(Time.get_unix_time_from_system())
	return account


static func canonical(display_name: String) -> String:
	return display_name.strip_edges().to_lower()


func set_password(password: String, iters: int) -> void:
	salt = NetCrypto.new_salt()
	iterations = iters
	verifier = NetCrypto.derive_key(password, salt, iters)
	token = "" # every existing reconnect token dies with the old password


## Check a challenge answer. The password never reaches here; `answer` is
## HMAC(derived key, nonce) and we recompute the same thing from the verifier.
func proves(nonce: PackedByteArray, answer: PackedByteArray) -> bool:
	if verifier.is_empty() or guest:
		return false
	return NetCrypto.equal(NetCrypto.proof(verifier, nonce), answer)


func permissions() -> PackedStringArray:
	return Permissions.effective(role, grants, denials)


func may(right: String) -> bool:
	return Permissions.allows(permissions(), right)


func rank() -> int:
	return Permissions.rank(role)


func is_muted() -> bool:
	if muted_until < 0:
		return true
	return muted_until > 0 and muted_until > int(Time.get_unix_time_from_system())


func mute_for(minutes: float) -> void:
	muted_until = -1 if minutes <= 0.0 \
			else int(Time.get_unix_time_from_system() + minutes * 60.0)


func issue_token(hours: float) -> String:
	if hours <= 0.0:
		token = ""
		token_expires_at = 0
		return ""
	token = NetCrypto.new_token()
	token_expires_at = int(Time.get_unix_time_from_system() + hours * 3600.0)
	return token


func token_valid(candidate: String) -> bool:
	if token == "" or candidate == "":
		return false
	if token_expires_at < int(Time.get_unix_time_from_system()):
		return false
	return NetCrypto.equal(token.hex_decode(), candidate.hex_decode())


# ── Persistence ─────────────────────────────────────────────────────────────
## Bytes are stored hex rather than base64 so that a human opening accounts.json
## to diagnose something sees a fixed-width field and not something that looks
## like it might be readable.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"salt": salt.hex_encode(),
		"verifier": verifier.hex_encode(),
		"iterations": iterations,
		"role": role,
		"grants": Array(grants),
		"denials": Array(denials),
		"created_at": created_at,
		"last_seen_at": last_seen_at,
		"last_address": last_address,
		"muted_until": muted_until,
		"warnings": warnings,
		"note": note,
		"runs": runs,
		"kills": kills,
		"best_score": best_score,
		"best_ascent": best_ascent,
		"play_seconds": play_seconds,
		"token": token,
		"token_expires_at": token_expires_at,
	}


## Anything missing falls back to a default rather than failing the load. One
## corrupt field must not cost an operator their whole account file.
static func from_dict(data: Dictionary) -> Account:
	var account := Account.new()
	account.name = str(data.get("name", ""))
	account.id = str(data.get("id", canonical(account.name)))
	account.salt = str(data.get("salt", "")).hex_decode()
	account.verifier = str(data.get("verifier", "")).hex_decode()
	account.iterations = int(data.get("iterations", NetCrypto.DEFAULT_ITERATIONS))
	account.role = str(data.get("role", Permissions.ROLE_PLAYER))
	if not Permissions.is_role(account.role):
		account.role = Permissions.ROLE_PLAYER
	account.grants = PackedStringArray(data.get("grants", []))
	account.denials = PackedStringArray(data.get("denials", []))
	account.created_at = int(data.get("created_at", 0))
	account.last_seen_at = int(data.get("last_seen_at", 0))
	account.last_address = str(data.get("last_address", ""))
	account.muted_until = int(data.get("muted_until", 0))
	account.warnings = int(data.get("warnings", 0))
	account.note = str(data.get("note", ""))
	account.runs = int(data.get("runs", 0))
	account.kills = int(data.get("kills", 0))
	account.best_score = int(data.get("best_score", 0))
	account.best_ascent = int(data.get("best_ascent", 0))
	account.play_seconds = float(data.get("play_seconds", 0.0))
	account.token = str(data.get("token", ""))
	account.token_expires_at = int(data.get("token_expires_at", 0))
	return account

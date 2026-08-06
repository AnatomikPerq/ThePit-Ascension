class_name AuthService
extends Node
## The handshake, server side: who is connecting, and are they allowed to.
##
## It runs on Godot's own authentication hook (`SceneMultiplayer.auth_callback`),
## which means a peer that fails it is never a peer at all — `peer_connected`
## never fires for it, no RPC of theirs can reach any node, and nothing in the
## game has to know it happened. That is the reason to use the engine's hook
## rather than a "please log in" message after connecting: an unauthenticated
## socket that can already talk to the tree is a socket that can already do
## damage.
##
## The conversation:
##
##   server → HELLO      who this server is, what build, and a fresh nonce
##   client → IDENT      their build, and how they mean to identify themselves
##   server → CHALLENGE  the account's salt and iteration count  (login/register)
##   client → PROOF      HMAC(PBKDF2(password, salt), nonce)
##   server → WELCOME    accepted, with who they are and what they may do
##
## The password never crosses. A captured PROOF is worthless on the next
## connection because the nonce is new. The one exception is registration, which
## has to send the derived key so there is something to check against later —
## that is spelled out in NetCrypto and in docs/SERVER.md rather than buried.
##
## **The expensive half runs on the client.** PBKDF2 at the default cost takes
## about 115 ms; the client pays it, because the client is the machine that has
## the password. All this server ever computes is one HMAC of a stored verifier
## against a nonce — microseconds. That is not only a saving: it means the login
## endpoint cannot be used as a CPU amplifier, where a stranger sends fifty
## passwords a second and each one costs the server an eighth of a second of
## stalling four rooms at 120 Hz.

## What a pending connection has told us so far.
enum Step {WAITING_IDENT, WAITING_PROOF}

class Pending extends RefCounted:
	var peer_id: int = 0
	var address: String = ""
	var step: int = Step.WAITING_IDENT
	var nonce: PackedByteArray = PackedByteArray()
	var intent: StringName = NetProtocol.INTENT_GUEST
	var display_name: String = ""
	var account: Account = null
	## Only set while registering: the salt and cost the new account will get.
	var salt: PackedByteArray = PackedByteArray()
	var iterations: int = NetCrypto.DEFAULT_ITERATIONS
	var started_at: float = 0.0

var server: PitServer

var _pending: Dictionary[int, Pending] = {}
## Failed logins, keyed by address. A password guesser gets a handful of tries a
## minute and then silence, whatever name they are guessing against.
var _login_limit: RateLimiter = RateLimiter.make(0.16, 10.0)


func configure() -> void:
	var per_minute := float(server.settings.get_int("auth/logins_per_minute"))
	_login_limit.configure(per_minute / 60.0, per_minute)
	var api := multiplayer as SceneMultiplayer
	api.auth_callback = _on_auth_message
	api.auth_timeout = server.settings.get_float("network/auth_timeout_seconds")
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.peer_authentication_failed.connect(_on_peer_authentication_failed)


func forget(peer_id: int) -> void:
	_pending.erase(peer_id)


func pending_count() -> int:
	return _pending.size()


# ── Step 0: somebody dialled the port ───────────────────────────────────────
func _on_peer_authenticating(peer_id: int) -> void:
	var address := server.address_of(peer_id)
	var refusal := server.gatekeeper_refusal(peer_id, address)
	if refusal != "":
		_deny(peer_id, refusal)
		return
	var record := Pending.new()
	record.peer_id = peer_id
	record.address = address
	record.nonce = NetCrypto.new_nonce()
	record.started_at = Time.get_ticks_msec() / 1000.0
	_pending[peer_id] = record
	server.logger.debug("auth", "%s is connecting" % address)
	_send(peer_id, {
		"t": NetProtocol.MSG_HELLO,
		"proto": NetProtocol.VERSION,
		"game": NetProtocol.GAME_ID,
		"content": NetProtocol.content_hash(),
		"name": server.settings.get_text("server/name"),
		"motd": server.settings.get_text("server/motd"),
		"mode": server.settings.get_text("auth/mode"),
		"registration": server.settings.get_bool("auth/allow_registration"),
		"token_required": server.settings.get_text("auth/registration_token") != "",
		"nonce": record.nonce,
	})


func _on_peer_authentication_failed(peer_id: int) -> void:
	var record: Pending = _pending.get(peer_id)
	if record != null:
		server.logger.info("auth", "%s gave up or timed out during the handshake"
			% record.address)
	forget(peer_id)


# ── Every message from a connecting peer lands here ─────────────────────────
func _on_auth_message(peer_id: int, data: PackedByteArray) -> void:
	var record: Pending = _pending.get(peer_id)
	if record == null:
		_deny(peer_id, "handshake out of order")
		return
	var message := NetProtocol.decode(data)
	if message.is_empty():
		_deny(peer_id, "that is not a %s client" % NetProtocol.GAME_ID)
		return
	match record.step:
		Step.WAITING_IDENT:
			_on_ident(record, message)
		Step.WAITING_PROOF:
			_on_proof(record, message)
		_:
			_deny(peer_id, "handshake out of order")


# ── Step 1: their build and their intent ────────────────────────────────────
func _on_ident(record: Pending, message: Dictionary) -> void:
	if StringName(message.get("t", "")) != NetProtocol.MSG_IDENT:
		_deny(record.peer_id, "handshake out of order")
		return
	if server.settings.get_bool("protection/enforce_build_match"):
		var problem := NetProtocol.incompatibility(
			int(message.get("proto", 0)), str(message.get("content", "")),
			StringName(message.get("game", "")), false)
		if problem != "":
			server.logger.warn("auth", "%s refused: %s" % [record.address, problem])
			_deny(record.peer_id, problem)
			return

	record.intent = StringName(message.get("intent", NetProtocol.INTENT_GUEST))
	record.display_name = str(message.get("name", "")).strip_edges()
	var refusal := _check_name(record)
	if refusal != "":
		_deny(record.peer_id, refusal)
		return
	_route_intent(record, message)


## Which of the three ways in this is, and whether the server offers it.
func _route_intent(record: Pending, message: Dictionary) -> void:
	var mode := server.settings.get_text("auth/mode")
	if mode == NetProtocol.AUTH_OPEN:
		_accept(record, Account.guest_for(record.display_name))
		return
	if record.intent == NetProtocol.INTENT_GUEST:
		_as_guest(record, mode)
		return
	if record.intent == NetProtocol.INTENT_REGISTER:
		_begin_registration(record, message)
		return
	_begin_login(record)


func _as_guest(record: Pending, mode: String) -> void:
	if mode == NetProtocol.AUTH_ACCOUNT:
		_deny(record.peer_id, "THIS SERVER NEEDS AN ACCOUNT — REGISTER OR LOG IN")
		return
	# A guest may not wear a registered player's name. Without this, "admin"
	# walks in as a guest and everybody in chat believes them.
	var prefixed := server.settings.get_text("auth/guest_prefix") + record.display_name
	if server.accounts.exists(record.display_name) or server.accounts.exists(prefixed):
		_deny(record.peer_id, "THAT NAME IS REGISTERED — LOG IN INSTEAD")
		return
	_accept(record, Account.guest_for(prefixed))


## `auth/logins_per_minute` says FAILED logins, and now means it: the allowance
## is only READ here and is spent in `_finish_login`, when an attempt actually
## turns out to be wrong. Spending it on every attempt locked out the player who
## reconnects eleven times in a minute on a bad line — the one person the setting
## was never about.
func _begin_login(record: Pending) -> void:
	if _login_limit.remaining(record.address) < 1.0:
		server.logger.warn("auth", "%s is trying too many logins" % record.address)
		_deny(record.peer_id, "TOO MANY ATTEMPTS — WAIT A MINUTE")
		return
	record.account = server.accounts.find(record.display_name)
	# An unknown name gets a challenge too, built from the server's own secret so
	# that it is stable and indistinguishable from a real one. Otherwise anybody
	# can ask this port which names exist here.
	record.salt = record.account.salt if record.account != null \
			else NetCrypto.decoy_salt(server.secret, record.display_name)
	record.iterations = record.account.iterations if record.account != null \
			else server.settings.get_int("auth/pbkdf2_iterations")
	record.step = Step.WAITING_PROOF
	_send(record.peer_id, {
		"t": NetProtocol.MSG_CHALLENGE,
		"salt": record.salt,
		"iterations": record.iterations,
		"nonce": record.nonce,
	})


func _begin_registration(record: Pending, message: Dictionary) -> void:
	if not server.settings.get_bool("auth/allow_registration"):
		_deny(record.peer_id, "THIS SERVER IS NOT TAKING NEW ACCOUNTS")
		return
	var token := server.settings.get_text("auth/registration_token")
	if token != "" and str(message.get("token", "")) != token:
		server.logger.warn("auth", "%s tried to register without the token" % record.address)
		_deny(record.peer_id, "THIS SERVER NEEDS AN INVITE TOKEN TO REGISTER")
		return
	if server.accounts.exists(record.display_name):
		_deny(record.peer_id, "THAT NAME IS TAKEN")
		return
	record.salt = NetCrypto.new_salt()
	record.iterations = server.settings.get_int("auth/pbkdf2_iterations")
	record.step = Step.WAITING_PROOF
	_send(record.peer_id, {
		"t": NetProtocol.MSG_CHALLENGE,
		"salt": record.salt,
		"iterations": record.iterations,
		"nonce": record.nonce,
	})


# ── Step 2: the proof ───────────────────────────────────────────────────────
func _on_proof(record: Pending, message: Dictionary) -> void:
	if StringName(message.get("t", "")) != NetProtocol.MSG_PROOF:
		_deny(record.peer_id, "handshake out of order")
		return
	if record.intent == NetProtocol.INTENT_REGISTER:
		_finish_registration(record, message)
		return
	_finish_login(record, message)


func _finish_registration(record: Pending, message: Dictionary) -> void:
	var verifier := NetProtocol.bytes_of(message, "verifier")
	if verifier.size() != NetCrypto.DIGEST_BYTES:
		_deny(record.peer_id, "REGISTRATION FAILED")
		return
	# Re-check under the lock of the same frame: two people registering the same
	# name at once both passed the earlier check.
	if server.accounts.exists(record.display_name):
		_deny(record.peer_id, "THAT NAME IS TAKEN")
		return
	var account := Account.new()
	account.name = record.display_name
	account.id = Account.canonical(record.display_name)
	account.salt = record.salt
	account.iterations = record.iterations
	account.verifier = verifier
	account.created_at = int(Time.get_unix_time_from_system())
	if server.settings.get_bool("auth/first_account_is_owner") and server.accounts.is_empty():
		account.role = Permissions.ROLE_OWNER
		server.logger.info("auth", "%s is the first account here and is the owner"
			% account.name)
	server.accounts.add(account)
	server.accounts.save()
	server.logger.info("auth", "%s registered from %s" % [account.name, record.address])
	_accept(record, account)


## Verifying is one HMAC, which is cheap — but a WRONG name has no account, and
## answering instantly for an unknown name while taking a moment for a known one
## is a timing oracle for who plays here. So the unknown case does the same work
## against a throwaway verifier before failing.
func _finish_login(record: Pending, message: Dictionary) -> void:
	var answer := NetProtocol.bytes_of(message, "proof")
	var ok := false
	if record.account != null:
		ok = record.account.proves(record.nonce, answer)
	else:
		NetCrypto.equal(NetCrypto.proof(record.salt, record.nonce), answer)
	if not ok:
		_login_limit.allow(record.address)
		server.logger.info("auth", "%s failed to log in as '%s'"
			% [record.address, record.display_name])
		_deny(record.peer_id, "WRONG NAME OR PASSWORD")
		return
	_accept(record, record.account)


## Called from the server's slow tick. Without it the table grows by one entry
## per address that ever tried to log in and never shrinks — which, for a limiter
## keyed on the address of whoever is attacking it, is the attacker choosing how
## much memory this process uses.
func prune() -> void:
	_login_limit.prune()


# ── Done, one way or the other ──────────────────────────────────────────────
func _accept(record: Pending, account: Account) -> void:
	var ban := server.bans.check(account.id, record.address)
	if not ban.is_empty():
		server.logger.info("auth", "%s is banned (%s)" % [account.name, ban.get("reason", "")])
		_deny(record.peer_id, BanList.notice(ban, server.settings.get_text("server/contact")))
		return
	account.last_seen_at = int(Time.get_unix_time_from_system())
	account.last_address = record.address
	if not account.guest:
		server.accounts.touch()
	server.attach_account(record.peer_id, account)
	_send(record.peer_id, {
		"t": NetProtocol.MSG_WELCOME,
		"account": account.name,
		"role": account.role,
		"guest": account.guest,
		"permissions": account.permissions(),
		"motd": server.settings.get_text("server/motd"),
		"server": server.settings.get_text("server/name"),
	})
	forget(record.peer_id)
	(multiplayer as SceneMultiplayer).complete_auth(record.peer_id)


## Refuse, with a sentence the player can read. The message is sent BEFORE the
## disconnect so that "you are banned until Tuesday" reaches them — a bare
## dropped connection is indistinguishable from the server being down, and every
## player who gets one asks about it.
func _deny(peer_id: int, reason: String) -> void:
	_send(peer_id, {"t": NetProtocol.MSG_DENY, "reason": reason})
	forget(peer_id)
	server.disconnect_peer_soon(peer_id)


func _send(peer_id: int, message: Dictionary) -> void:
	(multiplayer as SceneMultiplayer).send_auth(peer_id, NetProtocol.encode(message))


func _check_name(record: Pending) -> String:
	var name := record.display_name
	var low := server.settings.get_int("auth/name_min_length")
	var high := server.settings.get_int("auth/name_max_length")
	if name.length() < low or name.length() > high:
		return "NAMES ARE BETWEEN %d AND %d CHARACTERS" % [low, high]
	for i in name.length():
		var code := name.unicode_at(i)
		# Control characters and spaces make a name that cannot be typed back at
		# it — every moderation command takes a name as an argument.
		if code < 33 or code == 127:
			return "A NAME CANNOT CONTAIN SPACES OR CONTROL CHARACTERS"
	if server.settings.get_list("auth/reserved_names").has(name.to_lower()):
		return "THAT NAME IS RESERVED"
	return ""

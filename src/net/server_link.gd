class_name ServerLink
extends Node
## The client's half of the handshake with a dedicated server.
##
## The mirror of AuthService. It answers the server's HELLO with who we are,
## derives the password into a key when challenged, and proves it against the
## server's nonce — so the password itself never leaves this machine.
##
## **The derivation runs on a worker thread.** PBKDF2 at the server's iteration
## count takes about 115 ms, and doing it inline would freeze the menu mid-click
## in a way that reads as the game having hung. It is the one genuinely expensive
## thing in the handshake, and it is on the client on purpose: the machine with
## the password pays for stretching it, which also means a server cannot be made
## to burn CPU by a stranger sending passwords at it.

signal state_changed(state: int, message: String)

enum State {IDLE, DIALLING, HANDSHAKE, DERIVING, CONNECTED, REFUSED}

## Filled from the server's HELLO before we have agreed to anything, so a UI can
## show what it is about to join.
var server_name: String = ""
var motd: String = ""
var auth_mode: String = NetProtocol.AUTH_GUEST
var registration_open: bool = false
var token_required: bool = false

var state: int = State.IDLE
var message: String = ""

var _intent: StringName = NetProtocol.INTENT_GUEST
var _name: String = ""
var _password: String = ""
var _token: String = ""
var _nonce: PackedByteArray = PackedByteArray()
var _task: int = -1
var _derived: PackedByteArray = PackedByteArray()
## What to do once the worker thread finishes: prove, or register.
var _after_derive: StringName = &""


func _ready() -> void:
	set_process(false)


## Dial a dedicated server. `intent` is guest, login or register; the password is
## ignored for a guest.
func connect_to(address: String, port: int, intent: StringName, player_name: String,
		password: String, token: String = "") -> Error:
	_intent = intent
	_name = player_name.strip_edges()
	_password = password
	_token = token
	_reset_facts()

	var api := multiplayer as SceneMultiplayer
	# Before create_client, or the server's first message arrives with nobody
	# listening for it.
	api.auth_callback = _on_auth_message
	api.auth_timeout = 25.0
	if not api.peer_authentication_failed.is_connected(_on_auth_failed):
		api.peer_authentication_failed.connect(_on_auth_failed)

	var peer := ENetMultiplayerPeer.new()
	# ENet resolves a hostname itself, so `play.example.com` works as typed —
	# which is the whole of "connecting a domain" from this side.
	var err := peer.create_client(address, port)
	if err != OK:
		_fail("COULD NOT REACH %s:%d" % [address, port])
		return err
	NetProtocol.apply_transport(peer)
	multiplayer.multiplayer_peer = peer
	Net.session.active = true
	_set_state(State.DIALLING, "CONTACTING %s…" % address)
	return OK


func cancel() -> void:
	_reset_facts()
	_set_state(State.IDLE, "")


func _reset_facts() -> void:
	server_name = ""
	motd = ""
	_nonce = PackedByteArray()
	_derived = PackedByteArray()
	_after_derive = &""
	_task = -1


# ── Messages from the server ────────────────────────────────────────────────
func _on_auth_message(_peer_id: int, data: PackedByteArray) -> void:
	var packet := NetProtocol.decode(data)
	if packet.is_empty():
		_fail("THAT IS NOT A %s SERVER" % String(NetProtocol.GAME_ID).to_upper())
		return
	match StringName(packet.get("t", "")):
		NetProtocol.MSG_HELLO:
			_on_hello(packet)
		NetProtocol.MSG_CHALLENGE:
			_on_challenge(packet)
		NetProtocol.MSG_WELCOME:
			_on_welcome(packet)
		NetProtocol.MSG_DENY:
			_fail(str(packet.get("reason", "REFUSED")))
		_:
			_fail("THE SERVER SAID SOMETHING UNEXPECTED")


func _on_hello(packet: Dictionary) -> void:
	server_name = str(packet.get("name", ""))
	motd = str(packet.get("motd", ""))
	auth_mode = str(packet.get("mode", NetProtocol.AUTH_GUEST))
	registration_open = bool(packet.get("registration", false))
	token_required = bool(packet.get("token_required", false))
	_nonce = packet.get("nonce", PackedByteArray())

	# We check the server's build as strictly as it checks ours, and the message
	# names which side is behind — a player who is told "the server is older"
	# knows to wait, and one told "your game is older" knows to update.
	var problem := NetProtocol.incompatibility(int(packet.get("proto", 0)),
		str(packet.get("content", "")), StringName(packet.get("game", "")), true)
	if problem != "":
		_fail(problem)
		return

	_set_state(State.HANDSHAKE, "SAYING HELLO TO %s…" % server_name)
	_send({
		"t": NetProtocol.MSG_IDENT,
		"proto": NetProtocol.VERSION,
		"game": NetProtocol.GAME_ID,
		"content": NetProtocol.content_hash(),
		"intent": _intent,
		"name": _name,
		"token": _token,
	})


func _on_challenge(packet: Dictionary) -> void:
	var salt := NetProtocol.bytes_of(packet, "salt")
	var iterations := int(packet.get("iterations", NetCrypto.DEFAULT_ITERATIONS))
	if packet.has("nonce"):
		_nonce = packet.get("nonce")
	_after_derive = NetProtocol.INTENT_REGISTER if _intent == NetProtocol.INTENT_REGISTER \
			else NetProtocol.INTENT_LOGIN
	_set_state(State.DERIVING, "CHECKING YOUR PASSWORD…")
	_start_derivation(salt, iterations)


## Off the main thread, or the menu stops responding for an eighth of a second
## and the player clicks again.
func _start_derivation(salt: PackedByteArray, iterations: int) -> void:
	var password := _password
	_derived = PackedByteArray()
	_task = WorkerThreadPool.add_task(func() -> void:
		_derived = NetCrypto.derive_key(password, salt, iterations))
	set_process(true)


func _process(_delta: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	set_process(false)
	_send_proof()


func _send_proof() -> void:
	if _derived.is_empty():
		_fail("COULD NOT PREPARE YOUR PASSWORD")
		return
	if _after_derive == NetProtocol.INTENT_REGISTER:
		# The one thing that has to cross: the server needs something to check
		# against next time. Documented in NetCrypto and docs/SERVER.md.
		_send({"t": NetProtocol.MSG_PROOF, "verifier": _derived})
	else:
		_send({"t": NetProtocol.MSG_PROOF, "proof": NetCrypto.proof(_derived, _nonce)})
	# Kept no longer than it takes to use it.
	_password = ""
	_derived = PackedByteArray()
	_set_state(State.HANDSHAKE, "WAITING FOR THE SERVER…")


func _on_welcome(packet: Dictionary) -> void:
	motd = str(packet.get("motd", motd))
	server_name = str(packet.get("server", server_name))
	_password = ""
	(multiplayer as SceneMultiplayer).complete_auth(1)
	Game.local_peer_id = multiplayer.get_unique_id()
	_set_state(State.CONNECTED, "CONNECTED TO %s" % server_name)


func _on_auth_failed(_peer_id: int) -> void:
	if state != State.REFUSED:
		_fail("THE SERVER DID NOT ANSWER IN TIME")


func _send(packet: Dictionary) -> void:
	(multiplayer as SceneMultiplayer).send_auth(1, NetProtocol.encode(packet))


func _fail(reason: String) -> void:
	_password = ""
	_set_state(State.REFUSED, reason)
	# The socket is closed by Net, not here: Net owns the peer, and two places
	# tearing down one connection is how a reconnect ends up half-open.
	Net.close_session("")


func _set_state(next: int, text: String) -> void:
	state = next
	message = text
	state_changed.emit(next, text)

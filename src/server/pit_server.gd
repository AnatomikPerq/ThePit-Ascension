class_name PitServer
extends Node
## The dedicated server: one process, one socket, several rooms.
##
## It is a build of THIS project rather than a separate program, and that is the
## most important decision in the whole design. The pit is a pure function of a
## seed, enemies are host-simulated, a blast names the pieces it broke — every
## one of those agreements is between two builds of the same code. A server
## written separately would have to reimplement the simulation and would diverge
## from it on the first patch; a server that IS the game, with its presentation
## turned off, cannot.
##
## What that leaves this file to do:
##
##   - boot: arguments, `server.cfg`, the storage directory, the log
##   - the socket, and the gatekeeper in front of it
##   - who is connected (ServerPeer), and what they are allowed to do
##   - the console, and the command set the console, rcon and the in-game admin
##     panel all share
##   - the housekeeping tick
##
## Rooms are RoomManager's, the handshake is AuthService's, and everything a
## client says arrives through `Hub`, which is the one door — see its comment for
## why there is exactly one.

## The subdirectory of `storage/dir` that holds the server's own secret.
const SECRET_FILE := "server.secret"

var settings: ServerSettings = ServerSettings.new()
var logger: ServerLog = ServerLog.new()
var accounts: AccountStore = AccountStore.new()
var bans: BanList = BanList.new()
var commands: CommandRegistry = CommandRegistry.new()
var console: ServerConsole = ServerConsole.new()

var rooms: RoomManager
var moderation: Moderation
var auth: AuthService
var chat: ChatService
var guard: MovementGuard
var rcon: RconService
var status: StatusEndpoint
## How this server is found: announced to a directory on the internet, and
## answering probes on the local network. Both optional, neither load-bearing —
## see docs/SERVER.md, "Being found".
var directory: DirectoryClient
var beacon: LanBeacon

## peer id -> ServerPeer. Everyone past the handshake; the handshake's own
## pending records live in AuthService.
var peers: Dictionary[int, ServerPeer] = {}

## Random, per install, kept in the storage directory. Used to make an unknown
## account's login challenge indistinguishable from a real one, and to sign
## anything else that must not be forgeable across installs.
var secret: PackedByteArray = PackedByteArray()

var storage_dir: String = ""
var started_at: float = 0.0
var running: bool = false

## Messages a peer may send, and how often a new connection may arrive.
var _message_limit: RateLimiter = RateLimiter.make(90.0, 180.0)
var _join_limit: RateLimiter = RateLimiter.make(1.0, 60.0)
## Peers told to go away, with the frame budget to let the reason reach them.
var _closing: Dictionary[int, float] = {}
var _since_status: float = 0.0
var _frame_warned_at: float = 0.0
var _instance_id: String = ""


# ── Boot ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	started_at = Time.get_ticks_msec() / 1000.0
	_load_configuration()
	_prepare_presentation()
	if not _open_socket():
		get_tree().quit(1)
		return
	_build_services()
	_start_console()
	_announce()
	running = true


## The order here is load-bearing and was got wrong once.
##
## The command line is applied TWICE: before the storage directory is worked out,
## because `--set storage/dir=…` decides where `server.cfg` is even read from,
## and again afterwards, because the file would otherwise overwrite every
## override with its own value. In between, the file is written back — before the
## second application — so that an override meant for one run does not quietly
## become the file's new setting.
func _load_configuration() -> void:
	Net.dedicated = true
	var problems := _apply_command_line()
	storage_dir = _resolve_storage_dir()
	problems.append_array(settings.load_from(storage_dir))
	settings.save_to(storage_dir)
	problems.append_array(_apply_command_line())

	logger.configure(settings, storage_dir)
	for problem in problems:
		logger.warn("config", problem)

	accounts.backups = settings.get_int("storage/backups")
	var account_problem := accounts.load_from(storage_dir)
	if account_problem != "":
		logger.error("config", account_problem)
	bans.backups = settings.get_int("storage/backups")
	var ban_problem := bans.load_from(storage_dir)
	if ban_problem != "":
		logger.error("config", ban_problem)
	secret = _load_or_make_secret()
	settings.changed.connect(_on_setting_changed)


## `--set key=value` from the command line, applied over the file and NOT written
## back — a temporary override should stay temporary. `--port` is the same thing
## with a shorter name, because it is the one everybody reaches for.
func _apply_command_line() -> PackedStringArray:
	var problems := PackedStringArray()
	var pairs := ServerBoot.overrides()
	var port := ServerBoot.argument("port")
	if port != "":
		pairs.append("network/port=%s" % port)
	for pair in pairs:
		var split := pair.find("=")
		if split <= 0:
			problems.append("--set wants key=value, got '%s'" % pair)
			continue
		var problem := settings.set_from_text(pair.substr(0, split), pair.substr(split + 1))
		if problem != "":
			problems.append("--set %s" % problem)
	return problems


## `--data <dir>` wins, then the setting, then a directory next to the binary.
## A server started by a service manager usually has a working directory nobody
## chose, which is why the flag exists at all.
func _resolve_storage_dir() -> String:
	var wanted := ServerBoot.argument("data")
	if wanted == "":
		wanted = settings.get_text("storage/dir")
	return ServerBoot.absolute(wanted)


func _load_or_make_secret() -> PackedByteArray:
	var path := storage_dir.path_join(SECRET_FILE)
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path).strip_edges()
		if text.length() >= 32:
			return text.hex_decode()
	var fresh := NetCrypto.random_bytes(32)
	DirAccess.make_dir_recursive_absolute(storage_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(fresh.hex_encode())
		file.close()
	return fresh


## A server has no screen, no speakers and no window. Saying so once here is
## worth more than a branch at every call site: `Fx` and `Audio` are called from
## the middle of the simulation, several times per entity per frame, in every
## room at once.
func _prepare_presentation() -> void:
	Fx.enabled = false
	Audio.enabled = false
	Engine.max_fps = settings.get_int("performance/max_fps")


func _open_socket() -> bool:
	var port := settings.get_int("network/port")
	var peer := ENetMultiplayerPeer.new()
	var bind := settings.get_text("network/bind_address")
	if bind != "" and bind != "*":
		peer.set_bind_ip(bind)
	var err := peer.create_server(port, settings.get_int("network/max_players"))
	if err != OK:
		logger.error("net", "could not open UDP %d — %s. Another server on this "
			% [port, error_string(err)] + "port, or no permission to bind it.")
		return false
	NetProtocol.apply_transport(peer)
	multiplayer.multiplayer_peer = peer

	var api := multiplayer as SceneMultiplayer
	# Off means a client cannot address a packet to another client through this
	# server: everything a peer sends is something this server received and
	# judged. It is the single most valuable line in this file.
	api.server_relay = settings.get_bool("network/relay_between_clients")
	api.max_sync_packet_size = settings.get_int("network/max_packet_size")
	# Never on. The decoder that honours it instantiates classes named in the
	# packet, which on a public socket is remote code execution.
	api.allow_object_decoding = false

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.session.active = true
	Game.local_peer_id = 1
	return true


func _build_services() -> void:
	moderation = Moderation.new(self)
	rooms = RoomManager.new()
	rooms.name = "Rooms"
	rooms.server = self
	add_child(rooms)

	auth = AuthService.new()
	auth.name = "Auth"
	auth.server = self
	add_child(auth)
	auth.configure()

	chat = ChatService.new()
	chat.name = "Chat"
	chat.server = self
	add_child(chat)

	guard = MovementGuard.new()
	guard.name = "Guard"
	guard.server = self
	add_child(guard)

	rcon = RconService.new()
	rcon.name = "Rcon"
	rcon.server = self
	add_child(rcon)

	status = StatusEndpoint.new()
	status.name = "Status"
	status.server = self
	add_child(status)

	directory = DirectoryClient.new()
	directory.name = "Directory"
	directory.server = self
	add_child(directory)
	directory.configure()

	_start_beacon()
	ServerCommands.install(self)
	Hub.server = self
	_apply_limits()


## Answering discovery probes on the local network. A failure here is a log line
## and nothing else: the usual cause is a second server on the same box holding
## the port, and that server is still perfectly reachable by address.
func _start_beacon() -> void:
	beacon = LanBeacon.new()
	beacon.name = "Beacon"
	beacon.payload = _beacon_payload
	add_child(beacon)
	if not settings.get_bool("directory/lan_beacon"):
		return
	var problem := beacon.start(settings.get_int("directory/lan_port"))
	if problem != "":
		logger.warn("lan", "%s — this server will not appear on the local "
			% problem + "network's browser. Everything else is unaffected.")
		return
	logger.info("lan", "answering discovery probes on UDP %d"
		% settings.get_int("directory/lan_port"))


## What a probe on the local network is told. Deliberately the same shape as a
## directory listing, so the browser merges the two without a second reader —
## minus the badge, which a server is never allowed to claim for itself.
func _beacon_payload() -> Dictionary:
	return {
		"game": String(NetProtocol.GAME_ID),
		"directory_protocol": DirectoryProtocol.VERSION,
		"protocol": NetProtocol.VERSION,
		"content": NetProtocol.content_hash(),
		"instance": instance_id(),
		"name": settings.get_text("server/name"),
		"description": settings.get_text("server/description"),
		"tags": Array(settings.get_list("server/tags")),
		"region": settings.get_text("server/region"),
		"port": settings.get_int("network/port"),
		"players": peers.size(),
		"max_players": settings.get_int("network/max_players"),
		"rooms": rooms.count(),
		"rooms_running": rooms.running_count(),
		"auth": settings.get_text("auth/mode"),
		"registration": settings.get_bool("auth/allow_registration"),
	}


func _apply_limits() -> void:
	_message_limit.configure(
		float(settings.get_int("protection/messages_per_second")),
		float(settings.get_int("protection/message_burst")))
	var joins := float(settings.get_int("network/joins_per_minute"))
	_join_limit.configure(joins / 60.0, maxf(joins, 1.0))


func _start_console() -> void:
	if console.start():
		console.line_received.connect(_on_console_line)
	else:
		logger.warn("console", "no standard input — this server takes no typed "
			+ "commands. Use rcon, or the admin panel in the game.")


func _announce() -> void:
	logger.info("server", "%s — %s" % [
		settings.get_text("server/name"), NetProtocol.build_id()])
	logger.info("server", "listening on %s:%d, up to %d players in up to %d rooms" % [
		settings.get_text("network/bind_address"), settings.get_int("network/port"),
		settings.get_int("network/max_players"), settings.get_int("rooms/max_rooms")])
	logger.info("server", "authentication: %s · %d accounts · %d bans" % [
		settings.get_text("auth/mode"), accounts.count(), bans.count()])
	if accounts.is_empty() and settings.get_bool("auth/first_account_is_owner"):
		logger.info("server", "no accounts yet — the first one registered becomes "
			+ "the owner. Or make one now:  account register <name> <password>")
	logger.info("server", "type 'help' for commands.")


# ── Connections ─────────────────────────────────────────────────────────────
## Everything checked before a stranger is allowed to start the handshake.
## Returns "" to let them in, or the reason not to.
func gatekeeper_refusal(peer_id: int, address: String) -> String:
	if not _join_limit.allow("global"):
		return "THE SERVER IS BUSY — TRY AGAIN IN A MOMENT"
	var per_ip := settings.get_int("network/max_peers_per_ip")
	if per_ip > 0 and _count_from(address) >= per_ip:
		logger.warn("net", "%s already has %d connections" % [address, per_ip])
		return "TOO MANY CONNECTIONS FROM YOUR ADDRESS"
	var ban := bans.check("", address)
	if not ban.is_empty():
		return BanList.notice(ban, settings.get_text("server/contact"))
	if peers.size() >= settings.get_int("network/max_players"):
		return "THE SERVER IS FULL"
	if peer_id == 0:
		return "BAD CONNECTION"
	return ""


func _count_from(address: String) -> int:
	var found := 0
	for peer_id in peers:
		if peers[peer_id].address == address:
			found += 1
	return found


func address_of(peer_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var packet_peer := enet.get_peer(peer_id)
	return packet_peer.get_remote_address() if packet_peer != null else ""


## Called by AuthService the moment a handshake succeeds — before Godot reports
## the peer as connected, so the peer record always exists by the time anything
## can arrive from it.
func attach_account(peer_id: int, account: Account) -> void:
	var peer := ServerPeer.make(peer_id, address_of(peer_id))
	peer.account = account
	peer.stage = ServerPeer.Stage.LOBBY
	peers[peer_id] = peer


func _on_peer_connected(peer_id: int) -> void:
	var peer: ServerPeer = peers.get(peer_id)
	if peer == null:
		# Should be impossible: nobody reaches `peer_connected` without passing
		# the handshake, which is what creates the record.
		logger.warn("net", "peer %d connected without a record — dropping it" % peer_id)
		disconnect_peer_soon(peer_id)
		return
	logger.info("net", "%s joined from %s (%s)" % [
		peer.name_text(), peer.address, peer.account.role])
	Hub.rpc_id(peer_id, &"server_welcome", _welcome_payload(peer))
	broadcast_rooms()


func _on_peer_disconnected(peer_id: int) -> void:
	var peer: ServerPeer = peers.get(peer_id)
	if peer != null:
		rooms.drop(peer_id)
		logger.info("net", "%s left" % peer.name_text())
		_message_limit.forget(str(peer_id))
	peers.erase(peer_id)
	_closing.erase(peer_id)
	auth.forget(peer_id)
	guard.forget(peer_id)
	broadcast_rooms()


func _welcome_payload(peer: ServerPeer) -> Dictionary:
	return {
		"name": settings.get_text("server/name"),
		"motd": settings.get_text("server/motd"),
		"account": peer.account.name,
		"role": peer.account.role,
		"guest": peer.account.guest,
		"permissions": peer.account.permissions(),
		"rooms": rooms.listing(),
		"may_create": _may_create_rooms(peer),
		"chat": settings.get_bool("moderation/chat"),
	}


func _may_create_rooms(peer: ServerPeer) -> bool:
	if peer.may(Permissions.ROOM_CONFIGURE_ANY):
		return true
	return settings.get_bool("rooms/players_may_create") \
			and peer.may(Permissions.ROOM_CREATE)


# ── Talking to clients ──────────────────────────────────────────────────────
func hub() -> Node:
	return Hub


func hub_notice(peer_id: int, text: String) -> void:
	if peers.has(peer_id):
		Hub.rpc_id(peer_id, &"server_notice", text)


func broadcast_rooms() -> void:
	var listing := rooms.listing()
	for peer_id in peers:
		Hub.rpc_id(peer_id, &"room_listing_changed", listing)


## Refuse a message that arrived too fast. Returns true when the peer may be
## heard. A flooding peer is dropped rather than merely ignored when the setting
## says so — ignoring costs the same bandwidth and teaches nothing.
func may_speak(peer_id: int) -> bool:
	if _message_limit.allow(str(peer_id)):
		return true
	if settings.get_bool("protection/kick_on_flood"):
		kick(peer_id, "sending far too much, far too fast")
	return false


# ── Ending a connection ─────────────────────────────────────────────────────
## Close a socket after giving the last packet a moment to leave. ENet drops
## everything queued on an immediate disconnect, so a peer told why it was
## refused would learn nothing.
func disconnect_peer_soon(peer_id: int, seconds: float = 0.35) -> void:
	_closing[peer_id] = seconds


func kick(peer_id: int, reason: String) -> bool:
	var peer: ServerPeer = peers.get(peer_id)
	if peer == null:
		return false
	logger.info("mod", "kicked %s — %s" % [peer.name_text(), reason])
	Hub.rpc_id(peer_id, &"server_kicked", reason)
	peer.closing = true
	rooms.drop(peer_id)
	disconnect_peer_soon(peer_id, 0.5)
	return true


func _drain_closing(delta: float) -> void:
	if _closing.is_empty():
		return
	var done: Array[int] = []
	for peer_id in _closing:
		_closing[peer_id] -= delta
		if _closing[peer_id] <= 0.0:
			done.append(peer_id)
	for peer_id in done:
		_closing.erase(peer_id)
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)


# ── Finding people ──────────────────────────────────────────────────────────
## A peer by name, as a moderator would type it. Exact first, then a unique
## prefix — a moderator watching chat scroll past should not have to be careful
## about capitals, and an ambiguous prefix must never guess.
func find_peer(needle: String) -> ServerPeer:
	var lowered := needle.to_lower()
	var partial: ServerPeer = null
	var ambiguous := false
	for peer_id in peers:
		var peer: ServerPeer = peers[peer_id]
		var name := peer.name_text().to_lower()
		if name == lowered:
			return peer
		if name.begins_with(lowered):
			ambiguous = partial != null
			partial = peer
	return null if ambiguous else partial


func online_named(account_id: String) -> ServerPeer:
	for peer_id in peers:
		var peer: ServerPeer = peers[peer_id]
		if peer.account != null and peer.account.id == account_id:
			return peer
	return null


# ── The tick ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not running:
		return
	console.poll()
	_drain_closing(delta)
	accounts.tick(delta, settings.get_float("storage/save_interval_seconds"))
	bans.tick()
	_periodic_status(delta)
	_watch_frame_time(delta)


func _periodic_status(delta: float) -> void:
	var interval := settings.get_float("performance/status_interval_seconds")
	if interval <= 0.0:
		return
	_since_status += delta
	if _since_status < interval:
		return
	_since_status = 0.0
	logger.info("server", status_line())
	# Every limiter keyed on somebody else's address, not merely the two that
	# happened to be in this file. A bucket table that only ever grows is the
	# attacker choosing how much memory this process uses, and RateLimiter says
	# so in its own comment — two of its four users were not listening.
	_message_limit.prune()
	_join_limit.prune()
	auth.prune()
	rcon.prune()
	beacon.prune()


## The first sign that a box is carrying more rooms than it can. Reported once
## per burst rather than per frame: a server that is struggling must not spend
## what is left of its budget saying so.
##
## It measures WORK, not the frame interval. `delta` is the wrong number: with
## `performance/max_fps` at 60 the engine sleeps to fill each frame, so delta is
## 16.7 ms on a server with nothing to do at all and every idle server on earth
## would report itself overloaded. `TIME_PROCESS` and `TIME_PHYSICS_PROCESS` are
## the time actually spent stepping the tree.
func _watch_frame_time(_delta: float) -> void:
	var budget := settings.get_float("performance/frame_warn_ms") / 1000.0
	var spent: float = Performance.get_monitor(Performance.TIME_PROCESS)
	spent += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var now := Time.get_ticks_msec() / 1000.0
	if spent <= budget or now - _frame_warned_at < 10.0:
		return
	_frame_warned_at = now
	logger.warn("perf", "a frame spent %.1f ms in the tree (budget %.1f) with %d "
		% [spent * 1000.0, budget * 1000.0, rooms.count()]
		+ "rooms and %d players" % peers.size())


func uptime_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0 - started_at


## Which server this is, for a browser that has heard about it more than once.
##
## A machine has several addresses — loopback, one per network card, a public
## name — and a discovery probe gets an answer down each of them, so a browser
## keying rows on the address alone shows the same server three times. This is
## the thing all three answers agree on.
##
## Derived from the install's own secret and the port, so it survives a restart
## (a row that renamed itself every reboot would be no better than none) and
## carries nothing about the machine: it is a hash, one way, and the secret it
## is made from is the same one that already never leaves this box.
func instance_id() -> String:
	if _instance_id == "":
		var material := "instance|%s|%d" % [secret.hex_encode(),
			settings.get_int("network/port")]
		_instance_id = NetCrypto.sha256_hex(material.to_utf8_buffer()).substr(0, 16)
	return _instance_id


func status_line() -> String:
	return "up %s · %d players · %d rooms (%d running) · %d accounts · %d bans" % [
		ServerLog.duration(uptime_seconds()), peers.size(), rooms.count(),
		rooms.running_count(), accounts.count(), bans.count()]


# ── Commands from any of the three front-ends ───────────────────────────────
## The audit line is written BEFORE the command runs, not after. It reads
## backwards until you notice that `stop` closes the log — written afterwards,
## the one command an operator most wants to find in the file was the one command
## that never reached it.
func run_command(caller: CommandCaller, line: String) -> CommandCaller:
	var command := commands.resolve(ServerConsole.split(line)[0] if line != "" else "")
	if command != null and command.mutating:
		logger.info("cmd", "%s: %s" % [caller.label, line])
	commands.execute(caller, line)
	return caller


func _on_console_line(line: String) -> void:
	var caller := run_command(CommandCaller.for_console(), line)
	if not caller.lines.is_empty():
		logger.reply(caller.output())


func _on_setting_changed(key: String, _value: Variant) -> void:
	# The handful of settings that can be applied without a restart, applied.
	# Everything else is marked `(restart)` in the schema and says so when set.
	if key.begins_with("protection/") or key.begins_with("network/joins"):
		_apply_limits()
	elif key.begins_with("log/"):
		logger.configure(settings, storage_dir)
	elif key.begins_with("directory/") and not key.ends_with("lan_port"):
		# Turning announcing on, changing the directory or pasting a key all take
		# effect at once. The beacon's PORT is the exception and is marked
		# (restart), because rebinding a socket under a live server is a way to
		# end up with neither the old one nor the new.
		directory.configure()
	settings.save_to()


# ── Shutdown ────────────────────────────────────────────────────────────────
func shutdown(reason: String) -> void:
	if not running:
		return
	running = false
	logger.info("server", "shutting down: %s" % reason)
	for peer_id in peers.keys():
		Hub.rpc_id(peer_id, &"server_kicked", "SERVER SHUTTING DOWN — %s" % reason)
	for room_id in rooms.rooms.keys():
		rooms.close(room_id, "server shutting down")
	accounts.save()
	bans.save()
	settings.save_to()
	console.stop()
	rcon.stop()
	status.stop()
	beacon.stop()
	logger.info("server", "goodbye.")
	logger.close()
	# A moment, so the goodbye actually leaves the socket, and one last reap of
	# the console reader — by now stdin has usually reached its end and the
	# thread can be joined properly.
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		console.stop()
		get_tree().quit(0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		shutdown("interrupted")

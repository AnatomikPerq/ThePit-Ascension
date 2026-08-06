class_name PitDirectory
extends Node
## The service that lists dedicated servers, so a player opens MULTIPLAYER and
## sees somewhere to play instead of a box to type an address into.
##
##   godot --headless --path . -- --directory
##
## It is the third program in this one binary — the game, the dedicated server,
## and this. That is not economy: it is the reason a listing can carry a build
## fingerprint the client knows how to compare, and the reason the badge wording,
## the port default and the field names cannot drift between the three.
##
## **What it is not.** It never sees a player, never holds an account, and no
## game traffic passes through it. A server it has never heard of is perfectly
## playable — you type its address. Losing this service costs the browser and
## nothing else, which is the whole reason it is a separate process rather than
## something bolted onto one of the game servers.
##
## **What it decides.** Exactly one thing that a server cannot decide for itself:
## the badge. Everything else in a listing is a claim by whoever announced it,
## clamped by DirectoryEntry and believed. The badge is checked against a key
## this service issued, with a signature over the name and address, and that
## asymmetry is deliberate — see VerifyKeyStore.

var settings: ServerSettings = ServerSettings.new(ServerSettings.Profile.DIRECTORY)
var logger: ServerLog = ServerLog.new()
var store: DirectoryStore = DirectoryStore.new()
var keys: VerifyKeyStore = VerifyKeyStore.new()
var commands: CommandRegistry = CommandRegistry.new()
var console: ServerConsole = ServerConsole.new()
var listener: HttpListener

var storage_dir: String = ""
var started_at: float = 0.0
var running: bool = false

## Announces accepted per address. Configured from `listing/announce_per_minute`.
var _announce_limit: RateLimiter = RateLimiter.make(1.0, 20.0)
var _since_prune: float = 0.0
var _accepted: int = 0
var _refused: int = 0


# ── Boot ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	started_at = Time.get_ticks_msec() / 1000.0
	_load_configuration()
	Engine.max_fps = 30
	if not _open_listener():
		get_tree().quit(1)
		return
	DirectoryCommands.install(self, commands)
	_start_console()
	_announce_self()
	running = true


## The same twice-over as PitServer, and for the same reason: `--set
## storage/dir=…` decides where the file is read from, so the command line has to
## be applied before the file and again after it.
func _load_configuration() -> void:
	var problems := _apply_command_line()
	storage_dir = ServerBoot.absolute(ServerBoot.argument("data")
		if ServerBoot.argument("data") != "" else settings.get_text("storage/dir"))
	problems.append_array(settings.load_from(storage_dir))
	settings.save_to(storage_dir)
	problems.append_array(_apply_command_line())

	logger.configure(settings, storage_dir)
	for problem in problems:
		logger.warn("config", problem)

	var backups := settings.get_int("storage/backups")
	store.backups = backups
	keys.backups = backups
	for complaint in [keys.load_from(storage_dir), store.load_from(storage_dir)]:
		if complaint != "":
			logger.error("config", complaint)
	var withdrawn := store.refresh_badges(keys)
	if withdrawn > 0:
		logger.info("verify", "%d listed server(s) lost a badge: the key behind it "
			% withdrawn + "is revoked or gone")
	settings.changed.connect(_on_setting_changed)
	_apply_limits()


func _apply_command_line() -> PackedStringArray:
	var problems := PackedStringArray()
	var pairs := ServerBoot.overrides()
	var port := ServerBoot.argument("port")
	if port != "":
		pairs.append("listing/port=%s" % port)
	for pair in pairs:
		var split := pair.find("=")
		if split <= 0:
			problems.append("--set wants key=value, got '%s'" % pair)
			continue
		var problem := settings.set_from_text(pair.substr(0, split), pair.substr(split + 1))
		if problem != "":
			problems.append("--set %s" % problem)
	return problems


func _open_listener() -> bool:
	listener = HttpListener.new()
	listener.name = "Http"
	listener.handler = _handle
	listener.max_pending = settings.get_int("listing/max_pending")
	listener.max_request_bytes = settings.get_int("listing/max_request_bytes")
	listener.request_timeout = settings.get_float("listing/request_timeout_seconds")
	listener.trust_forwarded = settings.get_bool("listing/trust_forwarded")
	add_child(listener)
	var bind := settings.get_text("listing/bind_address")
	var port := settings.get_int("listing/port")
	var err := listener.listen(port, bind)
	if err != OK:
		logger.error("http", "could not listen on %s:%d — %s. Another program on "
			% [bind, port, error_string(err)] + "this port, or no permission.")
		return false
	return true


func _start_console() -> void:
	if console.start():
		console.line_received.connect(_on_console_line)
	else:
		logger.warn("console", "no standard input — this directory takes no typed "
			+ "commands. Issue keys with the process attached to a terminal.")


func _announce_self() -> void:
	logger.info("directory", "server directory — %s" % NetProtocol.build_id())
	logger.info("directory", "listening on http://%s:%d%s" % [
		settings.get_text("listing/bind_address"), settings.get_int("listing/port"),
		DirectoryProtocol.PATH_SERVERS])
	var public_url := settings.get_text("listing/public_url")
	if public_url != "":
		logger.info("directory", "servers should announce to %s" % public_url)
	logger.info("directory", "%d server(s) remembered · %d verification key(s)%s" % [
		store.count(), keys.count(),
		" · listing verified servers only" if settings.get_bool("listing/require_key")
		else ""])
	if keys.count() == 0:
		logger.info("directory", "no verification keys yet. Make one with: "
			+ "key issue official \"The PIT\" \"Run by the developer.\"")
	logger.info("directory", "type 'help' for commands.")


func _apply_limits() -> void:
	var per_minute := float(settings.get_int("listing/announce_per_minute"))
	_announce_limit.configure(per_minute / 60.0, maxf(per_minute, 1.0))


# ── HTTP ────────────────────────────────────────────────────────────────────
## One request in, [status, body] out. Everything that can go wrong answers with
## a sentence rather than a code alone: the reader is usually an operator with
## curl trying to work out why their server is not appearing.
func _handle(request: Dictionary) -> Array:
	var method := str(request.get("method", ""))
	var path := str(request.get("path", "")).trim_suffix("/")
	if method == "GET" and path == DirectoryProtocol.PATH_SERVERS:
		return _serve_listing(request)
	if method == "POST" and path == DirectoryProtocol.PATH_ANNOUNCE:
		return _serve_announce(request)
	if method == "GET" and path == DirectoryProtocol.PATH_HEALTH:
		return [200, {"ok": true, "servers": store.count(),
			"uptime_seconds": int(uptime_seconds()),
			"directory_protocol": DirectoryProtocol.VERSION}]
	return [404, {"error": "no such endpoint",
		"endpoints": [DirectoryProtocol.PATH_SERVERS, DirectoryProtocol.PATH_ANNOUNCE,
			DirectoryProtocol.PATH_HEALTH]}]


func _serve_listing(request: Dictionary) -> Array:
	var query: Dictionary = request.get("query", {})
	var verified_only := str(query.get("verified", "")) == "1"
	var now := int(Time.get_unix_time_from_system())
	return [200, {
		"directory_protocol": DirectoryProtocol.VERSION,
		"name": settings.get_text("server/name"),
		"description": settings.get_text("server/description"),
		"generated_at": now,
		"servers": store.listing(now, settings.get_int("listing/stale_seconds"),
			verified_only),
	}]


func _serve_announce(request: Dictionary) -> Array:
	var address := str(request.get("address", ""))
	if not _announce_limit.allow(address):
		_refused += 1
		return [429, {"error": "announcing too often"}]
	var body := str(request.get("body", ""))
	if body.length() > DirectoryProtocol.MAX_ANNOUNCE_BYTES:
		_refused += 1
		return [413, {"error": "announce too large"}]
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		_refused += 1
		return [400, {"error": "the body is not a JSON object"}]
	var message: Dictionary = parsed
	if str(message.get("game", "")) != String(NetProtocol.GAME_ID):
		_refused += 1
		return [400, {"error": "that is not this game"}]
	return _admit(message, address)


## Everything about an announce that is a decision rather than a parse. Split off
## so that `_serve_announce` stays a list of ways a body can be malformed and
## this stays a list of reasons a well-formed one is still not listed.
func _admit(message: Dictionary, address: String) -> Array:
	var now := int(Time.get_unix_time_from_system())
	var claimed := str(message.get("address", "")).strip_edges()
	if claimed == "":
		claimed = address
	if settings.get_list("listing/blocked").has(claimed.to_lower()):
		_refused += 1
		return [403, {"error": "that address is not listed here"}]

	var was_unbound := _is_unbound(str(message.get("verify_id", "")))
	var checked := keys.check(message, now,
		settings.get_bool("listing/bind_keys_on_first_use"))
	var key: VerifyKey = checked[0]
	var refusal := str(checked[1])
	if key != null and was_unbound and key.bind_address != "":
		logger.info("verify", "%s is now bound to %s — it will not badge any "
			% [key.id, key.bind_address] + "other address. Undo with: key bind %s -"
			% key.id)
	if refusal != "":
		# A bad claim does not hide the server; it only loses the badge. A key
		# that stopped working must not take a working server off the list with
		# it, and the operator is told exactly what happened.
		logger.warn("verify", "%s claimed %s and was refused: %s" % [
			claimed, str(message.get("verify_id", "")), refusal])
	if key == null and settings.get_bool("listing/require_key"):
		_refused += 1
		return [403, {"error": "this directory only lists verified servers",
			"reason": refusal}]

	var room := _room_for(message, claimed, now)
	if room != "":
		_refused += 1
		return [403, {"error": room}]

	var entry := store.accept(message, address, key, now)
	_accepted += 1
	logger.debug("announce", "%s (%s) · %d/%d players%s" % [
		entry.name, entry.key(), entry.players, entry.max_players,
		"" if key == null else " · " + DirectoryProtocol.badge_label(key.badge)])
	return [200, {
		"ok": true,
		"listed_as": entry.key(),
		"verified": entry.verified(),
		"badge": entry.badge,
		"next_announce_seconds": settings.get_int("listing/stale_seconds") / 2,
		"reason": refusal,
	}]


func _is_unbound(id: String) -> bool:
	var key := keys.find(id)
	return key != null and key.bind_address == ""


## "" when there is room for this server, or why there is not. Both limits only
## bite a server that is NOT already listed — an existing one re-announcing must
## never be pushed out by its own success.
func _room_for(message: Dictionary, claimed: String, _now: int) -> String:
	var port := clampi(int(message.get("port", NetProtocol.DEFAULT_PORT)), 1, 65535)
	if store.find(claimed, port) != null:
		return ""
	if store.count() >= settings.get_int("listing/max_servers"):
		return "this directory is full"
	if store.count_from(claimed) >= settings.get_int("listing/max_per_address"):
		return "too many servers from one address"
	return ""


# ── The tick ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not running:
		return
	console.poll()
	store.tick()
	keys.tick()
	_since_prune += delta
	if _since_prune < 30.0:
		return
	_since_prune = 0.0
	var gone := store.forget_stale(int(Time.get_unix_time_from_system()),
		settings.get_int("listing/forget_seconds"))
	if gone > 0:
		logger.info("directory", "forgot %d server(s) that stopped announcing" % gone)
	_announce_limit.prune()


func uptime_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0 - started_at


func status_line() -> String:
	var now := int(Time.get_unix_time_from_system())
	var live := store.listing(now, settings.get_int("listing/stale_seconds")).size()
	return "up %s · %d listed (%d remembered) · %d keys · %d announces accepted, %d refused" % [
		ServerLog.duration(uptime_seconds()), live, store.count(), keys.count(),
		_accepted, _refused]


# ── Commands ────────────────────────────────────────────────────────────────
## Audited before it runs, not after — see PitServer.run_command for the reason.
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
	if key.begins_with("listing/announce"):
		_apply_limits()
	elif key.begins_with("log/"):
		logger.configure(settings, storage_dir)
	settings.save_to()


# ── Shutdown ────────────────────────────────────────────────────────────────
func shutdown(reason: String) -> void:
	if not running:
		return
	running = false
	logger.info("directory", "shutting down: %s" % reason)
	store.save()
	keys.save()
	settings.save_to()
	console.stop()
	listener.stop()
	logger.info("directory", "goodbye.")
	logger.close()
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		console.stop()
		get_tree().quit(0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		shutdown("interrupted")

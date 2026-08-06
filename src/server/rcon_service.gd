class_name RconService
extends Node
## A remote console: the same commands, over TCP, for an operator who is not
## sitting at the machine.
##
## The protocol is lines of text on purpose, so that `nc host 24566` is a working
## client and nobody has to be given a tool to administer their own server:
##
##   → AUTH <password>          first line, always
##   ← OK <server name>         or  DENIED  followed by the socket closing
##   → <any command>
##   ← ...output...
##   ← --END ok                 or  --END error
##
## **It listens on 127.0.0.1 by default and that is not timidity.** One password
## on an open TCP port stands between a stranger and `server stop`, `account role
## <them> owner`, and every other command there is. The documented way to reach
## it from elsewhere is an SSH tunnel, which moves the authentication to
## something built for it. `rcon/bind_address` will happily be changed by an
## operator who has read that and decided otherwise.

## Anything longer is not a command. Commands are read a line at a time, so this
## is only a guard against a peer that opens a socket and never sends a newline.
const MAX_LINE: int = 4096
## How long an unauthenticated socket may stay open. A password guesser gets one
## attempt per connection and this long to make it.
const AUTH_GRACE: float = 10.0

class Session extends RefCounted:
	var stream: StreamPeerTCP
	var address: String = ""
	var authenticated: bool = false
	var opened_at: float = 0.0
	var last_seen: float = 0.0
	var buffer: String = ""

var server: PitServer

var _listener: TCPServer
var _sessions: Array[Session] = []
## Failed authentications per address: three tries a minute, then silence.
var _limit: RateLimiter = RateLimiter.make(0.05, 3.0)


func _ready() -> void:
	if not server.settings.get_bool("rcon/enabled"):
		return
	if server.settings.get_text("rcon/password") == "":
		server.logger.warn("rcon", "enabled but no password is set — refusing to "
			+ "listen. Set rcon/password in server.cfg.")
		return
	_listen()


func _listen() -> void:
	_listener = TCPServer.new()
	var bind := server.settings.get_text("rcon/bind_address")
	var port := server.settings.get_int("rcon/port")
	var err := _listener.listen(port, bind)
	if err != OK:
		server.logger.error("rcon", "could not listen on %s:%d — %s"
			% [bind, port, error_string(err)])
		_listener = null
		return
	server.logger.info("rcon", "remote console on %s:%d%s" % [bind, port,
		"" if bind == "127.0.0.1" else "  ← REACHABLE FROM OUTSIDE THIS MACHINE"])


func stop() -> void:
	for session in _sessions:
		session.stream.disconnect_from_host()
	_sessions.clear()
	if _listener != null:
		_listener.stop()
		_listener = null


func session_count() -> int:
	return _sessions.size()


## Called from the server's slow tick — see AuthService.prune for why a limiter
## keyed on a stranger's address has to be.
func prune() -> void:
	_limit.prune()


func _process(_delta: float) -> void:
	if _listener == null:
		return
	_accept_new()
	_pump_sessions()


func _accept_new() -> void:
	while _listener.is_connection_available():
		var stream := _listener.take_connection()
		if stream == null:
			return
		if _sessions.size() >= server.settings.get_int("rcon/max_sessions"):
			stream.put_data("BUSY\n".to_utf8_buffer())
			stream.disconnect_from_host()
			continue
		var session := Session.new()
		session.stream = stream
		session.address = stream.get_connected_host()
		session.opened_at = Time.get_ticks_msec() / 1000.0
		session.last_seen = session.opened_at
		_sessions.append(session)
		server.logger.info("rcon", "connection from %s" % session.address)


func _pump_sessions() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var idle := server.settings.get_float("rcon/idle_timeout_seconds")
	for session in _sessions.duplicate():
		session.stream.poll()
		if session.stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_close(session, "")
			continue
		if not session.authenticated and now - session.opened_at > AUTH_GRACE:
			_close(session, "TIMEOUT")
			continue
		if session.authenticated and now - session.last_seen > idle:
			_close(session, "IDLE")
			continue
		_read(session)


func _read(session: Session) -> void:
	var available := session.stream.get_available_bytes()
	if available <= 0:
		return
	var chunk: Array = session.stream.get_data(available)
	if chunk[0] != OK:
		_close(session, "")
		return
	session.buffer += (chunk[1] as PackedByteArray).get_string_from_utf8()
	if session.buffer.length() > MAX_LINE:
		_close(session, "LINE TOO LONG")
		return
	session.last_seen = Time.get_ticks_msec() / 1000.0
	while session.buffer.contains("\n"):
		var split := session.buffer.find("\n")
		var line := session.buffer.substr(0, split).strip_edges()
		session.buffer = session.buffer.substr(split + 1)
		if line != "":
			_handle(session, line)


func _handle(session: Session, line: String) -> void:
	if not session.authenticated:
		_authenticate(session, line)
		return
	if line.to_lower() in ["quit", "exit", "logout"]:
		_close(session, "BYE")
		return
	var caller := server.run_command(CommandCaller.for_rcon(session.address), line)
	_write(session, caller.output())
	_write(session, "--END %s" % ("error" if caller.failed else "ok"))


func _authenticate(session: Session, line: String) -> void:
	if not line.to_upper().begins_with("AUTH "):
		_write(session, "DENIED")
		_close(session, "")
		return
	if not _limit.allow(session.address):
		server.logger.warn("rcon", "%s is guessing the password" % session.address)
		_write(session, "DENIED")
		_close(session, "")
		return
	var offered := line.substr(5).strip_edges()
	var expected := server.settings.get_text("rcon/password")
	if not NetCrypto.equal(offered.to_utf8_buffer(), expected.to_utf8_buffer()):
		server.logger.warn("rcon", "wrong password from %s" % session.address)
		_write(session, "DENIED")
		_close(session, "")
		return
	session.authenticated = true
	server.logger.info("rcon", "%s authenticated" % session.address)
	_write(session, "OK %s — %s" % [
		server.settings.get_text("server/name"), server.status_line()])
	_write(session, "--END ok")


func _write(session: Session, text: String) -> void:
	if session.stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		session.stream.put_data(("%s\n" % text).to_utf8_buffer())


func _close(session: Session, farewell: String) -> void:
	if farewell != "":
		_write(session, farewell)
	session.stream.disconnect_from_host()
	_sessions.erase(session)

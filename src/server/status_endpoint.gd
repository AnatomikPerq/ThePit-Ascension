class_name StatusEndpoint
extends Node
## One line of JSON to anybody who asks, then the socket closes.
##
## For uptime monitoring, a website that wants to show whether the server is up,
## and a server browser if one is ever built. Deliberately not part of the game
## protocol: a monitor should not have to speak ENet, complete an authentication
## handshake or match the build, and this way it does not.
##
## It is **read-only and unauthenticated**, which is why what it says is
## carefully chosen. Player names are off by default (`status/show_player_names`)
## — who is playing right now is not something an anonymous port should tell —
## and there is no version of this that accepts input, so there is nothing here
## to inject into.

const MAX_PENDING: int = 16

var server: PitServer

var _listener: TCPServer
var _pending: Array[StreamPeerTCP] = []


func _ready() -> void:
	if not server.settings.get_bool("status/enabled"):
		return
	_listener = TCPServer.new()
	var bind := server.settings.get_text("status/bind_address")
	var port := server.settings.get_int("status/port")
	var err := _listener.listen(port, bind)
	if err != OK:
		server.logger.error("status", "could not listen on %s:%d — %s"
			% [bind, port, error_string(err)])
		_listener = null
		return
	server.logger.info("status", "status endpoint on %s:%d" % [bind, port])


func stop() -> void:
	for stream in _pending:
		stream.disconnect_from_host()
	_pending.clear()
	if _listener != null:
		_listener.stop()
		_listener = null


func _process(_delta: float) -> void:
	if _listener == null:
		return
	while _listener.is_connection_available() and _pending.size() < MAX_PENDING:
		var stream := _listener.take_connection()
		if stream != null:
			_pending.append(stream)
	for stream in _pending.duplicate():
		stream.poll()
		if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_pending.erase(stream)
			continue
		# Answer immediately without reading a request. A monitor that sends an
		# HTTP GET, a monitor that sends nothing and a raw TCP probe all get the
		# same answer, and nothing this endpoint does depends on input.
		stream.put_data(("%s\n" % JSON.stringify(payload())).to_utf8_buffer())
		stream.disconnect_from_host()
		_pending.erase(stream)


func payload() -> Dictionary:
	var settings := server.settings
	var out := {
		"name": settings.get_text("server/name"),
		"description": settings.get_text("server/description"),
		"address": settings.get_text("server/public_address"),
		"port": settings.get_int("network/port"),
		"tags": Array(settings.get_list("server/tags")),
		"protocol": NetProtocol.VERSION,
		"content": NetProtocol.content_hash(),
		"auth": settings.get_text("auth/mode"),
		"players": server.peers.size(),
		"max_players": settings.get_int("network/max_players"),
		"rooms": _rooms(),
		"uptime_seconds": int(server.uptime_seconds()),
	}
	if settings.get_bool("status/show_player_names"):
		out["player_names"] = _names()
	return out


func _rooms() -> Array:
	var out: Array = []
	for room_id in server.rooms.rooms:
		var room: Room = server.rooms.rooms[room_id]
		out.append({
			"name": room.name,
			"mode": Room.mode_name(room.mode),
			"state": Room.state_name(room.state),
			"players": room.climbers().size(),
			"max_players": room.max_players,
			"locked": room.locked(),
		})
	return out


func _names() -> Array:
	var out: Array = []
	for peer_id in server.peers:
		out.append(server.peers[peer_id].name_text())
	return out

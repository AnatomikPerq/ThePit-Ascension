class_name HttpListener
extends Node
## A very small HTTP/1.1 server: enough to answer a game client's `HTTPRequest`,
## a curl on somebody's laptop, and an nginx in front doing TLS.
##
## Godot ships an HTTP *client* and no server, so this is hand-rolled — and
## because it is hand-rolled and faces the open internet, what it refuses matters
## more than what it serves. Every one of these is a limit somebody would
## otherwise find: a ceiling on the request line, on the headers, on the body, on
## how many connections may be in flight at once, and a deadline after which a
## connection that has sent nothing is closed. A socket that is opened and left
## silent is the cheapest denial of service there is, and the only defence is to
## stop waiting.
##
## Every response closes the connection. No keep-alive, no pipelining, no chunked
## bodies: one request, one answer, one socket. The traffic here is a handful of
## announces a minute and a browser refresh, and every feature past that is a way
## to be surprised by a stranger.
##
## TLS is deliberately NOT here. A directory that matters is behind nginx or
## Caddy, which do it properly and renew the certificate; one that does not is
## on a local network. Half a TLS implementation would be worse than neither.

## `func(request: Dictionary) -> Array` returning [status_code, body_dictionary].
## The request carries method, path, query, body, address and headers.
var handler: Callable

var max_pending: int = 32
var max_request_bytes: int = 32768
var request_timeout: float = 8.0
## Read the caller's address out of X-Forwarded-For. Only turn this on when
## something you control is in front: any client can send the header, so trusting
## it on a directly-exposed port is trusting a stranger about who they are.
var trust_forwarded: bool = false

var _listener: TCPServer
var _pending: Array[Conn] = []


class Conn:
	extends RefCounted
	var stream: StreamPeerTCP
	var buffer: PackedByteArray = PackedByteArray()
	var age: float = 0.0
	var address: String = ""


func listen(port: int, bind_address: String) -> Error:
	_listener = TCPServer.new()
	var err := _listener.listen(port, bind_address)
	if err != OK:
		_listener = null
	return err


func stop() -> void:
	for conn in _pending:
		conn.stream.disconnect_from_host()
	_pending.clear()
	if _listener != null:
		_listener.stop()
		_listener = null


func listening() -> bool:
	return _listener != null


func _process(delta: float) -> void:
	if _listener == null:
		return
	_accept()
	for conn in _pending.duplicate():
		conn.age += delta
		_advance(conn)


func _accept() -> void:
	while _listener.is_connection_available():
		var stream := _listener.take_connection()
		if stream == null:
			return
		if _pending.size() >= max_pending:
			# Full. Refused immediately rather than queued: a queue is the thing
			# being attacked when there is one.
			stream.disconnect_from_host()
			continue
		var conn := Conn.new()
		conn.stream = stream
		conn.address = stream.get_connected_host()
		_pending.append(conn)


func _advance(conn: Conn) -> void:
	conn.stream.poll()
	if conn.stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_close(conn)
		return
	if conn.age > request_timeout:
		_reply(conn, 408, {"error": "took too long to send a request"})
		return
	var available := conn.stream.get_available_bytes()
	if available > 0:
		conn.buffer.append_array(conn.stream.get_data(available)[1])
	if conn.buffer.size() > max_request_bytes:
		_reply(conn, 413, {"error": "request too large"})
		return
	if _complete(conn.buffer):
		_serve(conn)


## Has the whole request arrived? Headers end at a blank line; a body is however
## many bytes Content-Length promised.
static func _complete(buffer: PackedByteArray) -> bool:
	var text := buffer.get_string_from_utf8()
	var split := text.find("\r\n\r\n")
	if split < 0:
		return false
	var length := _content_length(text.substr(0, split))
	return buffer.size() >= split + 4 + length


static func _content_length(head: String) -> int:
	for line in head.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return maxi(0, int(line.get_slice(":", 1).strip_edges()))
	return 0


func _serve(conn: Conn) -> void:
	var request := _parse(conn.buffer.get_string_from_utf8())
	if request.is_empty():
		_reply(conn, 400, {"error": "unreadable request"})
		return
	request["address"] = _caller_address(conn, request.get("headers", {}))
	if not handler.is_valid():
		_reply(conn, 503, {"error": "not ready"})
		return
	var answer: Array = handler.call(request)
	var status := int(answer[0]) if answer.size() > 0 else 500
	var body: Dictionary = answer[1] if answer.size() > 1 else {}
	_reply(conn, status, body)


## Who is asking. The socket's own peer, unless something in front of us is
## trusted to have said who it was forwarding for — the first entry in
## X-Forwarded-For is the original client, and everything after it is a proxy.
func _caller_address(conn: Conn, headers: Dictionary) -> String:
	if not trust_forwarded:
		return conn.address
	var forwarded := str(headers.get("x-forwarded-for", "")).strip_edges()
	if forwarded == "":
		return conn.address
	return forwarded.get_slice(",", 0).strip_edges()


## Request line, headers, body. Returns {} for anything that does not look like
## HTTP at all, which is what a port scanner sends.
static func _parse(text: String) -> Dictionary:
	var split := text.find("\r\n\r\n")
	if split < 0:
		return {}
	var head := text.substr(0, split)
	var lines := head.split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() < 2:
		return {}
	var target := request_line[1]
	var query_at := target.find("?")
	var headers := {}
	for index in range(1, lines.size()):
		var colon := lines[index].find(":")
		if colon > 0:
			headers[lines[index].substr(0, colon).strip_edges().to_lower()] = \
				lines[index].substr(colon + 1).strip_edges()
	return {
		"method": request_line[0].to_upper(),
		"path": target if query_at < 0 else target.substr(0, query_at),
		"query": _query(target if query_at < 0 else target.substr(query_at + 1)),
		"headers": headers,
		"body": text.substr(split + 4),
	}


static func _query(text: String) -> Dictionary:
	var out := {}
	if text.contains("="):
		for pair in text.split("&", false):
			var equals := pair.find("=")
			if equals > 0:
				out[pair.substr(0, equals).uri_decode()] = pair.substr(equals + 1).uri_decode()
	return out


func _reply(conn: Conn, status: int, body: Dictionary) -> void:
	var payload := JSON.stringify(body)
	var head := PackedStringArray([
		"HTTP/1.1 %d %s" % [status, _phrase(status)],
		"Content-Type: application/json; charset=utf-8",
		"Content-Length: %d" % payload.to_utf8_buffer().size(),
		# The browser in the game does not need this, but a website that wants to
		# show the server list does, and refusing it would only mean somebody
		# proxying the same public data through their own box.
		"Access-Control-Allow-Origin: *",
		"Cache-Control: no-store",
		"Connection: close",
		"", "",
	])
	conn.stream.put_data(("\r\n".join(head) + payload).to_utf8_buffer())
	_close(conn)


const PHRASES := {
	200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
	408: "Request Timeout", 413: "Payload Too Large", 429: "Too Many Requests",
	503: "Service Unavailable",
}


static func _phrase(status: int) -> String:
	return str(PHRASES.get(status, "Internal Server Error"))


func _close(conn: Conn) -> void:
	conn.stream.disconnect_from_host()
	_pending.erase(conn)

class_name LanBeacon
extends Node
## Answers "is there a server here?" on the local network.
##
## One UDP socket, silent until somebody asks. A client broadcasts
## DirectoryProtocol.LAN_PROBE and every beacon that hears it replies to the
## sender with one packet describing its server — which is how a game on the
## same network as you appears in the browser with no directory, no account, no
## port forwarding and nothing typed.
##
## Request and response rather than the usual periodic broadcast, because a
## periodic broadcast is traffic on somebody's network for as long as their
## server is up, whether or not a single person is looking at a browser. This
## costs one packet each way, only when asked.
##
## It answers a *probe* and nothing else. The payload is built by whoever owns
## the beacon and is public information — the same facts the browser shows — so
## there is nothing here to leak and nothing to command. The only thing an
## attacker gets out of it is the knowledge that a game server is on this
## network, which they got from the port being open.

## `func() -> Dictionary` — what to say when asked. Called per probe rather than
## cached, so a reply carries the player count as it is now.
var payload: Callable

var port: int = DirectoryProtocol.LAN_PORT

var _udp: PacketPeerUDP
## Answering the same address more often than this is refused. A probe is cheap
## to send and the reply is bigger than the question, which is the shape of an
## amplification attack; this is what stops it being one.
var _limit: RateLimiter = RateLimiter.make(2.0, 8.0)


## Returns "" or the reason it could not listen. Failing is not fatal anywhere it
## is used: a machine already running one beacon simply has one, and the server
## is still perfectly reachable by address.
func start(on_port: int = DirectoryProtocol.LAN_PORT) -> String:
	stop()
	port = on_port
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(port, "*", DirectoryProtocol.LAN_MAX_BYTES * 8)
	if err != OK:
		_udp = null
		return "could not listen on UDP %d — %s" % [port, error_string(err)]
	return ""


func listening() -> bool:
	return _udp != null


## Called from the server's slow tick — see AuthService.prune. One entry per
## address that ever probed, on a socket anybody on the network may reach.
func prune() -> void:
	_limit.prune()


func stop() -> void:
	if _udp != null:
		_udp.close()
		_udp = null


func _process(_delta: float) -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var from := _udp.get_packet_ip()
		if packet.size() > DirectoryProtocol.LAN_MAX_BYTES:
			continue
		if packet.get_string_from_utf8().strip_edges() != DirectoryProtocol.LAN_PROBE:
			continue
		if not _limit.allow(from):
			continue
		_answer(from, _udp.get_packet_port())


func _answer(to: String, to_port: int) -> void:
	if not payload.is_valid():
		return
	var body: Dictionary = payload.call()
	_udp.set_dest_address(to, to_port)
	_udp.put_packet(("%s%s" % [DirectoryProtocol.LAN_REPLY,
		JSON.stringify(body)]).to_utf8_buffer())

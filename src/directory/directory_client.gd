class_name DirectoryClient
extends Node
## The half of the server that says "I am here" to a directory.
##
## An HTTP POST every minute or so with a description of this server. What makes
## it worth its own file rather than a timer in PitServer is what it does when
## the directory is not there: it backs off, exponentially, to ten minutes. A
## server whose directory has been down for a week must not still be trying every
## sixty seconds — and, more to the point, a directory coming back up must not be
## met by every server on earth at once.
##
## If a verification key is configured, the announce is signed with it. The
## secret is used and never sent; see DirectoryProtocol.canonical for what the
## signature covers and why that matters.
##
## Nothing here is required for a server to work. Announcing is off by default,
## a failed announce is a log line, and the only thing lost is a row in a
## browser.

## Doubling from the configured interval, capped here. Long enough that a
## permanently-misconfigured server is not noise, short enough that a directory
## restarted at lunchtime has its list back by the end of it.
const MAX_BACKOFF_SECONDS: float = 600.0

var server: PitServer
## Set by `configure()` from `directory/*`.
var enabled: bool = false
var interval: float = 60.0
var base_url: String = ""

## What the last announce came to, for `status` and the admin panel.
var last_result: String = "not announced yet"
var listed: bool = false
var badge: String = ""

var _http: HTTPRequest
var _since: float = 0.0
var _wait: float = 5.0
var _in_flight: bool = false
var _failures: int = 0


## Built in code rather than authored in a scene, for the same reason `Net` builds
## its ServerLink that way: this hangs off the server node, which a dedicated
## server creates from one line of the router, and there is no scene to author it
## into.
func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "Http"
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_answer)


func configure() -> void:
	var settings := server.settings
	enabled = settings.get_bool("directory/announce")
	interval = settings.get_float("directory/interval_seconds")
	base_url = DirectoryDef.resolve(settings.get_text("directory/url"))
	_wait = 5.0 # the first one goes out shortly after boot, not a minute later
	_since = 0.0
	if not enabled:
		last_result = "not announcing (directory/announce is off)"
		return
	if base_url == "":
		enabled = false
		last_result = "no directory to announce to — set directory/url"
		server.logger.warn("directory", last_result)
		return
	server.logger.info("directory", "announcing to %s every %ds%s" % [base_url,
		int(interval), "" if settings.get_text("directory/verify_id") == ""
		else " with verification key " + settings.get_text("directory/verify_id")])


func _process(delta: float) -> void:
	if not enabled or _in_flight:
		return
	_since += delta
	if _since < _wait:
		return
	_since = 0.0
	announce_now()


## Also the `announce` console command, so an operator who has just fixed a
## setting does not have to wait out the interval to find out whether it worked.
func announce_now() -> void:
	if base_url == "" or _in_flight:
		return
	var message := build_message()
	var body := JSON.stringify(message)
	var err := _http.request(DirectoryDef.url_for(base_url, DirectoryProtocol.PATH_ANNOUNCE),
		PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		_fail("could not start the request — %s" % error_string(err))
		return
	_in_flight = true


## Everything the directory is told. Public information: the same facts the
## status endpoint already serves to anybody who asks, plus the build, which is
## what lets the browser say "that server is on a different version" instead of
## letting the player find out by being refused.
func build_message() -> Dictionary:
	var settings := server.settings
	var message := {
		"game": String(NetProtocol.GAME_ID),
		"directory_protocol": DirectoryProtocol.VERSION,
		"protocol": NetProtocol.VERSION,
		"content": NetProtocol.content_hash(),
		"instance": server.instance_id(),
		"name": settings.get_text("server/name"),
		"description": settings.get_text("server/description"),
		"region": settings.get_text("server/region"),
		"tags": Array(settings.get_list("server/tags")),
		"address": settings.get_text("server/public_address"),
		"port": settings.get_int("network/port"),
		"players": server.peers.size(),
		"max_players": settings.get_int("network/max_players"),
		"rooms": server.rooms.count(),
		"rooms_running": server.rooms.running_count(),
		"auth": settings.get_text("auth/mode"),
		"registration": settings.get_bool("auth/allow_registration"),
		"verify_id": settings.get_text("directory/verify_id"),
		"stamp": int(Time.get_unix_time_from_system()),
		"nonce": NetCrypto.new_token(16),
	}
	var secret := settings.get_text("directory/verify_key")
	if message["verify_id"] != "" and secret != "":
		message["proof"] = DirectoryProtocol.sign_announce(message, secret)
	return message


func _on_answer(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("the directory did not answer (result %d)" % result)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var answer: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if code != 200:
		_fail("%d — %s" % [code, str(answer.get("error", "refused"))])
		return
	_failures = 0
	_wait = interval
	listed = true
	badge = str(answer.get("badge", ""))
	last_result = "listed as %s%s" % [str(answer.get("listed_as", "?")),
		"" if badge == "" else " · " + DirectoryProtocol.badge_label(badge)]
	# A refusal of the BADGE while the listing itself succeeded is the one thing
	# here worth waking an operator for: the server is fine and the key is not.
	var complaint := str(answer.get("reason", ""))
	if complaint != "":
		server.logger.warn("directory", "listed, but the verification key was "
			+ "refused: %s" % complaint)
	else:
		server.logger.debug("directory", last_result)


func _fail(reason: String) -> void:
	listed = false
	_failures += 1
	last_result = reason
	_wait = minf(interval * pow(2.0, mini(_failures, 8)), MAX_BACKOFF_SECONDS)
	# Once loudly, then quietly. A directory that has been down all night should
	# not have filled the log with the same sentence six hundred times.
	if _failures <= 1:
		server.logger.warn("directory", "%s — retrying in %ds" % [reason, int(_wait)])
	else:
		server.logger.debug("directory", "%s — retrying in %ds" % [reason, int(_wait)])

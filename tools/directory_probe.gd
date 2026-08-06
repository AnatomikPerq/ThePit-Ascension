extends Node
## A real client's browser, against a real directory and a real server.
##
## `tools/run_directory_probe.sh` starts three processes: the directory, a
## dedicated server announcing to it with a verification key, and this. Nothing
## is stubbed — the HTTP is HTTP, the UDP probe goes out on the wire, and the
## screen under test is the actual MultiplayerMenu scene rather than a harness
## that resembles it.
##
## What it proves, and why each one needs three processes:
##
##   * the announce → listing → browser chain end to end, including the badge,
##     which no single process can check because the badge is one program's
##     decision about another's claim;
##   * that the badge arriving is the one the DIRECTORY issued — the server's
##     own claim to it is stripped before it is ever sent;
##   * that the same server is also found by shouting on the local network, with
##     the directory taken out of the path entirely;
##   * and that both answers merge into ONE row, because they are one server.

## The browser is asked once and then watched: the directory answers over HTTP
## and the local network answers over UDP, and neither is synchronous.
const PATIENCE_SECONDS: float = 20.0

var server_port: int = 25920
var expect_badge: String = DirectoryProtocol.BADGE_OFFICIAL
var failures: int = 0

var _menu: Node


func _ready() -> void:
	_begin.call_deferred()


func _begin() -> void:
	# The Router frees current_scene on every swap and the menu's buttons call
	# it; running as the main scene would make that this probe. Same placeholder
	# trick as net_probe.gd and server_probe.gd, for the same reason.
	var placeholder := Node.new()
	placeholder.name = "ProbePlaceholder"
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder

	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--server-port" and index + 1 < args.size():
			server_port = int(args[index + 1])
	_run()


func _run() -> void:
	_menu = (load("res://scenes/ui/MultiplayerMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_menu)
	await _frames(10)

	var finder: ServerFinder = _menu.get_node(^"Finder")
	_say("directory url: %s" % finder.directory_url)
	_check(finder.directory_url != "", "the browser has a directory to ask")

	# The badge is the assertion that carries the whole chain: a server may not
	# claim one, a LAN answer may not carry one, so the only way it can be here
	# is the directory having checked the signature and put it there.
	var row := await _wait_for_badge(finder)
	_check(row != null, "the announced server reached the browser with its badge")
	if row != null:
		_say("listed %s:%d as '%s' badge=%s via=%d" % [row.address, row.port,
			row.name, row.badge, row.source])
		_check(row.badge == expect_badge,
			"it is the badge the directory issued (%s)" % expect_badge)
		_check(row.badge_note != "", "the badge has hover text for a player to read")
		_check(row.joinable(), "it is on this build, so the browser offers it")

	# And the same server found with the directory taken out of the path
	# entirely. This is what makes a LAN party work on a network with no way out.
	_check(finder.lan_answers() > 0, "a server answered a probe on this network")
	_check(_rows_for_our_server() == 1,
		"every answer about it merged into one row, not one per address")
	_finish()


## Wait for a row for our server carrying a badge. Polled rather than awaited on
## the signal: both sources emit `changed` more than once, the server announces
## on its own timer, and the row we want may be in the fourth emission.
func _wait_for_badge(finder: ServerFinder) -> DirectoryEntry:
	var waited := 0.0
	while waited < PATIENCE_SECONDS:
		for item: Variant in finder.entries():
			var entry: DirectoryEntry = item
			if entry.port == server_port and entry.verified():
				return entry
		if int(waited) % 4 == 3:
			finder.refresh()
		await _frames(30)
		waited += 0.5
	return null


func _rows_for_our_server() -> int:
	var found := 0
	for child in _menu.get_node(^"UI/Body/Scroll/List").get_children():
		if child.entry != null and child.entry.port == server_port:
			found += 1
	return found


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(passed: bool, what: String) -> void:
	if passed:
		_say("ok   %s" % what)
	else:
		failures += 1
		print("PROBE FAIL %s" % what)


func _say(text: String) -> void:
	print("PROBE %s" % text)


func _finish() -> void:
	print("PROBE done — %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)

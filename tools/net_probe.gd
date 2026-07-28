extends Node
## Two-instance network probe. Run once as host, once as client:
##
##   godot --headless --path . tools/net_probe.tscn -- host [port]
##   godot --headless --path . tools/net_probe.tscn -- client [port]
##
## The host waits for the client, starts a CO-OP session with a FIXED seed,
## lets the world run, then checks the things multiplayer stands on. Both
## sides print `PROBE <name> <value>` lines; tools/run_net_probe.sh starts
## both and compares.
##
## Checked end to end, over a real ENet socket:
##   world_hash    — both machines built identical geometry from the seed
##   avatars       — both machines have both avatars, right authorities
##   enemies       — the host spawned, the client's spawner mirrored
##   score         — a host-credited kill reached the client's run mirror

const FIXED_SEED: int = 20260728
## Process frames to let the run live. At max_fps 144 this is ~3.3 s, safely
## past the first 2.0 s spawn interval.
const RUN_FRAMES: int = 480

var _role: String = "host"
var _port: int = 24565
var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# The Router frees current_scene on every swap, and when this probe runs
	# as the main scene, current_scene is the probe itself — the swap into the
	# world would kill the probe mid-await. Hand the Router a placeholder and
	# survive as a plain child of root, the way state_probe does.
	var placeholder := Node.new()
	placeholder.name = "ProbePlaceholder"
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_role = args[0]
	if args.size() > 1:
		_port = int(args[1])

	if _role == "host":
		await _run_host()
	else:
		await _run_client()


func _run_host() -> void:
	if Net.host(_port) != OK:
		_fail_now("host: could not open port %d" % _port)
		return
	print("PROBE hosting %d" % _port)

	# Wait for the client to connect.
	for i in 1200:
		await get_tree().process_frame
		if multiplayer.get_peers().size() > 0:
			break
	if multiplayer.get_peers().is_empty():
		_fail_now("host: no client connected")
		return

	# Give the client a beat to settle, then start the shared run.
	for i in 30:
		await get_tree().process_frame
	Net.start_session(Net.Mode.COOP, FIXED_SEED)

	if not await _await_world():
		_fail_now("host: never entered the world")
		return
	await _probe_world()

	# One authoritative kill credited to the client; its machine must see it.
	var client_peer: int = multiplayer.get_peers()[0]
	Game.enemy_killed(Vector2(1000, 7000), 100, Color.WHITE, client_peer)
	for i in 60:
		await get_tree().process_frame
	_expect_eq("score_p%d" % client_peer, Game.run_of(client_peer).score, 100)

	# Hold the session open until the client has finished its checks.
	for i in 300:
		await get_tree().process_frame
	_finish()


func _run_client() -> void:
	if Net.join("127.0.0.1", _port) != OK:
		_fail_now("client: join failed")
		return

	# The host's start_session swaps us into the world.
	if not await _await_world():
		_fail_now("client: never entered the world")
		return

	await _probe_world()

	# The kill the host credits to us must land in our run mirror.
	var deadline := 600
	while deadline > 0 and (Game.local_run() == null or Game.local_run().score < 100):
		deadline -= 1
		await get_tree().process_frame
	_expect_eq("score_p%d" % Game.local_peer_id, Game.local_run().score, 100)
	_finish()


func _await_world() -> bool:
	for i in 2400:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.name == "World":
			return true
	return false


## Shared checks, run inside the live world on both machines.
func _probe_world() -> void:
	var world := get_tree().current_scene
	_expect_eq("seed", world.world_seed, FIXED_SEED)
	print("PROBE world_hash %s" % _geometry_hash(world.get_node("Platforms")))

	# Both avatars, each owned by the right peer.
	for i in RUN_FRAMES:
		await get_tree().process_frame
	var avatars: Dictionary = world.players
	_expect_eq("avatar_count", avatars.size(), 2)
	for peer_id in avatars:
		if is_instance_valid(avatars[peer_id]):
			_expect_eq("authority_p%d" % peer_id,
				avatars[peer_id].get_multiplayer_authority(), peer_id)

	# The host spawns enemies; the client's MultiplayerSpawner mirrors them.
	var enemies := world.get_node("Enemies").get_child_count()
	print("PROBE enemies %d" % enemies)
	if enemies == 0:
		_failures.append("no enemies after %d frames" % RUN_FRAMES)


func _geometry_hash(platforms: Node) -> String:
	var rects: Array[String] = []
	for shape in _shapes(platforms):
		var rect := shape.shape as RectangleShape2D
		if rect == null:
			continue
		var origin := shape.global_transform.origin - rect.size * 0.5
		rects.append("%.4f,%.4f,%.4f,%.4f" % [origin.x, origin.y, rect.size.x, rect.size.y])
	rects.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for line in rects:
		ctx.update(line.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _shapes(root: Node) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	for child in root.get_children():
		var shape := child as CollisionShape2D
		if shape:
			out.append(shape)
		out.append_array(_shapes(child))
	return out


func _expect_eq(what: String, got: Variant, wanted: Variant) -> void:
	print("PROBE %s %s" % [what, got])
	if got != wanted:
		_failures.append("%s: got %s, wanted %s" % [what, got, wanted])


func _fail_now(reason: String) -> void:
	_failures.append(reason)
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PROBE %s PASSED" % _role)
		get_tree().quit(0)
		return
	print("PROBE %s FAILED" % _role)
	for f in _failures:
		print("  x ", f)
	get_tree().quit(1)

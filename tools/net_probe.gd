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
##   restart       — the host restarts the session and both machines land in
##                   the SAME new world, without anyone rejoining
##   race          — rivals are solid, each machine watches only its own hurt
##                   box, and a client's strike costs the host a heart

const FIXED_SEED: int = 20260728
const RACE_SEED: int = 20260729
## Process frames to let the run live. At max_fps 144 this is ~3.3 s, safely
## past the first 2.0 s spawn interval.
const RUN_FRAMES: int = 480

var _role: String = "host"
var _port: int = 24565
var _failures: Array[String] = []
## Host side: the client has finished the checks that a restart would wipe.
## The restart resets every run's score, so this is a barrier, not politeness.
var _client_done: bool = false
## Client side: the host has finished asserting our score, so we may climb.
## Climbing earns milestone and zone points, which would otherwise land on the
## host mid-assertion and make the expected 100 into 850.
var _host_done: bool = false


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
	_host_checkpoint.rpc_id(client_peer)

	# Wait for the client to reach the same point before wiping the run.
	for i in 1200:
		await get_tree().process_frame
		if _client_done:
			break
	if not _client_done:
		_failures.append("host: client never reached the restart barrier")

	var old_seed: int = get_tree().current_scene.world_seed
	Net.restart_session()
	await _probe_race(await _probe_restart(old_seed))

	# Hold the session open until the client has finished its checks.
	for i in 120:
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

	# The host has to be done reading our score before we go earn more of it.
	for i in 600:
		await get_tree().process_frame
		if _host_done:
			break
	if not _host_done:
		_failures.append("client: the host never released the score barrier")

	# Climb past the first upgrade milestone before the restart. The point is
	# what the host is still hearing about us when the new run starts: our
	# avatar node has the same path in every run, so position packets from the
	# run we just left land on the fresh puppet. Read as progress, they earn a
	# free upgrade at the bottom of the new pit — and a player near the surface
	# would end the fresh run on the spot.
	var world := get_tree().current_scene
	var mine: CharacterBody2D = world.players[Game.local_peer_id]
	var fractions: Array = world.profile.upgrade_fractions
	var above_first_upgrade: float = world.max_depth * float(fractions[0]) - 1000.0
	for i in 60:
		await get_tree().process_frame
		mine.global_position.y = above_first_upgrade
	print("PROBE climbed_to %d" % int(mine.global_position.y))

	# Everything a restart would wipe has been checked; let the host restart.
	var old_seed: int = get_tree().current_scene.world_seed
	_client_checkpoint.rpc_id(1)
	await _probe_race(await _probe_restart(old_seed))
	_finish()


## The host pressed restart. Nobody rejoins, nobody reloads by hand: a brand
## new world with a brand new seed arrives on both machines, and it is the
## same world on both. Returns the new seed, 0 if it never came.
func _probe_restart(old_seed: int) -> int:
	var new_seed := await _await_new_world(old_seed)
	if new_seed == 0:
		_failures.append("%s: the session never restarted" % _role)
		return 0
	var scene := get_tree().current_scene
	print("PROBE restart_seed %d" % new_seed)
	print("PROBE restart_hash %s" % _geometry_hash(scene.get_node("Platforms")))
	print("PROBE restart_players %d" % scene.players.size())
	if scene.players.size() != 2:
		_failures.append("restart: %d avatars, wanted 2" % scene.players.size())

	# A fresh run starts at the bottom, playing, with nothing unlocked and
	# nothing on offer. Anything else means progress leaked across the restart.
	for i in 180:
		await get_tree().process_frame
	print("PROBE restart_state %d" % scene.state)
	print("PROBE restart_menu %s" % scene.upgrade_menu.visible)
	if scene.state != scene.GameState.PLAYING:
		_failures.append("%s: the fresh run is in state %d, not PLAYING" % [_role, scene.state])
	if scene.upgrade_menu.visible:
		_failures.append("%s: the fresh run opened an upgrade menu at the bottom" % _role)
	return new_seed


## Race mode, the part a single instance can never check: solidity and hit
## resolution are per-machine decisions, and one machine always agrees with
## itself. The client walks up to the host's avatar and punches it; the heart
## has to come off on the HOST's machine, because the victim owns its damage.
func _probe_race(prev_seed: int) -> void:
	if _role == "host":
		Net.start_session(Net.Mode.RACE, RACE_SEED)
	if await _await_new_world(prev_seed) == 0:
		_failures.append("%s: never entered the race" % _role)
		return

	var world := get_tree().current_scene
	_expect_eq("versus", Net.is_versus(), true)

	var mine: CharacterBody2D = world.players[Game.local_peer_id]
	var rival: CharacterBody2D = null
	for peer_id in world.players:
		if peer_id != Game.local_peer_id:
			rival = world.players[peer_id]
	if not is_instance_valid(mine) or not is_instance_valid(rival):
		_failures.append("%s: race world is missing an avatar" % _role)
		return

	_expect_eq("solid_to_rivals", mine.get_collision_mask_value(Layers.BIT_PLAYER), true)
	_expect_eq("watches_own_hurtbox", mine.hurt_box.monitoring, true)
	_expect_eq("ignores_rival_hurtbox", rival.hurt_box.monitoring, false)

	if _role == "client":
		# Our machine owns where we stand, so we can walk into range; the
		# strike spawns on every machine and lands wherever the host sees us.
		for i in 30:
			await get_tree().process_frame
			mine.global_position = rival.global_position - Vector2(52, 0)
		mine._spawn_strike.rpc()
		print("PROBE struck_rival 1")
		for i in 240:
			await get_tree().process_frame
		return

	for i in 600:
		await get_tree().process_frame
		if mine.health < 5:
			break
	_expect_eq("health_after_rival_strike", mine.health, 4)


## Wait for a World whose seed is not `prev_seed`. Returns its seed, or 0.
func _await_new_world(prev_seed: int) -> int:
	for i in 2400:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.name == "World" and scene.world_seed != prev_seed:
			return scene.world_seed
	return 0


@rpc("any_peer", "call_remote", "reliable")
func _client_checkpoint() -> void:
	_client_done = true


@rpc("any_peer", "call_remote", "reliable")
func _host_checkpoint() -> void:
	_host_done = true


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


## The world's LAYOUT, not this frame's picture of it.
##
## A moving platform's live position is a function of how many physics ticks
## its own machine has run since building the world, and two peers never enter
## a world on exactly the same tick — so those shapes are folded back to the
## position they were authored at. Everything else is static and hashes as it
## stands. The result matches tools/world_fingerprint.gd, which hashes a world
## that has never been stepped.
func _geometry_hash(platforms: Node) -> String:
	var rects: Array[String] = []
	_collect_rects(platforms, Vector2.ZERO, rects)
	rects.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for line in rects:
		ctx.update(line.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _collect_rects(node: Node, correction: Vector2, out: Array[String]) -> void:
	var mover := node as MovingPlatform
	if mover != null:
		correction = mover.start_position() - mover.global_position
	var shape := node as CollisionShape2D
	if shape != null:
		var rect := shape.shape as RectangleShape2D
		if rect != null:
			var origin := shape.global_transform.origin + correction - rect.size * 0.5
			out.append("%.4f,%.4f,%.4f,%.4f" % [origin.x, origin.y, rect.size.x, rect.size.y])
	for child in node.get_children():
		_collect_rects(child, correction, out)


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

class_name MovementGuard
extends Node
## A tripwire on avatar movement, and an honest account of what it is not.
##
## **Movement in this game is client-authoritative and stays that way.** Each
## avatar is simulated by the machine of the player steering it and mirrored to
## everyone else (docs/NETWORKING.md, "one-peer mirror"). That is what keeps
## somebody else's lag off your controls, and rewriting it into server-
## authoritative movement with prediction and reconciliation would change how the
## game feels to every player in order to inconvenience a cheat.
##
## So this is not a wall. It is a tripwire: it notices an avatar reporting a
## position it could not have reached, and does what the operator asked — log it,
## warn the player, or disconnect them. What it catches is speed hacks, teleports
## and flying outside the shaft, which is most of what a modified client actually
## does. What it does not catch is somebody moving legally but faster than a human
## could react, and nothing here pretends otherwise.
##
## The thresholds are deliberately loose. A false positive costs a real player
## their run on a bad connection, and that is a worse outcome than a cheat
## getting a few more seconds — `protection/violations_before_action` exists so
## that a single hiccup is never enough.

## How often positions are sampled. Not every frame: an avatar's position arrives
## on the synchronizer's own schedule, so sampling faster than it updates
## measures the network rather than the player.
const SAMPLE_SECONDS: float = 0.25

## The fastest a climber can legally travel: the dash-down speed, which is the
## largest number in player.gd by some distance. Everything else — running,
## falling at terminal velocity, a trampoline, a blast — is below it.
const FASTEST_LEGAL: float = 3600.0

var server: PitServer

var _accumulated: float = 0.0
## peer -> [position, seconds]. Separate from ServerPeer.last_position because a
## peer may pass through several rooms and each has its own coordinate history.
var _seen: Dictionary[int, Array] = {}


func forget(peer_id: int) -> void:
	_seen.erase(peer_id)


func _process(delta: float) -> void:
	if server.settings.get_text("protection/movement_guard") == "off":
		return
	_accumulated += delta
	if _accumulated < SAMPLE_SECONDS:
		return
	var elapsed := _accumulated
	_accumulated = 0.0
	for room_id in server.rooms.rooms:
		var room: Room = server.rooms.rooms[room_id]
		if room.running():
			_check_room(room, elapsed)


func _check_room(room: Room, elapsed: float) -> void:
	var world := room.world
	var profile: WorldProfile = world.profile
	var slack := server.settings.get_float("protection/bounds_slack_px")
	var max_speed := FASTEST_LEGAL * server.settings.get_float("protection/max_speed_factor")
	var max_step := server.settings.get_float("protection/max_step_px")

	for peer_id: int in world.players.keys():
		var avatar: Node2D = world.players[peer_id]
		if not is_instance_valid(avatar):
			continue
		var problem := _problem_with(avatar, peer_id, profile, world.max_depth,
			slack, max_speed, max_step, elapsed)
		_seen[peer_id] = [avatar.global_position, elapsed]
		if problem != "":
			_flag(peer_id, room, problem)


func _problem_with(avatar: Node2D, peer_id: int, profile: WorldProfile,
		max_depth: float, slack: float, max_speed: float, max_step: float,
		elapsed: float) -> String:
	var at := avatar.global_position
	if at.x < -slack or at.x > profile.world_width + slack:
		return "outside the shaft sideways (x=%d)" % int(at.x)
	if at.y > max_depth + slack or at.y < profile.camera_top_limit - slack:
		return "outside the shaft vertically (y=%d)" % int(at.y)

	var previous: Array = _seen.get(peer_id, [])
	if previous.is_empty():
		return ""
	var moved := at.distance_to(previous[0] as Vector2)
	if moved > max_step:
		return "moved %d px in one sample" % int(moved)
	if moved / maxf(elapsed, 0.001) > max_speed:
		return "travelling at %d px/s" % int(moved / maxf(elapsed, 0.001))
	return ""


func _flag(peer_id: int, room: Room, problem: String) -> void:
	var peer: ServerPeer = server.peers.get(peer_id)
	if peer == null:
		return
	var limit := server.settings.get_int("protection/violations_before_action")
	var decay := server.settings.get_float("protection/violation_decay_seconds")
	var crossed := peer.add_violation(limit, decay)
	server.logger.debug("guard", "%s in room %d: %s (%d/%d)"
		% [peer.name_text(), room.id, problem, peer.violations, limit])
	if not crossed:
		return
	peer.violations = 0
	_act(peer, problem)


func _act(peer: ServerPeer, problem: String) -> void:
	var action := server.settings.get_text("protection/movement_guard")
	server.logger.warn("guard", "%s tripped the movement guard: %s"
		% [peer.name_text(), problem])
	match action:
		"warn":
			server.hub_notice(peer.peer_id,
				"THE SERVER DOES NOT BELIEVE WHERE YOUR CLIMBER IS")
		"kick":
			server.kick(peer.peer_id, "the movement guard: %s" % problem)
		_:
			pass # "log" — the warning above is the whole action

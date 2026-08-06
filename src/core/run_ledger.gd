class_name RunLedger
extends Node
## The score, kills and combo of one run — one ledger per world, authored into
## World.tscn as `Run`.
##
## This used to live on the `Game` autoload, and moving it is the single change
## a dedicated server needed most. Two reasons, and the second is the one that
## actually forced it:
##
## 1. **State.** `new_run()` clears the table. With one world per process that is
##    correct; with a server running four rooms, the fourth room starting a climb
##    wiped the scores of the three already in progress.
## 2. **Address.** The score and kill events are `@rpc`s, and an RPC is addressed
##    by node path. On the autoload that path is `/root/Game` — one path shared by
##    every room on the socket, so room 3's kill was deliverable to room 1's
##    players. Inside the world it is `World3/Run`, a path that exists only for
##    the peers in that room, and the mistake stops being expressible.
##
## `Game` still answers the old questions (`Game.local_run()`, `Game.add_score()`)
## by forwarding to whichever ledger belongs to the world this machine is
## looking at — the same "the active scene registers itself" arrangement
## `Fx.effects_root` and `Audio.world_root` already use. A dedicated server looks
## at no world and registers none, so nothing on the server can reach for "the"
## run and silently get somebody else's.

signal score_changed(peer_id: int, score: int, combo: int)

const COMBO_WINDOW: float = 3.0
## Camera kick on a kill, and what each further step of the combo adds.
const KILL_SHAKE: float = 0.3
const KILL_SHAKE_PER_COMBO: float = 0.05
const KILL_SHAKE_MAX: float = 0.6
## Kills are broadcast, so their feedback fades over this distance. Without it
## every player's screen jumps for everybody else's fights, anywhere in the pit.
const KILL_FEEDBACK_RANGE: float = 2600.0

## Per-player run state for the current run, keyed by peer id.
var runs: Dictionary[int, PlayerRun] = {}
var run_start_ms: int = 0

var _kill_burst: BurstPreset


func _ready() -> void:
	# load, not a preload const: an autoload's preloads pin resources past
	# shutdown, and this node is reachable from one.
	_kill_burst = load("res://data/fx/kill.tres")


## The ledger a node's events belong to: its world's, or the local machine's
## when the node is under no world — which is every unit test that builds an
## enemy and a player under a bare Node2D.
static func of(node: Node) -> RunLedger:
	var walk := node
	while walk != null:
		if walk.is_in_group(NetSession.HOST_GROUP):
			var found: Variant = walk.get(&"run")
			if found != null:
				return found
		walk = walk.get_parent()
	return Game.ledger


## The room this ledger's events are addressed to. Resolved per call rather than
## cached, because a ledger under the Game autoload has no world above it until
## one registers.
func session() -> NetSession:
	return NetSession.of(self)


## Start a fresh run for the given peers. Empty means "just the local peer",
## which is what solo play and every test uses.
func new_run(peer_ids: Array[int] = []) -> void:
	runs.clear()
	var ids := peer_ids if not peer_ids.is_empty() else ([Game.local_peer_id] as Array[int])
	for id in ids:
		var run := PlayerRun.new()
		run.peer_id = id
		runs[id] = run
		score_changed.emit(id, 0, 0)
	run_start_ms = Time.get_ticks_msec()


func run_of(peer_id: int) -> PlayerRun:
	return runs.get(peer_id)


func local_run() -> PlayerRun:
	return runs.get(Game.local_peer_id)


func run_time_seconds() -> float:
	return float(Time.get_ticks_msec() - run_start_ms) / 1000.0


func run_time_text() -> String:
	var total := int(run_time_seconds())
	return "%d:%02d" % [total / 60, total % 60]


func _process(delta: float) -> void:
	for run in runs.values():
		if run.combo > 0:
			run.combo_time -= delta
			if run.combo_time <= 0.0:
				run.combo = 0
				score_changed.emit(run.peer_id, run.score, 0)


## Called by enemies when a player kills/converts them — only where the sim
## authority lives (solo, or the server). `killer_peer` 0 means "the local
## player". Chained kills within COMBO_WINDOW multiply the reward for that
## player only. In a session the resulting numbers are broadcast as an EVENT;
## every machine fires its own cosmetics from it.
func enemy_killed(pos: Vector2, base_points: int, color: Color, killer_peer: int = 0) -> void:
	if not Net.is_sim_authority():
		return # kills are the authority's call
	var run := run_of(killer_peer if killer_peer != 0 else Game.local_peer_id)
	if run == null:
		return
	run.kills += 1
	run.combo += 1
	run.max_combo = maxi(run.max_combo, run.combo)
	run.combo_time = COMBO_WINDOW
	var gained := base_points * run.combo
	run.score += gained
	score_changed.emit(run.peer_id, run.score, run.combo)
	_kill_feedback(pos, gained, run.combo, color)
	session().broadcast_remote(self, &"_remote_kill", [run.peer_id, pos, gained, color,
		run.score, run.kills, run.combo, run.max_combo])


## Everyone else mirrors the authority's numbers and fires local cosmetics.
@rpc("authority", "call_remote", "reliable")
func _remote_kill(peer_id: int, pos: Vector2, gained: int, color: Color,
		score: int, kills: int, combo: int, max_combo: int) -> void:
	var run := run_of(peer_id)
	if run == null:
		return
	run.score = score
	run.kills = kills
	run.combo = combo
	run.max_combo = max_combo
	run.combo_time = COMBO_WINDOW
	score_changed.emit(peer_id, run.score, run.combo)
	_kill_feedback(pos, gained, combo, color)


func _kill_feedback(pos: Vector2, gained: int, combo: int, color: Color) -> void:
	var text := "+%d" % gained
	if combo > 1:
		text += "  x%d" % combo
	Fx.popup(pos + Vector2(0, -50), text, color)
	Fx.burst(pos, _kill_burst, color, 14 + mini(combo * 2, 16))
	Fx.shake_from(pos, minf(KILL_SHAKE + combo * KILL_SHAKE_PER_COMBO, KILL_SHAKE_MAX),
		KILL_FEEDBACK_RANGE)
	Audio.play_at(&"kill", pos, clampf(0.9 + combo * 0.07, 0.9, 1.7))


## Flat score without combo (projectiles, milestones). `peer_id` 0 = local.
## Anyone who is not the authority routes through it, so its numbers stay the
## ones everybody ends up with.
func add_score(points: int, pos: Vector2 = Vector2.INF, color: Color = Color.WHITE,
		peer_id: int = 0) -> void:
	var target := peer_id if peer_id != 0 else Game.local_peer_id
	if not Net.is_sim_authority():
		rpc_id(1, &"_request_score", points, pos, color, target)
		return
	var run := run_of(target)
	if run == null:
		return
	run.score += points
	score_changed.emit(run.peer_id, run.score, run.combo)
	if pos != Vector2.INF:
		Fx.popup(pos + Vector2(0, -40), "+%d" % points, color, 24)
	session().broadcast_remote(self, &"_remote_score",
		[run.peer_id, run.score, run.combo, points, pos, color])


## A client may only ask for score on its own behalf, and only for a run this
## ledger is actually keeping — which, since the ledger lives inside the world,
## means only for a peer in this room.
@rpc("any_peer", "call_remote", "reliable")
func _request_score(points: int, pos: Vector2, color: Color, peer_id: int) -> void:
	if not Net.is_sim_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id or not runs.has(sender):
		return
	add_score(points, pos, color, peer_id)


@rpc("authority", "call_remote", "reliable")
func _remote_score(peer_id: int, score: int, combo: int, points: int,
		pos: Vector2, color: Color) -> void:
	var run := run_of(peer_id)
	if run == null:
		return
	run.score = score
	score_changed.emit(peer_id, score, combo)
	if pos != Vector2.INF:
		Fx.popup(pos + Vector2(0, -40), "+%d" % points, color, 24)

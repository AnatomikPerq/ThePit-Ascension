extends Node
## Game — autoload holding run state, one PlayerRun per peer. Enemies report
## kills here with the killer's peer id; the HUD listens to score_changed and
## shows the local peer's numbers. Solo play is a single run for peer 1.

signal score_changed(peer_id: int, score: int, combo: int)

const COMBO_WINDOW: float = 3.0
const SAVE_PATH := "user://thepit_save.cfg"
## Camera kick on a kill, and what each further step of the combo adds.
## CLAUDE.md §4 has said since the hitstop was removed that kill feedback is
## "screen shake, particles, the score popup and the sound" — the shake was
## the one of the four nobody actually wired up.
const KILL_SHAKE: float = 0.3
const KILL_SHAKE_PER_COMBO: float = 0.05
const KILL_SHAKE_MAX: float = 0.6
## Kills are broadcast, so their feedback fades over this distance. Without it
## every player's screen jumps for everybody else's fights, anywhere in the pit.
const KILL_FEEDBACK_RANGE: float = 2600.0

## Per-player run state for the current run, keyed by peer id.
var runs: Dictionary[int, PlayerRun] = {}
## The peer whose run this machine's HUD and end screens follow. 1 in solo
## and for a multiplayer host; the Net layer sets the real id on join.
var local_peer_id: int = 1
var best_score: int = 0
var run_start_ms: int = 0
var _kill_burst: BurstPreset


func _ready() -> void:
	# load, not a preload const: an autoload's preloads pin resources past
	# shutdown (same lesson as the sound bank).
	_kill_burst = load("res://data/fx/kill.tres")
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_score = cf.get_value("run", "best_score", 0)


## Start a fresh run for the given peers. Empty means "just the local peer",
## which is what solo play and every test uses.
func new_run(peer_ids: Array[int] = []) -> void:
	runs.clear()
	var ids := peer_ids if not peer_ids.is_empty() else ([local_peer_id] as Array[int])
	for id in ids:
		var run := PlayerRun.new()
		run.peer_id = id
		runs[id] = run
		score_changed.emit(id, 0, 0)
	run_start_ms = Time.get_ticks_msec()


func run_of(peer_id: int) -> PlayerRun:
	return runs.get(peer_id)


func local_run() -> PlayerRun:
	return runs.get(local_peer_id)


## Called once at the end of a run. Persists a new record for THIS machine's
## player. Returns true if the local run set a new best score.
func finish_run() -> bool:
	var run := local_run()
	if run == null or run.score <= best_score:
		return false
	best_score = run.score
	var cf := ConfigFile.new()
	cf.set_value("run", "best_score", best_score)
	cf.save(SAVE_PATH)
	return true


func _process(delta: float) -> void:
	for run in runs.values():
		if run.combo > 0:
			run.combo_time -= delta
			if run.combo_time <= 0.0:
				run.combo = 0
				score_changed.emit(run.peer_id, run.score, 0)


## Called by enemies when a player kills/converts them — only where the sim
## authority lives (solo, or the host). `killer_peer` 0 means "the local
## player". Chained kills within COMBO_WINDOW multiply the reward for that
## player only. In a session the resulting numbers are broadcast as an EVENT;
## every machine fires its own cosmetics from it.
func enemy_killed(pos: Vector2, base_points: int, color: Color, killer_peer: int = 0) -> void:
	if Net.active and not multiplayer.is_server():
		return # kills are the host's call
	var run := run_of(killer_peer if killer_peer != 0 else local_peer_id)
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
	if Net.is_host():
		_remote_kill.rpc(run.peer_id, pos, gained, color,
			run.score, run.kills, run.combo, run.max_combo)


## Clients mirror the host's authoritative numbers and fire local cosmetics.
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
## Clients route through the host so the host's numbers stay authoritative.
func add_score(points: int, pos: Vector2 = Vector2.INF, color: Color = Color.WHITE,
		peer_id: int = 0) -> void:
	var target := peer_id if peer_id != 0 else local_peer_id
	if Net.active and not multiplayer.is_server():
		_request_score.rpc_id(1, points, pos, color, target)
		return
	var run := run_of(target)
	if run == null:
		return
	run.score += points
	score_changed.emit(run.peer_id, run.score, run.combo)
	if pos != Vector2.INF:
		Fx.popup(pos + Vector2(0, -40), "+%d" % points, color, 24)
	if Net.is_host():
		_remote_score.rpc(run.peer_id, run.score, run.combo, points, pos, color)


## A client may only ask for score on its own behalf.
@rpc("any_peer", "call_remote", "reliable")
func _request_score(points: int, pos: Vector2, color: Color, peer_id: int) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
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


func run_time_seconds() -> float:
	return float(Time.get_ticks_msec() - run_start_ms) / 1000.0


func run_time_text() -> String:
	var total := int(run_time_seconds())
	return "%d:%02d" % [total / 60, total % 60]

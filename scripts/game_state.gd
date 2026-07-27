extends Node
## Game — autoload holding run state: score, combo chain, kill count and
## run timing. Enemies report kills here; the World HUD listens to signals.

signal score_changed(score: int, combo: int)

const COMBO_WINDOW: float = 3.0
const SAVE_PATH := "user://thepit_save.cfg"

var score: int = 0
var kills: int = 0
var combo: int = 0
var max_combo: int = 0
var best_score: int = 0
var run_start_ms: int = 0
var _combo_time: float = 0.0


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_score = cf.get_value("run", "best_score", 0)


## Called once at the end of a run. Persists a new record.
## Returns true if this run set a new best score.
func finish_run() -> bool:
	if score <= best_score:
		return false
	best_score = score
	var cf := ConfigFile.new()
	cf.set_value("run", "best_score", best_score)
	cf.save(SAVE_PATH)
	return true


func new_run() -> void:
	score = 0
	kills = 0
	combo = 0
	max_combo = 0
	_combo_time = 0.0
	run_start_ms = Time.get_ticks_msec()
	score_changed.emit(score, combo)


func _process(delta: float) -> void:
	if combo > 0:
		_combo_time -= delta
		if _combo_time <= 0.0:
			combo = 0
			score_changed.emit(score, combo)


## Called by enemies when the player kills/converts them.
## Chained kills within COMBO_WINDOW multiply the reward.
func enemy_killed(pos: Vector2, base_points: int, color: Color) -> void:
	kills += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	_combo_time = COMBO_WINDOW
	var gained := base_points * combo
	score += gained
	score_changed.emit(score, combo)

	var text := "+%d" % gained
	if combo > 1:
		text += "  x%d" % combo
	Fx.popup(pos + Vector2(0, -50), text, color)
	Fx.burst(pos, color, 14 + mini(combo * 2, 16))
	Fx.hitstop(0.045, 0.12)
	Sfx.play("kill", -6.0, clampf(0.9 + combo * 0.07, 0.9, 1.7))


## Flat score without combo (projectiles, milestones).
func add_score(points: int, pos: Vector2 = Vector2.INF, color: Color = Color.WHITE) -> void:
	score += points
	score_changed.emit(score, combo)
	if pos != Vector2.INF:
		Fx.popup(pos + Vector2(0, -40), "+%d" % points, color, 24)


func run_time_seconds() -> float:
	return float(Time.get_ticks_msec() - run_start_ms) / 1000.0


func run_time_text() -> String:
	var total := int(run_time_seconds())
	return "%d:%02d" % [total / 60, total % 60]

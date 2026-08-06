extends Node
## Game — autoload for what belongs to this MACHINE rather than to a run: the
## climber roster, the pick this machine plays, the best score it has ever set,
## and which peer it is.
##
## The run itself — score, kills, combo — moved out to `RunLedger`, a node inside
## each World. There is one per room, because a dedicated server hosts several
## runs at once and a single table keyed by nothing would have them overwriting
## each other (see RunLedger for the whole reasoning). What is left here is the
## facade: the active world registers its ledger and the old questions keep
## their old answers, exactly the way `Fx.effects_root` works.
##
## A dedicated server registers nothing, because it is looking at no world. That
## is deliberate: on a server, `Game.local_run()` has no correct answer, and it
## returning the fallback ledger's empty run is better than it returning some
## arbitrary room's.

signal score_changed(peer_id: int, score: int, combo: int)

const SAVE_PATH := "user://thepit_save.cfg"

## The peer whose run this machine's HUD and end screens follow. 1 in solo and
## for a peer-to-peer host; the Net layer sets the real id on join.
var local_peer_id: int = 1
var best_score: int = 0

## Every playable climber, in the order the select screen shows them.
var roster: CharacterRoster
## The climber this machine picked, remembered between sessions. Held as an id
## rather than a resource so an unknown one (a save from a build that had a
## character this one does not) simply falls back instead of failing to load.
var selected_character: StringName = &""

## The run this machine is watching. A World registers its own on entering the
## tree and puts this back on the way out — so between runs, and in every test
## that never builds a world, it is the standalone one below.
var ledger: RunLedger:
	set(value):
		if ledger == value:
			return
		if ledger != null and ledger.score_changed.is_connected(_relay_score):
			ledger.score_changed.disconnect(_relay_score)
		ledger = value if value != null else _fallback
		if ledger != null and not ledger.score_changed.is_connected(_relay_score):
			ledger.score_changed.connect(_relay_score)

## The ledger for code that is not inside a world: the unit suites that build an
## enemy and a player under a bare Node2D, and the probes. It is a real node so
## that combo decay still runs.
var _fallback: RunLedger


func _ready() -> void:
	roster = load("res://data/characters/roster.tres")
	_fallback = RunLedger.new()
	_fallback.name = "Run"
	add_child(_fallback)
	ledger = _fallback
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_score = cf.get_value("run", "best_score", 0)
		selected_character = StringName(cf.get_value("run", "character", ""))


func _relay_score(peer_id: int, score: int, combo: int) -> void:
	score_changed.emit(peer_id, score, combo)


## Put the facade back on the standalone ledger. A world calls this on its way
## out so that a freed ledger is never the one `Game.local_run()` answers from.
func release_ledger(leaving: RunLedger) -> void:
	if ledger == leaving:
		ledger = _fallback


# ── Character choice ────────────────────────────────────────────────────────
## The climber this machine plays. Never null while the roster has anybody in
## it, so callers do not have to have an opinion about a bad saved id.
func character_def() -> CharacterDef:
	return roster.resolve(selected_character)


## The id a peer is assumed to have picked when it never said. Used when a
## session roster is locked.
func default_character_id() -> StringName:
	var fallback := roster.fallback()
	return fallback.id if fallback != null else CharacterRoster.SPECTATOR


func select_character(id: StringName) -> void:
	if selected_character == id:
		return
	selected_character = id
	_save()


# ── The run, through whichever ledger is active ─────────────────────────────
var runs: Dictionary[int, PlayerRun]:
	get:
		return ledger.runs


func new_run(peer_ids: Array[int] = []) -> void:
	ledger.new_run(peer_ids)


func run_of(peer_id: int) -> PlayerRun:
	return ledger.run_of(peer_id)


func local_run() -> PlayerRun:
	return ledger.local_run()


func enemy_killed(pos: Vector2, base_points: int, color: Color, killer_peer: int = 0) -> void:
	ledger.enemy_killed(pos, base_points, color, killer_peer)


func add_score(points: int, pos: Vector2 = Vector2.INF, color: Color = Color.WHITE,
		peer_id: int = 0) -> void:
	ledger.add_score(points, pos, color, peer_id)


func run_time_seconds() -> float:
	return ledger.run_time_seconds()


func run_time_text() -> String:
	return ledger.run_time_text()


## Called once at the end of a run. Persists a new record for THIS machine's
## player. Returns true if the local run set a new best score.
func finish_run() -> bool:
	var run := local_run()
	if run == null or run.score <= best_score:
		return false
	best_score = run.score
	_save()
	return true


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("run", "best_score", best_score)
	cf.set_value("run", "character", String(selected_character))
	cf.save(SAVE_PATH)

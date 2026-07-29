extends SceneTree
## One-shot: writes data/enemies/*.tres from the constants the five enemy
## scripts carried inline before EnemyCombat existed.
##
##   godot --headless --path . -s tools/build_enemy_stats.gd
##
## Re-running OVERWRITES inspector edits. It exists so the origin of these
## numbers is traceable, not as part of the build.

const OUT_DIR := "res://data/enemies/"

# key: score, colour, requires_dash, rebound, stomp sound
const ENEMIES: Dictionary = {
	# Converts into a platform. Its own death reaction plays the petrification
	# thud, so the shared stomp sound is left empty.
	"golem": [50, Color(0.75, 0.72, 0.62), false, -600.0, ""],
	# Converts into a trampoline. Silent on stomp, as it always was.
	"slime": [75, Color(0.35, 0.90, 0.40), false, -700.0, ""],
	"pursuer": [150, Color(0.95, 0.35, 0.35), true, -900.0, "stomp"],
	"bat": [125, Color(0.75, 0.40, 0.95), true, -900.0, "stomp"],
	"spitter": [150, Color(0.50, 0.95, 0.30), true, -900.0, "stomp"],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for key: String in ENEMIES:
		var e: Array = ENEMIES[key]
		var stats := EnemyStats.new()
		stats.resource_name = key
		stats.score = int(e[0])
		stats.score_color = e[1]
		stats.requires_dash_to_stomp = bool(e[2])
		stats.stomp_rebound = float(e[3])
		stats.stomp_sound = StringName(e[4])
		var path := OUT_DIR + key + ".tres"
		var err := ResourceSaver.save(stats, path)
		if err != OK:
			push_error("failed to save %s (error %d)" % [path, err])
			quit(1)
			return
		print("wrote ", path)
	quit(0)

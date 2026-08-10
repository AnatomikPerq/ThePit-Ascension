extends SceneTree
## One-shot: builds the SpriteFrames resources that replace the frame-array
## animation state machines in player.gd, pursuer.gd and strike.gd.
##
##   godot --headless --path . -s tools/build_sprite_frames.gd
##
## Frame rates are derived from the millisecond delays those scripts used, so
## the animations play at exactly the old speed:
##   standing 300ms -> 3.333 fps, running 150ms -> 6.667 fps,
##   jumping/falling/attacking 100ms -> 10 fps, pursuer 200ms -> 5 fps,
##   strike 100ms -> 10 fps and does not loop (the old code clamped on the last
##   frame rather than wrapping).
##
## Re-running OVERWRITES the resources, losing inspector edits. It exists so the
## origin of these numbers is traceable, not as part of the build.
##
## Two entries in a spec are about art that is not drawn yet:
##
## - `optional` — a listed frame that is not on disk is skipped with a note
##   instead of failing the build, and an animation whose frames are all missing
##   is still created, empty. The animation exists in the resource and in the
##   inspector, the scenes already point at it, and dropping the next frame in
##   and re-running this is the entire job.
## - `fallback` — the same reservation, but for an animation that something
##   PLAYS. An empty clip would leave the sprite drawing nothing, so the listed
##   stand-in is used until the real frames exist. Every `died` clip is a
##   character's standing frame today, and Tessa swings with her standing frame
##   because her attack is not drawn yet.

const SPR := "res://assets/sprites/"

# name -> { fps, loop, frames[], dir?, optional?, fallback? }
const CYN := {
	"dir": "cyn/",
	"standing": {"fps": 1000.0 / 300.0, "loop": true,
		"frames": ["cyn_standing_1.png", "cyn_standing_2.png"]},
	"running": {"fps": 1000.0 / 150.0, "loop": true,
		"frames": ["cyn_running_1.png", "cyn_running_2.png", "cyn_running_3.png"]},
	"jumping": {"fps": 10.0, "loop": true, "frames": ["cyn_jumping_1.png"]},
	"falling": {"fps": 10.0, "loop": true, "frames": ["cyn_falling_1.png"]},
	"attacking": {"fps": 10.0, "loop": false,
		"frames": ["cyn_attacking_1.png", "cyn_attacking_2.png", "cyn_attacking_3.png"]},
	"died": {"fps": 1.0, "loop": true, "frames": ["cyn_died.png"]},
}

const TESSA := {
	"dir": "tessa/",
	"standing": {"fps": 1000.0 / 300.0, "loop": true,
		"frames": ["tessa_standing_1.png", "tessa_standing_2.png"]},
	"running": {"fps": 1000.0 / 150.0, "loop": true,
		"frames": ["tessa_running_1.png", "tessa_running_2.png", "tessa_running_3.png"]},
	"jumping": {"fps": 10.0, "loop": true, "frames": ["tessa_jumping_1.png"]},
	"falling": {"fps": 10.0, "loop": true, "frames": ["tessa_falling_1.png"]},
	"attacking": {"fps": 10.0, "loop": false, "frames": ["tessa_attacking_1.png"]},
	"shooting": {"fps": 14.0, "loop": false,
		"frames": ["tessa_shooting_1.png", "tessa_shooting_2.png"]},
	"died": {"fps": 1.0, "loop": true, "frames": ["tessa_died.png"]},
}

# Uzi. One drawing so far — everything else is a reserved slot standing in with
# it, which is what `optional` + `fallback` is for. Drop `uzi_running_1.png` in
# beside it, re-run this, and she runs; nothing else has to change.
#
# `aiming` and `shooting` are the two poses the railgun asks for by name (see
# Railgun.pose()). They stand in with `standing` too, so the weapon works before
# either is drawn — the gun itself is a separate sprite that rotates on top.
const UZI := {
	"dir": "uzi/",
	"standing": {"fps": 1000.0 / 300.0, "loop": true, "optional": true,
		"frames": ["uzi_standing_1.png", "uzi_standing_2.png"],
		"fallback": ["uzi_standing_1.png"]},
	"running": {"fps": 1000.0 / 150.0, "loop": true, "optional": true,
		"frames": ["uzi_running_1.png", "uzi_running_2.png", "uzi_running_3.png"],
		"fallback": ["uzi_standing_1.png"]},
	"jumping": {"fps": 10.0, "loop": true, "optional": true,
		"frames": ["uzi_jumping_1.png"], "fallback": ["uzi_standing_1.png"]},
	"falling": {"fps": 10.0, "loop": true, "optional": true,
		"frames": ["uzi_falling_1.png"], "fallback": ["uzi_standing_1.png"]},
	"attacking": {"fps": 10.0, "loop": false, "optional": true,
		"frames": ["uzi_attacking_1.png"], "fallback": ["uzi_standing_1.png"]},
	"aiming": {"fps": 10.0, "loop": true, "optional": true,
		"frames": ["uzi_aiming_1.png"], "fallback": ["uzi_standing_1.png"]},
	"shooting": {"fps": 14.0, "loop": false, "optional": true,
		"frames": ["uzi_shooting_1.png", "uzi_shooting_2.png"],
		"fallback": ["uzi_standing_1.png"]},
	"died": {"fps": 1.0, "loop": true, "optional": true,
		"frames": ["uzi_died.png"], "fallback": ["uzi_standing_1.png"]},
}

const PURSUER := {
	"walk": {"fps": 1000.0 / 200.0, "loop": true,
		"frames": ["pursuer_1.png", "pursuer_2.png"]},
}

# Cyn's strike is ONE drawing. What animates is the transform — it spins the
# whole time while growing out of nothing and shrinking back into it — and that
# is an AnimationPlayer clip on Strike.tscn, not a frame sequence.
const STRIKE := {
	"punch": {"fps": 1.0, "loop": false, "frames": ["punch_1.png"]},
}

# Tessa's blade. Five crescents sweeping from above her head down past her feet,
# at 22 fps, so the whole swing is over inside the 0.23 s the hitbox lives.
const SWORD := {
	"punch": {"fps": 22.0, "loop": false,
		"frames": ["sword_1.png", "sword_2.png", "sword_3.png",
			"sword_4.png", "sword_5.png"]},
}

# Golem swaps between two single-frame looks rather than animating; expressing
# that as two named animations keeps the texture swap out of the script.
const GOLEM := {
	"falling": {"fps": 1.0, "loop": true, "frames": ["golem_falling.png"]},
	"petrified": {"fps": 1.0, "loop": true, "frames": ["golem_active.png"]},
}

# The bomb. `explode` is a reserved slot for a drawn explosion: empty today, so
# the blast is carried by particles (data/fx/blast_*.tres) and shards of the
# bomb itself, and Explosion.tscn hides the sprite until there is something in
# it, then scales it to the blast radius. The core lights up over half a second
# per frame, so `falling` is 2 fps.
const BOMB := {
	"falling": {"fps": 2.0, "loop": true, "optional": true,
		"frames": ["bomb_falling_1.png", "bomb_falling_2.png", "bomb_falling_3.png"]},
	"explode": {"fps": 12.0, "loop": false, "optional": true,
		"frames": ["bomb_explode_1.png", "bomb_explode_2.png", "bomb_explode_3.png"]},
}


# Tessa's bullet: one drawing, pointing right. The scene flips it.
const BULLET := {
	"fly": {"fps": 1.0, "loop": true, "frames": ["bullet.png"]},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/animations")
	_build(CYN, "res://data/animations/cyn_frames.tres", "standing")
	_build(TESSA, "res://data/animations/tessa_frames.tres", "standing")
	_build(UZI, "res://data/animations/uzi_frames.tres", "standing")
	_build(PURSUER, "res://data/animations/pursuer_frames.tres", "walk")
	_build(STRIKE, "res://data/animations/strike_frames.tres", "punch")
	_build(SWORD, "res://data/animations/sword_frames.tres", "punch")
	_build(BULLET, "res://data/animations/bullet_frames.tres", "fly")
	_build(GOLEM, "res://data/animations/golem_frames.tres", "falling")
	_build(BOMB, "res://data/animations/bomb_frames.tres", "falling")
	quit(0)


func _build(spec: Dictionary, out_path: String, default_anim: String) -> void:
	var frames := SpriteFrames.new()
	var dir: String = SPR + String(spec.get("dir", ""))
	var animations := 0
	# SpriteFrames always ships with a "default" animation; drop it once our own
	# animations exist so the resource has no dead entries.
	for anim_name: String in spec:
		if anim_name == "dir":
			continue
		animations += 1
		var entry: Dictionary = spec[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, float(entry["fps"]))
		frames.set_animation_loop(anim_name, bool(entry["loop"]))
		if not _add_frames(frames, anim_name, dir, entry["frames"],
				bool(entry.get("optional", false))):
			return
		if frames.get_frame_count(anim_name) == 0 and entry.has("fallback"):
			print("  standing in for '%s': %s" % [anim_name, entry["fallback"]])
			if not _add_frames(frames, anim_name, dir, entry["fallback"], false):
				return
	if frames.has_animation("default") and not spec.has("default"):
		frames.remove_animation("default")

	var err := ResourceSaver.save(frames, out_path)
	if err != OK:
		push_error("failed to save %s (error %d)" % [out_path, err])
		quit(1)
		return
	print("wrote %s (%d animations, default '%s')" % [out_path, animations, default_anim])


## False means the build has already been failed and quit.
func _add_frames(frames: SpriteFrames, anim_name: String, dir: String,
		files: Array, optional: bool) -> bool:
	for file: String in files:
		if optional and not ResourceLoader.exists(dir + file):
			print("  reserved slot, not drawn yet: ", file)
			continue
		var tex: Texture2D = load(dir + file)
		if tex == null:
			push_error("missing sprite: " + dir + file)
			quit(1)
			return false
		frames.add_frame(anim_name, tex)
	return true

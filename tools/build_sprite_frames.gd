extends SceneTree
## One-shot: builds the SpriteFrames resources that replace the frame-array
## animation state machines in player.gd, pursuer.gd and strike.gd.
##
##   godot --headless --path . -s tools/build_sprite_frames.gd
##
## Frame rates are derived from the millisecond delays those scripts used, so
## the animations play at exactly the old speed:
##   player standing 300ms -> 3.333 fps, running 150ms -> 6.667 fps,
##   jumping/falling/attacking 100ms -> 10 fps, pursuer 200ms -> 5 fps,
##   strike 100ms -> 10 fps and does not loop (the old code clamped on the last
##   frame rather than wrapping).
##
## Re-running OVERWRITES the resources, losing inspector edits. It exists so the
## origin of these numbers is traceable, not as part of the build.

const SPR := "res://assets/sprites/"

# name -> { fps, loop, frames[] }
const PLAYER := {
	"standing": {"fps": 1000.0 / 300.0, "loop": true,
		"frames": ["player_standing_1.png", "player_standing_2.png"]},
	"running": {"fps": 1000.0 / 150.0, "loop": true,
		"frames": ["player_running_1.png", "player_running_2.png"]},
	"jumping": {"fps": 10.0, "loop": true, "frames": ["player_jumping.png"]},
	"falling": {"fps": 10.0, "loop": true, "frames": ["player_falling.png"]},
	"attacking": {"fps": 10.0, "loop": true, "frames": ["player_attacking.png"]},
}

const PURSUER := {
	"walk": {"fps": 1000.0 / 200.0, "loop": true,
		"frames": ["pursuer_1.png", "pursuer_2.png"]},
}

const STRIKE := {
	"punch": {"fps": 10.0, "loop": false,
		"frames": ["punch_1.png", "punch_2.png", "punch_3.png"]},
}

# Golem swaps between two single-frame looks rather than animating; expressing
# that as two named animations keeps the texture swap out of the script.
const GOLEM := {
	"falling": {"fps": 1.0, "loop": true, "frames": ["golem_falling.png"]},
	"petrified": {"fps": 1.0, "loop": true, "frames": ["golem_active.png"]},
}

# The bomb, and the only spec with RESERVED slots.
#
# `optional` means a listed frame that is not on disk is skipped with a note
# instead of failing the build, and an animation whose frames are all missing is
# still created — empty. That is what reserving a slot means here: the animation
# exists in the resource and in the inspector, the scenes already point at it,
# and dropping the next frame in and re-running this is the entire job. Nothing
# in code has to change and nothing has to be wired.
#
# The core lights up over half a second per frame, so 2 fps.
#
# `explode` is the same arrangement for a drawn explosion. Empty today; the
# blast is carried by particles (data/fx/blast_*.tres) and shards of the bomb
# itself, and Explosion.tscn hides the sprite until there is something in it,
# then scales it to the blast radius.
const BOMB := {
	"falling": {"fps": 2.0, "loop": true, "optional": true,
		"frames": ["bomb_falling_1.png", "bomb_falling_2.png", "bomb_falling_3.png"]},
	"explode": {"fps": 12.0, "loop": false, "optional": true,
		"frames": ["bomb_explode_1.png", "bomb_explode_2.png", "bomb_explode_3.png"]},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/animations")
	_build(PLAYER, "res://data/animations/player_frames.tres", "standing")
	_build(PURSUER, "res://data/animations/pursuer_frames.tres", "walk")
	_build(STRIKE, "res://data/animations/strike_frames.tres", "punch")
	_build(GOLEM, "res://data/animations/golem_frames.tres", "falling")
	_build(BOMB, "res://data/animations/bomb_frames.tres", "falling")
	quit(0)


func _build(spec: Dictionary, out_path: String, default_anim: String) -> void:
	var frames := SpriteFrames.new()
	# SpriteFrames always ships with a "default" animation; drop it once our own
	# animations exist so the resource has no dead entries.
	for anim_name: String in spec:
		var entry: Dictionary = spec[anim_name]
		var optional: bool = entry.get("optional", false)
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, float(entry["fps"]))
		frames.set_animation_loop(anim_name, bool(entry["loop"]))
		for file: String in entry["frames"]:
			if optional and not ResourceLoader.exists(SPR + file):
				print("  reserved slot, not drawn yet: ", file)
				continue
			var tex: Texture2D = load(SPR + file)
			if tex == null:
				push_error("missing sprite: " + SPR + file)
				quit(1)
				return
			frames.add_frame(anim_name, tex)
	if frames.has_animation("default") and not spec.has("default"):
		frames.remove_animation("default")

	var err := ResourceSaver.save(frames, out_path)
	if err != OK:
		push_error("failed to save %s (error %d)" % [out_path, err])
		quit(1)
		return
	print("wrote %s (%d animations, default '%s')" % [
		out_path, spec.size(), default_anim])

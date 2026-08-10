extends Node2D
## The railgun, drawn — the one part of it no test can look at.
##
##   godot --path . --fixed-fps 60 tools/rail_check.tscn -- out.png
##
## Advisory, like visual_check. It exists because five of the railgun's numbers
## are facts about where the drawing sits on Uzi's hands, and there is no way to
## be right about those by reasoning:
##
##   grip_offset    the nail the gun turns on, in avatar space
##   hold_offset    where the drawing sits along the barrel from that nail
##   muzzle_offset  where the beam leaves, from the same nail
##   stow_offset    where it hangs when it is on her back
##   stow_degrees   and at what tilt
##
## All five are in data/weapons/railgun.tres. Nudge one, run this, look.
##
## The top row is the gun aimed at eight angles round the clock, so the flip
## across the vertical shows up: past a quarter turn the drawing is mirrored so
## it is not hanging upside down, and the muzzle has to follow it. The bottom is
## a real traced beam inside a real box, which is the only place the bounce
## count, the taper and the three stacked Line2Ds can be seen at once.

const ROSTER: CharacterRoster = preload("res://data/characters/roster.tres")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const SHOT_SCENE: PackedScene = preload("res://scenes/RailShot.tscn")
const STATS: RailgunStats = preload("res://data/weapons/railgun.tres")

## Nine poses — eight round the clock plus the stowed one — have to FIT. At the
## old 300 px spacing the last two fell off the right of the frame, so the one
## pose the harness exists to show was the one it never showed.
const CLOCK_AT := Vector2(120.0, 250.0)
const CLOCK_SPACING: float = 235.0
const CLOCK_ANGLES: Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, -135.0, -90.0, -45.0]

## The box the beam is fired inside, bottom half of the frame.
const BOX_CENTRE := Vector2(960.0, 760.0)
const BOX_HALF := Vector2(880.0, 300.0)

var _out_path: String = "user://rail_check.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	RenderingServer.set_default_clear_color(Color(0.09, 0.07, 0.11))
	_run.call_deferred()


## The order matters and it is the same trap character_test.gd records: a static
## body is not in the physics server until a step has run, so a beam traced in
## _ready() finds an empty room and reports one straight segment. Positions go on
## BEFORE add_child, and the trace waits for a physics frame.
func _run() -> void:
	_build_clock()
	_build_walls()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire_beam()
	await _capture()


## Uzi holding the gun at eight angles, plus one with it stowed.
func _build_clock() -> void:
	for i in CLOCK_ANGLES.size():
		var uzi := _uzi(CLOCK_AT + Vector2(i * CLOCK_SPACING, 0.0))
		var gun: Node2D = uzi.weapon
		uzi.aiming = true
		uzi.aim_angle = deg_to_rad(CLOCK_ANGLES[i])
		uzi.facing_right = absf(uzi.aim_angle) < PI * 0.5
		gun.call(&"_place")
		# A dot exactly where the beam would leave, so an offset that is close
		# but not on the barrel is obvious rather than plausible.
		var pip := ColorRect.new()
		pip.color = Color(1.0, 0.2, 0.4)
		pip.size = Vector2(6.0, 6.0)
		add_child(pip)
		pip.global_position = gun.call(&"muzzle_position") - Vector2(3.0, 3.0)

	# Below the row rather than after it: a ninth column fell off the right of
	# the frame, and the stowed pose is the one this harness is most often opened
	# to look at.
	var stowed := _uzi(CLOCK_AT + Vector2(0.0, 190.0))
	stowed.weapon.call(&"_place")


func _uzi(at: Vector2) -> CharacterBody2D:
	var uzi: CharacterBody2D = PLAYER_SCENE.instantiate()
	uzi.character = ROSTER.by_id(&"uzi")
	uzi.position = at
	add_child(uzi)
	uzi.has_ranged = true
	uzi.process_mode = Node.PROCESS_MODE_DISABLED
	return uzi


## Four static bodies on the WORLD layer, with a grey rectangle over each so the
## capture shows what the beam is bouncing off.
func _build_walls() -> void:
	for side: Array in [
		[Vector2(-BOX_HALF.x, 0.0), Vector2(16.0, BOX_HALF.y)],
		[Vector2(BOX_HALF.x, 0.0), Vector2(16.0, BOX_HALF.y)],
		[Vector2(0.0, -BOX_HALF.y), Vector2(BOX_HALF.x, 16.0)],
		[Vector2(0.0, BOX_HALF.y), Vector2(BOX_HALF.x, 16.0)],
	]:
		var body := StaticBody2D.new()
		body.collision_layer = Layers.WORLD
		body.position = BOX_CENTRE + (side[0] as Vector2)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = (side[1] as Vector2) * 2.0
		shape.shape = rect
		body.add_child(shape)
		add_child(body)
		var seen := ColorRect.new()
		seen.color = Color(0.22, 0.2, 0.26)
		seen.size = (side[1] as Vector2) * 2.0
		seen.position = BOX_CENTRE + (side[0] as Vector2) - (side[1] as Vector2)
		add_child(seen)


## A real trace: the same solver the weapon uses, from a real muzzle.
func _fire_beam() -> void:
	var shooter := _uzi(BOX_CENTRE + Vector2(-700.0, 200.0))
	var gun: Node2D = shooter.weapon
	shooter.aiming = true
	shooter.aim_angle = deg_to_rad(-24.0)
	gun.call(&"_place")

	var muzzle: Vector2 = gun.call(&"muzzle_position")
	var path := RailBeam.trace(self, muzzle, Vector2.from_angle(shooter.aim_angle), STATS)
	var shot := SHOT_SCENE.instantiate()
	add_child(shot)
	shot.call(&"fire", shooter, STATS, path)
	# Hold the beam at full width: the clip would otherwise have faded most of it
	# out by the time the frame is captured.
	shot.get_node(^"AnimationPlayer").stop()
	shot.get_node(^"Core").width = 6.0
	shot.get_node(^"Glow").width = 22.0
	shot.get_node(^"Haze").width = 52.0
	print("beam: %d points, %d segments, landed=%s"
		% [path.points.size(), path.segment_count(), path.landed])


func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_path)
	if err != OK:
		push_error("rail_check: could not write %s (error %d)" % [_out_path, err])
		get_tree().quit(1)
		return
	print("wrote ", _out_path)
	get_tree().quit(0)

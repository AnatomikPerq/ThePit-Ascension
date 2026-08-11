extends Node2D
## One railgun shot: the drawing, the hitbox, and the noise it makes.
##
## Spawned on EVERY machine by the same `call_local` broadcast that spawns a
## Strike or a Bullet, and for the same two reasons — the authority needs the
## hitbox to resolve kills, and everybody else needs to see it. What travels is
## the muzzle and the angle, two numbers; each machine then runs `RailBeam.trace`
## against its own copy of a pit every machine built from the same seed, and
## arrives at the same corners.
##
## A moving platform is a few ticks out of step between peers, so a beam that
## bounces off one can land a pixel or two apart on two screens. That is
## deliberate and it is the cheap half of the trade: the alternative is sending
## a polyline, which costs a round trip before you see your own shot — and a
## HELD beam, which is where this is going, would be sending one every frame.
## The corners are cosmetic; what is authoritative is the hitbox, and only the
## authority acts on that.
##
## ## The drawing
##
## Three `Line2D`s over the same points, all additive, all tapering along their
## length through the same `width_curve`: a near-white core inside an energy-green
## glow inside a wide, faint haze. The taper is what makes a bounced beam read —
## it arrives bright at the muzzle and is visibly spent by the last corner.
##
## Widths and alpha are an `AnimationPlayer` clip: up in 35 ms, held, then gone
## over half a second. Nothing here counts milliseconds.

const HIT_GROUP: StringName = &"strike"

@onready var core: Line2D = $Core
@onready var glow: Line2D = $Glow
@onready var haze: Line2D = $Haze
@onready var hit_area: Area2D = $BeamHit
@onready var anim: AnimationPlayer = $AnimationPlayer
## How long the beam may still hurt the person who fired it. A Timer node and
## not an accumulator, and not a track on the clip either: the clip is the
## drawing and this is a number in RailgunStats. It counts on the PHYSICS clock,
## because what it gates is an overlap and overlaps happen there.
@onready var self_window: Timer = $SelfHarmWindow

var _stats: RailgunStats


## Lay the beam out and set it off. Called AFTER `add_child` — unlike a Bullet,
## which is set up before, this one needs its children.
func fire(shooter: Node2D, stats: RailgunStats, path: RailBeam.Path) -> void:
	_stats = stats
	if path.points.size() < 2:
		queue_free()
		return

	global_position = Vector2.ZERO
	global_rotation = 0.0

	var local := PackedVector2Array()
	for point in path.points:
		local.append(to_local(point))
	core.points = local
	glow.points = local
	haze.points = local

	for line: Line2D in [core, glow, haze]:
		line.default_color = Color(stats.energy, line.default_color.a)
	core.default_color = Color(
		lerpf(stats.energy.r, 1.0, 0.8),
		lerpf(stats.energy.g, 1.0, 0.8),
		lerpf(stats.energy.b, 1.0, 0.8),
		core.default_color.a)

	_lay_hitbox(shooter, stats, path)
	_throw_particles(stats, path)
	_kick(shooter, stats, path)

	anim.play(&"fire")


## A rectangle along every straight run, inside one Area2D.
##
## The shapes are authored in the scene and only ever moved — `RailBeam` says how
## many there can be and the scene has that many, so a beam never allocates. Each
## one carries `resource_local_to_scene`, because Shockwave once shared a single
## shape across every instance while writing its size every frame.
##
## `monitorable` and `monitoring` both, and `monitoring` LAST: Godot does not
## report an area with monitoring off from another area's `get_overlapping_areas`,
## and `EnemyCombat` resolves every kill in the game by asking exactly that.
func _lay_hitbox(shooter: Node2D, stats: RailgunStats, path: RailBeam.Path) -> void:
	var shapes := hit_area.get_children()
	var runs := mini(path.segment_count(), shapes.size())
	for i in shapes.size():
		var shape := shapes[i] as CollisionShape2D
		if shape == null:
			continue
		if i >= runs:
			shape.disabled = true
			continue
		var a: Vector2 = path.points[i]
		var b: Vector2 = path.points[i + 1]
		var along := (b - a).normalized()
		# Carried a little past the corner, into whatever the beam turned on —
		# see RailgunStats.hit_overshoot. Without it a beam bounces off a golem
		# and never touches the areas that set the golem off.
		var over := stats.hit_overshoot
		var span := a.distance_to(b) + over
		shape.position = to_local((a + b) * 0.5 + along * over * 0.5)
		shape.rotation = along.angle()
		(shape.shape as RectangleShape2D).size = Vector2(maxf(span, 1.0), stats.beam_width)
		shape.disabled = false

	hit_area.set_meta(&"owner_peer", int(shooter.get(&"peer_id")))
	# What the bomb reads to decide how far off centre it was hit. A beam is a
	# line, so its reach is its width — a bomb it clips is a bomb it clips.
	hit_area.set_meta(&"hit_reach", stats.beam_width)
	# Your own beam, come back off a wall into your own body, hurts. Every other
	# hitbox in the game is skipped by the player who owns it; this one asks not
	# to be, and asks it of a smaller box — see Player._on_own_area.
	#
	# It asks for a shorter time, too. Everything else the beam can reach stays
	# in danger for as long as the hitbox is up; its owner is only in danger at
	# the moment of the shot, so recoiling into your own reflection is a near
	# miss rather than a heart.
	hit_area.set_meta(&"self_harm", stats.self_harm_seconds > 0.0)
	if stats.self_harm_seconds > 0.0:
		self_window.start(stats.self_harm_seconds)
	hit_area.monitorable = true
	hit_area.monitoring = true


func _throw_particles(stats: RailgunStats, path: RailBeam.Path) -> void:
	if stats.muzzle_burst != null:
		Fx.burst(path.points[0], stats.muzzle_burst, stats.energy)
	# Every interior corner is a reflection; the last point is where it stopped.
	for i in range(1, path.points.size() - 1):
		if stats.bounce_burst != null:
			Fx.burst(path.points[i], stats.bounce_burst, stats.energy)
	if not path.landed:
		return
	var end: Vector2 = path.points[path.points.size() - 1]
	if stats.impact_burst != null:
		Fx.burst(end, stats.impact_burst, stats.energy)
	Audio.play_at(stats.impact_sound, end)


## Camera, screen and shooter.
##
## The kick and the wash are measured FROM THE MUZZLE and fade with distance,
## because this runs on every machine: without that, a rival firing three levels
## up shakes your camera as hard as your own shot. `screen_flash` does not scale
## itself — Blast multiplies by `loudness_at` by hand and so does this.
func _kick(shooter: Node2D, stats: RailgunStats, path: RailBeam.Path) -> void:
	var muzzle: Vector2 = path.points[0]
	Fx.shake_from(muzzle, stats.shake, stats.feedback_range)
	Fx.screen_flash(stats.flash * Fx.loudness_at(muzzle, stats.feedback_range),
		muzzle, false)

	if stats.recoil <= 0.0 or not shooter.has_method(&"shove"):
		return
	# Shoved away from a point out along the barrel, which is the same as saying
	# "backwards". `shove` refuses on a machine that does not steer this avatar,
	# so this is safe to call on all of them.
	var heading := (path.points[1] - muzzle).normalized()
	shooter.call(&"shove", muzzle + heading * 64.0, stats.recoil)


## The shooter's own window has run out; the beam still bites everybody else.
func _close_self_harm() -> void:
	hit_area.set_meta(&"self_harm", false)


## The hitbox closes long before the drawing fades. Called from the clip.
func _close() -> void:
	hit_area.monitoring = false
	hit_area.monitorable = false


func _done() -> void:
	queue_free()

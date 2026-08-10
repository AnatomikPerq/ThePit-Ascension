extends GdUnitTestSuite
## Uzi's railgun: where the beam goes, what it goes through, and how it fills.
##
## The beam is the reason this suite exists. Its rules read like a table of
## exceptions — bombs go off, a falling golem sets and reflects, a slime is
## passed through in any state, enemies are passed through and killed, walls
## reflect — and the implementation has NO branches for any of it, because the
## collision layers already say all of that. A suite is the only way to hold
## that claim: if somebody later "tidies up" by turning `collide_with_areas` on,
## nothing about the code will look wrong and the beam will silently start
## stopping dead on slimes.
##
## Every case builds its own container and frees it at once. The contact suite
## learned the hard way what a golem left standing between cases does.

const ROSTER: CharacterRoster = preload("res://data/characters/roster.tres")
const STATS: RailgunStats = preload("res://data/weapons/railgun.tres")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const SHOT_SCENE: PackedScene = preload("res://scenes/RailShot.tscn")

## The test box: a room 800 wide and 800 tall centred on the origin, so a beam
## fired along +x has somewhere to come back from.
const ROOM: float = 400.0

var _root: Node2D


func before_test() -> void:
	Game.new_run()
	_root = Node2D.new()
	add_child(_root)


func after_test() -> void:
	Net.active = false
	Net.mode = Net.Mode.COOP
	if is_instance_valid(_root):
		_root.free()


## Four static walls facing inwards, on the WORLD layer like everything the
## world builder makes.
func _build_room() -> void:
	var sides := [
		[Vector2(-ROOM, 0.0), Vector2(20.0, ROOM)],
		[Vector2(ROOM, 0.0), Vector2(20.0, ROOM)],
		[Vector2(0.0, -ROOM), Vector2(ROOM, 20.0)],
		[Vector2(0.0, ROOM), Vector2(ROOM, 20.0)],
	]
	for side: Array in sides:
		var body := StaticBody2D.new()
		body.collision_layer = Layers.WORLD
		body.position = side[0]
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = side[1] * 2.0
		shape.shape = rect
		body.add_child(shape)
		_root.add_child(body)


func _trace(from: Vector2, heading: Vector2, stats: RailgunStats = STATS) -> RailBeam.Path:
	# A node in the tree is all `trace` wants — it reads the physics space off it.
	var probe := Node2D.new()
	_root.add_child(probe)
	var path := RailBeam.trace(probe, from, heading, stats)
	probe.free()
	return path


# ── Reflection ──────────────────────────────────────────────────────────────
## Five reflections is six corners plus the muzzle: seven points. The count is
## the whole shape of the weapon and it is a number the owner set.
func test_the_beam_bounces_exactly_as_many_times_as_it_is_told() -> void:
	_build_room()
	await get_tree().physics_frame

	var path := _trace(Vector2.ZERO, Vector2(1.0, 0.37))
	assert_int(path.points.size()) \
		.override_failure_message(
			"%d reflections should give %d points, got %d" \
			% [STATS.bounces, STATS.bounces + 2, path.points.size()]) \
		.is_equal(STATS.bounces + 2)
	assert_bool(path.landed) \
		.override_failure_message("a beam that used every bounce ended on a wall") \
		.is_true()


func test_a_beam_that_meets_nothing_is_one_straight_run() -> void:
	await get_tree().physics_frame
	var path := _trace(Vector2.ZERO, Vector2.RIGHT)
	assert_int(path.points.size()).is_equal(2)
	assert_bool(path.landed) \
		.override_failure_message("nothing was hit, so nothing should be reported hit") \
		.is_false()
	assert_float(path.points[0].distance_to(path.points[1])) \
		.is_equal_approx(STATS.segment_length, 1.0)


## Every corner has to be ON a wall. A bounce computed from the wrong normal
## still produces the right NUMBER of points, so counting them is not enough.
func test_every_corner_lands_on_the_geometry() -> void:
	_build_room()
	await get_tree().physics_frame

	var path := _trace(Vector2.ZERO, Vector2(1.0, 0.37))
	for i in range(1, path.points.size()):
		var corner: Vector2 = path.points[i]
		var on_wall := absf(absf(corner.x) - ROOM) < 25.0 or absf(absf(corner.y) - ROOM) < 25.0
		assert_bool(on_wall) \
			.override_failure_message("corner %d is at %s, nowhere near a wall" % [i, corner]) \
			.is_true()


## The clamp is real and it is tied to how many shapes RailShot.tscn authors.
## Raising `bounces` past it without adding shapes would silently drop segments
## that are drawn but cannot hit anything.
func test_the_bounce_count_is_capped_by_the_shapes_that_exist() -> void:
	_build_room()
	await get_tree().physics_frame

	var greedy := STATS.duplicate() as RailgunStats
	greedy.bounces = 40
	var path := _trace(Vector2.ZERO, Vector2(1.0, 0.37), greedy)
	assert_int(path.segment_count()).is_less_equal(RailBeam.MAX_SEGMENTS)

	var shot := SHOT_SCENE.instantiate()
	_root.add_child(shot)
	assert_int(shot.get_node("BeamHit").get_child_count()) \
		.override_failure_message(
			"RailShot must author one collision shape per possible segment") \
		.is_equal(RailBeam.MAX_SEGMENTS)
	shot.free()


# ── What it goes through, and what it does not ──────────────────────────────
## A slime is a Node2D with two Area2Ds on the ENEMY layer and no physics body
## in any state, so a WORLD-masked ray never sees it. This is the case that
## breaks the moment somebody turns `collide_with_areas` on.
func test_a_slime_does_not_stop_the_beam() -> void:
	var slime: Node2D = load("res://scenes/Slime.tscn").instantiate()
	slime.position = Vector2(200.0, 0.0)
	_root.add_child(slime)
	await get_tree().physics_frame

	var path := _trace(Vector2.ZERO, Vector2.RIGHT)
	assert_int(path.points.size()) \
		.override_failure_message("the beam bent around a slime") \
		.is_equal(2)
	assert_bool(path.landed).is_false()


## Neither does a bat, which has no body at all — and yet the hitbox still kills
## it, because the killing is the `strike` group's job and not the ray's.
func test_a_bat_does_not_stop_the_beam() -> void:
	var bat: Node2D = load("res://scenes/Bat.tscn").instantiate()
	bat.position = Vector2(200.0, 0.0)
	_root.add_child(bat)
	await get_tree().physics_frame

	assert_int(_trace(Vector2.ZERO, Vector2.RIGHT).points.size()).is_equal(2)


## A FALLING golem carries a CrushBody on the WORLD layer, so it is a mirror
## before it has been activated as well as after. The owner asked for exactly
## that and it costs no code — which is precisely why it needs a test.
func test_a_falling_golem_reflects_the_beam_like_a_platform() -> void:
	var golem: Node2D = load("res://scenes/Golem.tscn").instantiate()
	golem.position = Vector2(200.0, 0.0)
	_root.add_child(golem)
	await get_tree().physics_frame

	var path := _trace(Vector2(0.0, 0.0), Vector2.RIGHT)
	# It BENT, which in open space means a second point short of the golem and a
	# third somewhere else entirely. `landed` would be the wrong question: that
	# only says the beam ran out of bounces on something, and this one has five
	# left to spend flying off into nothing.
	assert_int(path.points.size()) \
		.override_failure_message("the beam passed straight through a falling golem") \
		.is_greater(2)
	assert_float(path.points[1].x) \
		.override_failure_message("the beam turned somewhere other than at the golem") \
		.is_between(100.0, 200.0)


## The bug this pair of tests exists for: a golem is DRAWN 64×64 but its solid
## `CrushBody` is 54×38 and sits low, so the top third of it had no collider and
## a beam aimed at a golem's head went straight through one that was plainly in
## the way. Its hurt boxes now claim the rest via `beam_response()`.
func test_a_beam_reflects_off_the_top_of_a_golem_not_only_its_middle() -> void:
	var golem: Node2D = load("res://scenes/Golem.tscn").instantiate()
	golem.position = Vector2(200.0, 0.0)
	_root.add_child(golem)
	await get_tree().physics_frame

	# y = -22 is inside the drawing and ABOVE CrushBody, which starts at -9.
	var high := _trace(Vector2(0.0, -22.0), Vector2.RIGHT)
	assert_int(high.points.size()) \
		.override_failure_message("the beam went through the top of a golem") \
		.is_greater(2)
	assert_float(high.points[1].x).is_between(100.0, 200.0)


## And the shot sets it off, which is the other half of what was asked for. The
## reflection is the ray's job; the activation is the hitbox's, and the hitbox
## has to reach PAST the surface it bounced off to touch the areas that do it.
func test_a_shot_sets_a_falling_golem_off() -> void:
	var golem: Node2D = load("res://scenes/Golem.tscn").instantiate()
	golem.position = Vector2(200.0, 0.0)
	_root.add_child(golem)
	var uzi := PLAYER_SCENE.instantiate()
	uzi.character = ROSTER.by_id(&"uzi")
	uzi.peer_id = Game.local_peer_id
	_root.add_child(uzi)
	await get_tree().physics_frame

	var combat: EnemyCombat = golem.get_node(^"Combat")
	assert_bool(combat.is_dead) \
		.override_failure_message("the golem started out already activated") \
		.is_false()

	var shot := SHOT_SCENE.instantiate()
	_root.add_child(shot)
	shot.fire(uzi, STATS, _trace(Vector2(0.0, 0.0), Vector2.RIGHT))
	for i in 10:
		await get_tree().physics_frame

	assert_bool(combat.is_dead) \
		.override_failure_message("the beam bounced off a falling golem and did not set it off") \
		.is_true()


## The one hook, for the breakable furniture the map is going to grow.
func test_a_collider_can_ask_to_be_passed_through() -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = Layers.WORLD
	wall.position = Vector2(200.0, 0.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40.0, 400.0)
	shape.shape = rect
	wall.add_child(shape)
	_root.add_child(wall)
	await get_tree().physics_frame

	# Solid by default: the beam turns at it.
	assert_int(_trace(Vector2.ZERO, Vector2.RIGHT).points.size()) \
		.override_failure_message("a plain body on the WORLD layer should be a mirror") \
		.is_greater(2)

	var script := GDScript.new()
	script.source_code = "extends StaticBody2D\nfunc beam_response() -> int:\n\treturn 1\n"
	script.reload()
	wall.set_script(script)
	await get_tree().physics_frame

	# Response.PASS: straight through, one run, and nothing at the far end.
	var through := _trace(Vector2.ZERO, Vector2.RIGHT)
	assert_int(through.points.size()) \
		.override_failure_message("beam_response() PASS did not let the beam through") \
		.is_equal(2)
	assert_bool(through.landed).is_false()


# ── The hitbox ──────────────────────────────────────────────────────────────
## The contract every enemy in the game already understands, plus the two things
## only this weapon says: it detonates bombs where they stand, and it is allowed
## to come back and hit the player who fired it.
func test_the_beam_hitbox_speaks_the_language_every_enemy_knows() -> void:
	_build_room()
	var uzi := PLAYER_SCENE.instantiate()
	uzi.character = ROSTER.by_id(&"uzi")
	uzi.peer_id = 7
	_root.add_child(uzi)
	await get_tree().physics_frame

	var shot := SHOT_SCENE.instantiate()
	_root.add_child(shot)
	shot.fire(uzi, STATS, _trace(Vector2.ZERO, Vector2(1.0, 0.37)))
	await get_tree().physics_frame

	var box: Area2D = shot.get_node("BeamHit")
	assert_bool(box.is_in_group(&"strike")) \
		.override_failure_message("nothing can be killed by a hitbox outside 'strike'") \
		.is_true()
	assert_bool(box.is_in_group(&"detonator")) \
		.override_failure_message("a beam sets a bomb off; a punch throws it") \
		.is_true()
	assert_int(int(box.get_meta(&"owner_peer"))).is_equal(7)
	assert_bool(bool(box.get_meta(&"self_harm"))) \
		.override_failure_message("the owner asked for the beam to hit Uzi herself") \
		.is_true()
	# Both flags, or EnemyCombat's get_overlapping_areas() never reports it.
	assert_bool(box.monitorable).is_true()
	assert_bool(box.monitoring).is_true()


## One shape per straight run, laid along it, and every unused shape disabled —
## a shape left over from a longer beam would kill things nowhere near this one.
func test_the_hitbox_covers_every_segment_and_no_more() -> void:
	_build_room()
	var uzi := PLAYER_SCENE.instantiate()
	uzi.character = ROSTER.by_id(&"uzi")
	_root.add_child(uzi)
	await get_tree().physics_frame

	var short := STATS.duplicate() as RailgunStats
	short.bounces = 1
	var path := _trace(Vector2.ZERO, Vector2.RIGHT, short)

	var shot := SHOT_SCENE.instantiate()
	_root.add_child(shot)
	shot.fire(uzi, short, path)
	await get_tree().physics_frame

	var live := 0
	for child in shot.get_node("BeamHit").get_children():
		if not (child as CollisionShape2D).disabled:
			live += 1
	assert_int(live).is_equal(path.segment_count())


# ── Charges ─────────────────────────────────────────────────────────────────
func _armed_uzi() -> Node2D:
	var uzi := PLAYER_SCENE.instantiate()
	uzi.character = ROSTER.by_id(&"uzi")
	uzi.peer_id = Game.local_peer_id
	_root.add_child(uzi)
	uzi.has_ranged = true
	return uzi.weapon


func test_the_gun_arrives_with_something_in_it() -> void:
	var gun := _armed_uzi()
	assert_bool(gun.armed()).is_true()
	assert_int(gun.charges).is_equal(STATS.initial_charges)


## Score EARNED, never spent — the owner was explicit. The run's own number must
## be exactly what it would have been without a railgun in the pit.
func test_score_fills_the_gun_without_being_taken_off_the_board() -> void:
	var gun := _armed_uzi()
	var before: int = gun.charges
	Game.add_score(STATS.score_per_charge)
	assert_int(gun.charges).is_equal(before + 1)
	assert_int(Game.local_run().score) \
		.override_failure_message("the railgun charged itself out of the player's score") \
		.is_equal(STATS.score_per_charge)


func test_part_of_a_charge_shows_on_the_meter() -> void:
	var gun := _armed_uzi()
	var empty: float = gun.fill()
	Game.add_score(STATS.score_per_charge / 2)
	assert_int(gun.charges) \
		.override_failure_message("half the score should not be a whole charge") \
		.is_equal(STATS.initial_charges)
	assert_float(gun.fill()) \
		.override_failure_message("a part-charge has to move the meter, or an ult cannot drain it") \
		.is_greater(empty)


## A hard ceiling on both the count and the meter: a kill streak while full must
## not be bankable and cashed in later as a second magazine.
func test_a_full_gun_banks_nothing() -> void:
	var gun := _armed_uzi()
	Game.add_score(STATS.score_per_charge * STATS.charges * 3)
	assert_int(gun.charges).is_equal(STATS.charges)
	assert_float(gun.fill()).is_equal_approx(1.0, 0.001)

	gun.charges -= 1
	Game.add_score(1)
	assert_int(gun.charges) \
		.override_failure_message("score banked while full came back after a shot") \
		.is_equal(STATS.charges - 1)


## The meter answers "what can I fire right now", which is not the same question
## as "what does the gun hold" — and showing the second one was the bug: a bar
## reading five-sixths on a gun that refuses to fire.
func test_the_meter_shows_what_can_be_fired_not_what_is_held() -> void:
	var gun := _armed_uzi()
	var held: float = gun.fill()
	assert_float(gun.meter()) \
		.override_failure_message("a ready gun should show everything it holds") \
		.is_equal_approx(held, 0.001)

	# Mid-cooldown: the charges are still there, but they are not available, and
	# the meter has to say so.
	gun.cooldown.start()
	await get_tree().physics_frame
	assert_float(gun.meter()) \
		.override_failure_message("the meter stayed full on a gun that cannot fire") \
		.is_less(held * 0.5)

	gun.cooldown.stop()
	assert_float(gun.meter()).is_equal_approx(held, 0.001)


## And the part-charge bought with score is shown at all times — it is the half
## of the design that ties the weapon to the climb, so it must survive the
## cooldown rather than being scaled away with the rest.
func test_earned_progress_shows_even_while_reloading() -> void:
	var gun := _armed_uzi()
	gun.charges = 0
	gun.cooldown.start()
	await get_tree().physics_frame
	var empty: float = gun.meter()
	Game.add_score(STATS.score_per_charge / 2)
	assert_float(gun.meter()) \
		.override_failure_message("score earned during a reload moved nothing") \
		.is_greater(empty)


## Another player's kills are another player's charges.
func test_somebody_elses_score_does_not_charge_this_gun() -> void:
	var gun := _armed_uzi()
	var before: int = gun.charges
	Game.ledger.runs[999] = PlayerRun.new()
	Game.ledger.runs[999].peer_id = 999
	Game.add_score(STATS.score_per_charge * 2, Vector2.INF, Color.WHITE, 999)
	assert_int(gun.charges).is_equal(before)


# ── The two buttons ─────────────────────────────────────────────────────────
## Stowed, the attack button is not the gun's — which is what leaves it free for
## a melee swing on a character who has one.
func test_the_attack_button_is_only_the_guns_while_it_is_out() -> void:
	var gun := _armed_uzi()
	assert_bool(gun.wants_attack()).is_false()
	assert_bool(gun.locks_facing()).is_false()

	gun.alt_pressed()
	assert_bool(gun.wants_attack()).is_true()
	assert_bool(gun.locks_facing()) \
		.override_failure_message("an aimed weapon decides which way she looks") \
		.is_true()

	gun.alt_pressed()
	assert_bool(gun.wants_attack()) \
		.override_failure_message("right mouse has to put it back, not only take it out") \
		.is_false()


# ── Hitting yourself ────────────────────────────────────────────────────────
## The owner's answer, in one case: a beam that has come back off a wall hurts
## the person who fired it, and it does so SOLO — not only in a race, which is
## the only mode any hitbox could reach its own owner in before.
##
## The mechanism is one piece of metadata rather than a mode check, so this also
## pins that an ordinary swing is still ignored by its owner: `versus_test.gd`
## holds that end.
func test_your_own_beam_comes_back_and_hurts_you_in_solo() -> void:
	var uzi := PLAYER_SCENE.instantiate()
	uzi.character = ROSTER.by_id(&"uzi")
	uzi.peer_id = 1
	_root.add_child(uzi)
	uzi.global_position = Vector2.ZERO
	var full: int = uzi.max_health
	await get_tree().physics_frame

	# A beam laid straight through where she is standing.
	var path := RailBeam.Path.new()
	path.points = PackedVector2Array([Vector2(-300.0, 0.0), Vector2(300.0, 0.0)])
	var shot := SHOT_SCENE.instantiate()
	_root.add_child(shot)
	shot.fire(uzi, STATS, path)

	for i in 8:
		await get_tree().physics_frame

	assert_int(uzi.health) \
		.override_failure_message("Uzi walked through her own beam unharmed") \
		.is_equal(full - 1)


func test_a_stowed_gun_cannot_fire_and_a_spent_one_cannot_either() -> void:
	var gun := _armed_uzi()
	assert_bool(gun.ready_to_fire()).is_true()
	gun.charges = 0
	assert_bool(gun.ready_to_fire()) \
		.override_failure_message("an empty gun reported itself ready") \
		.is_false()

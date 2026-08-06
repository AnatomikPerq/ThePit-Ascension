extends GdUnitTestSuite
## Two climbers, one Player script.
##
## The rule this suite exists to hold: nothing outside CharacterDef decides who
## it is steering. Hearts, jump strength, how many jumps come free, which attack
## scene and which upgrades are offered are all fields on a resource, and the
## two characters differ only in those fields. Anything that starts branching on
## an id somewhere will show up here as a test that has to be told which
## character it is testing.

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const ROSTER: CharacterRoster = preload("res://data/characters/roster.tres")

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


func _avatar(id: StringName) -> CharacterBody2D:
	var avatar: CharacterBody2D = PLAYER_SCENE.instantiate()
	avatar.character = ROSTER.by_id(id)
	_root.add_child(avatar)
	return avatar


# ── The roster ──────────────────────────────────────────────────────────────
func test_the_roster_has_both_climbers_and_resolves_junk() -> void:
	assert_object(ROSTER.by_id(&"cyn")).is_not_null()
	assert_object(ROSTER.by_id(&"tessa")).is_not_null()
	assert_object(ROSTER.by_id(&"nobody")).is_null()
	assert_object(ROSTER.resolve(&"nobody")) \
		.override_failure_message("an unknown id must fall back, never come back null") \
		.is_same(ROSTER.fallback())


func test_every_character_carries_every_animation() -> void:
	for character in ROSTER.characters:
		for anim in ["standing", "running", "jumping", "falling", "attacking", "died"]:
			assert_bool(character.frames.has_animation(anim)) \
				.override_failure_message("%s has no '%s' clip" % [character.id, anim]) \
				.is_true()
			assert_int(character.frames.get_frame_count(anim)) \
				.override_failure_message(
					"%s's '%s' clip is empty — a reserved slot needs a fallback frame" \
					% [character.id, anim]) \
				.is_greater(0)


func test_every_character_has_an_attack_scene_and_upgrades() -> void:
	for character in ROSTER.characters:
		assert_object(character.attack_scene) \
			.override_failure_message("%s has no attack scene" % character.id).is_not_null()
		assert_array(character.upgrades) \
			.override_failure_message("%s has nothing to unlock" % character.id).is_not_empty()


# ── What the two climbers actually are ──────────────────────────────────────
func test_cyn_is_five_hearts_and_one_jump() -> void:
	var cyn := _avatar(&"cyn")
	assert_int(cyn.max_health).is_equal(5)
	assert_int(cyn.health).is_equal(5)
	assert_int(cyn.max_jumps) \
		.override_failure_message("Cyn's double jump is an upgrade, not a starting kit") \
		.is_equal(1)


func test_tessa_is_one_heart_and_a_double_jump_from_the_start() -> void:
	var tessa := _avatar(&"tessa")
	assert_int(tessa.max_health).is_equal(1)
	assert_int(tessa.max_jumps).is_equal(2)


func test_tessa_jumps_a_little_shorter_than_cyn() -> void:
	var cyn := _avatar(&"cyn")
	var tessa := _avatar(&"tessa")
	assert_float(absf(tessa.jump_force())) \
		.override_failure_message("Tessa should jump less hard than Cyn").is_less(absf(cyn.jump_force()))
	# "A little", not "half": her double jump has to be worth having.
	assert_float(absf(tessa.jump_force()) / absf(cyn.jump_force())).is_between(0.85, 0.99)


func test_the_two_climbers_swing_different_things() -> void:
	var cyn := _avatar(&"cyn")
	var tessa := _avatar(&"tessa")
	assert_str(cyn.character.attack_scene.resource_path) \
		.is_not_equal(tessa.character.attack_scene.resource_path)


# ── Jumping ─────────────────────────────────────────────────────────────────
## A character with no EXTRA_JUMP unlocked gets exactly one jump, and walking
## off a ledge does not quietly hand out a second.
func test_the_ground_jump_is_spent_by_walking_off_a_ledge() -> void:
	var cyn := _avatar(&"cyn")
	cyn.global_position = Vector2(0, -2000) # in the air, nothing under it
	for i in 4:
		await get_tree().physics_frame
	assert_int(cyn.jump_count) \
		.override_failure_message("airborne without jumping still costs the ground jump") \
		.is_equal(1)


func test_an_extra_jump_upgrade_adds_exactly_one() -> void:
	var tessa := _avatar(&"tessa")
	var before: int = tessa.max_jumps
	tessa.max_jumps += 1 # what World._apply_upgrade does for EXTRA_JUMP
	assert_int(tessa.max_jumps).is_equal(before + 1)
	assert_int(tessa.max_jumps) \
		.override_failure_message("Tessa's upgrade is a TRIPLE jump").is_equal(3)


# ── The dash-down hitbox ────────────────────────────────────────────────────
## It exists only while the dive does. Anything else and a player standing next
## to an enemy would be stomping it.
func test_the_dash_box_is_live_only_while_dashing() -> void:
	var cyn := _avatar(&"cyn")
	assert_bool(cyn.dash_box.monitorable) \
		.override_failure_message("the dash box is armed before any dash").is_false()
	cyn.dashing_down = true
	assert_bool(cyn.dash_box.monitorable).is_true()
	# `monitoring` too, and not as a formality: an Area2D with monitoring off is
	# not reported by another area's get_overlapping_areas(), so a box that armed
	# only `monitorable` was invisible to every enemy on the way down.
	assert_bool(cyn.dash_box.monitoring) \
		.override_failure_message("monitoring off means no enemy can see the box at all") \
		.is_true()
	cyn.dashing_down = false
	assert_bool(cyn.dash_box.monitorable).is_false()
	assert_bool(cyn.dash_box.monitoring).is_false()


## The reason it is a box of its own: it reaches further than the body, so a
## dive that clips a shoulder still counts.
func test_the_dash_box_reaches_past_the_body() -> void:
	var cyn := _avatar(&"cyn")
	var body: RectangleShape2D = cyn.get_node("CollisionShape2D").shape
	var dash: RectangleShape2D = cyn.dash_box.get_node("CollisionShape2D").shape
	assert_float(dash.size.x).is_greater(body.size.x)
	assert_float(dash.size.y).is_greater(body.size.y)


## And it is deliberately NOT on the layer a rival's hurt box watches: diving
## past somebody in a race is not a punch.
func test_the_dash_box_is_not_a_player_attack() -> void:
	var cyn := _avatar(&"cyn")
	assert_bool(cyn.dash_box.get_collision_layer_value(Layers.BIT_PLAYER_STOMP)).is_true()
	assert_bool(cyn.dash_box.get_collision_layer_value(Layers.BIT_PLAYER_ATTACK)) \
		.override_failure_message("a dash would register as a rival's strike") \
		.is_false()


## What the extra width is FOR, at the only offsets where it can be seen.
##
## The golem's stomp strip is 58 wide and the avatar's body is 48, so the two
## touch while their centres are under 53 apart; the 56-wide dash box reaches
## 57. A dive at 55 is therefore a clean miss for the body and a hit for the
## box — the case the owner asked for, and the one no other test can tell
## apart. 64 is past both, and is here so a box that grew without limit would
## be caught too.
##
## The golem, because it holds still sideways: a bat homes in on the player and
## would close any gap this test opened.
func test_a_dash_that_the_body_would_miss_still_lands() -> void:
	assert_bool(await _dive_at(55.0)) \
		.override_failure_message("a dive 55 px off centre missed; the dash box is not doing its job") \
		.is_true()
	assert_bool(await _dive_at(64.0)) \
		.override_failure_message("a dive 64 px off centre killed something it never touched") \
		.is_false()


## Drop a dashing climber past a golem, `offset` px to one side. Returns whether
## the golem was converted.
##
## Its own container, freed on the way out. The contact suite learned this the
## hard way: leave the last case's avatar in the tree and it is still falling
## through the next case's enemy.
##
## The position is set BEFORE add_child, and that is the whole test. An avatar
## added at the origin and moved afterwards is registered with the physics
## server at the origin, and area monitoring runs a frame behind — so the
## enemy's stomp strip reports an overlap with an avatar that is by then two
## hundred pixels away, and every offset "lands". The contact suite never saw
## this because its avatar is genuinely on top of the enemy either way.
func _dive_at(offset: float) -> bool:
	var stage := Node2D.new()
	_root.add_child(stage)

	var enemy: Node2D = load("res://scenes/Golem.tscn").instantiate()
	enemy.position = Vector2.ZERO
	stage.add_child(enemy)
	var cyn: CharacterBody2D = PLAYER_SCENE.instantiate()
	cyn.character = ROSTER.by_id(&"cyn")
	cyn.position = Vector2(offset, -40)
	stage.add_child(cyn)
	if enemy.has_method("set_player_ref"):
		enemy.set_player_ref(cyn)
	cyn.velocity = Vector2(0, 200.0)
	cyn.dashing_down = true
	for i in 6:
		await get_tree().physics_frame

	var died := not is_instance_valid(enemy) or enemy.is_queued_for_deletion()
	if not died:
		var combat := enemy.get_node_or_null("Combat")
		died = combat != null and combat.is_dead
	stage.free()
	return died


# ── The attack each climber swings ──────────────────────────────────────────
## The ATTACK upgrade spawns whatever the character's own scene is, and it lands
## in the "strike" group like everything else that can hurt an enemy — so no
## enemy has to know either weapon exists.
func test_each_climber_spawns_its_own_attack() -> void:
	for id in [&"cyn", &"tessa"]:
		var avatar := _avatar(id)
		avatar.has_attack = true
		avatar._spawn_strike()
		var spawned: Node = null
		for child in _root.get_children():
			if child.is_in_group(&"strike"):
				spawned = child
		assert_object(spawned) \
			.override_failure_message("%s's attack spawned nothing" % id).is_not_null()
		assert_str(spawned.scene_file_path) \
			.is_equal(avatar.character.attack_scene.resource_path)
		spawned.free()


# ── The shot ────────────────────────────────────────────────────────────────
## Only Tessa carries a gun, and the whole of "Cyn cannot shoot" is that her
## CharacterDef has no ranged scene — not a branch anywhere.
func test_only_tessa_has_something_to_shoot_with() -> void:
	assert_object(ROSTER.by_id(&"tessa").ranged_scene) \
		.override_failure_message("Tessa's pistol is not wired to a scene").is_not_null()
	assert_object(ROSTER.by_id(&"cyn").ranged_scene) \
		.override_failure_message("Cyn has no gun; her ranged scene must stay empty").is_null()


func test_the_gun_is_one_of_tessas_upgrades() -> void:
	var ids: Array[StringName] = []
	for upgrade in ROSTER.by_id(&"tessa").upgrades:
		ids.append(upgrade.id)
	assert_array(ids).contains([&"gun"])
	# And nobody else's.
	for upgrade in ROSTER.by_id(&"cyn").upgrades:
		assert_int(upgrade.effect) \
			.override_failure_message("Cyn was offered a ranged upgrade") \
			.is_not_equal(UpgradeDef.Effect.RANGED)


## The bullet leaves the muzzle, on the side being faced, and it is a "strike"
## like every other thing that can hurt an enemy — so no enemy scene has to
## learn that guns exist.
func test_the_shot_leaves_the_muzzle_on_the_side_being_faced() -> void:
	for facing in [true, false]:
		var tessa := _avatar(&"tessa")
		tessa.has_ranged = true
		tessa.facing_right = facing
		tessa.global_position = Vector2(500, -1000)
		var muzzle: Vector2 = tessa.muzzle_position()
		assert_bool(muzzle.x > tessa.global_position.x) \
			.override_failure_message("the muzzle is on the wrong side for facing_right=%s" % facing) \
			.is_equal(facing)

		tessa._try_shoot()
		var bullet: Node = null
		for child in _root.get_children():
			if child.is_in_group(&"strike"):
				bullet = child
		assert_object(bullet) \
			.override_failure_message("firing spawned no bullet").is_not_null()
		assert_vector(bullet.global_position).is_equal_approx(muzzle, Vector2.ONE)
		assert_int(int(bullet.get_meta(&"owner_peer", -1))) \
			.override_failure_message("the bullet carries no kill credit").is_equal(tessa.peer_id)
		bullet.free()


func test_the_gun_has_a_cooldown() -> void:
	var tessa := _avatar(&"tessa")
	tessa.has_ranged = true
	assert_float(tessa.ranged_cd_timer.wait_time) \
		.override_failure_message("Tessa's pistol cooldown did not come from her CharacterDef") \
		.is_equal(ROSTER.by_id(&"tessa").ranged_cooldown)

	tessa._try_shoot()
	tessa._try_shoot() # blocked: the timer is running
	var bullets := 0
	for child in _root.get_children():
		if child.is_in_group(&"strike"):
			bullets += 1
	assert_int(bullets) \
		.override_failure_message("the pistol fired twice inside its cooldown").is_equal(1)


func test_a_bullet_flies_the_way_it_was_fired_and_dies_on_a_wall() -> void:
	for facing in [true, false]:
		var stage := Node2D.new()
		_root.add_child(stage)
		var bullet: Area2D = load("res://scenes/Bullet.tscn").instantiate()
		bullet.setup(_avatar(&"tessa"), facing, Vector2(0, -2000))
		stage.add_child(bullet)
		var start: float = bullet.global_position.x
		for i in 4:
			await get_tree().physics_frame
		var moved: float = bullet.global_position.x - start
		assert_bool(moved > 0.0) \
			.override_failure_message("a bullet fired facing_right=%s went the wrong way" % facing) \
			.is_equal(facing)
		assert_float(absf(moved)) \
			.override_failure_message("the bullet barely moved").is_greater(30.0)
		stage.free()


func test_a_bullet_stops_at_a_wall() -> void:
	var stage := Node2D.new()
	_root.add_child(stage)
	# A slab of world geometry a short flight to the right.
	var wall := StaticBody2D.new()
	wall.collision_layer = Layers.WORLD
	var col := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(64, 400)
	col.shape = box
	wall.add_child(col)
	wall.position = Vector2(300, -2000)
	stage.add_child(wall)

	var bullet: Area2D = load("res://scenes/Bullet.tscn").instantiate()
	bullet.setup(_avatar(&"tessa"), true, Vector2(0, -2000))
	stage.add_child(bullet)
	for i in 30:
		await get_tree().physics_frame
		if not is_instance_valid(bullet):
			break
	assert_bool(is_instance_valid(bullet) and not bullet.is_queued_for_deletion()) \
		.override_failure_message("the bullet went straight through a wall").is_false()
	stage.free()

extends GdUnitTestSuite
## The bomb: what sets it off, what does not, and what happens when it does.
##
## The load-bearing asymmetry here is the mirror image of the enemy contact
## matrix. A bomb is NOT an enemy:
##
##   contact                  falling bomb        thrown bomb
##   the level (a platform)   passes through      goes off
##   the player               goes off            goes off
##   a dash from above        goes off            goes off
##   Strike / Shockwave       thrown, not fired   nothing (it is already going)
##   a spitter's acid blob    goes off            goes off
##   an enemy                 ignored             goes off
##
## Passing through the level is the whole reason bombs do not quietly demolish
## the climb above you before you arrive, so it is the first thing to break if
## someone gives the bomb a move_and_collide in its falling branch.
##
## Every case builds its own container and frees it immediately afterwards —
## the enemy contact suite learned the hard way that a petrified golem left in
## the tree becomes solid ground for the next case.

const BOMB := "res://scenes/Bomb.tscn"
const PLATFORM := "res://scenes/Platform.tscn"
const PLAYER := "res://scenes/Player.tscn"
const STRIKE := "res://scenes/Strike.tscn"
const PROJECTILE := "res://scenes/Projectile.tscn"

var root: Node2D


func before_test() -> void:
	Game.new_run()
	root = Node2D.new()
	add_child(root)
	# Fireballs, rubble and the blast's own hitbox live under the effects root,
	# the same opt-in World does in _ready.
	Fx.effects_root = root
	Audio.world_root = root
	Fx.listener_position = Vector2.ZERO


func after_test() -> void:
	Fx.effects_root = null
	Audio.world_root = null
	Fx.listener_position = Vector2.ZERO
	if is_instance_valid(root):
		root.free()


## Physics frames, never wall-clock: an earlier harness in this repo waited
## milliseconds and the first case in a run spent its budget loading scenes.
func _step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## Position BEFORE add_child, the way World spawns everything. Moving a body
## after it has entered the tree leaves the physics server holding the overlap it
## had at the origin for one step — which here meant a player parked 44 px clear
## of a bomb still setting it off.
func _spawn(path: String, at: Vector2) -> Node2D:
	var node: Node2D = load(path).instantiate()
	node.position = at
	root.add_child(node)
	return node


func _bomb(at: Vector2 = Vector2.ZERO) -> CharacterBody2D:
	return _spawn(BOMB, at) as CharacterBody2D


func _player(at: Vector2) -> CharacterBody2D:
	return _spawn(PLAYER, at) as CharacterBody2D


## An avatar that exists so enemies have something to track, and does nothing
## else: level with them so nothing despawns, far enough sideways that no blast
## at the origin touches it, and frozen so it does not fall out of either role.
func _frozen_bystander() -> CharacterBody2D:
	var player := _player(Vector2(4000, 0))
	player.can_input = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player


## Variant, not Node: GDScript refuses to bind an already-freed object to a
## typed parameter, and "already freed" is exactly the answer being asked for.
func _gone(node: Variant) -> bool:
	return not is_instance_valid(node) or (node as Node).is_queued_for_deletion()


# ── Falling ─────────────────────────────────────────────────────────────────
## "A shade quicker than the golem and the slime" is a feel requirement, so it
## is measured rather than read off a constant: whatever the three scripts do
## per frame, the bomb has to end up lower.
func test_a_bomb_falls_faster_than_a_golem_and_a_slime() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var golem := _spawn("res://scenes/Golem.tscn", Vector2(300, 0))
	var slime := _spawn("res://scenes/Slime.tscn", Vector2(600, 0))
	await _step(60)
	assert_float(bomb.global_position.y) \
		.override_failure_message("the bomb did not out-fall the golem") \
		.is_greater(golem.global_position.y)
	assert_float(bomb.global_position.y) \
		.override_failure_message("the bomb did not out-fall the slime") \
		.is_greater(slime.global_position.y)


## The rule the whole design rests on. A falling bomb is not a physical body as
## far as the pit is concerned — it goes through platforms exactly like the
## golem and the slime do, so nothing above you is demolished by bombs you never
## saw.
func test_a_falling_bomb_passes_through_a_platform_without_going_off() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var platform := _spawn(PLATFORM, Vector2(0, 200))
	await _step(90)
	assert_bool(_gone(bomb)) \
		.override_failure_message("a bomb went off on level geometry while merely falling") \
		.is_false()
	assert_bool(_gone(platform)) \
		.override_failure_message("a falling bomb destroyed a platform it should have fallen through") \
		.is_false()
	assert_float(bomb.global_position.y) \
		.override_failure_message("the bomb stopped on the platform instead of passing through") \
		.is_greater(240.0)


# ── The player sets it off ──────────────────────────────────────────────────
## Walking into one is the worst way to find a bomb: it goes off against your
## body, and that case is deliberately harsher than being caught in a blast —
## two hearts rather than one.
func test_touching_a_bomb_sets_it_off_and_costs_two_hearts() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var player := _player(Vector2(0, -40))
	player.velocity = Vector2(0, 200.0)
	await _step(20)
	assert_bool(_gone(bomb)) \
		.override_failure_message("walking into a bomb did not set it off").is_true()
	assert_int(player.health) \
		.override_failure_message("a bomb against the body cost %d hearts, expected 2" \
			% (5 - player.health)) \
		.is_equal(3)


## A bomb is not something you can stomp. The dash only gets you there sooner —
## it still goes off, and it still goes off in your face.
func test_a_dash_down_onto_a_bomb_sets_it_off_and_still_hurts() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var player := _player(Vector2(0, -40))
	player.velocity = Vector2(0, 3600.0)
	player.dashing_down = true
	await _step(20)
	assert_bool(_gone(bomb)) \
		.override_failure_message("a dash-down did not set the bomb off").is_true()
	assert_int(player.health) \
		.override_failure_message("dashing onto a bomb was treated as a free stomp") \
		.is_equal(3)


## A corpse is not a trigger. Without this a bomb pops on the body of a player
## who is already mid-death-tween.
func test_a_dead_avatar_does_not_set_a_bomb_off() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var player := _player(Vector2(0, -20))
	player.health = 0
	await _step(20)
	assert_bool(_gone(bomb)) \
		.override_failure_message("a bomb went off on a dead avatar").is_false()


# ── Being hit by an ability ─────────────────────────────────────────────────
## A punch throws it rather than setting it off, and throws it AWAY: the player
## sits on the left here, so the bomb has to end up to the right of where it
## started, and higher than a straight fall would have left it.
func test_a_strike_throws_the_bomb_away_from_the_player() -> void:
	var bomb := _bomb(Vector2(0, 0))
	# Close enough for the fist, too far for the body.
	var player := _player(Vector2(-100, 0))
	player.can_input = false
	var strike: Area2D = load(STRIKE).instantiate()
	strike.setup(player, true)
	strike.position = Vector2(-48, 0)
	root.add_child(strike)

	await _step(30)
	assert_bool(_gone(bomb)) \
		.override_failure_message("a punch set the bomb off instead of throwing it") \
		.is_false()
	assert_bool(bomb.launched) \
		.override_failure_message("the bomb was not thrown at all").is_true()
	assert_float(bomb.global_position.x) \
		.override_failure_message("the bomb was not thrown away from the player") \
		.is_greater(60.0)
	assert_float(absf(bomb.rotation)) \
		.override_failure_message("the bomb slid instead of tumbling") \
		.is_greater(0.1)


## And once it is in the air, the first thing it touches ends it — which is what
## makes a thrown bomb a tool: that platform is gone because it was aimed at.
##
## The target is a tall slab rather than a plank, deliberately. A thrown bomb
## arcs — apex about 80 px up, back down half a screen away — so a 32 px plank
## placed by hand is a test of my arithmetic rather than of the bomb, and the
## first version of this case sailed clean over one.
func test_a_thrown_bomb_goes_off_on_the_first_thing_it_hits() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var player := _player(Vector2(-100, 0))
	player.can_input = false
	var strike: Area2D = load(STRIKE).instantiate()
	strike.setup(player, true)
	strike.position = Vector2(-48, 0)
	root.add_child(strike)

	var slab: StaticBody2D = load(PLATFORM).instantiate()
	var col: CollisionShape2D = slab.get_node("CollisionShape2D")
	col.shape = col.shape.duplicate() # the scene shares the sub-resource
	col.shape.size = Vector2(64, 900)
	slab.position = Vector2(300, 0)
	root.add_child(slab)

	await _step(120)
	assert_bool(_gone(bomb)) \
		.override_failure_message("a thrown bomb bounced off the level instead of going off") \
		.is_true()
	assert_bool(_gone(slab)) \
		.override_failure_message("the platform it was thrown at survived") \
		.is_true()


## Thrown along the line away from the swing, not merely sideways. A hitbox
## directly BELOW the bomb has to send it up, and leave it roughly where it was
## horizontally.
##
## The strike is set up with no owner so it does not snap itself to a player's
## side every frame — it stays where the test put it.
func test_a_hit_from_below_throws_the_bomb_upward() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var strike: Area2D = load(STRIKE).instantiate()
	strike.setup(null, true)
	strike.position = Vector2(0, 70)
	root.add_child(strike)

	await _step(25)
	assert_bool(_gone(bomb)) \
		.override_failure_message("the bomb went off instead of being thrown").is_false()
	assert_bool(bomb.launched).is_true()
	assert_float(bomb.global_position.y) \
		.override_failure_message("a hit from below did not throw the bomb upward (y=%.0f)" \
			% bomb.global_position.y) \
		.is_less(-40.0)
	assert_float(absf(bomb.global_position.x)) \
		.override_failure_message("a hit from straight below pushed it sideways (x=%.0f)" \
			% bomb.global_position.x) \
		.is_less(80.0)


## And how far depends on how squarely it was caught. Two bombs, two hits of the
## same kind: one right against the middle of the swing, one clipped by its edge.
## Both are in the same case on purpose — they must be compared under identical
## timing.
func test_a_centred_hit_throws_the_bomb_much_further_than_a_clipped_one() -> void:
	var centred := _bomb(Vector2(0, 0))
	var clipped := _bomb(Vector2(3000, 0))
	for spec in [[centred, Vector2(-8, 0)], [clipped, Vector2(3000 - 48, 0)]]:
		var strike: Area2D = load(STRIKE).instantiate()
		strike.setup(null, true)
		strike.position = spec[1]
		root.add_child(strike)

	await _step(2)
	var from_centred: Vector2 = centred.global_position
	var from_clipped: Vector2 = clipped.global_position
	await _step(18)
	var travel_centred := from_centred.distance_to(centred.global_position)
	var travel_clipped := from_clipped.distance_to(clipped.global_position)
	assert_float(travel_centred) \
		.override_failure_message("centred %.0f px vs clipped %.0f px — the swing's reach is not being read" \
			% [travel_centred, travel_clipped]) \
		.is_greater(travel_clipped * 1.3)


## An expanding ring has to advertise its FULL reach, not the radius it happens
## to have when it touches something. It grows outward, so it always meets a bomb
## exactly when it has grown far enough to reach it — measured against the
## current radius, every bomb is at the edge of the wave and none of them would
## ever be thrown hard, which is the opposite of "closer to the middle throws
## further".
func test_a_shockwave_advertises_its_full_reach_not_its_current_one() -> void:
	var player := _player(Vector2.ZERO)
	player.can_input = false
	var wave: Node2D = load("res://scenes/Shockwave.tscn").instantiate()
	wave.setup(player)
	root.add_child(wave)
	var hit_area: Area2D = wave.get_node("HitArea")

	await _step(2)
	var early: float = float(hit_area.get_meta(&"hit_reach", 0.0))
	var early_radius: float = (hit_area.get_node("CollisionShape2D").shape as CircleShape2D).radius
	await _step(20)
	var late: float = float(hit_area.get_meta(&"hit_reach", 0.0))

	assert_float(early) \
		.override_failure_message("the ring reported a reach of %.0f while only %.0f px across" \
			% [early, early_radius]) \
		.is_greater(early_radius)
	assert_float(late) \
		.override_failure_message("the advertised reach changed as the ring grew (%.0f -> %.0f)" \
			% [early, late]) \
		.is_equal_approx(early, 0.5)


# ── The spitter ─────────────────────────────────────────────────────────────
func test_an_acid_blob_sets_a_bomb_off() -> void:
	var bomb := _bomb(Vector2(0, 0))
	var player := _player(Vector2(-200, 0))
	player.can_input = false
	var blob: Area2D = load(PROJECTILE).instantiate()
	root.add_child(blob)
	blob.setup(Vector2(-10, 0), Vector2(400, 0), player)

	await _step(20)
	assert_bool(_gone(bomb)) \
		.override_failure_message("a spitter's blob passed straight through a bomb") \
		.is_true()
	assert_bool(_gone(blob)) \
		.override_failure_message("the blob survived the explosion it caused") \
		.is_true()


# ── What the blast reaches ─────────────────────────────────────────────────
## Everything alive inside the radius, not just what the bomb touched. The blast
## kills through the same "strike" hitbox a punch does, which is why no enemy
## scene had to learn that bombs exist.
func test_the_blast_kills_every_enemy_inside_it() -> void:
	var enemies: Array[Node2D] = []
	var labels: Array[String] = []
	var x := -400.0
	for path in ["res://scenes/Golem.tscn", "res://scenes/Slime.tscn",
			"res://scenes/Pursuer.tscn", "res://scenes/Bat.tscn",
			"res://scenes/Spitter.tscn"]:
		var e := _spawn(path, Vector2(x, 0))
		enemies.append(e)
		labels.append(String(e.name)) # read now: most of them will be freed
		x += 200.0
	# Level with the enemies but well outside the radius, and frozen. Level,
	# because an enemy despawns once it is despawn_below beneath the avatar it is
	# tracking — parking the player far above made every enemy leave on its own
	# and the assertion below pass for the wrong reason.
	var player := _frozen_bystander()
	for e in enemies:
		if e.has_method("set_player_ref"):
			e.set_player_ref(player)

	var def: BlastDef = load("res://data/fx/blast.tres")
	Blast.detonate(root, Vector2.ZERO, def, 1, Blast.targets(root, Vector2.ZERO, def))
	await _step(20)

	for i in enemies.size():
		if _gone(enemies[i]):
			continue # freed itself, which is the usual death
		var combat: EnemyCombat = enemies[i].get_node_or_null("Combat")
		assert_bool(combat != null and combat.is_dead) \
			.override_failure_message("%s survived a blast it was standing in" % labels[i]) \
			.is_true()


func test_the_blast_spares_what_is_outside_its_radius() -> void:
	var def: BlastDef = load("res://data/fx/blast.tres")
	var far := _spawn("res://scenes/Golem.tscn", Vector2(def.radius + 400.0, 0))
	var player := _frozen_bystander()
	far.set_player_ref(player)

	Blast.detonate(root, Vector2.ZERO, def, 1, Blast.targets(root, Vector2.ZERO, def))
	await _step(20)
	assert_bool(_gone(far)) \
		.override_failure_message("the blast reached an enemy well outside its radius") \
		.is_false()
	var combat: EnemyCombat = far.get_node_or_null("Combat")
	assert_bool(combat.is_dead) \
		.override_failure_message("an enemy outside the radius was marked dead") \
		.is_false()


# ── Being thrown by a blast ─────────────────────────────────────────────────
## Away from the epicentre along BOTH axes, not just sideways.
##
## Flight is switched on to take gravity out: over the handful of frames a test
## can afford to wait, a fall swamps the vertical half of the push and the
## assertion would be measuring g. The shove itself does not care about flight.
func test_a_blast_throws_the_player_along_both_axes() -> void:
	var player := _player(Vector2.ZERO)
	player.flying = true
	var def: BlastDef = load("res://data/fx/blast.tres")
	Blast.detonate(root, Vector2(-300, 300), def, -1, PackedStringArray())
	await _step(15)
	assert_float(player.global_position.x) \
		.override_failure_message("not thrown away horizontally (x=%.0f)" \
			% player.global_position.x) \
		.is_greater(30.0)
	assert_float(player.global_position.y) \
		.override_failure_message("not thrown away vertically (y=%.0f)" \
			% player.global_position.y) \
		.is_less(-30.0)


## The shove reaches further than the damage does, deliberately: a bomb going off
## nearby should move you even when it never got close enough to hurt you.
func test_a_blast_moves_you_even_when_it_did_not_hurt_you() -> void:
	var def: BlastDef = load("res://data/fx/blast.tres")
	var beyond_harm := def.radius + (def.push_radius - def.radius) * 0.5
	var player := _player(Vector2(beyond_harm, 0))
	Blast.detonate(root, Vector2.ZERO, def, -1, PackedStringArray())
	await _step(20)
	assert_int(player.health) \
		.override_failure_message("a blast %.0f px away hurt a player it should not reach" \
			% beyond_harm) \
		.is_equal(5)
	assert_float(player.global_position.x) \
		.override_failure_message("standing %.0f px out, the blast did not move the player" \
			% beyond_harm) \
		.is_greater(beyond_harm + 20.0)


func test_beyond_its_push_radius_a_blast_leaves_you_alone() -> void:
	var def: BlastDef = load("res://data/fx/blast.tres")
	var far := def.push_radius + 300.0
	var player := _player(Vector2(far, 0))
	Blast.detonate(root, Vector2.ZERO, def, -1, PackedStringArray())
	await _step(20)
	assert_float(absf(player.global_position.x - far)) \
		.override_failure_message("a blast well outside its push radius still moved the player") \
		.is_less(1.0)


## The point-blank case is the same mechanic with a much bigger number, and this
## is the number being asserted: walking into one throws you far further than
## standing next to one that went off.
func test_a_bomb_against_the_body_throws_you_far_further() -> void:
	var caught := await _blast_travel(false)
	var point_blank := await _blast_travel(true)
	assert_float(point_blank) \
		.override_failure_message("point blank threw the player %.0f px, merely nearby %.0f px" \
			% [point_blank, caught]) \
		.is_greater(caught * 1.8)


## One blast, one throwaway stage, the distance the player covered. Flight is on
## for the same reason as above — this is measuring the push, not gravity.
func _blast_travel(point_blank: bool) -> float:
	var stage := Node2D.new()
	root.add_child(stage)
	var player: CharacterBody2D = load(PLAYER).instantiate()
	player.position = Vector2.ZERO
	stage.add_child(player)
	player.flying = true
	await _step(2)

	var def: BlastDef = load("res://data/fx/blast.tres")
	var from := player.global_position
	Blast.detonate(stage, Vector2(0, 90), def, -1, PackedStringArray(),
		Game.local_peer_id if point_blank else -1)
	await _step(15)
	var travel := from.distance_to(player.global_position)
	stage.free()
	return travel


# ── Credit ──────────────────────────────────────────────────────────────────
func test_setting_a_bomb_off_scores_for_whoever_did_it() -> void:
	var def: BlastDef = load("res://data/fx/blast.tres")
	var bomb := _bomb(Vector2(0, 0))
	var player := _player(Vector2(0, -40))
	player.velocity = Vector2(0, 200.0)
	await _step(20)
	assert_bool(_gone(bomb)).is_true()
	assert_int(Game.local_run().score) \
		.override_failure_message("nobody was credited for a bomb the player set off") \
		.is_equal(def.score)


## A blast with no author pays nobody. Otherwise the host quietly collects points
## for every bomb the pit sets off on its own, three levels away.
func test_a_blast_nobody_caused_scores_nothing() -> void:
	var def: BlastDef = load("res://data/fx/blast.tres")
	var player := _player(Vector2(0, -3000))
	player.can_input = false
	Blast.detonate(root, Vector2.ZERO, def, -1, PackedStringArray())
	await _step(4)
	assert_int(Game.local_run().score) \
		.override_failure_message("an unattributed blast paid out anyway") \
		.is_equal(0)

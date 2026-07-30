extends CharacterBody2D
## Bomb — a cracked drone head with a live core, tumbling down the pit.
##
## It falls straight THROUGH the level, exactly like the golem and the slime do:
## no geometry sets it off, so bombs do not quietly demolish the climb above you
## before you get there. What sets one off is a player: touching it, coming down
## on it, or — the interesting one — hitting it with a Strike or a Shockwave,
## which does not merely reverse its fall but throws it, spinning, on an arc.
## From that moment it is armed against everything, and where it lands is your
## problem or your plan. A spitter's acid blob will also set one off, from
## either side of that.
##
## Everything an explosion does lives in Blast; this script only decides when.
##
## Networking: the host simulates it and the MultiplayerSpawner mirrors it, like
## every other thing in the Enemies container. Detonation is the host's call
## (it is the machine that can see every avatar) and travels as one event.

enum State {FALLING, LAUNCHED, SPENT}

@export var stats: BombStats

## Set once it has been batted. Replicated so every machine can draw the trail —
## the trail is a cosmetic and cosmetics are always local, but they need to know
## the state to fire from.
var launched: bool = false

var state: int = State.FALLING
var _velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
## Who gets the credit — and the points — when it goes off. -1 is nobody.
var _credit: int = -1
var _trail: float = 0.0
var _player: CharacterBody2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var contact: Area2D = $ContactArea


## Called by the spawner before this node enters the tree, when @onready values
## are still null — so it must not touch them.
func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _ready() -> void:
	contact.body_entered.connect(_on_body)
	contact.area_entered.connect(_on_area)


func _physics_process(delta: float) -> void:
	if launched:
		_trail += delta
		if _trail >= 0.04:
			_trail = 0.0
			Fx.ghost(sprite, Color(1.0, 0.55, 0.3, 0.45))

	if not Net.is_sim_authority():
		return # motion is mirrored from the host
	if state == State.SPENT:
		return

	if state == State.FALLING:
		# No move_and_collide, so the level is not there as far as it is
		# concerned. Same as the golem and the slime, on purpose.
		position.y += stats.fall_speed * delta
		_despawn_if_left_behind()
		return

	_velocity.y += stats.launch_gravity * delta
	rotation += _spin * delta
	if move_and_collide(_velocity * delta) != null:
		_detonate_soon(_credit)
		return
	_despawn_if_left_behind()


# ── What sets it off ────────────────────────────────────────────────────────
func _on_body(body: Node2D) -> void:
	if not Net.is_sim_authority() or state == State.SPENT:
		return
	if body.is_in_group(&"player"):
		# Any touch does it, dash or no dash — a bomb is not something you can
		# stomp, and the dash only gets you there sooner.
		#
		# Body contact is the point-blank case, and that peer is named separately
		# from the credit: a bomb somebody else threw into you still earns THEM
		# the points, and still goes off in YOUR face.
		if int(body.get("health")) <= 0:
			return
		var victim := int(body.get("peer_id"))
		_detonate_soon(_credit if state == State.LAUNCHED else victim, victim)
		return
	if state == State.LAUNCHED:
		_detonate_soon(_credit)


func _on_area(area: Area2D) -> void:
	if not Net.is_sim_authority() or state == State.SPENT:
		return
	if area.is_in_group(&"strike"):
		# A punch never sets it off in either state; it throws it. Note that a
		# blast's own hitbox is in this group too, so an explosion punts any
		# other bomb it engulfs instead of setting it off — it flies out and goes
		# off on whatever it lands on, credited to whoever started the chain.
		if state == State.FALLING:
			_launch(area)
		return
	if area.is_in_group(&"enemy_projectile"):
		# The spitter has no idea what it just hit. Nobody is credited for a
		# bomb the pit set off on its own. Only the authority gets here, so the
		# blob is ours to free and the spawner mirrors it.
		_detonate_soon(-1)
		area.queue_free()
		return
	if state == State.LAUNCHED:
		# In flight everything counts: another bomb, a golem, a spitter.
		_detonate_soon(_credit)


## Batted away by a Strike or a Shockwave. It does not change direction — it is
## thrown, along the line away from wherever the swing came from, and it keeps
## the momentum until something stops it.
##
## How far depends on how squarely it was caught. Every hitbox stamps its own
## reach on itself (`hit_reach`), so "at the centre of the swing" means the same
## thing for a punch, for a Shockwave that has grown to 300 px, and for another
## explosion — and a bomb caught right against you goes roughly twice as far as
## one clipped by the outer edge of the same ring.
func _launch(area: Area2D) -> void:
	var offset := global_position - area.global_position
	if offset.length_squared() < 4.0:
		# Dead centre: nothing to push along, so pick a side and lob it.
		offset = Vector2(1.0 if randf() < 0.5 else -1.0, -0.4)
	var away := offset.normalized()

	var reach: float = maxf(float(area.get_meta(&"hit_reach", stats.launch_default_reach)), 1.0)
	var centrality := 1.0 - clampf(offset.length() / reach, 0.0, 1.0)
	var power: float = lerpf(stats.launch_power_min, 1.0, centrality)

	state = State.LAUNCHED
	launched = true
	_credit = int(area.get_meta(&"owner_peer", -1))
	_velocity = (away * stats.launch_speed + Vector2(0.0, stats.launch_lift)) * power
	_spin = signf(away.x) * stats.launch_spin * power
	if is_zero_approx(_spin):
		_spin = stats.launch_spin * power
	if stats.launch_sound != &"":
		Audio.play_at(stats.launch_sound, global_position)


## Going off restructures the tree — platforms are freed, areas stop watching —
## and we are usually inside an Area2D signal while the physics server is still
## iterating. Deferred, for the same reason the golem defers petrifying.
func _detonate_soon(credited_peer: int, point_blank_peer: int = -1) -> void:
	if state == State.SPENT:
		return
	state = State.SPENT
	_explode.call_deferred(credited_peer, point_blank_peer)


func _explode(credited_peer: int, point_blank_peer: int) -> void:
	# Deferred by one frame, so it is worth asking whether we are still anybody's
	# business: a bomb can be touched on the same frame it falls out of the world
	# and despawns itself.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var epicentre := global_position
	var doomed := Blast.targets(self, epicentre, stats.blast)
	if Net.active:
		_boom.rpc(epicentre, doomed, credited_peer, point_blank_peer)
	else:
		_boom(epicentre, doomed, credited_peer, point_blank_peer)


## The event. The epicentre travels rather than being read from our replicated
## position, so every machine puts the fireball, the rubble and the sound in
## exactly the same place whatever their packets were doing that frame.
@rpc("authority", "call_local", "reliable")
func _boom(epicentre: Vector2, doomed: PackedStringArray, credited_peer: int,
		point_blank_peer: int) -> void:
	state = State.SPENT
	launched = false
	# Cut up and thrown before it is hidden, so the shell is seen to come apart
	# rather than to disappear. Stands in for the explosion frames.
	Fx.shards(sprite, stats.shards)
	visible = false
	Blast.detonate(self, epicentre, stats.blast, credited_peer, doomed, point_blank_peer)
	# Only the sim authority frees: the MultiplayerSpawner mirrors the removal,
	# and a client that frees it itself leaves the host despawning a node that
	# is no longer there.
	if Net.is_sim_authority():
		queue_free()


# ── Housekeeping ────────────────────────────────────────────────────────────
## Same rule as an enemy: once it is far enough below the avatar it is tracking,
## it is nobody's problem. Retargets to the nearest living avatar first, which is
## the seam EnemyCombat uses for the same reason.
func _despawn_if_left_behind() -> void:
	var nearest := _nearest_avatar()
	if nearest != null:
		_player = nearest
	if not is_instance_valid(_player):
		return
	if global_position.y > _player.global_position.y + stats.despawn_below:
		queue_free()


func _nearest_avatar() -> CharacterBody2D:
	var best: CharacterBody2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"player"):
		var avatar := node as CharacterBody2D
		if avatar == null or not is_instance_valid(avatar) or int(avatar.get("health")) <= 0:
			continue
		var d := global_position.distance_squared_to(avatar.global_position)
		if d < best_distance:
			best_distance = d
			best = avatar
	return best

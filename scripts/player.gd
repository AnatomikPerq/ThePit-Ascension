extends CharacterBody2D
## Player controller for "The PIT: Ascension"
## All physics values are ×2 scaled from original Pygame version.

# ── Constants (×2 from legacy) ──────────────────────────────────────────────
const GRAVITY: float = 5760.0 # 0.8 * 60 * 60 * 2
const TERMINAL_VELOCITY: float = 1800.0 # 15 * 60 * 2
const SPEED: float = 600.0 # 300 * 2
const JUMP_FORCE: float = -1800.0 # -15 * 60 * 2
const DASH_SPEED: float = 3600.0 # 30 * 60 * 2
const FLIGHT_SPEED: float = 1000.0 # 500 * 2
const KNOCKBACK_FORCE: float = -1200.0 # -10 * 60 * 2
const HARD_LANDING_SPEED: float = 900.0 # fall speed that kicks up dust
## Crush recovery: the pop that gets you out and the sideways shove a rival's
## hit adds on top of the usual knockback. The phase-through window itself is
## CrushRecoveryTimer's wait_time.
const CRUSH_POP_FORCE: float = -900.0
const PVP_KNOCKBACK: float = 700.0
## Dash-stomping a rival in a race rebounds you exactly like a dash-killed
## enemy does (see data/enemies/*.tres).
const PVP_STOMP_REBOUND: float = -900.0
## A shockwave spawns on every machine, so its camera kick fades over this
## distance. Yours is at zero and lands in full.
const SHOCKWAVE_SHAKE_RANGE: float = 1800.0
## How fast the sideways half of an external shove bleeds off, in e-folds per
## second. See shove() for why only that half needs carrying.
const SHOVE_DECAY: float = 7.0

const STRIKE_SCENE: PackedScene = preload("res://scenes/Strike.tscn")
const SHOCKWAVE_SCENE: PackedScene = preload("res://scenes/Shockwave.tscn")

const DOUBLE_JUMP_BURST: BurstPreset = preload("res://data/fx/double_jump.tres")
const HURT_BURST: BurstPreset = preload("res://data/fx/player_hurt.tres")
const DEATH_BURST: BurstPreset = preload("res://data/fx/player_death.tres")

# ── State ───────────────────────────────────────────────────────────────────
## Which peer this avatar belongs to. 1 in solo; World assigns it on spawn.
## Kills, score and milestones are credited through it.
var peer_id: int = 1

## The seed of the run this avatar is climbing. The owning machine stamps it on
## spawn; a puppet holds -1 until its owner's first sync packet arrives.
##
## It is replicated ALWAYS, in the same packet as `position`, and that is the
## whole point. An avatar's node path is identical in every run, so after a host
## restart the previous run's position packets still land on the fresh puppet —
## and read as progress they earned the client a free upgrade at the bottom of
## the new pit, or would have ended the new run outright for anyone near the
## surface. Riding along with the position means a stale position arrives
## labelled stale, with no assumption about packet ordering.
var run_seed: int = -1

var health: int = 5
var max_health: int = 5

## Invincibility drives the blink animation directly, so nothing has to poll it
## every frame.
var invincible: bool = false:
	set(value):
		if invincible == value:
			return
		invincible = value
		if not is_node_ready():
			return
		if value:
			anim_player.play(&"blink")
		else:
			anim_player.stop()
			sprite.visible = true

var jump_count: int = 0
var has_double_jump: bool = false
var has_strike: bool = false
var has_shockwave: bool = false
var dashing_down: bool = false
var flying: bool = false
var is_crushed: bool = false

var facing_right: bool = true

var current_strike: Node = null
var current_shockwave: Node = null
var can_input: bool = true

var _trail_timer: float = 0.0
var _squash_tween: Tween
var _puppet_anim: StringName = &""
## Outstanding sideways push — see shove().
var _shove_x: float = 0.0

# ── Node References ─────────────────────────────────────────────────────────
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var inv_timer: Timer = $InvincibilityTimer
@onready var crush_timer: Timer = $CrushRecoveryTimer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var strike_cd_timer: Timer = $StrikeCooldownTimer
@onready var shockwave_cd_timer: Timer = $ShockwaveCooldownTimer
## Watches for hostile PLAYER_ATTACK hitboxes. It is on no layer at all, so
## nothing can see it back, and it only monitors in a race — the mode is a
## physical fact about the scene rather than an `if` in a hot path.
@onready var hurt_box: Area2D = $HurtBox

# ── Signals ─────────────────────────────────────────────────────────────────
signal player_damaged(new_health: int)
signal player_died


func _ready() -> void:
	inv_timer.timeout.connect(_on_invincibility_timeout)
	# Race: rivals are solid, so you can stand on a head — and their strikes
	# reach you. Co-op and solo: nothing changes, players pass through each
	# other and the hurt box never wakes up.
	set_collision_mask_value(Layers.BIT_PLAYER, Net.is_versus())
	# Only the machine steering this avatar watches for incoming hits. Damage
	# belongs to the victim; a puppet's overlap test here would be somebody
	# else's opinion about our health.
	hurt_box.monitoring = Net.is_versus() and is_multiplayer_authority()
	hurt_box.area_entered.connect(_on_hostile_area)


func _physics_process(delta: float) -> void:
	if Net.active and not is_multiplayer_authority():
		_puppet_process(delta)
		return

	if not can_input:
		velocity.x = 0.0
	else:
		_handle_input()

	if not flying:
		_apply_gravity(delta)

	_apply_shove(delta)

	# Coyote time: if just walked off edge, start timer
	var was_on_floor := is_on_floor()
	var was_dashing := dashing_down
	var fall_speed := velocity.y
	move_and_slide()
	var now_on_floor := is_on_floor()

	# Before the landing bookkeeping below clears the dash: in a race, coming
	# down on a rival's head is an attack, not a landing.
	if was_dashing and Net.is_versus():
		_resolve_versus_stomp()

	if was_on_floor and not now_on_floor and velocity.y >= 0:
		coyote_timer.start()

	if now_on_floor:
		if dashing_down:
			dashing_down = false
		jump_count = 0

	# Landing feedback: dust + thud + squash after a serious fall.
	if not was_on_floor and now_on_floor and fall_speed > HARD_LANDING_SPEED:
		Fx.dust(global_position + Vector2(0, 30), 12)
		Audio.play(&"land")
		_squash(Vector2(2.5, 1.5))

	# Cancel dash if moving upwards (e.g. trampolines, bounces)
	if velocity.y < 0:
		dashing_down = false

	# Dash trail ghosts.
	if dashing_down:
		_trail_timer += delta
		if _trail_timer >= 0.03:
			_trail_timer = 0.0
			Fx.ghost(sprite, Color(0.6, 0.85, 1.0, 0.45))

	if can_input and not invincible and not is_crushed:
		if _crushed_by_geometry():
			_handle_crush()
	elif is_crushed:
		_recover_from_crush()

	_update_animation()


## Remote avatar: position, velocity and state flags arrive from the owning
## peer's machine through the MultiplayerSynchronizer. Only presentation runs
## here — no input, no gravity, no collision response.
func _puppet_process(delta: float) -> void:
	sprite.flip_h = not facing_right
	if sprite.animation != _puppet_anim:
		_puppet_anim = sprite.animation
		sprite.play(_puppet_anim)
	if dashing_down:
		_trail_timer += delta
		if _trail_timer >= 0.03:
			_trail_timer = 0.0
			Fx.ghost(sprite, Color(0.6, 0.85, 1.0, 0.45))


# ── Gravity ─────────────────────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if dashing_down:
		return # Gravity ignored while dashing down

	velocity.y += GRAVITY * delta
	if velocity.y > TERMINAL_VELOCITY:
		velocity.y = TERMINAL_VELOCITY


## Is the player wedged in solid geometry right now?
##
## Probed against WORLD only. In a race rivals are solid bodies, and standing
## on somebody's head would otherwise read as a ceiling and crush the player
## underneath — a squeeze is a hazard of the level, not of the other climber.
func _crushed_by_geometry() -> bool:
	var saved := collision_mask
	collision_mask = Layers.WORLD
	# Cannot move in either direction along an axis, or already overlapping in
	# place (the diagonal squeeze).
	var stuck_h := test_move(global_transform, Vector2.RIGHT) and test_move(global_transform, Vector2.LEFT)
	var stuck_v := test_move(global_transform, Vector2.UP) and test_move(global_transform, Vector2.DOWN)
	var embedded := test_move(global_transform, Vector2.ZERO)
	collision_mask = saved
	return stuck_h or stuck_v or embedded


# ── Input ───────────────────────────────────────────────────────────────────
func _handle_input() -> void:
	# Toggle flight
	if Input.is_action_just_pressed("toggle_flight"):
		flying = not flying
		if flying:
			velocity.y = 0.0

	if flying:
		_handle_flight_input()
		return

	# Horizontal
	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * SPEED

	if dir > 0.0:
		facing_right = true
	elif dir < 0.0:
		facing_right = false

	# Dash down
	if Input.is_action_just_pressed("dash_down") and not is_on_floor():
		dashing_down = true
		velocity.y = DASH_SPEED
		_squash(Vector2(1.5, 2.5))

	# Jump (just_pressed events)
	if Input.is_action_just_pressed("jump"):
		_try_jump()

	# Attack
	if Input.is_action_just_pressed("attack") and has_strike:
		_try_strike()

	# Shockwave (radial blast) — unlocked upgrade, longer cooldown.
	if Input.is_action_just_pressed("shockwave") and has_shockwave:
		_try_shockwave()


func _handle_flight_input() -> void:
	var dir_x := Input.get_axis("move_left", "move_right")
	var dir_y := Input.get_axis("move_up", "move_down")
	velocity.x = dir_x * FLIGHT_SPEED
	velocity.y = dir_y * FLIGHT_SPEED

	if dir_x > 0.0:
		facing_right = true
	elif dir_x < 0.0:
		facing_right = false


# ── Jump ────────────────────────────────────────────────────────────────────
func _try_jump() -> void:
	if flying:
		return

	if is_on_floor() or not coyote_timer.is_stopped():
		velocity.y = JUMP_FORCE
		jump_count = 1
		coyote_timer.stop()
		dashing_down = false
		Fx.dust(global_position + Vector2(0, 30), 8)
		Audio.play(&"jump")
		_squash(Vector2(1.6, 2.4))
	elif has_double_jump and jump_count < 2:
		velocity.y = JUMP_FORCE * 0.9
		jump_count = 2
		dashing_down = false
		Fx.burst(global_position + Vector2(0, 20), DOUBLE_JUMP_BURST)
		Audio.play(&"double_jump")
		_squash(Vector2(1.6, 2.4))


# ── Strike ──────────────────────────────────────────────────────────────────
## Attacks spawn on EVERY machine: the host needs the hitbox to resolve
## kills, the others need the visual. The cooldown gates only the owner.
func _try_strike() -> void:
	if not strike_cd_timer.is_stopped():
		return
	strike_cd_timer.start()
	# The swing is ours to hear. It used to live inside the RPC below, which
	# spawns on every machine — so every punch anyone threw played in every
	# lobby, wherever in the pit it happened.
	Audio.play(&"strike")
	if Net.active:
		_spawn_strike.rpc()
	else:
		_spawn_strike()


@rpc("authority", "call_local", "reliable")
func _spawn_strike() -> void:
	var s := STRIKE_SCENE.instantiate()
	s.setup(self, facing_right)
	get_parent().add_child(s)
	current_strike = s


# ── Shockwave ────────────────────────────────────────────────────────────────
func _try_shockwave() -> void:
	if not shockwave_cd_timer.is_stopped():
		return
	shockwave_cd_timer.start()
	Audio.play(&"shockwave")
	if Net.active:
		_spawn_shockwave.rpc()
	else:
		_spawn_shockwave()


@rpc("authority", "call_local", "reliable")
func _spawn_shockwave() -> void:
	# Fired on every machine, so the kick has to be measured from where it went
	# off: a rival letting one off across the pit used to shake a camera nowhere
	# near it. At zero distance — your own blast — this is the same 0.45.
	Fx.shake_from(global_position, 0.45, SHOCKWAVE_SHAKE_RANGE)
	var wave := SHOCKWAVE_SCENE.instantiate()
	wave.setup(self)
	get_parent().add_child(wave)
	current_shockwave = wave


# ── Player versus player (race only) ────────────────────────────────────────
## A rival's Strike or Shockwave hitbox has reached us. Only our own machine
## ever gets here — the hurt box does not monitor on a puppet — so the rule
## "the victim owns its damage" holds without a single extra check.
func _on_hostile_area(area: Area2D) -> void:
	if int(area.get_meta(&"owner_peer", 0)) == peer_id:
		return # our own punch, passing through our own body
	if not take_damage():
		return
	# Shoved away from whoever hit us, on top of take_damage()'s knockback. This
	# used to write velocity.x directly, which _handle_input() overwrote on the
	# very next frame — the knockback was in the code and not on the screen.
	shove(area.global_position, PVP_KNOCKBACK)


## Coming down on a rival's head while dashing. The rebound is ours to apply;
## the hit is theirs to resolve, so it goes to their machine as a request.
func _resolve_versus_stomp() -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := hit.get_collider() as CharacterBody2D
		if other == null or other == self or not other.is_in_group(&"player"):
			continue
		if hit.get_normal().y > -0.5:
			continue # brushed their side, did not land on them
		if int(other.get("health")) <= 0:
			continue
		velocity.y = PVP_STOMP_REBOUND
		dashing_down = false
		Audio.play(&"stomp")
		Fx.shake(0.4)
		other.rpc_id(other.get_multiplayer_authority(), &"remote_hurt")
		return


# ── Being pushed around ─────────────────────────────────────────────────────
## Shoved away from a point, along both axes. The one entry point for "something
## moved this avatar without being its input": a blast uses it, a rival's hit
## uses it, and anything added later can.
##
## The two axes are handled differently, because the game already treats them
## differently:
##
## - **Vertical** is a plain impulse. `velocity.y` carries from frame to frame and
##   gravity is what takes it back, so adding to it once gives a real arc whose
##   height falls off with the strength — exactly what a blast under your feet
##   should do.
## - **Horizontal** has to be carried and bled off, because `_handle_input()`
##   reassigns `velocity.x` outright every single frame. A one-off write there is
##   gone before it moves anybody, which is what made the old rival knockback
##   invisible.
##
## Getting that split wrong is not subtle. Adding the whole vector to `velocity`
## every frame — which is what this did first — makes the vertical half an
## acceleration applied without a delta: it compounds into the velocity that
## carried over, and a bomb anywhere below you fired you off the top of the pit
## at roughly seventeen times the intended strength, near enough regardless of
## how far away it was.
##
## Only the machine steering this avatar may push it: velocity is its business,
## and a puppet's position arrives already moved.
func shove(from: Vector2, strength: float) -> void:
	if Net.active and not is_multiplayer_authority():
		return
	if strength <= 0.0 or is_crushed:
		return
	var dir := global_position - from
	if dir.length_squared() < 1.0:
		dir = Vector2.UP
	var push := dir.normalized() * strength
	velocity.y += push.y
	_shove_x += push.x
	dashing_down = false


func _apply_shove(delta: float) -> void:
	if absf(_shove_x) < 1.0:
		_shove_x = 0.0
		return
	velocity.x += _shove_x
	_shove_x = lerpf(_shove_x, 0.0, clampf(SHOVE_DECAY * delta, 0.0, 1.0))


# ── Damage & Crush ──────────────────────────────────────────────────────────
## `amount` is almost always one heart. A bomb that goes off against your body
## takes two, which is the only reason this is a parameter.
func take_damage(amount: int = 1) -> bool:
	# Health belongs to the owning machine; puppets never take damage locally.
	if Net.active and not is_multiplayer_authority():
		return false
	if invincible or flying or not can_input:
		return false
	health -= maxi(amount, 1)
	invincible = true
	inv_timer.start()
	velocity.y = KNOCKBACK_FORCE
	Audio.play(&"hurt")
	Fx.shake(0.35)
	Fx.flash(sprite)
	Fx.burst(global_position, HURT_BURST)
	player_damaged.emit(health)
	if health <= 0:
		_die()
	return true


## Being squeezed costs a heart and spits you out. The old penalty was two
## seconds of drifting downward at a fifth of gravity with the controls dead,
## which felt like a bug rather than a hit; this is a pop clear of the squeeze
## and a short intangible fall at normal speed.
func _handle_crush() -> void:
	is_crushed = true
	can_input = false
	velocity.x = 0.0
	velocity.y = CRUSH_POP_FORCE
	dashing_down = false
	_set_phasing(true)

	health -= 1
	invincible = true
	inv_timer.start()
	Audio.play(&"crush")
	Fx.shake(0.55)
	Fx.flash(sprite)
	Fx.dust(global_position, 10)
	# Squashed flat, then springing back — the shape of what just happened.
	_squash(Vector2(2.8, 1.2))
	player_damaged.emit(health)

	if health <= 0:
		_die()
	else:
		# A SceneTreeTimer keeps counting while the tree is paused, so pausing used
		# to serve the crush penalty for free. A Timer node pauses with the game,
		# the way InvincibilityTimer always did.
		crush_timer.start()


## Called every frame while crushed. CrushRecoveryTimer is read here rather
## than listened to, because the clock is only half the answer: the timer says
## when the penalty is served, the geometry says when it is safe to be solid.
func _recover_from_crush() -> void:
	# Fall safe: intangible means the floor is intangible too.
	var floor_y := _floor_limit()
	if global_position.y >= floor_y:
		global_position.y = floor_y
		velocity.y = 0.0
		_end_crush(true)
		return
	if crush_timer.is_stopped():
		_end_crush()


## Hand collision back. Not while still inside a wall: that is an instant
## re-crush and another heart, which is how a bad squeeze used to eat a whole
## run. `force` is the fall-safe path, where staying intangible is worse.
func _end_crush(force: bool = false) -> void:
	if not is_crushed or health <= 0:
		return
	if not force and _crushed_by_geometry():
		return # try again next frame
	is_crushed = false
	_set_phasing(false)
	can_input = true


## Intangible to everything you can be squeezed by or land on: level geometry,
## and in a race the rival who may be standing right where you popped out.
func _set_phasing(on: bool) -> void:
	set_collision_mask_value(Layers.BIT_WORLD, not on)
	set_collision_mask_value(Layers.BIT_PLAYER, Net.is_versus() and not on)


func _floor_limit() -> float:
	var world_node := get_parent()
	if world_node and "max_depth" in world_node:
		return world_node.max_depth - 100.0
	return 8000.0


func _die() -> void:
	if Net.active:
		_die_everywhere.rpc()
	else:
		_die_everywhere()


## Runs on every machine so the death is seen everywhere; only the owning
## machine emits player_died (its world shows the end screen) and the shake
## is scaled down for spectators.
@rpc("authority", "call_local", "reliable")
func _die_everywhere() -> void:
	can_input = false
	velocity.x = 0.0
	velocity.y = -600.0
	dashing_down = false
	sprite.rotation_degrees = -90.0
	collision_mask = Layers.NONE
	hurt_box.monitoring = false
	var mine := not Net.active or is_multiplayer_authority()
	# Announced everywhere, so it is a world sound with a long range rather than
	# a private one: ours plays at zero distance and full volume, and somebody
	# going down three levels up is not something we can hear.
	Audio.play_at(&"die", global_position)
	Fx.shake(0.7 if mine else 0.25)
	Fx.burst(global_position, DEATH_BURST)

	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void:
		if mine:
			player_died.emit()
		queue_free()
	)


## Harm resolved elsewhere, applied here — the machine that steers this avatar
## is the only one that may change its health.
##
## The host sends this for world hazards (a mistimed stomp onto an enemy). In a
## race a rival sends it for a stomp on our head, which is why the sender is not
## pinned to peer 1: peers in a session are trusted, the same assumption that
## lets a client tell the host it moved.
@rpc("any_peer", "call_remote", "reliable")
func remote_hurt() -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.get_remote_sender_id() == 1 or Net.is_versus():
		take_damage()


## Host-resolved stomp rebound for an avatar the host does not own. The sound
## comes with it rather than playing where the stomp was resolved: it is our
## avatar's boot, so it belongs on our machine and nobody else's.
@rpc("any_peer", "call_remote", "reliable")
func remote_stomp(rebound: float, sound: StringName = &"") -> void:
	if is_multiplayer_authority() and multiplayer.get_remote_sender_id() == 1:
		velocity.y = rebound
		dashing_down = false
		if sound != &"":
			Audio.play(sound)


func _on_invincibility_timeout() -> void:
	invincible = false


# ── Squash & stretch ────────────────────────────────────────────────────────
## Briefly deform the sprite (base scale is 2×2), then spring back.
func _squash(target: Vector2) -> void:
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	sprite.scale = target
	_squash_tween = create_tween()
	_squash_tween.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ── Animation ───────────────────────────────────────────────────────────────
## Picks which clip should be playing. Frame timing lives in the SpriteFrames
## resource (data/animations/player_frames.tres), not here.
func _update_animation() -> void:
	var wanted := &"standing"
	if current_strike:
		wanted = &"attacking"
	elif not is_on_floor() and not flying:
		wanted = &"jumping" if velocity.y < 0 else &"falling"
	elif absf(velocity.x) > 0.1:
		wanted = &"running"

	if sprite.animation != wanted:
		sprite.play(wanted)
	sprite.flip_h = not facing_right

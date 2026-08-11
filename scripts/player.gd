extends CharacterBody2D
## Player controller for "The PIT: Ascension"
## All physics values are ×2 scaled from original Pygame version.
##
## What differs between climbers is not in here. `character` is a CharacterDef
## resource — hearts, jump strength, how many jumps come free, which attack
## scene, which frames — and this script reads it once in _ready(). Nothing
## below asks *who* it is steering.

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
## The little pop a body gives when it goes down, before it falls to the floor.
const DOWNED_POP_FORCE: float = -300.0
## The hop a revived climber gets, so being picked up is something you see from
## across the pit rather than a heart quietly changing on somebody's bar.
const REVIVE_HOP_FORCE: float = -520.0
## Laid out on their back. The sprite also drops to the floor by this much,
## because a drawing on its side is half as tall as one standing up.
const DOWNED_SPRITE_Y: float = 0.0

const SHOCKWAVE_SCENE: PackedScene = preload("res://scenes/Shockwave.tscn")

const DOUBLE_JUMP_BURST: BurstPreset = preload("res://data/fx/double_jump.tres")
const HURT_BURST: BurstPreset = preload("res://data/fx/player_hurt.tres")
const DEATH_BURST: BurstPreset = preload("res://data/fx/player_death.tres")

# ── Identity ────────────────────────────────────────────────────────────────
## Which climber this avatar is. World assigns it from the session roster before
## add_child; the scene's own default keeps Player.tscn standing on its own for
## the probes and the visual harness.
@export var character: CharacterDef

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

# ── State ───────────────────────────────────────────────────────────────────
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
## Jumps available before the ground has to be touched again. The character's
## `base_jumps` to start with; every EXTRA_JUMP upgrade adds one.
var max_jumps: int = 1
var has_attack: bool = false
var has_shockwave: bool = false

## The RANGED unlock. A character whose weapon is a MOUNTED one rather than a
## projectile is told here rather than polled, because the weapon has a drawing
## that has to appear the moment it is earned.
var has_ranged: bool = false:
	set(value):
		has_ranged = value
		if value and weapon != null:
			weapon.call(&"arm")

## The mounted weapon, if this climber has one — `CharacterDef.weapon_scene`,
## which is where the four-method interface it answers is written down.
var weapon: Node2D = null

## Aiming a mounted weapon. Replicated, so a rival's gun is visibly out.
var aiming: bool = false

## Where that weapon is pointed, in radians — the only thing about the mouse
## that ever leaves this machine. It is in the sync stream because it is
## continuous state: the gun turns whether or not it is firing. A shot still
## carries its own angle as an argument, the way a bullet carries its facing.
var aim_angle: float = 0.0

## True while diving. The dash-down hitbox lives and dies with it — see the
## DashBox node, which is a couple of art pixels bigger than the body on every
## side, so a dive that clips the edge of something still counts.
##
## Replicated, so a puppet's box is live on the host too: the host resolves every
## kill, and it can only do that against a hitbox that exists on its machine.
var dashing_down: bool = false:
	set(value):
		if dashing_down == value:
			return
		dashing_down = value
		if is_node_ready():
			_arm_dash_box(value)

var flying: bool = false
var is_crushed: bool = false

## Multiplayer only: out of hearts, but not out of the run. The body drops where
## it died and lies there until a teammate spends a heart to bring it back. Solo
## death is unchanged — it ends the run.
var is_downed: bool = false

var facing_right: bool = true

var current_strike: Node = null
var current_shockwave: Node = null
var can_input: bool = true

var _trail_timer: float = 0.0
var _squash_tween: Tween
var _puppet_anim: StringName = &""
## Where the sprite sits when standing — authored in the scene, because the art
## is taller than the collision box. _lay_down() restores it.
@onready var _sprite_y: float = $AnimatedSprite2D.position.y
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
@onready var ranged_cd_timer: Timer = $RangedCooldownTimer
## How long the firing pose is held. Only the pose — the bullet has left.
@onready var shot_pose_timer: Timer = $ShotPoseTimer
## Watches for hostile PLAYER_ATTACK hitboxes. It is on no layer at all, so
## nothing can see it back, and it only monitors on the machine steering this
## avatar — see _ready.
@onready var hurt_box: Area2D = $HurtBox
## The same watch, for hits that belong to US — which today means one thing, a
## railgun beam that has come back off a wall into the person who fired it.
##
## It is a SEPARATE box because it is half the size and centred: your own beam
## has to actually go through you rather than graze the shoulder of a hitbox
## drawn generously so that other people's attacks feel fair. Two boxes rather
## than one box and a rule, because the size IS the rule — nothing reads a flag
## to decide how big your own beam's target is.
@onready var self_hurt_box: Area2D = $SelfHurtBox
## The dash-down hitbox. On its own layer so that a race rival's HurtBox, which
## watches PLAYER_ATTACK, does not read a dive going past as a punch.
@onready var dash_box: Area2D = $DashBox
## The sign over a corpse. Cosmetic and local: each machine shows it on the
## bodies ITS player could pick up, and World decides that every frame.
@onready var revive_prompt: RevivePrompt = $RevivePrompt

## The run this avatar is climbing in, resolved from the world above it rather
## than read off the Net autoload. On a player's machine the two are the same
## thing; on a dedicated server hosting a race in one room and a co-op climb in
## the next, only this one is right. With no world above — which is how every
## unit suite builds an avatar — it falls back to this machine's own session.
@onready var session: NetSession = NetSession.of(self)

# ── Signals ─────────────────────────────────────────────────────────────────
signal player_damaged(new_health: int)
signal player_died
## Multiplayer: this avatar is down and revivable. Emitted on its own machine.
signal player_downed
signal player_revived


func _ready() -> void:
	_apply_character()
	inv_timer.timeout.connect(_on_invincibility_timeout)
	# Race: rivals are solid, so you can stand on a head — and their strikes
	# reach you. Co-op and solo: nothing changes, players pass through each
	# other and the hurt box never wakes up.
	set_collision_mask_value(Layers.BIT_PLAYER, session.is_versus())
	# Only the machine steering this avatar watches for incoming hits. Damage
	# belongs to the victim; a puppet's overlap test here would be somebody
	# else's opinion about our health.
	#
	# It used to also require a race, because a rival's fist was the only thing
	# on PLAYER_ATTACK that could reach you. A railgun beam bounced back into its
	# own owner is the second, and it lands in every mode — so the mode question
	# moved into _on_hostile_area, which still reaches every old outcome.
	hurt_box.area_entered.connect(_on_hostile_area)
	self_hurt_box.area_entered.connect(_on_own_area)
	_arm_hurt_boxes(true)
	_arm_dash_box(dashing_down)


## Both watches, together. They go off when the body stops being a body — while
## it is dying, and for as long as it lies downed — and come back when somebody
## pays a heart for it. One call rather than four scattered assignments, because
## they were already out of step: stand_up() used to re-arm the hurt box only in
## a race, so a revived climber walked through her own beam untouched.
func _arm_hurt_boxes(on: bool) -> void:
	var mine := on and is_multiplayer_authority()
	hurt_box.monitoring = mine
	self_hurt_box.monitoring = mine


## The dash-down hitbox exists only while the dive does.
##
## Both flags, IN THIS ORDER, and neither part of that is cosmetic:
##
## - An Area2D with `monitoring` off is not reported by another area's
##   get_overlapping_areas() even with `monitorable` on. A box that armed only
##   `monitorable` was invisible to every enemy's stomp strip, and the dash
##   silently fell back to the body's own reach — the widening did nothing at
##   all, and nothing failed to say so.
## - Setting `monitoring` LAST is what makes the pairing take. The other order
##   also leaves the box undetected: measured against a golem, monitoring-first
##   reaches 53 px (the body) and monitorable-first reaches 57 px (the box), and
##   57 is what the two shapes actually add up to.
##
## The box detects nothing itself — its mask is empty — so monitoring costs a
## query against no layers.
func _arm_dash_box(on: bool) -> void:
	dash_box.monitorable = on
	dash_box.monitoring = on


## Everything this climber is, read once. Nothing else in the game may branch on
## which character is being played — if a difference is not expressible here, it
## belongs in CharacterDef as a new field.
func _apply_character() -> void:
	if character == null:
		return
	sprite.sprite_frames = character.frames
	sprite.play(&"standing")
	max_health = character.max_health
	health = max_health
	max_jumps = character.base_jumps
	strike_cd_timer.wait_time = character.attack_cooldown
	ranged_cd_timer.wait_time = character.ranged_cooldown
	shot_pose_timer.wait_time = character.ranged_pose
	_mount_weapon()


## A climber who carries something builds it once and keeps it for the life of
## the avatar, hidden and inert until the RANGED upgrade arms it. Set up BEFORE
## add_child: the weapon's own _ready() reads the numbers it was handed.
func _mount_weapon() -> void:
	if character.weapon_scene == null:
		return
	var built := character.weapon_scene.instantiate() as Node2D
	if built == null:
		return
	built.call(&"setup", self, character.weapon_stats)
	add_child(built)
	weapon = built
	if has_ranged:
		weapon.call(&"arm")


func _physics_process(delta: float) -> void:
	if session.active and not is_multiplayer_authority():
		_puppet_process(delta)
		return

	if is_downed:
		_downed_process(delta)
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
	if was_dashing and session.is_versus():
		_resolve_versus_stomp()

	if was_on_floor and not now_on_floor and velocity.y >= 0:
		coyote_timer.start()

	if now_on_floor:
		if dashing_down:
			dashing_down = false
		jump_count = 0
	elif jump_count == 0:
		# Airborne without having jumped — walked off a ledge, bounced, spawned.
		# The ground jump is spent either way, so the air jumps that follow are
		# counted from one. Without this a character with no EXTRA_JUMP at all
		# would get a free jump every time they stepped off something.
		jump_count = 1

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


## A body with nobody in it: no input, no attacks, nothing can touch it. It
## still falls, because a corpse hanging in the air where you happened to run
## out of hearts is not where anyone would come looking for it.
func _downed_process(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()


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
	var xf := global_transform
	var stuck_h := test_move(xf, Vector2.RIGHT) and test_move(xf, Vector2.LEFT)
	var stuck_v := test_move(xf, Vector2.UP) and test_move(xf, Vector2.DOWN)
	var embedded := test_move(xf, Vector2.ZERO)
	collision_mask = saved
	return stuck_h or stuck_v or embedded


# ── Input ───────────────────────────────────────────────────────────────────
func _handle_input() -> void:
	# Toggle flight
	if Input.is_action_just_pressed("toggle_flight"):
		flying = not flying
		if flying:
			velocity.y = 0.0
			# Debug mode hands you a loaded weapon — it exists to try things with.
			if weapon != null and weapon.has_method(&"debug_refill"):
				weapon.call(&"debug_refill")

	# Flight replaces the walking, the dash and the jump — and nothing else. It
	# used to `return` here, which made the one mode that exists for trying
	# things out the one mode where no ability could be tried at all.
	if flying:
		_handle_flight_input()
	else:
		var dir := Input.get_axis("move_left", "move_right")
		velocity.x = dir * SPEED

		# Which way she is looking is which way she is running — unless a weapon
		# is being aimed, in which case the weapon has already answered and this
		# would be overwriting it every single physics frame.
		if not _facing_locked():
			if dir > 0.0:
				facing_right = true
			elif dir < 0.0:
				facing_right = false

		if Input.is_action_just_pressed("dash_down") and not is_on_floor():
			dashing_down = true
			velocity.y = DASH_SPEED
			_squash(Vector2(1.5, 2.5))

		if Input.is_action_just_pressed("jump"):
			_try_jump()

	# Attack. A mounted weapon that is out takes this button ahead of the melee
	# swing — Uzi has no swing at all, so hers is the only one that answers, but
	# the order is what a character with both would want.
	if Input.is_action_just_pressed("attack"):
		if weapon != null and bool(weapon.call(&"wants_attack")):
			weapon.call(&"fire_pressed")
		elif has_attack:
			_try_strike()

	# The second attack button. Tessa's pistol fires from here; Uzi's railgun
	# comes off her back here instead and fires from the button above. A
	# character with neither never unlocks anything to put on it.
	if Input.is_action_just_pressed("attack_alt") and has_ranged:
		if weapon != null:
			weapon.call(&"alt_pressed")
		else:
			_try_shoot()

	# Shockwave (radial blast) — unlocked upgrade, longer cooldown.
	if Input.is_action_just_pressed("shockwave") and has_shockwave:
		_try_shockwave()


func _handle_flight_input() -> void:
	var dir_x := Input.get_axis("move_left", "move_right")
	var dir_y := Input.get_axis("move_up", "move_down")
	velocity.x = dir_x * FLIGHT_SPEED
	velocity.y = dir_y * FLIGHT_SPEED

	if not _facing_locked():
		if dir_x > 0.0:
			facing_right = true
		elif dir_x < 0.0:
			facing_right = false


## True while a weapon is being aimed: she faces the cursor, not her running.
func _facing_locked() -> bool:
	return weapon != null and bool(weapon.call(&"locks_facing"))


# ── Jump ────────────────────────────────────────────────────────────────────
## How hard this climber jumps. Tessa's is shorter than Cyn's, and that is the
## whole of the difference: one multiplier on her CharacterDef.
func jump_force() -> float:
	return JUMP_FORCE * (character.jump_scale if character else 1.0)


func _try_jump() -> void:
	if flying:
		return

	if is_on_floor() or not coyote_timer.is_stopped():
		velocity.y = jump_force()
		jump_count = 1
		coyote_timer.stop()
		dashing_down = false
		Fx.dust(global_position + Vector2(0, 30), 8)
		Audio.play(&"jump")
		_squash(Vector2(1.6, 2.4))
	elif jump_count < max_jumps:
		velocity.y = jump_force() * 0.9
		jump_count += 1
		dashing_down = false
		Fx.burst(global_position + Vector2(0, 20), DOUBLE_JUMP_BURST)
		Audio.play(&"double_jump")
		_squash(Vector2(1.6, 2.4))


# ── Strike ──────────────────────────────────────────────────────────────────
## Attacks spawn on EVERY machine: the host needs the hitbox to resolve
## kills, the others need the visual. The cooldown gates only the owner.
func _try_strike() -> void:
	if not strike_cd_timer.is_stopped() or character == null:
		return
	strike_cd_timer.start()
	# The swing is ours to hear. It used to live inside the RPC below, which
	# spawns on every machine — so every punch anyone threw played in every
	# lobby, wherever in the pit it happened.
	Audio.play(character.attack_sound)
	session.broadcast(self, &"_spawn_strike")


@rpc("authority", "call_local", "reliable")
func _spawn_strike() -> void:
	if character == null or character.attack_scene == null:
		return
	var s := character.attack_scene.instantiate()
	s.setup(self, facing_right)
	get_parent().add_child(s)
	current_strike = s


# ── Shot ────────────────────────────────────────────────────────────────────
## Where the bullet leaves the drawing, on the side being faced.
func muzzle_position() -> Vector2:
	if character == null:
		return global_position
	var off := character.muzzle_offset
	if not facing_right:
		off.x = -off.x
	return global_position + off


func _try_shoot() -> void:
	if not ranged_cd_timer.is_stopped() or character == null 			or character.ranged_scene == null:
		return
	ranged_cd_timer.start()
	shot_pose_timer.start()
	# Ours to hear, like the swing: the RPC below runs on every machine.
	Audio.play(character.ranged_sound)
	session.broadcast(self, &"_spawn_bullet", [facing_right, muzzle_position()])


## Spawned on every machine, exactly like a Strike, and for the same reasons:
## the host needs the hitbox to resolve kills and everybody else needs to see
## it. `facing` and `from` travel because the shot has to leave the muzzle it
## was fired from even if the avatar has already turned round by the time the
## packet lands.
@rpc("authority", "call_local", "reliable")
func _spawn_bullet(facing: bool, from: Vector2) -> void:
	if character == null or character.ranged_scene == null:
		return
	shot_pose_timer.start()
	var b := character.ranged_scene.instantiate()
	b.setup(self, facing, from)
	get_parent().add_child(b)


# ── Mounted weapon ──────────────────────────────────────────────────────────
## A carried weapon has gone off. The muzzle and the angle travel as arguments
## for the same reason a bullet's do — the shot leaves the barrel it was fired
## from even if the avatar has swung round by the time the packet lands.
##
## The RPC is here rather than on the weapon because authority is: World sets it
## on the avatar, and a child added afterwards does not inherit it.
func fire_weapon(from: Vector2, angle: float) -> void:
	session.broadcast(self, &"_spawn_weapon_shot", [from, angle])


## Every machine in the room, so the authority has the hitbox and everybody else
## has the picture. What the shot actually IS, this does not know.
@rpc("authority", "call_local", "reliable")
func _spawn_weapon_shot(from: Vector2, angle: float) -> void:
	if weapon != null and weapon.has_method(&"spawn_shot"):
		weapon.call(&"spawn_shot", from, angle)


# ── Shockwave ────────────────────────────────────────────────────────────────
func _try_shockwave() -> void:
	if not shockwave_cd_timer.is_stopped():
		return
	shockwave_cd_timer.start()
	Audio.play(&"shockwave")
	session.broadcast(self, &"_spawn_shockwave")


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
## A rival's Strike, Shockwave or beam has reached us. Only our own machine ever
## gets here — the hurt box does not monitor on a puppet — so the rule "the
## victim owns its damage" holds without a single extra check.
func _on_hostile_area(area: Area2D) -> void:
	# Our own attacks pass through our own body, as they always have. What comes
	# back at us goes to the smaller box instead: see _on_own_area.
	if int(area.get_meta(&"owner_peer", 0)) == peer_id:
		return
	# Somebody else's hit only lands in a race — in co-op a teammate's swing has
	# never reached you and a teammate's beam must not either. This check used to
	# be `hurt_box.monitoring` in _ready().
	if not session.is_versus():
		return
	_take_hit_from(area)


## Something WE fired has reached us. Today that is one thing: a railgun beam,
## which the owner asked to hit Uzi herself in every mode — firing down a
## corridor you are standing in is meant to be a decision.
##
## Two things make it survivable rather than a tax on aiming down. The box is
## half the size of the one a rival aims at, so it takes a beam through the
## middle of her and not a beam past her elbow; and the hitbox only carries
## `self_harm` for the first moment of the shot, so being shoved into your own
## reflection a beat later is a near miss. Both are in RailgunStats.
func _on_own_area(area: Area2D) -> void:
	if int(area.get_meta(&"owner_peer", 0)) != peer_id:
		return
	if not bool(area.get_meta(&"self_harm", false)):
		return
	_take_hit_from(area)


func _take_hit_from(area: Area2D) -> void:
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
	if session.active and not is_multiplayer_authority():
		return
	if strength <= 0.0 or is_crushed or is_downed:
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
	if session.active and not is_multiplayer_authority():
		return false
	if invincible or flying or not can_input or is_downed:
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
	set_collision_mask_value(Layers.BIT_PLAYER, session.is_versus() and not on)


func _floor_limit() -> float:
	var world_node := get_parent()
	if world_node and "max_depth" in world_node:
		return world_node.max_depth - 100.0
	return 16000.0


# ── Death ───────────────────────────────────────────────────────────────────
## Out of hearts. In a session that is not the end of you — the body drops where
## it fell and anyone still climbing can spend a heart on it. Solo, it is the
## end of the run, exactly as it always was.
func _die() -> void:
	if session.active:
		session.broadcast(self, &"_go_down")
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
	_lay_down(true)
	collision_mask = Layers.NONE
	_arm_hurt_boxes(false)
	var mine := not session.active or is_multiplayer_authority()
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


# ── Down and out (multiplayer) ──────────────────────────────────────────────
## The body stops being a player and becomes scenery that can be picked back up.
## It is off every collision layer, so no enemy, trampoline or rival can see it,
## and it keeps WORLD in its mask so it falls to the nearest floor instead of
## hanging in the air where the last heart went.
@rpc("authority", "call_local", "reliable")
func _go_down() -> void:
	if is_downed:
		return
	is_downed = true
	health = 0
	can_input = false
	invincible = false
	is_crushed = false
	dashing_down = false
	flying = false
	velocity = Vector2(0.0, DOWNED_POP_FORCE)
	collision_layer = Layers.NONE
	collision_mask = Layers.WORLD
	_arm_hurt_boxes(false)
	sprite.play(&"died")
	_puppet_anim = &"died"
	_lay_down(true)
	var mine := is_multiplayer_authority()
	Audio.play_at(&"die", global_position)
	Fx.shake(0.7 if mine else 0.25)
	Fx.burst(global_position, DEATH_BURST)
	if mine:
		player_damaged.emit(0)
		player_downed.emit()


## The host has decided somebody paid for this body. Health belongs to the
## machine steering the avatar, so the host asks rather than tells, exactly as it
## does for a world hazard — see remote_hurt. That machine then announces the
## pick-up to everyone, because it is the one with the authority to.
@rpc("any_peer", "call_remote", "reliable")
func remote_revive() -> void:
	if is_multiplayer_authority() and multiplayer.get_remote_sender_id() == 1:
		session.broadcast(self, &"stand_up")


@rpc("any_peer", "call_remote", "reliable")
func remote_pay_revive() -> void:
	if is_multiplayer_authority() and multiplayer.get_remote_sender_id() == 1:
		session.broadcast(self, &"pay_revive")


## Somebody paid a heart for this body. It stands up where it fell with one
## heart and a moment of invincibility, so being revived under an enemy is not
## instantly being downed again.
@rpc("authority", "call_local", "reliable")
func stand_up() -> void:
	if not is_downed:
		return
	is_downed = false
	health = 1
	# Up onto your feet with a hop — the one moment in a session worth looking
	# across the pit for.
	velocity = Vector2(0.0, REVIVE_HOP_FORCE)
	_lay_down(false)
	_squash(Vector2(1.5, 2.6))
	_restore_collision()
	_arm_hurt_boxes(true)
	revive_prompt.show_sign(false)
	sprite.play(&"standing")
	_puppet_anim = &"standing"
	invincible = true
	inv_timer.start()
	can_input = true
	Audio.play_at(&"heal", global_position)
	Fx.burst(global_position, DOUBLE_JUMP_BURST)
	if is_multiplayer_authority():
		player_damaged.emit(health)
		player_revived.emit()


## The cost, on the machine of whoever paid it. A plain heart off the bar: no
## knockback, no invincibility, no flash — you were not hit, you gave it away.
@rpc("authority", "call_local", "reliable")
func pay_revive() -> void:
	health = maxi(health - 1, 1)
	if is_multiplayer_authority():
		player_damaged.emit(health)
		Audio.play(&"hurt")


## On your back, or back on your feet. The sprite drops as it turns, because a
## climber lying down is half as tall as one standing up and would otherwise
## float above the floor its collider is resting on.
func _lay_down(on: bool) -> void:
	if on and weapon != null:
		weapon.call(&"holster") # and the aiming cursor with it
	sprite.rotation_degrees = -90.0 if on else 0.0
	sprite.position.y = DOWNED_SPRITE_Y if on else _sprite_y


func _restore_collision() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD
	set_collision_mask_value(Layers.BIT_PLAYER, session.is_versus())


## World decides, every frame, which bodies this machine's player could pick up.
## It is a local, cosmetic answer — nothing about it crosses the wire.
func set_revive_prompt(on: bool) -> void:
	revive_prompt.show_sign(on)


# ── Harm resolved elsewhere ─────────────────────────────────────────────────
## Applied here — the machine that steers this avatar is the only one that may
## change its health.
##
## The host sends this for world hazards (a mistimed stomp onto an enemy). In a
## race a rival sends it for a stomp on our head, which is why the sender is not
## pinned to peer 1: peers in a session are trusted, the same assumption that
## lets a client tell the host it moved.
@rpc("any_peer", "call_remote", "reliable")
func remote_hurt() -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.get_remote_sender_id() == 1 or session.is_versus():
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
## resource (data/animations/<character>_frames.tres), not here.
func _update_animation() -> void:
	var wanted := &"standing"
	# A carried weapon says which pose it wants, or says nothing. It outranks
	# running and falling because a drawn railgun is the loudest thing about how
	# the avatar is standing; it does not outrank a swing in progress.
	var carried: StringName = weapon.call(&"pose") if weapon != null else &""
	if current_strike:
		wanted = &"attacking"
	elif carried != &"":
		wanted = carried
	elif not shot_pose_timer.is_stopped():
		wanted = &"shooting"
	elif not is_on_floor() and not flying:
		wanted = &"jumping" if velocity.y < 0 else &"falling"
	elif absf(velocity.x) > 0.1:
		wanted = &"running"

	# A clip a character does not have is simply not played. Only Tessa has a
	# `shooting` pose, and only she can unlock the thing that asks for it, but a
	# CharacterDef is data and data can be wrong.
	if sprite.animation != wanted and sprite.sprite_frames.has_animation(wanted):
		sprite.play(wanted)
	sprite.flip_h = not facing_right

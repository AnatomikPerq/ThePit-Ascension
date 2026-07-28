extends CharacterBody2D
## Spitter — stationary ranged enemy. Stands on platforms and lobs acid blobs
## at the player when they are roughly horizontal and within range.
##
## DamageArea: contact hurts the player.
## StompArea: stomp from above (with dash_down) or a Strike kills it.
##
## Texture lives on the scene's Sprite2D (assets/sprites/spitter.png).

const GRAVITY: float = 4500.0
const TERMINAL_VEL: float = 1800.0
const SHOOT_RANGE: float = 1100.0
const SHOOT_COOLDOWN: float = 2.2
const SCORE: int = 150
const SCORE_COLOR := Color(0.5, 0.95, 0.3)
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/Projectile.tscn")

var _player: CharacterBody2D
var _is_dead: bool = false
var _shoot_timer: float = SHOOT_COOLDOWN
var _facing_right: bool = true
var _charge: float = 0.0 # ramps while aiming for a telegraph glow

@onready var sprite: Sprite2D = $Sprite2D


func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if global_position.y > _player.global_position.y + 1500.0:
		queue_free()
		return

	if _is_dead:
		return

	# Gravity so it rests on platforms like the Pursuer.
	velocity.y += GRAVITY * delta
	if velocity.y > TERMINAL_VEL:
		velocity.y = TERMINAL_VEL
	move_and_slide()

	# Aim at the player.
	var dist_x: float = _player.global_position.x - global_position.x
	var dist_y: float = _player.global_position.y - global_position.y
	var within_range: bool = abs(dist_x) < SHOOT_RANGE and abs(dist_y) < 700.0
	_facing_right = dist_x > 0.0
	sprite.flip_h = not _facing_right

	_shoot_timer -= delta
	if within_range and _shoot_timer <= 0.0:
		_shoot(delta)
	else:
		# Fade the charge glow out when not firing.
		_charge = move_toward(_charge, 0.0, delta * 2.0)

	# Reddish tint ramps up as a telegraph right before/at firing.
	sprite.modulate = Color(1.0, 1.0 - _charge * 0.5, 1.0 - _charge * 0.5)

	_check_collisions()


func _shoot(delta: float) -> void:
	# Small wind-up telegraph before the shot fires.
	_charge += delta * 4.0
	if _charge < 1.0:
		return
	_charge = 0.0
	_shoot_timer = SHOOT_COOLDOWN

	var proj: Area2D = PROJECTILE_SCENE.instantiate()
	var muzzle: Vector2 = global_position + Vector2(28.0 if _facing_right else -28.0, -10.0)
	proj.setup(muzzle, _player.global_position, _player)
	get_parent().add_child(proj)


func _check_collisions() -> void:
	var areas: Array[Area2D] = $StompArea.get_overlapping_areas()
	if has_node("DamageArea"):
		areas.append_array($DamageArea.get_overlapping_areas())

	# Priority 1: Strike / Shockwave
	for area in areas:
		if area.is_in_group("strike"):
			_die()
			return

	# Priority 2: Stomp — require a downward dash (like the Pursuer).
	for body in $StompArea.get_overlapping_bodies():
		if body.is_in_group("player") and body.velocity.y >= 0.0:
			if body.get("dashing_down") == true:
				body.velocity.y = -900.0 # dash-kill rebound
				body.dashing_down = false
				Audio.play(&"stomp")
				_die()
				return
			else:
				body.take_damage()
				return

	# Priority 3: Contact damage
	if has_node("DamageArea"):
		for body in $DamageArea.get_overlapping_bodies():
			if body.is_in_group("player"):
				# A player who is dashing down from above is mid-stomp. Without this
				# guard the outcome depends on which Area2D the engine happens to
				# report first: DamageArea covers the whole body while StompArea is a
				# thin strip on top, so a legitimate dash-kill was frequently turned
				# into the player taking a hit, then knocked upward so that the stomp
				# check failed its `velocity.y >= 0` guard a frame later.
				if body.get("dashing_down") == true and body.global_position.y < global_position.y:
					continue
				body.take_damage()
				return


func _die() -> void:
	_is_dead = true
	Game.enemy_killed(global_position, SCORE, SCORE_COLOR)
	queue_free()

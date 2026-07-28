extends Node2D
## Bat — flying chaser. Ignores gravity, homes toward the player with a gentle
## sine-bob so it feels erratic and unsettling.
## DamageArea: hurts the player on contact.
## StompArea: stomping from above (with dash_down) OR a Strike kills it.
##
## Texture lives on the scene's Sprite2D (assets/sprites/bat.png).

const HOMING_SPEED: float = 320.0
const ACCELERATION: float = 900.0
const DETECT_RANGE: float = 1400.0
const BOB_AMPLITUDE: float = 28.0
const BOB_FREQUENCY: float = 6.0 # radians / second
const SCORE: int = 125
const SCORE_COLOR := Color(0.75, 0.4, 0.95)

var _player: CharacterBody2D
var _is_dead: bool = false
var _bob_timer: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _facing_right: bool = true

@onready var sprite: Sprite2D = $Sprite2D


func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	# Despawn when far below the player (same convention as Golem/Slime).
	if is_instance_valid(_player) and position.y > _player.global_position.y + 1500.0:
		queue_free()
		return

	_bob_timer += delta

	if is_instance_valid(_player):
		var to_player: Vector2 = _player.global_position - global_position
		var dist: float = to_player.length()
		var target_vel := Vector2.ZERO
		if dist < DETECT_RANGE and dist > 1.0:
			var dir := to_player / dist
			# Add a perpendicular sine wobble so flight looks erratic.
			var perp := Vector2(-dir.y, dir.x)
			var wobble := perp * sin(_bob_timer * BOB_FREQUENCY) * BOB_AMPLITUDE
			target_vel = dir * HOMING_SPEED + wobble
			# `dir` is normalized, so this used to read `abs(dir.x) > 4.0` and could
			# never be true: every bat faced right for its whole life. The deadzone
			# keeps a bat directly above or below the player from flickering.
			if absf(dir.x) > 0.05:
				_facing_right = dir.x > 0.0

		_velocity = _velocity.move_toward(target_vel, ACCELERATION * delta)
		position += _velocity * delta

	sprite.flip_h = not _facing_right
	# Wing-flap squash for flavour.
	var flap: float = 1.0 + sin(_bob_timer * BOB_FREQUENCY * 2.0) * 0.08
	sprite.scale = Vector2(flap, 2.0 / flap)

	_check_collisions()


func _check_collisions() -> void:
	var areas: Array[Area2D] = $StompArea.get_overlapping_areas()
	if has_node("DamageArea"):
		areas.append_array($DamageArea.get_overlapping_areas())

	# Priority 1: Strike / Shockwave (anything in group "strike")
	for area in areas:
		if area.is_in_group("strike"):
			_die()
			return

	# Priority 2: Stomp — bats are airborne, so require a downward dash stomp.
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

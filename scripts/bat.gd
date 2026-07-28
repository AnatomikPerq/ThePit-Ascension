extends Node2D
## Bat — flying chaser. Ignores gravity and homes on the player with a sine
## wobble so its approach reads as erratic. Airborne, so only a dash-down kills
## it; brushing it costs you health.
##
## Contact resolution lives in the Combat child (EnemyCombat); this script keeps
## only the flight.

const HOMING_SPEED: float = 320.0
const ACCELERATION: float = 900.0
const DETECT_RANGE: float = 1400.0
const BOB_AMPLITUDE: float = 28.0
const BOB_FREQUENCY: float = 6.0 # radians / second
## Below this share of horizontal travel the bat keeps its current facing, so it
## does not flicker while directly above or below the player.
const FACING_DEADZONE: float = 0.05

var _bob_timer: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _facing_right: bool = true

@onready var combat: EnemyCombat = $Combat
@onready var sprite: Sprite2D = $Sprite2D


func set_player_ref(player: CharacterBody2D) -> void:
	# $Combat, not the @onready reference: the spawner calls this before
	# the enemy is added to the tree, when @onready values are still null.
	($Combat as EnemyCombat).player = player


func _physics_process(delta: float) -> void:
	if not Net.is_sim_authority():
		return # movement is mirrored from the host
	if combat.is_dead or not is_instance_valid(combat.player):
		return

	_bob_timer += delta

	var to_player: Vector2 = combat.player.global_position - global_position
	var dist := to_player.length()
	var target_vel := Vector2.ZERO
	if dist < DETECT_RANGE and dist > 1.0:
		var dir := to_player / dist
		# A perpendicular sine wobble on top of the homing vector.
		var perp := Vector2(-dir.y, dir.x)
		target_vel = dir * HOMING_SPEED + perp * sin(_bob_timer * BOB_FREQUENCY) * BOB_AMPLITUDE
		# This used to compare against 4.0 on a normalized vector, which can
		# never exceed 1.0 — so every bat faced right for its whole life.
		if absf(dir.x) > FACING_DEADZONE:
			_facing_right = dir.x > 0.0

	_velocity = _velocity.move_toward(target_vel, ACCELERATION * delta)
	position += _velocity * delta

	sprite.flip_h = not _facing_right
	# The wing flap is an autoplaying AnimationPlayer clip on the scene. It used
	# to be sprite.scale written from a sine every physics tick, which meant the
	# flap rate could not be retimed without editing this file.

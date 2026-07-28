extends CharacterBody2D
## Pursuer — chases the player along the ground and jumps over walls and gaps.
## Only a dash-down kills it; landing on it any other way costs you health.
##
## Contact resolution lives in the Combat child (EnemyCombat); this script keeps
## only the chase.

const GRAVITY: float = 4500.0
const TERMINAL_VEL: float = 1800.0
const MOVE_SPEED: float = 300.0 # slightly under the player's top speed, for fairness
const ACCELERATION: float = 1200.0
const FRICTION: float = 2400.0
const JUMP_POWER: float = -1700.0
const JUMP_COOLDOWN: float = 0.5
const PLAYER_DETECT: float = 1600.0

var _jump_timer: float = 0.0
var _stuck_timer: float = 0.0
var _facing_right: bool = true

@onready var combat: EnemyCombat = $Combat
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var edge_ray: RayCast2D = $EdgeDetector
@onready var wall_ray: RayCast2D = $WallDetector


func set_player_ref(player: CharacterBody2D) -> void:
	# $Combat, not the @onready reference: the spawner calls this before
	# the enemy is added to the tree, when @onready values are still null.
	($Combat as EnemyCombat).player = player


func _physics_process(delta: float) -> void:
	if not Net.is_sim_authority():
		return # movement is mirrored from the host
	if combat.is_dead or not is_instance_valid(combat.player):
		return
	_update_ai(delta)
	sprite.flip_h = not _facing_right


func _update_ai(delta: float) -> void:
	if _jump_timer > 0.0:
		_jump_timer -= delta
	_stuck_timer = 0.0 if is_on_floor() else _stuck_timer + delta

	var target := combat.player.global_position
	var dist_x: float = target.x - global_position.x
	var dist_y: float = target.y - global_position.y
	var dist_total := sqrt(dist_x * dist_x + dist_y * dist_y)

	var target_speed := 0.0
	if absf(dist_x) > 10.0 and dist_total < PLAYER_DETECT:
		var direction := signf(dist_x)
		target_speed = direction * MOVE_SPEED
		_facing_right = direction > 0.0

	if target_speed != 0.0:
		velocity.x = move_toward(velocity.x, target_speed, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	velocity.y = minf(velocity.y + GRAVITY * delta, TERMINAL_VEL)

	# Point both feelers the way we are walking.
	var ray_dir_x: float = 30.0 if _facing_right else -30.0
	edge_ray.position.x = ray_dir_x
	wall_ray.position.x = ray_dir_x * 0.5
	wall_ray.target_position.x = 20.0 if _facing_right else -20.0

	move_and_slide()

	if is_on_floor() and _jump_timer <= 0.0 and _should_jump(dist_x, target.y):
		velocity.y = JUMP_POWER
		_jump_timer = JUMP_COOLDOWN


func _should_jump(dist_x: float, player_y: float) -> bool:
	if wall_ray.is_colliding():
		return true # wall ahead
	# No ground ahead, and the player is on the far side of the gap.
	if not edge_ray.is_colliding():
		if (dist_x > 0.0 and _facing_right) or (dist_x < 0.0 and not _facing_right):
			return true
	if player_y < global_position.y - 200.0 and absf(dist_x) < 300.0:
		return true # player is above us
	if _stuck_timer > 3.0:
		_stuck_timer = 0.0
		return true # wedged somewhere; hop and hope
	return false

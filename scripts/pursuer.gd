extends CharacterBody2D
## Pursuer — chases the player, jumps over walls and pits.

const GRAVITY: float = 4032.0 # 0.8 * 60 * 60 * 2 * 0.7
const TERMINAL_VEL: float = 480.0 # term_vel 4 * 60 * 2
const MOVE_SPEED: float = 160.0 # speed 80 * 2
const JUMP_POWER: float = -1560.0 # -13 * 60 * 2
const JUMP_COOLDOWN: float = 1.333 # 80 frames / 60 fps
const PLAYER_DETECT: float = 1600.0 # 800 * 2
const WORLD_BOTTOM: float = 8400.0

var _player: CharacterBody2D
var _jump_timer: float = 0.0
var _stuck_timer: float = 0.0
var _facing_right: bool = true

# Animation
var _frames: Array[Texture2D] = []
var _anim_timer: float = 0.0
var _anim_idx: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var edge_ray: RayCast2D = $EdgeDetector
@onready var wall_ray: RayCast2D = $WallDetector
@onready var hurt_area: Area2D = $HurtArea


func _ready() -> void:
	_frames = [
		preload("res://assets/sprites/pursuer_1.png"),
		preload("res://assets/sprites/pursuer_2.png"),
	]
	hurt_area.body_entered.connect(_on_hurt_body_entered)
	hurt_area.area_entered.connect(_on_hurt_area_entered)


func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if global_position.y > WORLD_BOTTOM:
		queue_free()
		return

	_update_ai(delta)
	_update_animation(delta)


func _update_ai(delta: float) -> void:
	# Timers
	if _jump_timer > 0.0:
		_jump_timer -= delta

	if is_on_floor():
		_stuck_timer = 0.0
	else:
		_stuck_timer += delta

	# Chase player within detection range
	var dist_x: float = _player.global_position.x - global_position.x
	var dist_y: float = _player.global_position.y - global_position.y
	var dist_total: float = sqrt(dist_x * dist_x + dist_y * dist_y)

	if abs(dist_x) > 20.0 and dist_total < PLAYER_DETECT:
		var direction: float = sign(dist_x)
		velocity.x = direction * MOVE_SPEED
		_facing_right = direction > 0.0
	else:
		velocity.x = 0.0

	# Gravity
	velocity.y += GRAVITY * delta
	if velocity.y > TERMINAL_VEL:
		velocity.y = TERMINAL_VEL

	# Update raycast directions based on facing
	var ray_dir_x: float = 30.0 if _facing_right else -30.0
	edge_ray.position.x = ray_dir_x
	wall_ray.position.x = ray_dir_x * 0.5
	wall_ray.target_position.x = 20.0 if _facing_right else -20.0

	move_and_slide()

	# Jump conditions
	if is_on_floor() and _jump_timer <= 0.0:
		var should_jump := false

		# Wall ahead
		if wall_ray.is_colliding():
			should_jump = true

		# Edge ahead — no ground below, player across gap
		if not should_jump and not edge_ray.is_colliding():
			if (dist_x > 0.0 and _facing_right) or (dist_x < 0.0 and not _facing_right):
				should_jump = true

		# Player above
		if not should_jump and _player.global_position.y < global_position.y - 200.0 and abs(dist_x) < 300.0:
			should_jump = true

		# Stuck
		if not should_jump and _stuck_timer > 3.0:
			should_jump = true
			_stuck_timer = 0.0

		if should_jump:
			velocity.y = JUMP_POWER
			_jump_timer = JUMP_COOLDOWN


func _update_animation(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= 0.2:
		_anim_timer = 0.0
		_anim_idx = (_anim_idx + 1) % _frames.size()

	sprite.texture = _frames[_anim_idx]
	sprite.flip_h = not _facing_right


func _on_hurt_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# If player is stomping
		if body.velocity.y > 0 and body.global_position.y + 40 < global_position.y:
			body.velocity.y = -1440.0 # -12 * 60 * 2
			queue_free()
		elif body.dashing_down:
			body.velocity.y = -960.0
			queue_free()
		else:
			body.take_damage()


func _on_hurt_area_entered(area: Area2D) -> void:
	if area.is_in_group("strike"):
		queue_free()

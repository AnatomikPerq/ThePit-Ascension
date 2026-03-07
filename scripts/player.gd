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

const STRIKE_SCENE: PackedScene = preload("res://scenes/Strike.tscn")

# ── Sprites ─────────────────────────────────────────────────────────────────
var sprite_frames: Dictionary = {}

# ── State ───────────────────────────────────────────────────────────────────
var health: int = 5
var max_health: int = 5
var invincible: bool = false

var jump_count: int = 0
var has_double_jump: bool = false
var has_strike: bool = false
var dashing_down: bool = false
var flying: bool = false

var facing_right: bool = true
var animation_state: String = "standing"
var animation_frame: int = 0
var animation_timer: float = 0.0

var current_strike: Node = null
var can_input: bool = true

# ── Node References ─────────────────────────────────────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var inv_timer: Timer = $InvincibilityTimer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var strike_cd_timer: Timer = $StrikeCooldownTimer

# ── Animation delays (ms) ──────────────────────────────────────────────────
const ANIM_DELAYS: Dictionary = {
	"standing": 300.0,
	"running": 150.0,
	"jumping": 100.0,
	"falling": 100.0,
	"attacking": 100.0,
}

# ── Signals ─────────────────────────────────────────────────────────────────
signal player_damaged(new_health: int)
signal player_died


func _ready() -> void:
	inv_timer.timeout.connect(_on_invincibility_timeout)
	_load_sprites()
	_update_sprite()


func _load_sprites() -> void:
	sprite_frames = {
		"standing": [
			preload("res://assets/sprites/player_standing_1.png"),
			preload("res://assets/sprites/player_standing_2.png"),
		],
		"running": [
			preload("res://assets/sprites/player_running_1.png"),
			preload("res://assets/sprites/player_running_2.png"),
		],
		"jumping": [preload("res://assets/sprites/player_jumping.png")],
		"falling": [preload("res://assets/sprites/player_falling.png")],
		"attacking": [preload("res://assets/sprites/player_attacking.png")],
	}


func _physics_process(delta: float) -> void:
	if not can_input:
		velocity.x = 0.0
	else:
		_handle_input()

	if not flying:
		_apply_gravity(delta)

	# Coyote time: if just walked off edge, start timer
	var was_on_floor := is_on_floor()
	move_and_slide()
	var now_on_floor := is_on_floor()

	if was_on_floor and not now_on_floor and velocity.y >= 0:
		coyote_timer.start()

	if now_on_floor:
		if dashing_down:
			dashing_down = false
		jump_count = 0

	# Cancel dash if moving upwards (e.g. trampolines, bounces)
	if velocity.y < 0:
		dashing_down = false

	_update_animation(delta)

	if current_strike:
		_snap_strike()

	# Blinking while invincible
	if invincible:
		sprite.visible = fmod(Time.get_ticks_msec(), 100.0) > 50.0
	else:
		sprite.visible = true


# ── Gravity ─────────────────────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if dashing_down:
		return # Gravity ignored while dashing down

	velocity.y += GRAVITY * delta
	if velocity.y > TERMINAL_VELOCITY:
		velocity.y = TERMINAL_VELOCITY


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

	# Jump (just_pressed events)
	if Input.is_action_just_pressed("jump"):
		_try_jump()

	# Attack
	if Input.is_action_just_pressed("attack") and has_strike:
		_try_strike()


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
	elif has_double_jump and jump_count < 2:
		velocity.y = JUMP_FORCE * 0.9
		jump_count = 2
		dashing_down = false


# ── Strike ──────────────────────────────────────────────────────────────────
func _try_strike() -> void:
	if not strike_cd_timer.is_stopped():
		return
	strike_cd_timer.start()
	var s := STRIKE_SCENE.instantiate()
	s.setup(self , facing_right)
	get_parent().add_child(s)
	current_strike = s


func _snap_strike() -> void:
	if not is_instance_valid(current_strike):
		current_strike = null
		return
	if facing_right:
		current_strike.global_position = global_position + Vector2(52, 0)
	else:
		current_strike.global_position = global_position + Vector2(-52, 0)


# ── Damage ──────────────────────────────────────────────────────────────────
func take_damage() -> bool:
	if invincible or flying:
		return false
	health -= 1
	invincible = true
	inv_timer.start()
	velocity.y = KNOCKBACK_FORCE
	player_damaged.emit(health)
	if health <= 0:
		player_died.emit()
	return true


func _on_invincibility_timeout() -> void:
	invincible = false


# ── Animation ───────────────────────────────────────────────────────────────
func _update_animation(delta: float) -> void:
	animation_timer += delta * 1000.0

	var new_state := "standing"
	if current_strike:
		new_state = "attacking"
	elif not is_on_floor() and not flying:
		new_state = "jumping" if velocity.y < 0 else "falling"
	elif abs(velocity.x) > 0.1:
		new_state = "running"

	if new_state != animation_state:
		animation_state = new_state
		animation_frame = 0
		animation_timer = 0.0

	var delay: float = ANIM_DELAYS.get(animation_state, 100.0)
	if animation_timer >= delay:
		animation_timer = 0.0
		var frames_arr: Array = sprite_frames.get(animation_state, [])
		if frames_arr.size() > 0:
			animation_frame = (animation_frame + 1) % frames_arr.size()

	_update_sprite()


func _update_sprite() -> void:
	var frames_arr: Array = sprite_frames.get(animation_state, [])
	if frames_arr.size() == 0:
		return
	var idx := mini(animation_frame, frames_arr.size() - 1)
	sprite.texture = frames_arr[idx]
	sprite.flip_h = not facing_right

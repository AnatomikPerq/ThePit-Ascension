extends CharacterBody2D
## Spitter — stationary ranged enemy. Rests on a platform and lobs acid at the
## player when they are roughly level and in range. Only a dash-down kills it.
##
## Contact resolution lives in the Combat child (EnemyCombat); this script keeps
## only the aiming and shooting.

const GRAVITY: float = 4500.0
const TERMINAL_VEL: float = 1800.0
const SHOOT_RANGE: float = 1100.0
const SHOOT_VERTICAL_RANGE: float = 700.0
const SHOOT_COOLDOWN: float = 2.2
## Seconds of wind-up between deciding to fire and the shot leaving.
const CHARGE_TIME: float = 0.25
## Seconds for the telegraph glow to fade once the player leaves range.
const CHARGE_DECAY: float = 0.5
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/Projectile.tscn")

var _shoot_timer: float = SHOOT_COOLDOWN
var _facing_right: bool = true
var _charge: float = 0.0 # 0..1, drives the telegraph tint

@onready var combat: EnemyCombat = $Combat
@onready var sprite: Sprite2D = $Sprite2D


func set_player_ref(player: CharacterBody2D) -> void:
	# $Combat, not the @onready reference: the spawner calls this before
	# the enemy is added to the tree, when @onready values are still null.
	($Combat as EnemyCombat).player = player


func _physics_process(delta: float) -> void:
	if combat.is_dead or not is_instance_valid(combat.player):
		return

	# Gravity, so it settles onto whatever platform it spawned above.
	velocity.y = minf(velocity.y + GRAVITY * delta, TERMINAL_VEL)
	move_and_slide()

	var to_player: Vector2 = combat.player.global_position - global_position
	_facing_right = to_player.x > 0.0
	sprite.flip_h = not _facing_right

	var in_range := absf(to_player.x) < SHOOT_RANGE and absf(to_player.y) < SHOOT_VERTICAL_RANGE
	_shoot_timer -= delta
	if in_range and _shoot_timer <= 0.0:
		_charge += delta / CHARGE_TIME
		if _charge >= 1.0:
			_fire()
	else:
		_charge = move_toward(_charge, 0.0, delta / CHARGE_DECAY)

	# Reddens as the shot winds up, so the player gets a tell.
	sprite.modulate = Color(1.0, 1.0 - _charge * 0.5, 1.0 - _charge * 0.5)


func _fire() -> void:
	_charge = 0.0
	_shoot_timer = SHOOT_COOLDOWN
	var proj: Area2D = PROJECTILE_SCENE.instantiate()
	var muzzle: Vector2 = global_position + Vector2(28.0 if _facing_right else -28.0, -10.0)
	proj.setup(muzzle, combat.player.global_position, combat.player)
	get_parent().add_child(proj)

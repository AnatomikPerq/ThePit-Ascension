extends CharacterBody2D
## Spitter — stationary ranged enemy. Rests on a platform and lobs acid at the
## player when they are roughly level and in range. Only a dash-down kills it.
##
## Contact resolution lives in the Combat child (EnemyCombat). The wind-up
## telegraph and the shot itself live in the `telegraph` AnimationPlayer clip:
## it tints the sprite red over 0.25s and fires from a method track at the end.
## Previously the tint was a float accumulator written to modulate every physics
## tick, and the projectile was spawned from inside a function named _shoot that
## usually did not shoot.

const GRAVITY: float = 4500.0
const TERMINAL_VEL: float = 1800.0
const SHOOT_RANGE: float = 1100.0
const SHOOT_VERTICAL_RANGE: float = 700.0
const SHOOT_COOLDOWN: float = 2.2
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/Projectile.tscn")

var _facing_right: bool = true

@onready var combat: EnemyCombat = $Combat
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var cooldown: Timer = $ShootCooldown


func set_player_ref(player: CharacterBody2D) -> void:
	# $Combat, not the @onready reference: the spawner calls this before the
	# enemy is added to the tree, when @onready values are still null.
	($Combat as EnemyCombat).player = player


func _ready() -> void:
	cooldown.start()


func _physics_process(delta: float) -> void:
	if not Net.is_sim_authority():
		return # movement and the telegraph are mirrored from the host
	if combat.is_dead or not is_instance_valid(combat.player):
		return

	# Gravity, so it settles onto whatever platform it spawned above.
	velocity.y = minf(velocity.y + GRAVITY * delta, TERMINAL_VEL)
	move_and_slide()

	var to_player: Vector2 = combat.player.global_position - global_position
	_facing_right = to_player.x > 0.0
	sprite.flip_h = not _facing_right

	var in_range := absf(to_player.x) < SHOOT_RANGE and absf(to_player.y) < SHOOT_VERTICAL_RANGE
	if in_range and cooldown.is_stopped() and not anim.is_playing():
		anim.play(&"telegraph")
	elif not in_range and anim.is_playing():
		# Player left the window mid-wind-up: unwind at half speed, which is the
		# 0.5s fade the old accumulator decayed over.
		anim.play(&"telegraph", -1.0, -0.5, true)


## Called from the telegraph clip's method track, at the moment the tell peaks.
func fire() -> void:
	cooldown.start()
	sprite.modulate = Color.WHITE
	var proj: Area2D = PROJECTILE_SCENE.instantiate()
	var muzzle: Vector2 = global_position + Vector2(28.0 if _facing_right else -28.0, -10.0)
	proj.setup(muzzle, combat.player.global_position, combat.player)
	# add_child(_, true): readable names let the MultiplayerSpawner mirror it.
	get_parent().add_child(proj, true)

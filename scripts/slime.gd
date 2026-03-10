extends Node2D
## Slime — falls and drifts sideways.
## Stomp from above → spawn Trampoline. Otherwise → damage player.
## Strike also kills it → spawn Trampoline.

const FALL_SPEED: float = 480.0 # term_vel 4 * 60 * 2
const DRIFT_SPEED: float = 100.0 # speed 50 * 2
const WORLD_BOTTOM: float = 8400.0

const TRAMPOLINE_SCENE: PackedScene = preload("res://scenes/Trampoline.tscn")

var _direction: float = 1.0
var _player: CharacterBody2D
var _is_dead: bool = false


func _ready() -> void:
	_direction = 1.0 if randf() < 0.5 else -1.0


func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	position.y += FALL_SPEED * delta
	position.x += DRIFT_SPEED * _direction * delta

	if is_instance_valid(_player) and position.y > _player.global_position.y + 1500.0:
		queue_free()
		return

	var areas: Array[Area2D] = $StompArea.get_overlapping_areas()
	if has_node("DamageArea"):
		areas.append_array($DamageArea.get_overlapping_areas())
	
	# Priority 1: Strike
	for area in areas:
		if area.is_in_group("strike"):
			_die_and_spawn()
			return

	# Priority 2: Stomp
	for body in $StompArea.get_overlapping_bodies():
		if body.is_in_group("player") and body.velocity.y >= 0.0:
			body.velocity.y = 0.0
			body.dashing_down = false
			_die_and_spawn()
			return

	# Priority 3: Damage
	if has_node("DamageArea"):
		for body in $DamageArea.get_overlapping_bodies():
			if body.is_in_group("player"):
				body.take_damage()


func _die_and_spawn() -> void:
	_is_dead = true
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite:
		sprite.visible = false
	call_deferred("_deferred_spawn_trampoline")


func _deferred_spawn_trampoline() -> void:
	var t := TRAMPOLINE_SCENE.instantiate()
	t.global_position = global_position
	get_parent().add_child(t)
	queue_free()

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


func _ready() -> void:
	_direction = 1.0 if randf() < 0.5 else -1.0
	$HitArea.body_entered.connect(_on_body_entered)
	$HitArea.area_entered.connect(_on_area_entered)


func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	position.y += FALL_SPEED * delta
	position.x += DRIFT_SPEED * _direction * delta

	if position.y > WORLD_BOTTOM:
		queue_free()


func _spawn_trampoline() -> void:
	# Use call_deferred to avoid physics state errors
	call_deferred("_deferred_spawn_trampoline")


func _deferred_spawn_trampoline() -> void:
	var t := TRAMPOLINE_SCENE.instantiate()
	t.global_position = global_position
	get_parent().add_child(t)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.velocity.y > 0 and body.global_position.y + 32 < global_position.y:
			body.velocity.y = -1440.0
			_spawn_trampoline()
		elif body.dashing_down:
			body.velocity.y = -960.0
			_spawn_trampoline()
		else:
			body.take_damage()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("strike"):
		_spawn_trampoline()

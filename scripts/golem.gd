extends Node2D
## Golem — falls down, converts to Platform when stomped/struck.
## DamageArea (bottom): hurts the player.
## TransformArea (top+sides): player contact → spawn Platform.

const FALL_SPEED: float = 360.0 # term_vel 3 * 60 * 2
const WORLD_BOTTOM: float = 8400.0

const PLATFORM_SCENE: PackedScene = preload("res://scenes/Platform.tscn")

var _active_texture: Texture2D
var _player: CharacterBody2D


func _ready() -> void:
	_active_texture = preload("res://assets/sprites/golem_active.png")

	$DamageArea.body_entered.connect(_on_damage_body_entered)
	$TransformArea.body_entered.connect(_on_transform_body_entered)
	$TransformArea.area_entered.connect(_on_transform_area_entered)


func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	position.y += FALL_SPEED * delta

	if position.y > WORLD_BOTTOM:
		queue_free()


func _transform_to_platform() -> void:
	# Use call_deferred to avoid physics state errors
	call_deferred("_deferred_transform")


func _deferred_transform() -> void:
	var plat := PLATFORM_SCENE.instantiate()
	plat.global_position = global_position
	plat.get_node("Sprite2D").texture = _active_texture
	get_parent().add_child(plat)
	queue_free()


func _on_damage_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.velocity.y > 0 and body.global_position.y + 32 < global_position.y:
			body.velocity.y = -1440.0
			_transform_to_platform()
		elif body.dashing_down:
			body.velocity.y = -960.0
			_transform_to_platform()
		else:
			body.take_damage()


func _on_transform_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.velocity.y = -960.0
		_transform_to_platform()


func _on_transform_area_entered(area: Area2D) -> void:
	if area.is_in_group("strike"):
		_transform_to_platform()

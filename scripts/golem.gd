extends Node2D
## Golem — falls down, converts to Platform when stomped/struck.
## DamageArea (bottom): hurts the player.
## StompArea (top): player contact → spawn Platform.

const FALL_SPEED: float = 360.0 # term_vel 3 * 60 * 2
const WORLD_BOTTOM: float = 8400.0

var _active_texture: Texture2D
var _player: CharacterBody2D
var _is_dead: bool = false


func _ready() -> void:
	_active_texture = preload("res://assets/sprites/golem_active.png")


func set_player_ref(player: CharacterBody2D) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	position.y += FALL_SPEED * delta

	if is_instance_valid(_player) and position.y > _player.global_position.y + 1500.0:
		queue_free()
		return

	var areas: Array[Area2D] = $StompArea.get_overlapping_areas()
	if has_node("DamageArea"):
		areas.append_array($DamageArea.get_overlapping_areas())

	# Priority 1: Strike
	for area in areas:
		if area.is_in_group("strike"):
			_die_and_transform()
			return

	# Priority 2: Stomp
	for body in $StompArea.get_overlapping_bodies():
		if body.is_in_group("player") and body.velocity.y >= 0.0:
			body.velocity.y = 0.0
			body.dashing_down = false
			_die_and_transform()
			return

	# Priority 3: Damage
	if has_node("DamageArea"):
		for body in $DamageArea.get_overlapping_bodies():
			if body.is_in_group("player"):
				body.take_damage()


func _die_and_transform() -> void:
	_is_dead = true
	call_deferred("_deferred_transform")


func _deferred_transform() -> void:
	set_physics_process(false)
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite:
		sprite.texture = _active_texture
	
	if has_node("DamageArea"):
		$DamageArea.queue_free()
	if has_node("StompArea"):
		$StompArea.queue_free()
		
	if has_node("CrushBody"):
		$CrushBody.queue_free()
		
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(64, 64)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

extends Area2D
## Projectile — lobbed acid blob fired by the Spitter.
## Travels in a straight line at spawn velocity, despawns off-screen or on
## contact with the player. Strikes/Shockwaves can also destroy it.

const LIFETIME: float = 4.0
const SPEED: float = 700.0

var _velocity: Vector2 = Vector2.ZERO
var _life: float = LIFETIME
var _player: CharacterBody2D

@onready var sprite: Sprite2D = $Sprite2D


func setup(origin: Vector2, target: Vector2, player: CharacterBody2D) -> void:
	global_position = origin
	_player = player
	var dir := (target - origin)
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	_velocity = dir.normalized() * SPEED
	# Slight arc: add a bit of upward velocity so the blob lobs.
	_velocity.y -= 150.0


func _ready() -> void:
	sprite.texture = _make_blob_texture()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	# Gravity for the lob arc.
	_velocity.y += 900.0 * delta
	position += _velocity * delta
	sprite.rotation += delta * 12.0

	# Despawn far away from the player.
	if is_instance_valid(_player):
		if global_position.y > _player.global_position.y + 1400.0 or global_position.distance_to(_player.global_position) > 2200.0:
			queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.take_damage()
		Fx.burst(global_position, Color(0.45, 0.95, 0.3), 8, 180.0, 0.35)
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Destroyed by the player's Strike or Shockwave.
	if area.is_in_group("strike"):
		Fx.burst(global_position, Color(0.45, 0.95, 0.3), 10, 220.0, 0.4)
		Game.add_score(10, global_position, Color(0.45, 0.95, 0.3))
		queue_free()


func _make_blob_texture() -> ImageTexture:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(8, 8)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(center)
			if d <= 6.0:
				var edge := smoothstep(4.0, 6.0, d)
				img.set_pixel(x, y, Color(0.45, 0.95, 0.3, 1.0 - edge * 0.4))
	return ImageTexture.create_from_image(img)

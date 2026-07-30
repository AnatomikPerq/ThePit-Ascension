extends Node2D
## Shockwave — radial energy blast unlocked as an upgrade.
## Spawns at the player, expands outward, hits every enemy it touches.
## Its HitArea is added to the "strike" group, so existing enemy logic
## (Golem / Slime / Pursuer / Bat / Spitter) reacts to it identically to a
## normal Strike — no per-enemy coupling required.
##
## The ring texture and its tint live on the scene (assets/sprites/shockwave_ring.png).

const EXPAND_SPEED: float = 4200.0 # px / second growth
const MAX_RADIUS: float = 520.0
const LIFETIME: float = 0.45

var _player: Node2D
var _radius: float = 0.0
var _life_timer: float = LIFETIME

@onready var _visual: Sprite2D = $Visual
@onready var _hit_area: Area2D = $HitArea
@onready var _hit_shape: CollisionShape2D = $HitArea/CollisionShape2D


func setup(player: Node2D) -> void:
	_player = player


func _ready() -> void:
	# Important: enemies detect strikes via `area.is_in_group("strike")`.
	_hit_area.add_to_group("strike")
	# …and credit the kill to whoever owns the hitbox.
	_hit_area.set_meta(&"owner_peer",
		_player.get("peer_id") if is_instance_valid(_player) else 0)
	# How far this attack reaches at full extent, for anything that cares how
	# squarely it was caught — the bomb is thrown further the nearer the middle
	# of the ring it was standing.
	#
	# The FULL radius, deliberately, not the radius at the moment of contact. The
	# ring grows outward, so it always meets a bomb exactly when it has grown to
	# reach it: measured against the current radius every bomb is at the edge of
	# the wave and none of them would ever be thrown hard.
	_hit_area.set_meta(&"hit_reach", MAX_RADIUS)
	# Start with a zero-radius hit shape so the wave grows from the player.
	var circ := _hit_shape.shape as CircleShape2D
	if circ:
		circ.radius = 0.0


func _physics_process(delta: float) -> void:
	_life_timer -= delta
	if _life_timer <= 0.0:
		_cleanup()
		return

	# Follow the player while expanding.
	if is_instance_valid(_player):
		global_position = _player.global_position

	# Grow the radius (ease out a touch so it slams then fades).
	_radius += EXPAND_SPEED * delta
	_radius = minf(_radius, MAX_RADIUS)

	# Scale the ring visual (texture is 128px square, ring sits at outer edge).
	var ring_scale: float = (_radius * 2.0) / 128.0
	_visual.scale = Vector2(ring_scale, ring_scale)
	_visual.modulate.a = clampf(_life_timer / LIFETIME, 0.0, 1.0)

	# Grow the hit area to match the visual.
	var circ := _hit_shape.shape as CircleShape2D
	if circ:
		circ.radius = _radius

	# No need to iterate enemies here: each enemy's own _physics_process
	# calls get_overlapping_areas() on its StompArea/DamageArea and finds
	# our "strike"-grouped HitArea, triggering its death path directly.


func _cleanup() -> void:
	if is_instance_valid(_player) and _player.get("current_shockwave") == self:
		_player.current_shockwave = null
	queue_free()

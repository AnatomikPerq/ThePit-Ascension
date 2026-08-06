extends Area2D
## Tessa's shot. Flies flat out to the side she was facing, at a fixed speed,
## until it meets a surface or runs out of life.
##
## It is spawned on EVERY machine by the same `call_local` RPC that spawns a
## Strike, for the same two reasons: the host needs the hitbox to resolve kills
## and everyone else needs to see it. Nothing about its flight is replicated —
## it does not need to be. Straight line, fixed speed, no gravity, from a
## position every machine already agrees on, through geometry every machine
## rebuilt from the same seed: the same bullet is in the same place everywhere
## without a single packet.
##
## Its hitbox joins the `"strike"` group and stamps `owner_peer`, so every enemy
## already knows what to do with it and no enemy scene knows guns exist.

const HIT_BURST: BurstPreset = preload("res://data/fx/bullet_hit.tres")

@export var speed: float = 1900.0
## Long enough to cross the shaft, short enough that one that flies out of a gap
## is not still travelling a second later.
@export var lifetime: float = 1.2
## Half-diagonal of the collision box, for anything that asks how squarely it
## was hit — the bomb does.
@export var hit_reach: float = 10.0

var _direction: float = 1.0
var _life: float = 0.0
## Set the frame the bullet meets something it should die on. It is not freed
## until the NEXT physics frame: an enemy resolves its own kills in its
## `_physics_process`, and freeing inside the overlap callback would sometimes
## take the hitbox away before the enemy had looked at it.
var _spent: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


## `from` is the muzzle, already offset to the side by the shooter.
func setup(shooter: Node2D, facing_right: bool, from: Vector2) -> void:
	_direction = 1.0 if facing_right else -1.0
	global_position = from
	set_meta(&"owner_peer", shooter.get("peer_id") if is_instance_valid(shooter) else 0)


func _ready() -> void:
	_life = lifetime
	sprite.flip_h = _direction < 0.0
	set_meta(&"hit_reach", hit_reach)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _spent:
		_burst()
		queue_free()
		return
	position.x += _direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


## A wall, a platform, the floor — anything on the WORLD layer stops it.
func _on_body_entered(_body: Node2D) -> void:
	_spent = true


## An enemy. It kills through the "strike" group like everything else; this only
## stops the bullet carrying on through the rest of the row.
func _on_area_entered(_area: Area2D) -> void:
	_spent = true


func _burst() -> void:
	Fx.burst(global_position, HIT_BURST)

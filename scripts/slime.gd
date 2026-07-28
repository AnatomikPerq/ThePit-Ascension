extends Node2D
## Slime — falls while drifting sideways. Struck or landed on, it is replaced by
## a trampoline, turning a hazard into altitude.
##
## Contact resolution lives in the Combat child (EnemyCombat); this script keeps
## only the drift and the conversion.

const FALL_SPEED: float = 480.0 # term_vel 4 * 60 * 2
const DRIFT_SPEED: float = 100.0 # speed 50 * 2
const TRAMPOLINE_SCENE: PackedScene = preload("res://scenes/Trampoline.tscn")

var _direction: float = 1.0

@onready var combat: EnemyCombat = $Combat
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_direction = 1.0 if randf() < 0.5 else -1.0
	combat.killed.connect(_on_killed)


func set_player_ref(player: CharacterBody2D) -> void:
	# $Combat, not the @onready reference: the spawner calls this before
	# the enemy is added to the tree, when @onready values are still null.
	($Combat as EnemyCombat).player = player


func _physics_process(delta: float) -> void:
	if combat.is_dead:
		return
	position.y += FALL_SPEED * delta
	position.x += DRIFT_SPEED * _direction * delta


func _on_killed(_by_strike: bool) -> void:
	sprite.visible = false
	_leave_trampoline.call_deferred()


func _leave_trampoline() -> void:
	var t := TRAMPOLINE_SCENE.instantiate()
	# Our own parent is the Enemies container, so parenting the trampoline there
	# left World.tscn's Trampolines node empty for the whole life of the project.
	var container := get_tree().get_first_node_in_group(&"trampoline_container")
	if container == null:
		container = get_parent()
	container.add_child(t)
	t.global_position = global_position
	queue_free()

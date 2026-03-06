extends Area2D

var _anim_timer: int = 0
var _original_scale: Vector2


func _ready() -> void:
	_original_scale = $Sprite2D.scale
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	if _anim_timer > 0:
		_anim_timer -= 1
		if _anim_timer > 7:
			$Sprite2D.scale = Vector2(_original_scale.x, _original_scale.y * 0.5)
		else:
			$Sprite2D.scale = _original_scale


func trigger() -> void:
	_anim_timer = 15


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# Only bounce if player is falling onto the trampoline
		if body.velocity.y > 0:
			trigger()
			body.velocity.y = -2760.0 # -23 * 60 * 2
			body.jump_count = 0
			body.dashing_down = false

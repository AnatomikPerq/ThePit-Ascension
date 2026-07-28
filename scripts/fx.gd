extends Node
## Fx — autoload with global "juice" helpers:
## screen shake, hitstop, one-shot particle bursts, floating score popups,
## ghost trails and damage flashes. Everything is spawned into the current
## scene so no per-entity setup is required.

var _trauma: float = 0.0
var _rng := RandomNumberGenerator.new()

const SHAKE_DECAY: float = 2.4
const SHAKE_MAX_OFFSET: float = 30.0


func _ready() -> void:
	# Shake must decay even while the tree is paused (menus).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = maxf(_trauma - delta * SHAKE_DECAY, 0.0)


# ── Screen shake ────────────────────────────────────────────────────────────
## Add trauma (0..1). The camera owner reads get_shake_offset() every frame.
func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func get_shake_offset() -> Vector2:
	if _trauma <= 0.0:
		return Vector2.ZERO
	var strength := _trauma * _trauma # quadratic falloff feels better
	return Vector2(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * SHAKE_MAX_OFFSET * strength


# ── Hitstop ─────────────────────────────────────────────────────────────────
## Brief global slowdown for impact frames. Real-time timer restores scale.
func hitstop(duration: float = 0.05, time_scale: float = 0.1) -> void:
	if Engine.time_scale < 1.0:
		return # already in a hitstop, don't stack
	Engine.time_scale = time_scale
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)


# ── Particles ───────────────────────────────────────────────────────────────
## One-shot radial burst of colored particles at a world position.
func burst(pos: Vector2, color: Color, count: int = 16, speed: float = 320.0,
		life: float = 0.55, gravity: float = 800.0) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = count
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0.0, gravity)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.z_index = 50
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)


## Soft dust puff (landing, golem petrification).
func dust(pos: Vector2, count: int = 10) -> void:
	burst(pos, Color(0.75, 0.68, 0.58, 0.8), count, 140.0, 0.45, 150.0)


# ── Floating popups ─────────────────────────────────────────────────────────
## Floating text in world space ("+300 x3"). Rises and fades out.
func popup(pos: Vector2, text: String, color: Color = Color.WHITE, font_size: int = 30) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.z_index = 100
	l.size = Vector2(240, 40)
	root.add_child(l)
	l.position = pos - Vector2(120, 20)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 0.8)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


# ── Ghost trail ─────────────────────────────────────────────────────────────
## Fading afterimage copy of a sprite (dash trails).
## Accepts either a Sprite2D or an AnimatedSprite2D — the ghost only ever needs
## the texture that is on screen right now.
func ghost(src: Node2D, tint: Color = Color(1.0, 1.0, 1.0, 0.4), fade: float = 0.25) -> void:
	var root := get_tree().current_scene
	if root == null or src == null:
		return
	var tex := _current_texture(src)
	if tex == null:
		return
	var g := Sprite2D.new()
	g.texture = tex
	g.flip_h = src.get("flip_h")
	g.modulate = tint
	g.z_index = -1
	root.add_child(g)
	g.global_transform = src.global_transform
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, fade)
	tw.tween_callback(g.queue_free)


## The texture a sprite node is currently showing, whichever kind it is.
func _current_texture(src: Node2D) -> Texture2D:
	var still := src as Sprite2D
	if still:
		return still.texture
	var animated := src as AnimatedSprite2D
	if animated and animated.sprite_frames:
		var anim := animated.animation
		if animated.sprite_frames.has_animation(anim):
			return animated.sprite_frames.get_frame_texture(anim, animated.frame)
	return null


# ── Flash ───────────────────────────────────────────────────────────────────
## Quick color flash on any CanvasItem (damage feedback).
func flash(item: CanvasItem, color: Color = Color(1.0, 0.25, 0.25), time: float = 0.18) -> void:
	if not is_instance_valid(item):
		return
	item.modulate = color
	var tw := item.create_tween()
	tw.tween_property(item, "modulate", Color.WHITE, time)

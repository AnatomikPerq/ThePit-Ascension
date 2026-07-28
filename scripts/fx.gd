extends Node
## Fx — autoload with global "juice" helpers: screen shake, particle bursts,
## floating score popups, ghost trails and damage flashes.
##
## Everything world-space spawns under `effects_root`, which the active scene
## registers (World does in _ready). There is NO fallback to
## get_tree().current_scene: a scene that wants effects opts in, and its
## effects die with it. Cosmetics stay local — in a networked session these
## are triggered by replicated events, never replicated as state.

var _trauma: float = 0.0
var _rng := RandomNumberGenerator.new()

const SHAKE_DECAY: float = 2.4
const SHAKE_MAX_OFFSET: float = 30.0

## Where world-space effects live. Set by the active scene, cleared on its
## exit. Bursts are pooled per root: the pool dies with the scene it served.
var effects_root: Node2D = null:
	set(value):
		effects_root = value
		_burst_pool.clear()

var _burst_scene: PackedScene
var _popup_scene: PackedScene
var _ghost_scene: PackedScene
var _dust_preset: BurstPreset
var _burst_pool: Array[FxBurst] = []


func _ready() -> void:
	# Shake must decay even while the tree is paused (menus).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Loaded here, not preloaded as consts: an autoload's preloads pin
	# resources past shutdown (same lesson as the sound bank).
	_burst_scene = load("res://scenes/fx/Burst.tscn")
	_popup_scene = load("res://scenes/fx/Popup.tscn")
	_ghost_scene = load("res://scenes/fx/Ghost.tscn")
	_dust_preset = load("res://data/fx/dust.tres")


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


# ── Particles ───────────────────────────────────────────────────────────────
## One-shot burst shaped by a BurstPreset from data/fx/. `tint` multiplies the
## preset color (kill bursts pass the enemy's color over a white preset);
## `count` overrides the preset amount when > 0 (combo-scaled kills).
## Bursts are pooled and returned on their `finished` signal.
func burst(pos: Vector2, preset: BurstPreset, tint: Color = Color.WHITE, count: int = 0) -> void:
	if preset == null or not is_instance_valid(effects_root):
		return
	var b := _acquire_burst()
	b.global_position = pos
	b.fire(preset, tint, count)


## Soft dust puff (landing, golem petrification).
func dust(pos: Vector2, count: int = 0) -> void:
	burst(pos, _dust_preset, Color.WHITE, count)


func _acquire_burst() -> FxBurst:
	while not _burst_pool.is_empty():
		var pooled := _burst_pool.pop_back() as FxBurst
		if is_instance_valid(pooled):
			return pooled
	var b: FxBurst = _burst_scene.instantiate()
	b.finished.connect(_on_burst_finished.bind(b))
	effects_root.add_child(b)
	return b


func _on_burst_finished(b: FxBurst) -> void:
	if is_instance_valid(b):
		_burst_pool.append(b)


# ── Floating popups ─────────────────────────────────────────────────────────
## Floating text in world space ("+300 x3"). Rises and fades out.
func popup(pos: Vector2, text: String, color: Color = Color.WHITE, font_size: int = 30) -> void:
	if not is_instance_valid(effects_root):
		return
	var p: Node2D = _popup_scene.instantiate()
	effects_root.add_child(p)
	p.global_position = pos
	p.setup(text, color, font_size)


# ── Ghost trail ─────────────────────────────────────────────────────────────
## Fading afterimage copy of a sprite (dash trails).
## Accepts either a Sprite2D or an AnimatedSprite2D — the ghost only ever needs
## the texture that is on screen right now.
func ghost(src: Node2D, tint: Color = Color(1.0, 1.0, 1.0, 0.4)) -> void:
	if not is_instance_valid(effects_root) or src == null:
		return
	var tex := _current_texture(src)
	if tex == null:
		return
	var g: Node2D = _ghost_scene.instantiate()
	effects_root.add_child(g)
	g.setup(tex, src.get("flip_h") == true, src.global_transform, tint)


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

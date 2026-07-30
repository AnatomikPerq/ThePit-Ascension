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

## Trauma per second bled off, and the offset trauma 1.0 is worth.
##
## These were 2.4 / 30.0, which put a hit at 0.35 trauma on screen as ±3.7 px
## for 150 ms — sub-pixel noise on a 1920-wide viewport. Nobody could see it,
## and once the kill hitstop was removed there was nothing else selling an
## impact, so the shake read as gone. Same curve, amplitude and dwell that
## actually land.
const SHAKE_DECAY: float = 1.8
const SHAKE_MAX_OFFSET: float = 80.0

## Where world-space effects live. Set by the active scene, cleared on its
## exit. Bursts are pooled per root: the pool dies with the scene it served.
var effects_root: Node2D = null:
	set(value):
		effects_root = value
		_burst_pool.clear()

## Where this machine's eyes are — the point the local avatar's camera follows.
## World keeps it current. Feedback that should fade with distance reads it, so
## a bomb on the far side of the pit does not shake a screen it is nowhere near
## and does not flash a room it cannot be seen from. It is deliberately a plain
## position rather than a node reference: Fx has no business holding on to an
## avatar that dies mid-run.
var listener_position: Vector2 = Vector2.ZERO

var _burst_scene: PackedScene
var _popup_scene: PackedScene
var _ghost_scene: PackedScene
var _debris_scene: PackedScene
var _shard_scene: PackedScene
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
	_debris_scene = load("res://scenes/fx/Debris.tscn")
	_shard_scene = load("res://scenes/fx/Shard.tscn")
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


## How much of something happening at `pos` reaches this machine: 1.0 on top of
## it, 0.0 at `range_px` and beyond. The one place distance-scaled feedback is
## defined, so shake, flash and anything added later agree about "far away".
func loudness_at(pos: Vector2, range_px: float) -> float:
	if range_px <= 0.0:
		return 1.0
	return clampf(1.0 - listener_position.distance_to(pos) / range_px, 0.0, 1.0)


## Trauma from an event that happened somewhere. A kill or a blast across the
## pit used to shake the camera as hard as one under your feet, which in a
## session meant every player's screen jumping for everyone else's fights.
func shake_from(pos: Vector2, amount: float, range_px: float) -> void:
	shake(amount * loudness_at(pos, range_px))


## Wash the screen with light. Nothing happens unless the active scene has
## instanced a BlastFlash — the same opt-in as effects_root.
##
## `close` is the other thing entirely: a fireball growing out of `world_pos`,
## for the one player who set a bomb off with their own body. Everybody else gets
## the wash, which covers the frame and does not care where it came from.
func screen_flash(strength: float, world_pos: Vector2, close: bool = false) -> void:
	if strength <= 0.0:
		return
	var flasher := get_tree().get_first_node_in_group(FxBlastFlash.GROUP) as FxBlastFlash
	if flasher != null:
		flasher.flash(strength, world_pos, close)


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


# ── Debris ──────────────────────────────────────────────────────────────────
## An object coming apart into pieces of ITSELF: `chunk` is the texture the
## thing that broke was drawn with, so no per-object debris art exists anywhere.
## `extents` is half the object's size (chunks emit across the whole footprint)
## and `away` the direction the wave pushed. Not pooled — things break rarely,
## and each burst carries a different texture and a different emission box.
func debris(pos: Vector2, chunk: Texture2D, extents: Vector2, away: Vector2,
		preset: BurstPreset, tint: Color = Color.WHITE) -> void:
	if not is_instance_valid(effects_root):
		return
	var d: FxDebris = _debris_scene.instantiate()
	effects_root.add_child(d)
	d.global_position = pos
	d.setup(preset, chunk, extents, away, tint)


# ── Shards ──────────────────────────────────────────────────────────────────
## A drawing cut up and thrown away from `away`.
##
## The other half of `debris`, for objects that are not visibly built from a
## repeating part: a slime, a petrified golem, a bomb. Throwing whole copies of
## those around reads as the thing multiplying, so the sprite is sliced into a
## grid and each cell leaves on its own trajectory. Nothing is drawn or built —
## every piece is a Sprite2D looking at one `region_rect` of the texture the
## object already had.
##
## `sprite` is the node that was on screen, not a texture, because where the
## pieces start has to match where the drawing was: its transform carries the
## position, the ×2 scale, any rotation (a bomb is usually spinning) and the flip.
func shards(sprite: Node2D, preset: ShardPreset, away: Vector2 = Vector2.ZERO,
		tint: Color = Color.WHITE) -> void:
	if not is_instance_valid(effects_root) or sprite == null or preset == null:
		return
	var tex := texture_of(sprite)
	if tex == null:
		return
	var size := tex.get_size()
	if size.x < 1.0 or size.y < 1.0:
		return

	var grid := preset.grid_for(size)
	var cell := Vector2(size.x / float(grid.x), size.y / float(grid.y))
	var flipped: bool = sprite.get("flip_h") == true
	var xf := sprite.global_transform
	var push := away.normalized() * preset.push_bias

	for cx in grid.x:
		for cy in grid.y:
			# Where this cell sits relative to the drawing's centre, in the
			# texture's own pixels. Mirrored when the sprite was, so a flipped
			# drawing breaks along the lines you could actually see.
			var offset := Vector2(
				(cx + 0.5) * cell.x - size.x * 0.5,
				(cy + 0.5) * cell.y - size.y * 0.5)
			if flipped:
				offset.x = -offset.x
			var radial := offset.normalized() if offset.length_squared() > 0.01 else Vector2.UP
			var dir := (radial + push).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.UP
			var speed := preset.speed * _rng.randf_range(
				1.0 - preset.speed_variance, 1.0 + preset.speed_variance)
			var spin := preset.spin * _rng.randf_range(0.5, 1.5) \
					* (1.0 if _rng.randf() < 0.5 else -1.0)

			var piece: FxShard = _shard_scene.instantiate()
			effects_root.add_child(piece)
			piece.global_transform = xf.translated_local(offset)
			piece.flip_h = flipped
			piece.setup(tex, Rect2(Vector2(cx, cy) * cell, cell), dir * speed, spin,
				preset.gravity, preset.life, tint)


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
	var tex := texture_of(src)
	if tex == null:
		return
	var g: Node2D = _ghost_scene.instantiate()
	effects_root.add_child(g)
	g.setup(tex, src.get("flip_h") == true, src.global_transform, tint)


## The texture a sprite node is currently showing, whichever kind it is. Public
## because debris needs the same answer about a node it is about to destroy.
func texture_of(src: Node2D) -> Texture2D:
	if src == null:
		return null
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

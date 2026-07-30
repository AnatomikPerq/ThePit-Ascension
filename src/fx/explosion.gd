class_name FxExplosion
extends Node2D
## The visible half of a blast, plus the hitbox that kills what it covers.
##
## The hitbox joins the "strike" group and stamps the causer's peer id on
## itself, which is the contract Strike and Shockwave already use: every enemy
## finds it through its own StompArea/DamageArea and dies down its existing
## path, the spitter's acid blobs fizzle, and nothing on the enemy side has to
## know that bombs exist.
##
## The whole timeline — when the hitbox opens, when it shuts, when this node
## goes — is the `boom` clip on the AnimationPlayer, not a float counting down
## in _physics_process.
##
## The fireball itself is particles, fired by Blast from the presets on the
## BlastDef. `Sprite` is the reserved slot for a drawn explosion: put frames
## into the `explode` animation of data/animations/bomb_frames.tres (see
## tools/build_sprite_frames.gd) and it appears, scaled to the blast, with no
## code change. Until then it stays hidden and the particles carry the effect.

const SPRITE_ANIM := &"explode"

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hit_area: Area2D = $HitArea
@onready var hit_shape: CollisionShape2D = $HitArea/CollisionShape2D
@onready var anim: AnimationPlayer = $AnimationPlayer


## Called right after add_child, before anything has been processed, so the
## radius is in place before the clip opens the hitbox on its first frame.
func fire(def: BlastDef, credited_peer: int) -> void:
	# resource_local_to_scene on the shape: Shockwave.tscn once shared one
	# CircleShape2D across every instance and wrote its radius every frame.
	var circle := hit_shape.shape as CircleShape2D
	if circle != null:
		circle.radius = def.radius
	hit_area.add_to_group(&"strike")
	hit_area.set_meta(&"owner_peer", credited_peer)
	# So a bomb caught by this blast is punted with force proportional to how
	# close to the middle of it it was standing.
	hit_area.set_meta(&"hit_reach", def.radius)
	_show_sprite(def)
	anim.play(&"boom")


## Sizes whatever has been drawn to the blast it belongs to, so the art does not
## have to be redrawn when the radius is tuned.
func _show_sprite(def: BlastDef) -> void:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(SPRITE_ANIM) \
			or frames.get_frame_count(SPRITE_ANIM) == 0:
		return
	var tex := frames.get_frame_texture(SPRITE_ANIM, 0)
	if tex != null and tex.get_width() > 0:
		var s := def.radius * 2.0 / float(tex.get_width())
		sprite.scale = Vector2(s, s)
	sprite.visible = true
	sprite.play(SPRITE_ANIM)


## Method track at the end of the `boom` clip.
func _done() -> void:
	queue_free()

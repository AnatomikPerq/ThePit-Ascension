class_name FxBlastFlash
extends ColorRect
## What an explosion does to the camera.
##
## Two clips, for two very different events:
##
## - `flash` — a warm wash over the frame, scaled by how far away the blast was.
##   What everybody sees for every bomb.
## - `blinding` — a fireball growing out of the blast itself and washing past the
##   camera, for the one player who set a bomb off by walking into it. Not a white
##   rectangle: `Fireball` is a radial gradient (white core, orange body, dark
##   smoked edge) that scales up from a point, so it reads as the blast arriving
##   rather than as a camera flash. It is placed at where the bomb actually went
##   off, not at the middle of the screen — you were standing next to it, not in
##   the exact centre of it.
##
## Strength scales the whole node through `modulate`, which multiplies both the
## wash and the fireball, so one number turns the whole thing up or down and the
## shape of it stays authored in the clips.
##
## Found by group rather than by path, so a scene opts in by instancing it and
## Fx never has to know where in the layer it was put.

const GROUP := &"screen_flash"

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var fireball: TextureRect = $Fireball


func _ready() -> void:
	add_to_group(GROUP)


## `strength` IS the peak alpha — there is no second ceiling here on purpose, so
## the only number that decides how bright a bomb is lives in its BlastDef, next
## to the shake it is balanced against. The pit is dark; for the ordinary wash,
## anything much above a quarter reads as a bug rather than a bomb.
##
## `world_pos` is where it went off. This node sits on a CanvasLayer, in screen
## space, so the point is carried through the viewport's canvas transform — the
## same transform the camera applies to everything else — and the fireball is
## centred on the result.
func flash(strength: float, world_pos: Vector2, close: bool = false) -> void:
	modulate.a = clampf(strength, 0.0, 1.0)
	var on_screen: Vector2 = get_viewport().get_canvas_transform() * world_pos
	fireball.position = on_screen - fireball.size * 0.5
	anim.stop()
	anim.play(&"blinding" if close else &"flash")

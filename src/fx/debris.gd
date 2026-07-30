class_name FxDebris
extends CPUParticles2D
## An object coming apart into pieces of itself.
##
## The texture is the destroyed object's own sprite, so a platform breaks into
## platform, a trampoline into trampoline and a petrified golem into stone —
## with no per-object debris art, and nothing drawn in code. Chunks emit from a
## rectangle the size of the thing that broke and fly away from the blast.
##
## The fixed look (spin, spread, fade ramp, draw order) is authored in
## Debris.tscn; setup() fills in what only the caller knows.

func setup(preset: BurstPreset, chunk: Texture2D, extents: Vector2,
		away: Vector2, tint: Color) -> void:
	texture = chunk
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emission_rect_extents = extents.max(Vector2(2.0, 2.0))
	# Thrown away from the epicentre, so the wave reads as having pushed.
	direction = away
	if preset != null:
		amount = preset.count
		lifetime = preset.life
		gravity = Vector2(0.0, preset.gravity)
		initial_velocity_min = preset.speed * 0.3
		initial_velocity_max = preset.speed
		scale_amount_min = preset.scale_min
		scale_amount_max = preset.scale_max
		modulate = preset.color * tint
	else:
		modulate = tint
	finished.connect(queue_free)
	restart()

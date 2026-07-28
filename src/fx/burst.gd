class_name FxBurst
extends CPUParticles2D
## One pooled one-shot burst. The fixed look (one_shot, explosiveness,
## spread, z_index) is authored in Burst.tscn; fire() fills in the preset.
## Fx returns this node to its pool on the `finished` signal.


func fire(preset: BurstPreset, tint: Color, count_override: int) -> void:
	amount = count_override if count_override > 0 else preset.count
	lifetime = preset.life
	gravity = Vector2(0.0, preset.gravity)
	initial_velocity_min = preset.speed * 0.35
	initial_velocity_max = preset.speed
	scale_amount_min = preset.scale_min
	scale_amount_max = preset.scale_max

	# The gradient is resource_local_to_scene, so mutating it is per-instance.
	var c := preset.color * tint
	var ramp := color_ramp as Gradient
	ramp.set_color(0, Color(c, 1.0))
	ramp.set_color(1, Color(c, 0.0))

	restart()

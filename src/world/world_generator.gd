class_name WorldGenerator
extends Object
## Deterministic function (profile, seed) -> WorldPlan. No scene access, no
## autoloads. It draws from the GLOBAL rng functions after seed(world_seed) —
## not from a RandomNumberGenerator instance, because the two produce
## different streams for the same seed (measured, first draw differs), and
## the global stream is what all pre-refactor worlds were built from.
## The side effect is explicit: generating a world reseeds the global RNG.
##
## The draw ORDER is part of the contract. tools/world_fingerprint.tscn hashes
## the geometry this produces, and every peer in a multiplayer session builds
## its world from the same seed — reordering the draws below silently changes
## every world and desyncs every session. Add new draws only at the end of a
## platform's block, never between existing ones.


static func generate(profile: WorldProfile, world_seed: int) -> WorldPlan:
	seed(world_seed)

	var plan := WorldPlan.new()
	plan.world_seed = world_seed
	var max_depth := profile.max_depth()

	# Shaft walls, floor to top, in stacked segments. No draws.
	var y := max_depth - profile.wall_segment_height
	while y > profile.wall_top_y:
		plan.add_static(WorldPlan.Kind.WALL, Rect2(
			-profile.wall_thickness, y,
			profile.wall_thickness, profile.wall_segment_height))
		plan.add_static(WorldPlan.Kind.WALL, Rect2(
			profile.world_width, y,
			profile.wall_thickness, profile.wall_segment_height))
		y -= profile.wall_segment_height

	# The floor. No draws.
	plan.add_static(WorldPlan.Kind.FLOOR, Rect2(
		0.0, max_depth - profile.floor_thickness,
		profile.world_width, profile.floor_thickness))

	# Level dividers: a ledge from each wall at every level boundary. No draws.
	var dividers_y := profile.divider_ys()
	for div_y in dividers_y:
		var top := div_y - profile.divider_thickness / 2.0
		plan.add_static(WorldPlan.Kind.DIVIDER, Rect2(
			0.0, top, profile.divider_width, profile.divider_thickness))
		plan.add_static(WorldPlan.Kind.DIVIDER, Rect2(
			profile.world_width - profile.divider_width, top,
			profile.divider_width, profile.divider_thickness))

	_plan_platforms(profile, plan, max_depth, dividers_y)
	return plan


## Platform rows, bottom to top. This is the only section that draws.
static func _plan_platforms(profile: WorldProfile,
		plan: WorldPlan, max_depth: float, dividers_y: Array[float]) -> void:
	var current_y := max_depth - profile.row_start_offset

	while current_y > profile.row_top_y:
		var progress := 1.0 - (maxf(current_y, 0.0) / max_depth)
		var step_y := lerpf(profile.row_step_bottom, profile.row_step_top, progress)

		# Rows too close to a divider are suppressed — before the chance draw,
		# so a suppressed row consumes nothing from the stream.
		var near_divider := false
		for div_y in dividers_y:
			if absf(current_y - div_y) < profile.divider_clearance:
				near_divider = true
				break
		if near_divider:
			current_y -= step_y
			plan.free_zones.append(Rect2(0.0, current_y, profile.world_width, step_y))
			continue

		var chance := lerpf(profile.row_chance_bottom, profile.row_chance_top, progress)
		if randf() < chance: # draw 1: does this row spawn
			var max_plats := int(lerpf(profile.per_row_bottom, profile.per_row_top, progress))
			var plat_count := randi_range(1, maxi(1, max_plats)) # draw 2

			for i in range(plat_count):
				var max_b := int(lerpf(profile.blocks_max_bottom, profile.blocks_max_top, progress))
				var blocks := randi_range(profile.blocks_min, maxi(profile.blocks_min, max_b)) # draw 3
				var w := blocks * profile.block_width

				var x := randf_range(profile.side_margin, profile.world_width - profile.side_margin - w) # draw 4
				var type_roll := randf() # draw 5
				var p_y := current_y + randf_range(-profile.row_jitter, profile.row_jitter) # draw 6

				if type_roll < profile.static_threshold:
					plan.add_static(WorldPlan.Kind.PLATFORM,
						Rect2(x, p_y, w, profile.platform_height))
				else:
					var mover := WorldPlan.MoverPiece.new()
					mover.position = Vector2(x, p_y)
					mover.size = Vector2(w, profile.platform_height)
					mover.speed = randf_range(profile.move_speed_min, profile.move_speed_max) # draw 7
					mover.delay = randi_range(0, profile.move_delay_max) # draw 8
					if type_roll < profile.horizontal_threshold:
						mover.axis = MovingPlatform.Axis.HORIZONTAL
						mover.travel = randf_range(
							profile.horizontal_travel_min, profile.horizontal_travel_max) # draw 9
					else:
						mover.axis = MovingPlatform.Axis.VERTICAL
						mover.travel = randf_range(
							profile.vertical_travel_min, profile.vertical_travel_max) # draw 9
					plan.movers.append(mover)

		current_y -= step_y
		plan.free_zones.append(Rect2(0.0, current_y, profile.world_width, step_y))

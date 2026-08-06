extends SceneTree
## What the pit actually looks like, level by level:
##
##   godot --headless --path . -s tools/world_balance.gd [samples]
##
## Not a gate — a measuring stick. Every ramp in WorldProfile is a lerp over
## ascent PROGRESS, so changing level_count silently restretches all of them,
## and the only honest way to know whether eight levels are still climbable is
## to generate a pile of them and look.
##
## The column that decides it is GAP: the largest vertical distance between two
## consecutive rows that actually got platforms. A climber has to cross that on
## jumps alone, and the jump heights are printed underneath for comparison. A
## level whose worst gap beats every character's reach is a level somebody gets
## stuck in.
##
## ENEMIES is the spawn table's weight mix at the middle of the level, in
## percent — the other half of "balance", and the reason the later enemies now
## carry a non-zero weight_start.

const PROFILE := "res://data/worlds/pit.tres"
const ROSTER := "res://data/characters/roster.tres"
const DEFAULT_SAMPLES := 40


func _initialize() -> void:
	var samples := DEFAULT_SAMPLES
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		samples = maxi(int(args[0]), 1)

	var profile: WorldProfile = load(PROFILE)
	var depth := profile.max_depth()
	print("pit: %d levels x %d = depth %d, %d seeds\n" % [
		profile.level_count, int(profile.level_height), int(depth), samples])

	# level index -> accumulated stats
	var rows := PackedInt32Array()
	var filled := PackedInt32Array()
	var pieces := PackedInt32Array()
	var widths := PackedFloat32Array()
	var worst_gap := PackedFloat32Array()
	var mean_gap := PackedFloat32Array()
	for i in profile.level_count:
		rows.append(0)
		filled.append(0)
		pieces.append(0)
		widths.append(0.0)
		worst_gap.append(0.0)
		mean_gap.append(0.0)

	for s in samples:
		var plan := WorldGenerator.generate(profile, 1000 + s * 7919)
		# Every platform-bearing y in the world, and every planned row.
		var occupied: Array[float] = []
		for piece in plan.statics:
			if piece.kind != WorldPlan.Kind.PLATFORM:
				continue
			occupied.append(piece.rect.position.y)
			var level := _level_of(piece.rect.position.y, profile)
			pieces[level] += 1
			widths[level] += piece.rect.size.x
		for mover in plan.movers:
			occupied.append(mover.position.y)
			var level := _level_of(mover.position.y, profile)
			pieces[level] += 1
			widths[level] += mover.size.x
		for zone in plan.free_zones:
			rows[_level_of(zone.position.y, profile)] += 1

		occupied.sort()
		var last := depth # the floor counts as ground you can stand on
		# Walk the rows from the floor upward, measuring how far apart the
		# occupied ones are. Duplicate ys inside one row collapse to one step.
		var seen: Array[float] = []
		for i in range(occupied.size() - 1, -1, -1):
			var y: float = occupied[i]
			if not seen.is_empty() and is_equal_approx(seen[-1], y):
				continue
			seen.append(y)
			var gap := last - y
			var level := _level_of(y, profile)
			filled[level] += 1
			if gap > worst_gap[level]:
				worst_gap[level] = gap
			mean_gap[level] += gap
			last = y

	print("LEVEL   DEPTH RANGE      ROWS  WITH-PLATS  PIECES  AVG-W   MEAN-GAP  WORST-GAP   ENEMIES")
	for i in profile.level_count:
		var top := depth - float(i + 1) * profile.level_height
		var bottom := depth - float(i) * profile.level_height
		var mid_progress := 1.0 - (bottom - profile.level_height * 0.5) / depth
		var per_seed := float(samples)
		print("%5d   %6d..%-6d  %5.1f  %9.1f  %6.1f  %5.0f   %7.0f  %8.0f   %s" % [
			i + 1, int(bottom), int(top),
			rows[i] / per_seed,
			filled[i] / per_seed,
			pieces[i] / per_seed,
			(widths[i] / maxf(pieces[i], 1.0)),
			mean_gap[i] / maxf(filled[i], 1.0),
			worst_gap[i],
			_mix(profile, mid_progress),
		])

	print("")
	_print_reach()
	quit(0)


## Which level a y falls in. Level 1 is the bottom.
func _level_of(y: float, profile: WorldProfile) -> int:
	var from_floor := profile.max_depth() - y
	return clampi(int(from_floor / profile.level_height), 0, profile.level_count - 1)


## The spawn table's weights at one point in the climb, as percentages.
func _mix(profile: WorldProfile, progress: float) -> String:
	var total := 0.0
	var weights: Array[float] = []
	for entry in profile.spawn_table:
		var w := lerpf(entry.weight_start, entry.weight_end, clampf(progress, 0.0, 1.0))
		weights.append(w)
		total += w
	var parts: Array[String] = []
	for i in profile.spawn_table.size():
		parts.append("%s %d%%" % [
			profile.spawn_table[i].resource_name.substr(0, 2),
			roundi(100.0 * weights[i] / maxf(total, 0.001)),
		])
	return " ".join(parts)


## How high each climber can actually get, so the gaps above mean something.
## h = v^2 / 2g, and an air jump starts from the top of the previous one.
func _print_reach() -> void:
	var roster: CharacterRoster = load(ROSTER)
	var g := 5760.0 # Player.GRAVITY
	var base := 1800.0 # -Player.JUMP_FORCE
	for character in roster.characters:
		var v := base * character.jump_scale
		var ground := v * v / (2.0 * g)
		var air := (v * 0.9) * (v * 0.9) / (2.0 * g)
		print("%-6s jump %4.0f px   with %d jumps %4.0f px   fully upgraded %4.0f px" % [
			character.display_name,
			ground,
			character.base_jumps,
			ground + air * (character.base_jumps - 1),
			ground + air * (character.base_jumps - 1 + _extra_jumps(character)),
		])


func _extra_jumps(character: CharacterDef) -> int:
	var n := 0
	for upgrade in character.upgrades:
		if upgrade != null and upgrade.effect == UpgradeDef.Effect.EXTRA_JUMP:
			n += 1
	return n

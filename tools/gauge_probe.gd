extends Node2D
## The charge gauge, measured: does a sixth of the scale light a sixth of the gun,
## and do the marks along the top stand where they say they do?
##
##   godot --path . --fixed-fps 60 tools/gauge_probe.tscn
##   godot --path . --fixed-fps 60 tools/gauge_probe.tscn -- out_dir   # + PNGs
##
## The indicator is the one widget in the game whose entire appearance is a
## shader uniform read against a painted mask, so "is it right" is not a question
## any unit test can reach: nothing about it exists until a frame has been drawn.
## This draws the widget alone on a black field, at fills set BY HAND, reads the
## pixels back and counts how much of the energy strip lit up.
##
## It is a gate, not a gallery. It fails when the scale stops being even — which
## is exactly the failure the owner reported twice and neither the suite nor
## ui_check could see:
##
##   - the mask ordered by pixel count, so the sparse end of the gun lit inside
##     the first five per cent of the scale and then never moved again;
##   - the mask regenerated on disk and NEVER RE-IMPORTED, so every probe on this
##     machine was rendering the previous one and agreeing with itself.
##
## The second is why this reads the mask through `preload` rather than off disk:
## it sees exactly what the game sees, and if that is stale the answer is wrong
## in the same direction as the game. Run `--import` after regenerating an asset.
##
## The marks are checked the same way round. RailGauge places them by asking the
## mask where the front will be; this reads them off the NODES and compares them
## against where the front actually is in the frame that was drawn. Neither side
## borrows the other's arithmetic, so a mark that has drifted is a mark that says
## so rather than one that agrees with a wrong answer.

const GAUGE: PackedScene = preload("res://scenes/ui/RailGauge.tscn")
const MASK: Texture2D = preload("res://assets/ui/rail_indicator_mask.png")

## Where the widget is put, in design pixels, and how big one mask texel is
## there — RailGauge.tscn is 474 wide over a 158-wide drawing.
const AT := Vector2(20.0, 20.0)
const TEXEL: float = 474.0 / 158.0

## What the gun holds, and therefore how many steps the scale has. Six is
## RailgunStats' shipped number; the probe only needs SOME capacity, and this
## keeps the printed fractions readable against the ones the owner sees.
const CAPACITY: int = 6
## Every step the meter will ever be asked for.
const FILLS: Array[float] = [
	1.0 / 6.0, 2.0 / 6.0, 3.0 / 6.0, 4.0 / 6.0, 5.0 / 6.0, 1.0,
]
## How far the lit fraction may sit from the fill. One column of the strip is
## 0.8%, so this is a couple of columns — enough for the bright front edge to
## bleed into its neighbour, not enough for a scale that is wrong to pass.
const TOLERANCE: float = 0.025

var _out_dir: String = ""
var _failed: int = 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	RenderingServer.set_default_clear_color(Color.BLACK)
	_run.call_deferred()


func _run() -> void:
	var gauge: TextureRect = GAUGE.instantiate()
	add_child(gauge)
	gauge.position = AT

	var columns := _energy_columns()
	if columns.is_empty():
		push_error("gauge_probe: the order mask has no energy pixels in it at all")
		get_tree().quit(1)
		return

	# Every column read at both ends of the scale, so each one is judged against
	# ITSELF rather than against a brightness threshold picked out of the air —
	# the cells are shaded, and a dark one lit is dimmer than a bright one spent.
	var empty := await _sample(gauge, 0.0, columns, "gauge_fill_000.png")
	var full := await _sample(gauge, 1.0, columns, "")

	print("gauge_probe: %d energy columns, x %d..%d" % [
		columns.size(), columns[0].x, columns[columns.size() - 1].x])
	for step in FILLS.size():
		var fill: float = FILLS[step]
		var here := await _sample(gauge, fill, columns,
			"gauge_fill_%03d.png" % int(round(fill * 100.0)))
		var lit := 0
		var front := -1
		for i in columns.size():
			if here[i] > (empty[i] + full[i]) * 0.5:
				lit += 1
				front = columns[i].x
		var shown := float(lit) / float(columns.size())
		var off := absf(shown - fill)
		var verdict := "ok" if off <= TOLERANCE else "OFF BY %.1f%% OF THE GUN" % (off * 100.0)
		if off > TOLERANCE:
			_failed += 1
		print("  fill %.3f -> %3d/%d columns lit (%.1f%%)%s  %s" % [
			fill, lit, columns.size(), shown * 100.0,
			_mark_verdict(gauge, step, front), verdict])

	if _failed > 0:
		printerr("gauge_probe: %d complaints." % _failed)
		printerr("  The mask is assets/ui/rail_indicator_mask.png — regenerate it with")
		printerr("  tools/aseprite/build_rail_mask.lua, then RE-IMPORT before believing")
		printerr("  any of these numbers again.")
	else:
		print("gauge_probe: the scale is even end to end and the marks sit on it.")
	get_tree().quit(1 if _failed > 0 else 0)


## The mark between charge `step` and the next one, against the front this frame
## actually rendered. The last step has no mark after it — a full gun's front is
## the end of the gun.
##
## Both sides are in TEXELS of the mask, which is the unit the whole widget is
## really in: the mark is read off the node and converted, the front is read off
## the screen. Neither borrows the other's arithmetic, which is the point.
func _mark_verdict(gauge: TextureRect, step: int, front: int) -> String:
	var marks := gauge.get_node(^"Ticks").get_children()
	if step >= marks.size() or step + 1 >= CAPACITY:
		return ""
	var mark := marks[step] as Control
	if not mark.visible:
		_failed += 1
		return "  MARK %d IS HIDDEN" % (step + 1)
	# The same KEEP_ASPECT_CENTERED arithmetic RailGauge does, from the outside.
	var frame := gauge.texture.get_size()
	var zoom := minf(gauge.size.x / frame.x, gauge.size.y / frame.y)
	var origin := (gauge.size.x - frame.x * zoom) * 0.5
	var at := (mark.position.x + mark.size.x * 0.5 - origin) / zoom
	if absf(at - float(front + 1)) > 1.0:
		_failed += 1
		return "  MARK %d AT TEXEL %.1f, FRONT AT %d" % [step + 1, at, front + 1]
	return "  mark %d on the front" % (step + 1)


## One energy pixel per column that has any, which is all the sampling needs:
## the generator gives every pixel in a column the same place in the order.
func _energy_columns() -> Array[Vector2i]:
	var img := MASK.get_image()
	var found: Array[Vector2i] = []
	for x in img.get_width():
		for y in img.get_height():
			if img.get_pixel(x, y).r > 0.0:
				found.append(Vector2i(x, y))
				break
	return found


## Set the uniform, let it draw, and read one screen pixel per column back.
func _sample(gauge: TextureRect, fill: float, columns: Array[Vector2i],
		save_as: String) -> PackedFloat32Array:
	# Through the front door rather than at the uniform, so the marks are laid out
	# by the code the HUD runs and not by the probe. 0 charges held keeps the
	# flash out of the picture.
	gauge.call(&"show_charge", fill, 0, CAPACITY)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if not _out_dir.is_empty() and not save_as.is_empty():
		img.save_png(_out_dir.path_join(save_as))

	# The window is stretched from the design size, so a design pixel is this
	# many real ones. Asking the image rather than assuming 1:1 is what makes the
	# probe survive somebody changing the resolution in project.godot.
	var design := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var zoom := float(img.get_width()) / design
	var read := PackedFloat32Array()
	for cell in columns:
		var at := (AT + (Vector2(cell) + Vector2(0.5, 0.5)) * TEXEL) * zoom
		var c := img.get_pixel(int(at.x), int(at.y))
		read.append((c.r + c.g + c.b) / 3.0)
	return read

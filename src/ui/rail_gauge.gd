class_name RailGauge
extends TextureRect
## The railgun's charge indicator: the gun itself, drawn once, lit as far as it
## is charged.
##
## Everything visual is in `assets/ui/rail_fill.gdshader` and its order mask —
## this only turns a weapon's `meter()` into the shader's one uniform, and notices
## when a whole charge has landed so the flash can say so. Six charges on a
## continuous bar are otherwise hard to count; the flash is what makes "that was
## the fourth" readable without a number.
##
## It asks the weapon three questions and nothing else, so a second charged weapon
## later would light it up with no change here.
##
## ## The marks along the top
##
## One per boundary BETWEEN charges — five of them on a gun that holds six — so
## that "how much of this bar is one shot" is a thing you can read off rather
## than estimate. They are MEASURED from the order mask, not authored at pixel
## positions: the mask is a picture and repainting it is the supported way to
## change the fill order, so a scale drawn anywhere else would start lying the
## moment somebody did that. `show_ticks` turns them off in the scene.

const FILL_PARAM: StringName = &"shader_parameter/fill"
## The same file the shader samples. Read here for its ORDER values, which is
## what makes the marks agree with the fill to the column.
const ORDER_MASK: Texture2D = preload("res://assets/ui/rail_indicator_mask.png")

## Whether the scale is drawn. It went in as a debugging aid — the owner wanted
## to see exactly how much of the gun one shot is worth — and it is a flag rather
## than a deletion because that question comes back every time the mask moves.
@export var show_ticks: bool = true

@onready var _flash: AnimationPlayer = $Flash
## The scene authors as many marks as RailgunStats can ever ask for (12 charges,
## 11 boundaries) and the spare ones are hidden. It is the same trade RailShot
## makes with its collision shapes: nothing is allocated while the game runs, and
## the count is visible in the scene instead of buried in a loop.
@onready var _marks: Array[Node] = $Ticks.get_children()

## The last whole-charge count shown, so a completed charge can be spotted. -1
## means nothing has been shown yet, which must not flash — arriving at two
## charges on unlock is not two charges being earned.
var _shown_charges: int = -1
## How many charges the marks were last laid out for. 0 means never.
var _marked_for: int = 0


func _ready() -> void:
	$Ticks.visible = show_ticks
	# The marks are placed in this widget's own space, and that space is not
	# final until the container above has had its say — which happens after
	# _ready. Laying them out on `resized` is what makes the first one right.
	resized.connect(_lay_marks)


## Called every frame by RunHud while the avatar carries something charged.
## `capacity` is what a full gun holds, which is the scale the marks divide.
func show_charge(fill: float, charges: int, capacity: int) -> void:
	(material as ShaderMaterial).set(FILL_PARAM, clampf(fill, 0.0, 1.0))
	if capacity != _marked_for:
		_marked_for = capacity
		_lay_marks()
	if charges > _shown_charges and _shown_charges >= 0:
		_flash.stop()
		_flash.play(&"charged")
	_shown_charges = charges


## A run ended, or the avatar put the weapon away for good. Next time it appears
## it must not flash for charges it already had.
func forget() -> void:
	_shown_charges = -1


# ── The scale ───────────────────────────────────────────────────────────────
## Put each mark where the fill front stands after that many charges.
##
## Which is not a fraction of the widget: the drawing has stretches with no
## energy on them, and the front skips those. The only honest answer is the one
## the shader would give, so this asks the same question of the same mask —
## the last column that lights at `n / capacity` — and puts the mark at its edge.
func _lay_marks() -> void:
	if not show_ticks or _marks.is_empty():
		return
	var order := _column_order()
	var drawn := _drawn_rect()
	for i in _marks.size():
		var mark := _marks[i] as Control
		var step := i + 1
		mark.visible = step < _marked_for
		if not mark.visible:
			continue
		var edge := float(_front_column(order, float(step) / float(_marked_for)) + 1)
		mark.position.x = drawn.position.x + edge * drawn.size.x - mark.size.x * 0.5


## Where the picture actually is inside the control, and how wide one mask column
## is drawn — `stretch_mode = KEEP_ASPECT_CENTERED`, worked out by hand because
## there is no way to ask a TextureRect where it put the texture. Change the
## stretch mode in the scene and this has to change with it.
##
## Returns the top-left corner in `position` and the size of ONE COLUMN in `size`.
func _drawn_rect() -> Rect2:
	var frame := ORDER_MASK.get_size()
	if frame.x <= 0.0 or frame.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var zoom := minf(size.x / frame.x, size.y / frame.y)
	return Rect2((size - frame * zoom) * 0.5, Vector2(zoom, zoom))


## One order value per column of the mask, 0 where a column carries no energy.
## Every energy pixel in a column shares a value, so the first one found is it.
func _column_order() -> PackedFloat32Array:
	var img := ORDER_MASK.get_image()
	var out := PackedFloat32Array()
	for x in img.get_width():
		var found := 0.0
		for y in img.get_height():
			var value := img.get_pixel(x, y).r
			if value > 0.0:
				found = value
				break
		out.append(found)
	return out


## The rightmost column that is lit at this fill, or -1 when none is.
func _front_column(order: PackedFloat32Array, fill: float) -> int:
	var last := -1
	for x in order.size():
		if order[x] > 0.0 and order[x] <= fill:
			last = x
	return last

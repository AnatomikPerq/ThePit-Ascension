class_name RailGauge
extends TextureRect
## The railgun's charge indicator: the gun itself, drawn once, lit as far as it
## is charged.
##
## Everything visual is in `assets/ui/rail_fill.gdshader` and its order mask —
## this only turns a weapon's `fill()` into the shader's one uniform, and notices
## when a whole charge has landed so the flash can say so. Six charges on a
## continuous bar are otherwise hard to count; the flash is what makes "that was
## the fourth" readable without a number.
##
## It asks the weapon two questions and nothing else, so a second charged weapon
## later would light it up with no change here.

const FILL_PARAM: StringName = &"shader_parameter/fill"

@onready var _flash: AnimationPlayer = $Flash

## The last whole-charge count shown, so a completed charge can be spotted. -1
## means nothing has been shown yet, which must not flash — arriving at two
## charges on unlock is not two charges being earned.
var _shown_charges: int = -1


## Called every frame by RunHud while the avatar carries something charged.
func show_charge(fill: float, charges: int) -> void:
	(material as ShaderMaterial).set(FILL_PARAM, clampf(fill, 0.0, 1.0))
	if charges > _shown_charges and _shown_charges >= 0:
		_flash.stop()
		_flash.play(&"charged")
	_shown_charges = charges


## A run ended, or the avatar put the weapon away for good. Next time it appears
## it must not flash for charges it already had.
func forget() -> void:
	_shown_charges = -1

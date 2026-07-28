class_name BurstPreset
extends Resource
## The shape of one particle burst: how many, how fast, how long, how heavy.
## One .tres per effect in data/fx/. Call sites may tint the color and
## override the count (combo-scaled kills do); everything else is data.

@export var count: int = 16
@export var speed: float = 320.0
@export var life: float = 0.55
@export var gravity: float = 800.0
## Multiplied by the tint the call site passes. The alpha channel is ignored:
## particles always ramp from opaque to transparent.
@export var color: Color = Color.WHITE
@export var scale_min: float = 2.0
@export var scale_max: float = 5.0

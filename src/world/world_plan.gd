class_name WorldPlan
extends RefCounted
## The output of WorldGenerator: pure placement records, no nodes.
##
## WorldBuilder turns a plan into bodies. Because a plan is a deterministic
## function of (profile, seed), a networked client rebuilds an identical world
## from nothing but the seed the host sends — the plan itself never travels.

enum Kind {WALL, FLOOR, DIVIDER, PLATFORM}

var world_seed: int = 0
var statics: Array[StaticPiece] = []
var movers: Array[MoverPiece] = []
## Horizontal bands the generator left empty, drawn by the debug overlay.
var free_zones: Array[Rect2] = []


func add_static(kind: Kind, rect: Rect2) -> void:
	var piece := StaticPiece.new()
	piece.kind = kind
	piece.rect = rect
	statics.append(piece)


## One axis-aligned box of static geometry, world space, origin = top-left.
class StaticPiece:
	var kind: Kind = Kind.WALL
	var rect: Rect2


## One oscillating platform. `position` is the body centre — the legacy
## generator anchored movers by centre while static pieces carry a rect.
class MoverPiece:
	var position: Vector2
	var size: Vector2
	var axis: MovingPlatform.Axis = MovingPlatform.Axis.HORIZONTAL
	var speed: float = 0.0
	var delay: int = 0
	var travel: float = 0.0

@tool
class_name ShardPreset
extends Resource
## How a drawing comes apart into pieces of itself.
##
## The counterpart to `BurstPreset` + `Fx.debris`, for the other kind of object.
## A platform is visibly built from one repeating block, so its rubble is copies
## of that block and nobody notices. A slime, a petrified golem or a bomb is a
## single drawing, and throwing whole copies of it around reads as the thing
## multiplying rather than breaking. These are cut up instead: the sprite is
## sliced into a grid and every cell flies off on its own.
##
## The grid is derived from a target piece size rather than fixed rows and
## columns, so one preset gives sensible shards for a 16 px trampoline and a
## 39 px bomb alike — which is the point, because the map is going to grow more
## kinds of thing that break this way.

## Target size of one piece, in SOURCE texture pixels. Smaller means more, finer
## shards; the grid is rounded to whole cells.
@export_range(2, 64, 1) var piece_pixels: int = 12

## Ceiling on the number of pieces, however big the sprite is. The grid is
## coarsened to stay under it rather than the extras being dropped, so an object
## never comes apart into half of itself.
@export_range(1, 64, 1) var max_pieces: int = 16

@export_group("Flight")
@export var speed: float = 900.0
## Each piece's speed is multiplied by 1 ± this.
@export_range(0.0, 1.0, 0.01) var speed_variance: float = 0.4
## How much the blast's own direction is mixed into the outward spray. 0 = pieces
## only fly apart from each other; 1 = they mostly all go the same way.
@export_range(0.0, 2.0, 0.05) var push_bias: float = 0.8
@export var gravity: float = 1500.0
## Tumble, radians per second, signed at random per piece.
@export var spin: float = 9.0
@export var life: float = 0.95


## Columns and rows for a source texture of this size.
func grid_for(size: Vector2) -> Vector2i:
	var cols := maxi(1, int(roundf(size.x / float(piece_pixels))))
	var rows := maxi(1, int(roundf(size.y / float(piece_pixels))))
	# Coarsen — never truncate — until the piece count fits.
	while cols * rows > max_pieces and (cols > 1 or rows > 1):
		if cols >= rows:
			cols -= 1
		else:
			rows -= 1
	return Vector2i(cols, rows)

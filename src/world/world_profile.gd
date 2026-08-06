class_name WorldProfile
extends Resource
## Every number one world is built and paced from. One .tres per world:
## the pit is data/worlds/pit.tres, and a second world is another file —
## not another script.
##
## WorldGenerator reads the geometry groups; World reads the pacing ones.

@export var theme: WorldTheme

@export_group("Shaft")
@export var world_width: float = 2000.0
@export var wall_thickness: float = 128.0
## Eight levels of 2000 — the pit is 16000 deep. Every ramp below is a lerp over
## ascent PROGRESS rather than over depth, so doubling this stretches all of
## them; the endpoints were re-tuned for the longer climb rather than left where
## a four-level pit had put them.
@export var level_count: int = 8
@export var level_height: float = 2000.0
## Walls are stacked in segments of this height …
@export var wall_segment_height: float = 512.0
## … from the floor up until they pass this y.
@export var wall_top_y: float = -3000.0
@export var floor_thickness: float = 64.0
## Level dividers: a ledge this wide grows from each wall at every
## level boundary, leaving a gap in the middle.
@export var divider_width: float = 600.0
@export var divider_thickness: float = 64.0

@export_group("Platform rows")
## The first row sits this far above the floor …
@export var row_start_offset: float = 800.0
## … and rows keep coming until they pass this y.
@export var row_top_y: float = -400.0
## Vertical distance between rows, by ascent progress.
##
## These endpoints did NOT move when the pit went from four levels to eight, and
## that is the point: every one of them is a lerp over PROGRESS, so eight levels
## sample the same difficulty curve the four-level pit had, at twice the
## resolution. tools/world_balance.gd measures it — the mean climb between two
## things you can stand on runs ~85 px at the floor to ~310 px at the surface in
## both, which is the shape the game was tuned around. Stretching the endpoints
## as well made the last two levels harder than any level had ever been.
@export var row_step_bottom: float = 80.0
@export var row_step_top: float = 180.0
## Rows are suppressed this close to a level divider.
@export var divider_clearance: float = 250.0
## Chance that a row spawns at all, by ascent progress.
@export var row_chance_bottom: float = 0.95
@export var row_chance_top: float = 0.6
## Up to this many platforms per row, by ascent progress.
@export var per_row_bottom: float = 4.0
@export var per_row_top: float = 1.0
## Platform width in blocks of block_width, by ascent progress.
@export var blocks_min: int = 2
@export var blocks_max_bottom: float = 8.0
@export var blocks_max_top: float = 3.0
@export var block_width: float = 64.0
@export var platform_height: float = 32.0
## Platforms keep this far from the walls.
@export var side_margin: float = 128.0
## Each platform's y is jittered by up to ± this.
@export var row_jitter: float = 30.0

@export_group("Moving platforms")
## One type roll per platform: below static_threshold it is static, below
## horizontal_threshold it oscillates horizontally, else vertically.
@export var static_threshold: float = 0.6
@export var horizontal_threshold: float = 0.8
@export var move_speed_min: float = 20.0
@export var move_speed_max: float = 50.0
## Movers start after a random delay of up to this many physics ticks,
## so rows don't oscillate in lockstep.
@export var move_delay_max: int = 90
@export var horizontal_travel_min: float = 300.0
@export var horizontal_travel_max: float = 800.0
@export var vertical_travel_min: float = 300.0
@export var vertical_travel_max: float = 600.0

@export_group("Run")
## The player spawns centred, this far above the floor.
@export var player_spawn_height: float = 300.0
## Ascending past this y wins the run.
@export var victory_y: float = 200.0
## Depth fractions that open the upgrade menu, each once. One at the top of
## every other level — 1, 3, 5 and 7 — which is four offers over eight levels.
## What a milestone actually gives depends on what the climber has left: a
## choice, an automatic grant when only one thing is missing, or score.
@export var upgrade_fractions: Array[float] = [0.875, 0.625, 0.375, 0.125]
@export var camera_top_limit: float = -384.0
@export var camera_bottom_margin: float = 120.0

@export_group("Enemy pacing")
@export var spawn_table: Array[SpawnEntry] = []
@export var spawn_interval_start: float = 2.0
@export var spawn_interval_min: float = 0.4
## The interval shrinks by this much per spawn until it hits the minimum. Halved
## when the pit went from four levels to eight: the ramp is counted in spawns,
## not in depth, so leaving it alone would have put the whole back half of a
## twice-as-long climb at the floor rate.
@export var spawn_interval_step: float = 0.025
## SKY and PLATFORM_BAND spawns keep this far from the walls.
@export var spawn_margin_x: float = 200.0
## SKY spawns never appear above this y.
@export var spawn_ceiling_y: float = -800.0
## WALL spawns hug the walls at these insets.
@export var wall_spawn_inset_left: float = 128.0
@export var wall_spawn_inset_right: float = 192.0


func max_depth() -> float:
	return level_count * level_height


## Level boundaries in descending depth order: [6000, 4000, 2000] for the pit.
## Dividers sit here, and crossing one is a zone milestone.
func divider_ys() -> Array[float]:
	var out: Array[float] = []
	for i in range(1, level_count):
		out.append(max_depth() - i * level_height)
	return out

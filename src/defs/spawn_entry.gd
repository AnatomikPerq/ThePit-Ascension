class_name SpawnEntry
extends Resource
## One row of a world's enemy spawn table: which scene, how its weight ramps
## as the player ascends, and where it is allowed to appear.


enum Placement {
	SKY, ## above the player, clamped by the world's spawn ceiling
	WALL, ## hugging the left or right wall (climbers)
	PLATFORM_BAND, ## somewhere in the platform band above the player (needs ground)
}

@export var scene: PackedScene
## Roll weight at the bottom of the pit …
@export var weight_start: float = 0.0
## … ramping linearly to this at the surface.
@export var weight_end: float = 0.0
@export var placement: Placement = Placement.SKY
## How far above the player to appear. Equal min/max means a fixed height.
@export var above_player_min: float = 1200.0
@export var above_player_max: float = 1200.0
## Optional group for counting live instances against max_alive.
@export var group: StringName = &""
## 0 = unlimited.
@export var max_alive: int = 0

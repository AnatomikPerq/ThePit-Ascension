class_name WorldTheme
extends Resource
## The look of one world: shaft textures and the background sky.
## A future world is this theme swapped out under the same WorldProfile —
## or the same theme under different numbers.


## Source PNGs are authored at half scale (the ×2 legacy of the Pygame
## original), so every piece of shaft geometry is drawn at this factor.
@export var pixel_scale: float = 2.0

@export var wall_texture: Texture2D
@export var floor_texture: Texture2D
@export var divider_texture: Texture2D
@export var platform_texture: Texture2D

## Background clear color, sampled by ascent progress
## (0 = the bottom of the pit, 1 = the surface).
@export var background_by_ascent: Gradient


func texture_for(kind: WorldPlan.Kind) -> Texture2D:
	match kind:
		WorldPlan.Kind.WALL:
			return wall_texture
		WorldPlan.Kind.FLOOR:
			return floor_texture
		WorldPlan.Kind.DIVIDER:
			return divider_texture
		_:
			return platform_texture

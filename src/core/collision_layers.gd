class_name Layers
extends Object
## Named collision layers, mirroring the 2d_physics layer names in
## project.godot. Code that builds bodies at runtime uses these instead of bare
## bitmask literals, so `collision_layer = 33` stops being a number nobody can
## explain.
##
## Layer 6 used to appear in that 33 (1 + 32) on the floor, the walls and the
## level dividers. Nothing anywhere in the project ever masked bit 32, so it was
## dead weight and is gone.

const NONE: int = 0                ## collides with nothing (a corpse, a probe)
const WORLD: int = 1 << 0          ## static geometry: floor, walls, platforms
const PLAYER: int = 1 << 1         ## the player's CharacterBody2D
const TRAMPOLINE: int = 1 << 2     ## trampoline trigger area
const PLAYER_ATTACK: int = 1 << 3  ## strike and shockwave hitboxes
const ENEMY: int = 1 << 4          ## enemy bodies and their hitboxes

## What an enemy hitbox watches for: the player, and anything that can hurt it.
const ENEMY_HITBOX_MASK: int = PLAYER | PLAYER_ATTACK

## The same layers as 1-based bit indices, for set_collision_mask_value() and
## set_collision_layer_value(). Those take an index, not a mask, so without
## these the code reads `set_collision_mask_value(3, false)` and nobody can say
## what 3 is without counting the project settings list.
const BIT_WORLD: int = 1
const BIT_PLAYER: int = 2
const BIT_TRAMPOLINE: int = 3
const BIT_PLAYER_ATTACK: int = 4
const BIT_ENEMY: int = 5

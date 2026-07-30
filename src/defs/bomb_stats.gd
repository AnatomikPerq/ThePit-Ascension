@tool
class_name BombStats
extends Resource
## Every number the bomb is tuned by. One .tres: data/enemies/bomb.tres.
##
## The bomb is not an enemy — it has no stomp, no contact matrix and no kill of
## its own — so it carries this instead of an EnemyStats.

## Straight down, a shade quicker than the golem (360) and the slime (480).
## ×2 scaled from the legacy units like everything else: 5 * 60 * 2.
@export var fall_speed: float = 600.0

@export_group("Batted away")
## Launch speed along the line away from the hit — both axes, so where the swing
## caught it decides where it goes: from below it sails up, from above it is
## driven into the floor.
@export var launch_speed: float = 1150.0
## A little extra arc on top, so a level hit still lobs rather than slides.
## Negative is up.
@export var launch_lift: float = -420.0
## Gravity while it is in flight. Higher than the player's, so it comes down.
@export var launch_gravity: float = 3200.0
## Tumble, radians per second, signed by the direction it was hit.
@export var launch_spin: float = 13.0
## How hard a swing that only clipped the bomb throws it, as a fraction of a
## dead-centre hit. Catching one right against you — the middle of a Shockwave,
## the middle of a punch — sends it much further, which is the thing worth
## aiming for.
@export_range(0.05, 1.0, 0.05) var launch_power_min: float = 0.45
## Fallback size of a hitbox that did not say how big it is. Strike and Shockwave
## both stamp `hit_reach` on their hitbox; anything new that does not gets this.
@export var launch_default_reach: float = 60.0
## Metal-on-fist, played from where it was hit.
@export var launch_sound: StringName = &"bomb_hit"

@export_group("Blast")
@export var blast: BlastDef
## How the bomb itself comes apart. A stand-in until there are explosion frames
## to play: the shell is cut up and thrown, which at least says "this was a solid
## object a moment ago" instead of the sprite simply vanishing.
@export var shards: ShardPreset

@export_group("Housekeeping")
## Give up once it is this far below the avatar it is tracking, same as an
## enemy. A bomb that nobody touched simply leaves.
@export var despawn_below: float = 1500.0

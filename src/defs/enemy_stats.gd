@tool
class_name EnemyStats
extends Resource
## Everything about an enemy that is a number rather than a behaviour.
##
## Adding an enemy later means a scene, one of these, and a row in the spawn
## table — not editing five scripts and a match statement.

## Points awarded for a kill, before the combo multiplier.
@export var score: int = 50

## Colour of the score popup and the death particle burst.
@export var score_color: Color = Color.WHITE

## How the enemy answers a downward contact.
## false — any landing from above converts or kills it (golem, slime).
## true  — only a dash-down kills; a plain landing hurts the player instead
##         (pursuer, bat, spitter).
@export var requires_dash_to_stomp: bool = false

## Upward impulse given to the player by a successful stomp. Negative is up.
@export_range(-2000.0, 0.0, 10.0) var stomp_rebound: float = -600.0

## Sound id played on a successful stomp. Empty means the enemy's own death
## reaction handles the audio (the golem plays its petrification thud).
@export var stomp_sound: StringName = &""

## Despawn once the enemy falls this far below the player it is tracking.
@export var despawn_below: float = 1500.0

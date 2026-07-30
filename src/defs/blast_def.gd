@tool
class_name BlastDef
extends Resource
## One explosion, as numbers. What reaches how far, how hard it pushes there,
## and what it looks and sounds like. One .tres per kind of explosion; the pit
## has one, data/fx/blast.tres, and the bomb points at it.
##
## The wave carries a FORCE that falls off with distance. An object breaks when
## that force beats its own `Destructible.strength`, so toughness is a single
## number per object and one explosion sorts everything it covers without
## anybody working out a radius per kind of thing. That is the whole point: the
## map is going to grow more sorts of breakable furniture, and each new one only
## has to say how strong it is.

## Nothing outside this happens at all — no damage, no breakage, no kill.
@export var radius: float = 520.0
## Force at the epicentre. Same units as `Destructible.strength`; 100 is "as
## hard as this game pushes", which keeps strengths readable as percentages.
@export var peak_force: float = 100.0
## Force multiplier by normalised distance: sampled at (distance / radius), so
## 0.0 is the epicentre and 1.0 the outer edge. Leave it empty for a straight
## line from peak_force down to nothing, which is what every number in
## data/ was tuned against.
@export var falloff: Curve

@export_group("Knockback")
## Peak shove at the epicentre, along the line away from it — both axes, so a
## bomb under your feet throws you up and one beside you throws you sideways.
@export var push: float = 1800.0
## Deliberately larger than `radius`: a bomb going off near you should move you
## even when it did not reach far enough to hurt you. Uses the same falloff shape
## over its own range.
@export var push_radius: float = 1000.0

@export_group("Point blank")
## What happens to the one player who set a bomb off by walking into it. Nobody
## else's screen or health knows the difference — they just watch that avatar
## leave at speed.
@export var point_blank_damage: int = 2
@export var point_blank_push: float = 4400.0
@export_range(0.0, 1.0, 0.05) var point_blank_shake: float = 1.0
@export_range(0.0, 1.0, 0.01) var point_blank_flash: float = 1.0
## Flat, not positional: this one is not an event you overheard.
@export var point_blank_sound: StringName = &"blast_close"

@export_group("Reward")
## Points for setting one off, credited to whoever caused it. A bomb that goes
## off by itself credits nobody and scores nothing.
@export var score: int = 50
@export var score_color: Color = Color(1.0, 0.6, 0.25)

@export_group("Presentation")
## Sound bank id. Positional, so every machine hears it from where it happened.
@export var sound: StringName = &"blast"
## Trauma at the epicentre, faded to nothing over `feedback_range`.
@export var shake: float = 0.95
## Peak screen-flash alpha at the epicentre, same falloff. The pit is dark:
## much above a quarter reads as a bug rather than a bomb.
@export_range(0.0, 1.0, 0.01) var flash: float = 0.28
## How far away shake and flash fade to nothing. Sound has its own range, on
## the SoundDef, because ears and eyes do not agree about distance.
@export var feedback_range: float = 2600.0
## Particle layers fired at the epicentre, in order. Empty is legal and silent.
@export var bursts: Array[BurstPreset] = []


## The force this wave still carries `distance` px from where it went off.
func force_at(distance: float) -> float:
	if radius <= 0.0 or distance >= radius:
		return 0.0
	var t := clampf(distance / radius, 0.0, 1.0)
	var k := falloff.sample(t) if falloff != null else 1.0 - t
	return peak_force * maxf(k, 0.0)


## How hard this wave shoves something `distance` px from where it went off.
## Same falloff shape as the force, over its own, longer range.
func push_at(distance: float) -> float:
	if push_radius <= 0.0 or distance >= push_radius:
		return 0.0
	var t := clampf(distance / push_radius, 0.0, 1.0)
	var k := falloff.sample(t) if falloff != null else 1.0 - t
	return push * maxf(k, 0.0)


## The furthest an object of this strength can be and still break. Nothing in
## the game needs it — it is here so the tuning numbers can be read back in the
## units they are actually judged in, by a test or by anyone in the inspector.
func reach_for(strength: float) -> float:
	var step := radius / 64.0
	var d := 0.0
	while d < radius:
		if force_at(d) <= strength:
			return d
		d += step
	return radius

@tool
class_name SoundDef
extends Resource
## One playable sound: the stream plus how it should be mixed.
##
## Everything that used to be passed at the call site — volume and the
## `randf_range(0.95, 1.05)` pitch jitter sprinkled through the gameplay code —
## lives here instead, so tuning a sound never means editing a script.

## The audio file. Any AudioStream works, including an AudioStreamRandomizer if
## you want several alternating takes of the same sound.
@export var stream: AudioStream

## Base mix level for this sound.
@export_range(-60.0, 12.0, 0.5) var volume_db: float = 0.0

## Pitch is picked uniformly in [pitch_min, pitch_max] on every play.
## Leave both at 1.0 for a sound that must always be identical.
@export_range(0.25, 4.0, 0.01) var pitch_min: float = 1.0
@export_range(0.25, 4.0, 0.01) var pitch_max: float = 1.0

## Which audio bus this plays on. See default_bus_layout.tres.
@export var bus: StringName = &"SFX"

@export_group("In the world")
## Does this sound happen at a PLACE, or in your head?
##
## A positional sound is played through an AudioStreamPlayer2D where it
## happened, so it is quieter the further away you are — and in 2D the listener
## is the active Camera2D, which in a session is each machine's own camera on its
## own avatar. Nothing about volume crosses the wire: the event replicates, and
## every machine works out for itself how loud that was from where it stands.
##
## Flat (the default) is right for two kinds of sound: the UI, and everything
## that belongs to YOUR avatar. Your own jump is not an event in the pit that you
## happen to be able to hear — it is you jumping, and it plays only on your
## machine anyway.
@export var positional: bool = false

## How far away a positional sound fades to silence.
## 0 = the range authored on WorldSound.tscn. Ignored when `positional` is off.
@export_range(0.0, 8000.0, 50.0) var max_distance: float = 0.0


## Roll a concrete pitch for one playback.
func roll_pitch(rng: RandomNumberGenerator = null) -> float:
	if is_equal_approx(pitch_min, pitch_max):
		return pitch_min
	if rng != null:
		return rng.randf_range(pitch_min, pitch_max)
	return randf_range(pitch_min, pitch_max)

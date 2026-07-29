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


## Roll a concrete pitch for one playback.
func roll_pitch(rng: RandomNumberGenerator = null) -> float:
	if is_equal_approx(pitch_min, pitch_max):
		return pitch_min
	if rng != null:
		return rng.randf_range(pitch_min, pitch_max)
	return randf_range(pitch_min, pitch_max)

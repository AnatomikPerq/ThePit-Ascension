@tool
class_name SoundBank
extends Resource
## The game's whole sound vocabulary, keyed by role.
##
## Gameplay code says `Audio.play(&"jump")` and never names a file. Swapping the
## jump sound is an inspector edit on this resource; adding a sound is a new
## entry, not a new code path.

## Role name -> SoundDef. Keys are the ids gameplay code passes to Audio.play().
@export var sounds: Dictionary[StringName, SoundDef] = {}

## Looping background track. Played on the Music bus and never restarted between
## scenes, so the ambience survives a run restart.
@export var music: AudioStream


func get_sound(id: StringName) -> SoundDef:
	return sounds.get(id)


func has_sound(id: StringName) -> bool:
	return sounds.has(id) and sounds[id] != null and sounds[id].stream != null


## Every id in the bank in alphabetical order. Used by the smoke test and by
## anything that wants to list the vocabulary. StringName sorts by internal
## pointer, not alphabetically, so sort as String and convert back.
func ids() -> Array[StringName]:
	var names: Array[String] = []
	for k: StringName in sounds.keys():
		names.append(String(k))
	names.sort()
	var out: Array[StringName] = []
	for n: String in names:
		out.append(StringName(n))
	return out

@tool
class_name CharacterRoster
extends Resource
## The list of playable climbers, in the order the select screen shows them.
##
## A resource rather than a folder scan: the order is a design decision, and a
## scan would make it depend on how a filesystem happens to sort. Game loads the
## one instance at data/characters/roster.tres and everything else reads it from
## there.

## The id a peer reports when it is watching rather than climbing. Not a
## character — nothing looks it up here; it is the absence of one.
const SPECTATOR: StringName = &""

@export var characters: Array[CharacterDef] = []


func by_id(id: StringName) -> CharacterDef:
	for c in characters:
		if c != null and c.id == id:
			return c
	return null


## The pick a machine falls back to: an unknown id, an empty save, a peer that
## never announced one. Never null as long as the roster has anybody in it.
func fallback() -> CharacterDef:
	return characters[0] if not characters.is_empty() else null


## `id` if it names a character, otherwise the fallback's id.
func resolve(id: StringName) -> CharacterDef:
	var found := by_id(id)
	return found if found != null else fallback()

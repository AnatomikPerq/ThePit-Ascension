extends GdUnitTestSuite
## The sound bank is the contract between gameplay code and audio files.
## Gameplay says Audio.play(&"jump"); if that id is missing the sound silently
## does not play, which no other check would notice.

const BANK_PATH := "res://data/audio/sound_bank.tres"

## Every id gameplay code actually calls. Grepped from the call sites; if a new
## Audio.play(&"...") appears it belongs here too.
const REQUIRED_IDS: Array[StringName] = [
	&"jump", &"double_jump", &"land", &"stomp", &"kill", &"hurt", &"crush",
	&"strike", &"shockwave", &"bounce", &"thud", &"upgrade", &"heal",
	&"die", &"win", &"ui_click", &"ui_confirm", &"zone",
	&"blast", &"blast_close", &"rubble", &"bomb_hit",
]

## Sounds that happened at a place in the pit. Every machine plays these from
## one replicated event, so they must fade with distance — otherwise a bomb
## eight levels up is as loud as one under your feet.
const POSITIONAL_IDS: Array[StringName] = [
	&"kill", &"thud", &"die", &"blast", &"rubble", &"bomb_hit",
]

## Sounds that belong to YOUR avatar, or to the UI. These are flat on purpose,
## and — the part that matters in a session — they are played only on the machine
## that owns the avatar making them. A lobby must not hear everyone else's
## jumping, landing, punching and stomping.
## `blast_close` is here rather than with the world sounds on purpose: a bomb
## that went off against your own body did not happen somewhere in the pit that
## you overheard, and only that one player's machine plays it at all.
const PRIVATE_IDS: Array[StringName] = [
	&"jump", &"double_jump", &"land", &"stomp", &"hurt", &"crush",
	&"strike", &"shockwave", &"bounce", &"heal", &"upgrade", &"win", &"zone",
	&"ui_click", &"ui_confirm", &"blast_close",
]

var bank: SoundBank


func before_test() -> void:
	bank = load(BANK_PATH)


func test_bank_loads() -> void:
	assert_object(bank).is_not_null()


func test_every_gameplay_id_is_registered() -> void:
	for id in REQUIRED_IDS:
		assert_bool(bank.has_sound(id)) \
			.override_failure_message("sound id '%s' is missing from the bank" % id) \
			.is_true()


func test_every_entry_has_a_stream_and_a_real_bus() -> void:
	for id in bank.ids():
		var def: SoundDef = bank.get_sound(id)
		assert_object(def).override_failure_message("'%s' has a null def" % id).is_not_null()
		assert_object(def.stream) \
			.override_failure_message("'%s' has no stream" % id).is_not_null()
		assert_int(AudioServer.get_bus_index(String(def.bus))) \
			.override_failure_message("'%s' targets missing bus '%s'" % [id, def.bus]) \
			.is_greater_equal(0)


func test_pitch_ranges_are_ordered() -> void:
	for id in bank.ids():
		var def: SoundDef = bank.get_sound(id)
		assert_float(def.pitch_min) \
			.override_failure_message("'%s' has pitch_min > pitch_max" % id) \
			.is_less_equal(def.pitch_max)


func test_roll_pitch_stays_in_range() -> void:
	for id in bank.ids():
		var def: SoundDef = bank.get_sound(id)
		for i in 20:
			var pitch := def.roll_pitch()
			assert_float(pitch).is_between(def.pitch_min, def.pitch_max)


func test_music_track_is_present() -> void:
	assert_object(bank.music).is_not_null()


func test_world_sounds_are_positional_and_have_a_range() -> void:
	for id in POSITIONAL_IDS:
		var def: SoundDef = bank.get_sound(id)
		assert_bool(def.positional) \
			.override_failure_message("'%s' happens in the world and must fade with distance" % id) \
			.is_true()
		assert_float(def.max_distance) \
			.override_failure_message("positional '%s' has no range, so it never fades" % id) \
			.is_greater(0.0)


## The other half of the same rule. A sound marked positional is broadcast by
## whatever fires it; one of these turning positional is the tell that somebody
## moved an avatar's own noise onto every machine in the lobby.
func test_avatar_and_ui_sounds_stay_flat() -> void:
	for id in PRIVATE_IDS:
		var def: SoundDef = bank.get_sound(id)
		assert_bool(def.positional) \
			.override_failure_message("'%s' belongs to one avatar or to the UI, not to the pit" % id) \
			.is_false()


## Between them the two lists must account for the whole vocabulary: a new sound
## has to be classified, not quietly default to flat.
func test_every_sound_is_classified() -> void:
	var unclassified: Array[String] = []
	for id in bank.ids():
		if not POSITIONAL_IDS.has(id) and not PRIVATE_IDS.has(id):
			unclassified.append(String(id))
	assert_array(unclassified) \
		.override_failure_message("sounds in neither list (flat or positional?): %s" % str(unclassified)) \
		.is_empty()


func test_buses_exist() -> void:
	for bus in ["Master", "SFX", "Music", "UI"]:
		assert_int(AudioServer.get_bus_index(bus)) \
			.override_failure_message("audio bus '%s' is missing" % bus) \
			.is_greater_equal(0)


## The old sfx.gd built sounds from oscillators at startup. Nothing should ever
## construct an AudioStreamWAV in code again.
func test_no_runtime_audio_synthesis() -> void:
	var offenders := _grep("res://src", "AudioStreamWAV")
	offenders.append_array(_grep("res://scripts", "AudioStreamWAV"))
	assert_array(offenders) \
		.override_failure_message("audio is synthesised at runtime in: %s" % str(offenders)) \
		.is_empty()


func _grep(dir_path: String, needle: String) -> Array[String]:
	var hits: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return hits
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				hits.append_array(_grep(full, needle))
		elif entry.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(full)
			if text.contains(needle):
				hits.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return hits

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

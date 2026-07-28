extends SceneTree
## Headless regression check. Exits non-zero if anything is broken, so it can be
## wired into CI or run before a commit:
##
##   godot --headless --path . -s tools/smoke_test.gd
##
## It deliberately checks the things that silently rot during a refactor:
## every sound id resolves to a real stream on a real bus, every scene still
## instantiates, and every autoload is present.

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_check_autoloads()
	_check_audio_buses()
	_check_sound_bank()
	_check_scenes()

	print("")
	if _failures.is_empty():
		print("smoke test PASSED — %d checks" % _checks)
		quit(0)
		return
	print("smoke test FAILED — %d of %d checks" % [_failures.size(), _checks])
	for f in _failures:
		print("  x ", f)
	quit(1)


func _ok(what: String) -> void:
	_checks += 1
	print("  . ", what)


func _fail(what: String) -> void:
	_checks += 1
	_failures.append(what)


func _check_autoloads() -> void:
	print("autoloads")
	# Running with -s replaces the main loop, so autoloads are never instantiated
	# here. Check that they are configured and that their scripts still parse.
	for autoload_name: String in ["Fx", "Audio", "Game", "Router"]:
		var setting := "autoload/" + autoload_name
		if not ProjectSettings.has_setting(setting):
			_fail("autoload not configured: " + autoload_name)
			continue
		var path := String(ProjectSettings.get_setting(setting)).trim_prefix("*")
		if load(path) == null:
			_fail("autoload script failed to load: %s (%s)" % [autoload_name, path])
		else:
			_ok("%s -> %s" % [autoload_name, path])


func _check_audio_buses() -> void:
	print("audio buses")
	for bus: String in ["Master", "SFX", "Music", "UI"]:
		if AudioServer.get_bus_index(bus) >= 0:
			_ok("bus " + bus)
		else:
			_fail("audio bus missing: " + bus)


func _check_sound_bank() -> void:
	print("sound bank")
	var bank: SoundBank = load("res://data/audio/sound_bank.tres")
	if bank == null:
		_fail("sound bank failed to load")
		return
	if bank.music == null:
		_fail("sound bank has no music stream")
	else:
		_ok("music stream")
	if bank.sounds.is_empty():
		_fail("sound bank is empty")
		return
	for id: StringName in bank.ids():
		var def: SoundDef = bank.get_sound(id)
		if def == null:
			_fail("sound '%s' has a null def" % id)
		elif def.stream == null:
			_fail("sound '%s' has no stream" % id)
		elif AudioServer.get_bus_index(String(def.bus)) < 0:
			_fail("sound '%s' targets missing bus '%s'" % [id, def.bus])
		elif def.pitch_min > def.pitch_max:
			_fail("sound '%s' has pitch_min > pitch_max" % id)
		else:
			_ok("sound %s" % id)


func _check_scenes() -> void:
	print("scenes")
	for path in _all_scenes("res://scenes"):
		var packed: PackedScene = load(path)
		if packed == null:
			_fail("scene failed to load: " + path)
			continue
		var inst := packed.instantiate()
		if inst == null:
			_fail("scene failed to instantiate: " + path)
			continue
		inst.free()
		_ok(path.get_file())


func _all_scenes(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if d.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_all_scenes(full))
		elif entry.get_extension() == "tscn":
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

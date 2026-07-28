extends SceneTree
## One-shot: builds data/audio/sound_bank.tres from the files in assets/audio.
##
## Volume and pitch values below are transcribed from the arguments the old
## scripts/sfx.gd call sites passed, so the mix is unchanged.
##
##   godot --headless --path . -s tools/build_sound_bank.gd
##
## After the resource exists it is the source of truth and is edited in the
## inspector. Re-running this OVERWRITES those edits — it is kept only so the
## initial values are traceable, not as part of the build.

const OUT_PATH := "res://data/audio/sound_bank.tres"
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC := "res://assets/audio/music/pit_ambience.ogg"

# id, file, volume_db, pitch_min, pitch_max, bus
const ENTRIES: Array = [
	["jump", "jump.ogg", -12.0, 0.95, 1.05, "SFX"],
	["double_jump", "double_jump.ogg", -12.0, 0.95, 1.05, "SFX"],
	["land", "land.ogg", -10.0, 0.95, 1.05, "SFX"],
	["stomp", "stomp.ogg", -6.0, 1.0, 1.0, "SFX"],
	# Pitch rises with the combo multiplier, so the caller overrides it.
	["kill", "kill.ogg", -6.0, 1.0, 1.0, "SFX"],
	["hurt", "hurt.ogg", -6.0, 1.0, 1.0, "SFX"],
	["crush", "crush.ogg", -4.0, 1.0, 1.0, "SFX"],
	["strike", "strike.ogg", -10.0, 0.9, 1.1, "SFX"],
	["shockwave", "shockwave.ogg", -6.0, 1.0, 1.0, "SFX"],
	["bounce", "bounce.ogg", -8.0, 0.9, 1.1, "SFX"],
	["thud", "thud.ogg", -8.0, 0.9, 1.1, "SFX"],
	["upgrade", "upgrade.ogg", -6.0, 1.0, 1.0, "SFX"],
	["heal", "heal.ogg", -6.0, 1.0, 1.0, "SFX"],
	["die", "die.ogg", -4.0, 1.0, 1.0, "SFX"],
	["win", "win.ogg", -4.0, 1.0, 1.0, "SFX"],
	# Same file, three roles: menu click, menu confirm, and the zone-reached
	# chirp (which the old code played as click at pitch 1.2).
	["ui_click", "click.ogg", -8.0, 1.0, 1.0, "UI"],
	["ui_confirm", "click.ogg", -6.0, 1.0, 1.0, "UI"],
	["zone", "click.ogg", -8.0, 1.2, 1.2, "SFX"],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/audio")

	var bank := SoundBank.new()
	var sounds: Dictionary[StringName, SoundDef] = {}

	for e: Array in ENTRIES:
		var path: String = SFX_DIR + String(e[1])
		var stream: AudioStream = load(path)
		if stream == null:
			push_error("missing audio file: " + path)
			quit(1)
			return
		var def := SoundDef.new()
		def.resource_name = String(e[0])
		def.stream = stream
		def.volume_db = float(e[2])
		def.pitch_min = float(e[3])
		def.pitch_max = float(e[4])
		def.bus = StringName(e[5])
		sounds[StringName(e[0])] = def

	bank.sounds = sounds
	bank.music = load(MUSIC)

	var err := ResourceSaver.save(bank, OUT_PATH)
	if err != OK:
		push_error("failed to save %s (error %d)" % [OUT_PATH, err])
		quit(1)
		return
	print("wrote %s with %d sounds" % [OUT_PATH, sounds.size()])
	quit(0)

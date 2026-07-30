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

# id, file, volume_db, pitch_min, pitch_max, bus, positional, max_distance
#
# `positional` splits the vocabulary in two, and the split is about WHOSE sound
# it is rather than how it was made:
#
#   flat — the UI, and everything that belongs to your own avatar. Your jump is
#          not an event in the pit you happen to overhear; it is you jumping,
#          and it plays on your machine only.
#   positional — things that happened at a place: an enemy dying, a golem
#          setting, a bomb going off, a platform coming apart. Every machine
#          plays these from the same replicated event and hears them at the
#          volume its own camera earns.
const ENTRIES: Array = [
	["jump", "jump.ogg", -12.0, 0.95, 1.05, "SFX", false, 0.0],
	["double_jump", "double_jump.ogg", -12.0, 0.95, 1.05, "SFX", false, 0.0],
	["land", "land.ogg", -10.0, 0.95, 1.05, "SFX", false, 0.0],
	["stomp", "stomp.ogg", -6.0, 1.0, 1.0, "SFX", false, 0.0],
	# Pitch rises with the combo multiplier, so the caller overrides it.
	["kill", "kill.ogg", -6.0, 1.0, 1.0, "SFX", true, 2600.0],
	["hurt", "hurt.ogg", -6.0, 1.0, 1.0, "SFX", false, 0.0],
	["crush", "crush.ogg", -4.0, 1.0, 1.0, "SFX", false, 0.0],
	["strike", "strike.ogg", -10.0, 0.9, 1.1, "SFX", false, 0.0],
	["shockwave", "shockwave.ogg", -6.0, 1.0, 1.0, "SFX", false, 0.0],
	["bounce", "bounce.ogg", -8.0, 0.9, 1.1, "SFX", false, 0.0],
	["thud", "thud.ogg", -8.0, 0.9, 1.1, "SFX", true, 2200.0],
	["upgrade", "upgrade.ogg", -6.0, 1.0, 1.0, "SFX", false, 0.0],
	["heal", "heal.ogg", -6.0, 1.0, 1.0, "SFX", false, 0.0],
	# A death is announced on every machine, so it gets a range instead of
	# privacy: your own is at zero distance and full volume, and somebody
	# dying three levels up is not your business.
	["die", "die.ogg", -4.0, 1.0, 1.0, "SFX", true, 3000.0],
	["win", "win.ogg", -4.0, 1.0, 1.0, "SFX", false, 0.0],
	# The bomb. `blast` carries furthest of anything in the game on purpose —
	# hearing one go off out of sight is the warning that the climb above you
	# just changed.
	["blast", "blast.ogg", -3.0, 0.95, 1.05, "SFX", true, 4200.0],
	# The one you set off with your own body. Flat and loud, because it did not
	# happen somewhere in the pit — it happened to you.
	["blast_close", "blast_close.ogg", -1.0, 1.0, 1.0, "SFX", false, 0.0],
	["rubble", "rubble.ogg", -7.0, 0.9, 1.1, "SFX", true, 2400.0],
	# Fist on a metal shell: stomp.ogg dropped a couple of semitones.
	["bomb_hit", "stomp.ogg", -6.0, 0.8, 0.9, "SFX", true, 2000.0],
	# Same file, three roles: menu click, menu confirm, and the zone-reached
	# chirp (which the old code played as click at pitch 1.2).
	["ui_click", "click.ogg", -8.0, 1.0, 1.0, "UI", false, 0.0],
	["ui_confirm", "click.ogg", -6.0, 1.0, 1.0, "UI", false, 0.0],
	["zone", "click.ogg", -8.0, 1.2, 1.2, "SFX", false, 0.0],
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
		def.positional = bool(e[6])
		def.max_distance = float(e[7])
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

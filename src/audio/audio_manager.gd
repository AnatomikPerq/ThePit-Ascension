extends Node
## Audio — autoload that plays sounds by role id and owns the music track.
##
## Replaces the old scripts/sfx.gd, which synthesised every sound from
## oscillators at startup and hand-rolled a 12-voice player pool with manual
## voice stealing. Both jobs are engine features:
##   * AudioStreamPolyphonic plays many overlapping sounds through one player,
##     each with its own volume and pitch — no pool, no stealing.
##   * Volume and pitch jitter are data on SoundDef, not arguments at call sites.
##
## Gameplay code only ever says Audio.play(&"jump").

## Emitted when music is toggled, so UI can reflect the state.
signal music_toggled(enabled: bool)

const BANK_PATH := "res://data/audio/sound_bank.tres"

## How many sounds may overlap on one bus before the oldest is dropped.
const POLYPHONY: int = 24

## Loaded at _ready rather than preloaded as a const: a script constant would
## pin the bank and every stream in it past engine shutdown, which Godot reports
## as "resources still in use at exit".
var bank: SoundBank

var music_enabled: bool = true:
	set(value):
		music_enabled = value
		if _music_player:
			_music_player.stream_paused = not value
		music_toggled.emit(value)

## Turned off wholesale by a dedicated server. A headless process has a dummy
## audio driver, so nothing was ever heard — but every gameplay event still did
## the bank lookup, rolled a pitch and pushed a stream into a polyphonic
## playback, per room, per frame. A server says once that it has no ears.
var enabled: bool = true

## Where positional sounds live, registered by the active scene the same way
## Fx.effects_root is (World does both in _ready). Without one, play_at falls
## back to the flat mix — a world sound in a menu is then merely
## un-attenuated, never silent.
var world_root: Node2D = null

var _music_player: AudioStreamPlayer
## bus name -> the polyphonic playback handle we push streams into.
var _playbacks: Dictionary[StringName, AudioStreamPlaybackPolyphonic] = {}
var _world_sound_scene: PackedScene


func _ready() -> void:
	# Sound must keep working while the tree is paused (menus, upgrade screen).
	process_mode = Node.PROCESS_MODE_ALWAYS
	bank = load(BANK_PATH)
	if bank == null:
		push_error("Audio: could not load " + BANK_PATH)
		return
	_world_sound_scene = load("res://scenes/fx/WorldSound.tscn")
	_build_players()
	_start_music()


func _build_players() -> void:
	# One polyphonic player per bus the bank actually references.
	var buses: Array[StringName] = [&"SFX"]
	for id: StringName in bank.sounds:
		var def: SoundDef = bank.sounds[id]
		if def and not buses.has(def.bus):
			buses.append(def.bus)

	for bus: StringName in buses:
		if AudioServer.get_bus_index(String(bus)) < 0:
			push_warning("Audio: bus '%s' is not in the bus layout, falling back to SFX" % bus)
			continue
		var player := AudioStreamPlayer.new()
		player.name = "%sPlayer" % bus
		player.bus = String(bus)
		var poly := AudioStreamPolyphonic.new()
		poly.polyphony = POLYPHONY
		player.stream = poly
		add_child(player)
		player.play()
		_playbacks[bus] = player.get_stream_playback() as AudioStreamPlaybackPolyphonic

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Music"
	add_child(_music_player)


func _start_music() -> void:
	if bank.music == null:
		return
	_music_player.stream = bank.music
	_music_player.play()
	_music_player.stream_paused = not music_enabled


## Play a sound by its role id. Volume and pitch come from the bank.
## `pitch_override` is for the rare case where pitch carries meaning rather than
## flavour — the kill sound rises with the combo multiplier. Pass 0.0 to use the
## bank's own pitch range.
func play(id: StringName, pitch_override: float = 0.0) -> void:
	if not enabled or bank == null:
		return
	var def: SoundDef = bank.get_sound(id)
	if def == null or def.stream == null:
		push_warning("Audio: no sound registered for id '%s'" % id)
		return
	var playback: AudioStreamPlaybackPolyphonic = _playbacks.get(def.bus)
	if playback == null:
		playback = _playbacks.get(&"SFX")
	if playback == null:
		return
	var pitch: float = pitch_override if pitch_override > 0.0 else def.roll_pitch()
	playback.play_stream(def.stream, 0.0, def.volume_db, pitch)


## Play a sound that happened at a place in the world. Whether distance actually
## matters is the SoundDef's business, not the call site's: an id marked flat
## comes straight back out of play() above, so which sounds attenuate is an
## inspector decision on data/audio/sound_bank.tres.
##
## Multiplayer needs nothing else. The listener is the active Camera2D, which is
## each machine's own camera on its own avatar, so the same replicated event is
## loud for the player standing in it and inaudible for the one three levels up.
func play_at(id: StringName, pos: Vector2, pitch_override: float = 0.0) -> void:
	if not enabled or bank == null:
		return
	var def: SoundDef = bank.get_sound(id)
	if def == null or def.stream == null:
		push_warning("Audio: no sound registered for id '%s'" % id)
		return
	if not def.positional or not is_instance_valid(world_root) or _world_sound_scene == null:
		play(id, pitch_override)
		return
	var voice: WorldSound = _world_sound_scene.instantiate()
	voice.stream = def.stream
	voice.volume_db = def.volume_db
	voice.pitch_scale = pitch_override if pitch_override > 0.0 else def.roll_pitch()
	voice.bus = String(def.bus)
	if def.max_distance > 0.0:
		voice.max_distance = def.max_distance
	world_root.add_child(voice)
	voice.global_position = pos
	voice.play()


func toggle_music() -> bool:
	music_enabled = not music_enabled
	return music_enabled


func _exit_tree() -> void:
	# Release everything we hold so the engine does not report the bank and its
	# streams as "still in use at exit". The players are freed rather than just
	# stopped: a queued free would run after the audio server has already been
	# torn down.
	_playbacks.clear()
	bank = null
	_music_player = null
	_world_sound_scene = null
	world_root = null
	for child in get_children():
		var player := child as AudioStreamPlayer
		if player == null:
			continue
		player.stop()
		player.stream = null
		remove_child(player)
		player.free()

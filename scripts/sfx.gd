extends Node
## Sfx — autoload that synthesizes all sound effects and the ambient music
## loop procedurally at startup (8-bit style, no audio assets needed).
## Usage: Sfx.play("jump"), Sfx.toggle_music().

const RATE: int = 22050
const POOL_SIZE: int = 12

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var music_enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_build_sounds()
	_music = AudioStreamPlayer.new()
	_music.volume_db = -18.0
	add_child(_music)
	_music.stream = _build_music()
	_music.play()


func play(sound: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStreamWAV = _streams.get(sound)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	# All voices busy: steal the first one.
	_pool[0].stream = s
	_pool[0].volume_db = vol_db
	_pool[0].pitch_scale = pitch
	_pool[0].play()


func _exit_tree() -> void:
	# Release the playing music stream so nothing leaks at shutdown.
	if _music:
		_music.stop()
		_music.stream = null


func toggle_music() -> bool:
	music_enabled = not music_enabled
	_music.stream_paused = not music_enabled
	return music_enabled


# ── Synthesis helpers ───────────────────────────────────────────────────────
func _env(t: float, dur: float, attack: float, curve: float) -> float:
	if t < attack:
		return t / attack
	var k := 1.0 - (t - attack) / maxf(dur - attack, 0.0001)
	return pow(clampf(k, 0.0, 1.0), curve)


func _osc(phase: float, kind: String) -> float:
	match kind:
		"sine":
			return sin(phase * TAU)
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"saw":
			return 2.0 * fmod(phase, 1.0) - 1.0
		"tri":
			return 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
		"noise":
			return randf_range(-1.0, 1.0)
	return 0.0


## A single tone sweeping from f0 to f1 Hz over dur seconds.
func _tone(dur: float, f0: float, f1: float, kind: String = "sine",
		vol: float = 0.7, attack: float = 0.008, curve: float = 1.6) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(f0, f1, t / dur)
		phase += f / RATE
		out[i] = _osc(phase, kind) * vol * _env(t, dur, attack, curve)
	return out


## Overlay b onto a (result length = max of both).
func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i < b.size():
			v += b[i]
		out[i] = v
	return out


## Concatenate tones for arpeggios / jingles.
func _notes(freqs: Array, note_dur: float, kind: String = "square", vol: float = 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		out.append_array(_tone(note_dur, f, f, kind, vol, 0.006, 1.8))
	return out


func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


# ── Sound bank ──────────────────────────────────────────────────────────────
func _build_sounds() -> void:
	_streams["jump"] = _make_wav(_tone(0.13, 190.0, 400.0, "square", 0.45))
	_streams["djump"] = _make_wav(_tone(0.13, 280.0, 590.0, "square", 0.45))
	_streams["land"] = _make_wav(_mix(
		_tone(0.10, 100.0, 60.0, "sine", 0.55),
		_tone(0.05, 900.0, 900.0, "noise", 0.18)))
	_streams["stomp"] = _make_wav(_mix(
		_tone(0.18, 95.0, 55.0, "sine", 0.7),
		_tone(0.07, 800.0, 800.0, "noise", 0.35)))
	_streams["kill"] = _make_wav(_tone(0.16, 640.0, 1050.0, "square", 0.4, 0.004, 2.2))
	_streams["hurt"] = _make_wav(_tone(0.24, 330.0, 105.0, "saw", 0.5))
	_streams["crush"] = _make_wav(_mix(
		_tone(0.35, 140.0, 45.0, "saw", 0.55),
		_tone(0.16, 700.0, 700.0, "noise", 0.3)))
	_streams["strike"] = _make_wav(_tone(0.13, 1400.0, 300.0, "noise", 0.45, 0.004, 2.6))
	_streams["shock"] = _make_wav(_mix(
		_tone(0.5, 520.0, 55.0, "sine", 0.7),
		_tone(0.30, 600.0, 600.0, "noise", 0.22)))
	_streams["boing"] = _make_wav(_tone(0.30, 140.0, 520.0, "tri", 0.55, 0.01, 1.2))
	_streams["thud"] = _make_wav(_mix(
		_tone(0.16, 75.0, 48.0, "sine", 0.65),
		_tone(0.06, 500.0, 500.0, "noise", 0.25)))
	_streams["upgrade"] = _make_wav(_notes([440.0, 554.4, 659.3, 880.0], 0.1, "square", 0.4))
	_streams["heal"] = _make_wav(_notes([523.3, 659.3, 784.0], 0.09, "tri", 0.5))
	_streams["die"] = _make_wav(_notes([392.0, 311.1, 261.6, 196.0, 130.8], 0.15, "saw", 0.4))
	_streams["win"] = _make_wav(_notes([523.3, 659.3, 784.0, 1046.5, 1318.5, 1568.0], 0.13, "square", 0.4))
	_streams["click"] = _make_wav(_tone(0.06, 800.0, 800.0, "square", 0.3, 0.002, 2.0))


# ── Music ───────────────────────────────────────────────────────────────────
## 8-second dark ambient loop: low drone in A + slow minor arpeggio + wind.
## Frequencies chosen to complete whole cycles in 8s so the loop is seamless.
func _build_music() -> AudioStreamWAV:
	var dur := 8.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)

	# Am / F minor-ish arpeggio, 16 notes x 0.5s.
	var pattern: Array[float] = [
		220.0, 261.63, 329.63, 440.0, 329.63, 261.63, 220.0, 196.0,
		174.61, 220.0, 261.63, 349.23, 261.63, 220.0, 174.61, 164.81,
	]
	var note_dur := 0.5

	for i in n:
		var t := float(i) / RATE
		# Drone: A1 + E2 (82.5 completes 660 cycles in 8s -> seamless loop).
		var lfo := 0.75 + 0.25 * sin(t / dur * TAU)
		var v := 0.16 * sin(TAU * 55.0 * t) * lfo
		v += 0.09 * sin(TAU * 82.5 * t) * lfo
		# Arpeggio.
		var idx := int(t / note_dur) % pattern.size()
		var nt := fmod(t, note_dur)
		var f: float = pattern[idx]
		var env := _env(nt, note_dur, 0.03, 2.0)
		v += 0.11 * (4.0 * absf(fmod(f * nt, 1.0) - 0.5) - 1.0) * env
		# Wind.
		v += 0.012 * randf_range(-1.0, 1.0) * (0.5 + 0.5 * sin(t / dur * TAU))
		out[i] = v

	return _make_wav(out, true)

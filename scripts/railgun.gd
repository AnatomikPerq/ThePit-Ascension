extends Node2D
## Uzi's railgun: the thing on her back, the thing in her hands, and the six
## charges the run's own score keeps topping up.
##
## It is a scene mounted on the avatar — `CharacterDef.weapon_scene` — not a
## branch in player.gd. The avatar knows it has "a weapon", asks it four
## questions (does it want the attack button, which pose should I be in, does it
## decide which way I face, is it aimed) and never asks what kind it is. A
## second weapon later is another scene answering the same four.
##
## ## Two states, and only two
##
## STOWED is the drawing slung across her back, tilted, drawn behind her. AIMED
## is the same drawing pinned through its grip, turning to follow the cursor —
## right mouse flips between them instantly, as often as you like, because there
## is nothing to interrupt: no animation gates the toggle and no cooldown is
## spent by it. The `enabled` art, the one with the energy visibly loose in it,
## belongs to neither: it is shown for a fifth of a second when the shot goes off
## and then it is gone.
##
## ## What is local and what is not
##
## The cursor, the crosshair texture and reading the mouse happen only on the
## machine steering this avatar. What crosses the wire is `aiming` and
## `aim_angle` on the Player — two values, on-change — so a rival's gun points
## where they are pointing it rather than sitting stiffly along their facing.
##
## The charge count crosses nothing at all, exactly like `has_ranged` and
## `max_jumps`: every machine watches its own ledger's `score_changed` and works
## out its own avatar's charges from it. There is nothing to disagree about
## because both machines are adding up the same replicated number.

## Which way the drawing has to be flipped to stay the right way up. Past a
## quarter turn either side of straight up, the gun is pointing leftwards.
const UPRIGHT_LIMIT: float = PI * 0.5

## How far past that quarter turn the aim has to go before the drawing actually
## flips, and how far back before it flips again.
##
## Without this the gun shakes itself apart when aimed STRAIGHT up or STRAIGHT
## down: those are exactly ±90°, the boundary, and a mouse resting one pixel
## either side of it re-decides the mirror every single frame — which also
## re-decides which way she is facing, which moves the grip, which moves the
## barrel. Ten degrees of deadband, and the state is latched rather than
## recomputed, so inside the band it simply stays as it was.
const FLIP_MARGIN: float = 0.18

const SHOT_SCENE: PackedScene = preload("res://scenes/RailShot.tscn")

@onready var pivot: Node2D = $Pivot
@onready var sprite: Sprite2D = $Pivot/Sprite
@onready var cooldown: Timer = $CooldownTimer
## Debug only: how fast the beam re-fires while the trigger is held in flight.
@onready var stream: Timer = $StreamTimer
@onready var anim: AnimationPlayer = $AnimationPlayer

## The avatar this is mounted on. Set by Player before it enters the tree.
var player: CharacterBody2D
var stats: RailgunStats

## Shots in the gun. Local, like every other unlock.
var charges: int = 0

## Score earned since the last charge landed. Never spent from the run — the
## owner was explicit about that: the railgun feeds on what you earn, it does not
## take it off the board.
var _progress: int = 0
## The last score this weapon has already counted, so a signal carrying an
## absolute number can be read as a delta.
var _score_seen: int = 0
var _armed: bool = false
var _cursor_shown: bool = false
## Latched: is the gun pointing leftwards enough to be drawn mirrored? See
## FLIP_MARGIN. Both the drawing and which way she faces read this one value, so
## they cannot disagree for a frame and jump the grip.
var _mirrored: bool = false


func _ready() -> void:
	set_process(false)
	visible = false
	if stats == null:
		return
	cooldown.wait_time = maxf(_cooldown_seconds(), 0.05)
	sprite.scale = Vector2.ONE * stats.sprite_scale


## Called by Player once the avatar is in the tree. Separate from `_ready` only
## because the ledger it listens to lives above the avatar.
func setup(owner_player: CharacterBody2D, weapon_stats: RailgunStats) -> void:
	player = owner_player
	stats = weapon_stats


## The RANGED upgrade has been taken. Until this, the gun does not exist as far
## as the player is concerned — it is not drawn and not carried.
func arm() -> void:
	if _armed:
		return
	_armed = true
	visible = true
	set_process(true)
	charges = stats.initial_charges
	_progress = 0

	var ledger := RunLedger.of(self)
	if ledger != null:
		var run := ledger.run_of(player.peer_id)
		# Start counting from here rather than from zero: the score already on
		# the board was earned before there was anything to put it in.
		_score_seen = run.score if run != null else 0
		if not ledger.score_changed.is_connected(_on_score_changed):
			ledger.score_changed.connect(_on_score_changed)
	_place()


func _exit_tree() -> void:
	_show_cursor(false)


# ── What the avatar asks ────────────────────────────────────────────────────
## True while the gun is out, which is when the attack button belongs to it
## rather than to a melee swing. Uzi has no melee, but the question is asked the
## same way for anything that might.
func wants_attack() -> bool:
	return _armed and _aiming()


## While she is aiming, she faces where she is aiming — not where she is walking.
func locks_facing() -> bool:
	return _armed and _aiming()


## Which clip the body should be in, or nothing to leave it alone. Both are
## reserved slots in `uzi_frames.tres` standing in with her standing frame until
## they are drawn.
func pose() -> StringName:
	if not _armed or not _aiming():
		return &""
	return &"shooting" if not anim.current_animation.is_empty() else &"aiming"


# ── Input ───────────────────────────────────────────────────────────────────
## Right mouse. Off her back, or back onto it. Instant, and spammable on purpose.
func alt_pressed() -> void:
	if not _armed:
		return
	var now := not _aiming()
	player.set(&"aiming", now)
	Audio.play(stats.draw_sound if now else stats.stow_sound)
	_show_cursor(now)
	_place()


## Left mouse, while it is out.
func fire_pressed() -> void:
	if not _armed or not _aiming() or charges <= 0 or not cooldown.is_stopped():
		return
	charges -= 1
	cooldown.start()
	# Her gun, so her machine hears it — outside the broadcast below, which runs
	# on every machine in the room.
	Audio.play(stats.fire_sound)
	anim.play(&"fire")
	player.call(&"fire_weapon", muzzle_position(), float(player.get(&"aim_angle")))


## Every machine in the room, through the avatar's broadcast. The beam is traced
## HERE rather than sent: each machine solves the same geometry from the same
## seed and arrives at the same corners, which costs two floats on the wire
## instead of a polyline — and a held beam, which is where this is going, would
## be sending one of those every frame.
##
## The `enabled` art plays on every machine too. That is the only time it shows:
## the gun is drawn `disabled` on her back and `disabled` in her hands, and the
## energy is only ever loose in it for the fifth of a second the shot lasts.
func spawn_shot(from: Vector2, angle: float) -> void:
	if stats == null or player == null:
		return
	if not anim.is_playing():
		anim.play(&"fire")
	var shot := SHOT_SCENE.instantiate()
	# Into the world beside the avatar, never under Fx.effects_root: the beam
	# carries the hitbox that does the killing, and a dedicated server registers
	# no effects root at all.
	var host := player.get_parent()
	if host == null:
		shot.queue_free()
		return
	host.add_child(shot)
	shot.call(&"fire", player, stats, RailBeam.trace(self, from, Vector2.from_angle(angle), stats))


# ── Where the drawing is ────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _is_mine() and _aiming():
		var to_cursor := get_global_mouse_position() - _grip_position()
		if to_cursor.length_squared() > 1.0:
			player.set(&"aim_angle", to_cursor.angle())
			# From the LATCH, not from the raw angle: she faces whichever way the
			# gun is actually drawn.
			player.set(&"facing_right", not _latch_mirror(to_cursor.angle()))
		if bool(player.get(&"flying")) and Input.is_action_pressed("attack"):
			_debug_stream()
	_place()


## Debug only, and only in FLIGHT: holding the trigger re-fires as fast as
## StreamTimer allows, spending no charges and ignoring the cooldown.
##
## This is the held beam the whole solver was shaped for, without being a
## mechanic yet: `RailBeam.trace` is a pure function of where the gun is
## pointing, so a beam that follows the cursor is that function called again.
## Firing a fresh shot every 60 ms is the cheap way to LOOK at that while it
## moves — a real held beam would re-lay one shot rather than spawn many.
func _debug_stream() -> void:
	if not _armed or not stream.is_stopped():
		return
	stream.start()
	anim.play(&"fire")
	player.call(&"fire_weapon", muzzle_position(), float(player.get(&"aim_angle")))


## Debug: a full gun, now. Called when flight is switched on.
func debug_refill() -> void:
	if not _armed:
		return
	charges = stats.charges
	_progress = 0
	cooldown.stop()


## Should the drawing be mirrored, with a deadband either side of straight up
## and straight down. Idempotent for a steady angle; only a move that clears the
## margin changes the answer.
func _latch_mirror(angle: float) -> bool:
	var away := absf(angle)
	if away > UPRIGHT_LIMIT + FLIP_MARGIN:
		_mirrored = true
	elif away < UPRIGHT_LIMIT - FLIP_MARGIN:
		_mirrored = false
	return _mirrored


## The gun, put where it belongs this frame. One function for both states, so
## they cannot drift apart.
func _place() -> void:
	if stats == null or player == null:
		return
	var facing := bool(player.get(&"facing_right"))
	var side := 1.0 if facing else -1.0

	if not _aiming():
		position = Vector2(stats.stow_offset.x * side, stats.stow_offset.y)
		pivot.rotation = deg_to_rad(stats.stow_degrees) * side
		sprite.position = Vector2.ZERO
		sprite.flip_h = not facing
		sprite.flip_v = false
		z_index = -1
		return

	var angle := float(player.get(&"aim_angle"))
	# Past a quarter turn the drawing would be hanging upside down, so it is
	# mirrored across the barrel instead — which is what a person aiming behind
	# themselves actually does with a rifle. Latched, so aiming dead up or dead
	# down does not flicker on the boundary.
	var upside_down := _latch_mirror(angle)
	# The grip follows the same latch, not `facing_right`, so a puppet whose
	# facing packet has not landed yet still has the gun in the right hand.
	position = Vector2(stats.grip_offset.x * (-1.0 if upside_down else 1.0),
		stats.grip_offset.y)
	pivot.rotation = angle
	sprite.flip_h = false
	sprite.flip_v = upside_down
	sprite.position = Vector2(stats.hold_offset.x,
		-stats.hold_offset.y if upside_down else stats.hold_offset.y)
	z_index = 1


## Where the beam leaves, in world space. Follows the drawing through both the
## rotation and the mirror, so a shot fired backwards still leaves the barrel.
func muzzle_position() -> Vector2:
	if stats == null:
		return global_position
	var off := stats.muzzle_offset
	if sprite.flip_v:
		off.y = -off.y
	return pivot.to_global(off)


## The nail the gun turns on.
func _grip_position() -> Vector2:
	return pivot.global_position


# ── Charges ─────────────────────────────────────────────────────────────────
## How full the gun is, 0 to 1, INCLUDING the part-charge in progress. The
## indicator wants a continuous number rather than a count, because the ult that
## is coming drains it continuously — see assets/ui/rail_fill.gdshader.
func fill() -> float:
	if stats == null or stats.charges <= 0:
		return 0.0
	var whole := float(charges)
	var part := float(_progress) / float(maxi(stats.score_per_charge, 1))
	return clampf((whole + part) / float(stats.charges), 0.0, 1.0)


## How much of the charge the METER should show, as opposed to how much the gun
## holds. They differ only while the gun is recharging between shots.
##
## The indicator answers "can I shoot" as well as "how many shots left", and it
## has to, because it was answering the first question wrongly: a full-looking
## meter on a gun that refuses to fire reads as a broken weapon. So a shot empties
## it and the 3.3 s cooldown fills it back — which is also the only honest
## picture, since during those seconds the shots you are holding are not
## available to you.
##
## A gun with no charges at all shows nothing, cooldown or no cooldown.
func readiness() -> float:
	if charges <= 0:
		return 0.0
	if cooldown.is_stopped() or cooldown.wait_time <= 0.0:
		return 1.0
	return clampf(1.0 - cooldown.time_left / cooldown.wait_time, 0.0, 1.0)


## What the METER shows: the shots you can actually take, plus the one you are
## earning. This is the number the indicator is driven by, and `fill()` is not.
##
## The two are different questions and showing only the first was the bug: a bar
## reading five-sixths on a gun that will not fire is a bar that is lying about
## the only thing you are looking at it for. So the whole charges are scaled by
## how far through the cooldown the gun is — they are yours, but not yet — while
## the part-charge bought with score is always shown, because it is always true
## and because watching it creep up is the point of it being tied to experience.
##
## Empty gun, empty meter: `readiness()` is 0 with no charges, and the only thing
## left is whatever fraction of the next one has been earned.
func meter() -> float:
	if stats == null or stats.charges <= 0:
		return 0.0
	var earned := float(_progress) / float(maxi(stats.score_per_charge, 1))
	var held := float(charges) * readiness()
	return clampf((held + earned) / float(stats.charges), 0.0, 1.0)


## What a full gun holds, which is the scale everything about the meter divides
## up. The HUD needs it to put its marks between the charges, and asks the weapon
## rather than the character — a second charged weapon later would answer for
## itself with no change anywhere.
func capacity() -> int:
	return stats.charges if stats != null else 0


func ready_to_fire() -> bool:
	return _armed and charges > 0 and cooldown.is_stopped()


## Has the upgrade that grants this been taken? Until it has, the gun is not
## drawn, not carried and not on the HUD.
func armed() -> bool:
	return _armed


## The ledger reports absolute numbers for every peer in the room; this cares
## about one of them, and about the difference rather than the total.
func _on_score_changed(peer_id: int, score: int, _combo: int) -> void:
	if not _armed or player == null or peer_id != int(player.get(&"peer_id")):
		return
	var gained := score - _score_seen
	_score_seen = score
	if gained <= 0:
		return
	if charges >= stats.charges:
		# Full. Nothing banks — the owner asked for a hard ceiling on both the
		# count and the indicator, so a kill streak cannot be cashed in later as
		# six shots at once.
		_progress = 0
		return
	_progress += gained
	while charges < stats.charges and _progress >= stats.score_per_charge:
		_progress -= stats.score_per_charge
		charges += 1
	if charges >= stats.charges:
		_progress = 0


# ── Plumbing ────────────────────────────────────────────────────────────────
func _aiming() -> bool:
	return player != null and bool(player.get(&"aiming"))


## Whether this machine is the one steering the avatar. A puppet's gun is drawn
## from the two replicated values and reads no mouse at all.
func _is_mine() -> bool:
	if player == null:
		return false
	var session: NetSession = player.get(&"session")
	return session == null or not session.active or player.is_multiplayer_authority()


func _cooldown_seconds() -> float:
	var def: CharacterDef = player.get(&"character") if player != null else null
	return def.ranged_cooldown if def != null else 3.3


## The crosshair, on this machine only. Put back on stow, on death and on the way
## out of the tree — a pointer left over from a run that ended is a bug you can
## see from the main menu.
func _show_cursor(on: bool) -> void:
	if not _is_mine() or stats == null or stats.crosshair == null:
		return
	if on == _cursor_shown:
		return
	_cursor_shown = on
	if on:
		Input.set_custom_mouse_cursor(stats.crosshair, Input.CURSOR_ARROW,
			stats.crosshair_hotspot)
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


## The avatar has gone down or died: the gun goes back and the pointer with it.
func holster() -> void:
	if player != null:
		player.set(&"aiming", false)
	_show_cursor(false)
	_place()

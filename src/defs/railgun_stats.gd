@tool
class_name RailgunStats
extends Resource
## Everything the railgun is, as numbers. One .tres — data/weapons/railgun.tres.
##
## The weapon itself is a scene mounted on the avatar (CharacterDef.weapon_scene)
## and this is its tuning surface, the way EnemyStats is a golem's and BlastDef is
## a bomb's. Nothing here is a literal in railgun.gd.
##
## The cooldown is NOT here: it is `CharacterDef.ranged_cooldown`, because it is
## a fact about the climber holding the gun rather than about the gun, and the
## avatar already owns a timer for it.

# ── The shot ────────────────────────────────────────────────────────────────
@export_group("Shot")
## How many times the beam bounces. Five reflections is six straight segments.
##
## Capped by RailBeam.MAX_SEGMENTS, which is how many collision shapes
## RailShot.tscn authors. Raising this past that needs more shapes in the scene,
## not a bigger number here — the solver says so out loud when it clamps.
@export_range(0, 7) var bounces: int = 5
## How far one segment reaches before it gives up and ends in open air. The pit
## is 16000 deep and about 1900 wide, so this crosses it comfortably.
@export_range(200.0, 12000.0, 50.0) var segment_length: float = 4200.0
## How wide the beam is as a hitbox — not as a drawing. The drawing is three
## Line2Ds in RailShot.tscn and is deliberately wider, because a beam you can
## see the edge of is easier to aim than one you can only just touch things with.
@export_range(2.0, 80.0, 1.0) var beam_width: float = 16.0
## How far a segment's HITBOX carries on past the point the beam turned at.
##
## The beam stops at a surface, but the things that make a surface interesting
## sit behind it: a golem's damage and stomp areas are what set it off, and they
## are offset from the body the beam bounced off. A hitbox that ends exactly at
## the impact point touches none of them — the beam visibly hit a golem and
## nothing happened, which is the bug this exists for. It is small enough not to
## reach through a wall into whatever is standing on the other side.
@export_range(0.0, 96.0, 1.0) var hit_overshoot: float = 28.0
## Whether an avatar stops the beam instead of being passed through.
##
## False is the shipped behaviour: the beam goes THROUGH a climber, hurting them
## on the way. True makes a body a mirror like a wall, which turns a teammate
## into cover and a rival into a shield. It is here because the owner asked for
## the possibility to exist, not because anything switches it today.
@export var stops_on_players: bool = false
## How long the beam can hurt THE PERSON WHO FIRED IT, counted from the shot.
##
## Everyone else it can reach stays in danger for as long as the hitbox is up,
## which is most of the time the beam is on screen. Its owner does not: firing
## into a corridor you are standing in is meant to cost you a heart at the
## moment you pull the trigger, not to leave you pinned in your own shot while
## it fades. 0 turns self harm off entirely.
##
## The smaller target is the other half of the same idea — see Player's
## SelfHurtBox, which is half the size of the one everything else aims at.
##
## MEASURE BEFORE TUNING THIS. A single shot's hitbox closes at 0.14 s — the
## `_close` track in RailShot.tscn, a fifth of the time the drawing is on screen
## — so at anything above that this is a ceiling that never binds, and lowering
## it is the only way to see it do anything. It is set where it is because the
## number the owner asked for is half a second, and because the beam this has to
## survive is the HELD one: a hitbox that lives as long as the trigger is exactly
## where "your own beam hurts you" turns into "your own beam kills you", and it
## is this that stops it.
@export_range(0.0, 2.0, 0.05) var self_harm_seconds: float = 0.5

# ── Charges ─────────────────────────────────────────────────────────────────
@export_group("Charges")
## How many shots the gun holds. The indicator is one drawing, not this many
## frames — see assets/ui/rail_fill.gdshader.
@export_range(1, 12) var charges: int = 6
## Score earned — not spent — per charge. The run's own number is untouched:
## this counts what has been earned SINCE the last charge landed, so climbing
## with the railgun never costs a place on the board.
@export_range(50, 5000, 10) var score_per_charge: int = 600
## What the gun arrives with when the upgrade is taken, so the unlock is worth
## something before the next 600 points are earned.
@export_range(0, 12) var initial_charges: int = 2

# ── Where it sits ───────────────────────────────────────────────────────────
@export_group("Carry")
## The grip, in avatar space, facing right. The gun turns about this point and
## nothing else — it is the nail it is pinned through.
@export var grip_offset: Vector2 = Vector2(4.0, -6.0)
## Where the drawing sits relative to the grip when it is being aimed, so the
## grip lands on the pistol grip of the art rather than on its centre.
@export var hold_offset: Vector2 = Vector2(26.0, 0.0)
## Slung on her back: offset and tilt, facing right. Mirrored for the other side.
@export var stow_offset: Vector2 = Vector2(-10.0, -14.0)
@export_range(-180.0, 180.0, 1.0) var stow_degrees: float = -28.0
## The barrel tip, measured from the grip along the gun, facing right. The beam
## leaves here and the muzzle flash happens here.
@export var muzzle_offset: Vector2 = Vector2(96.0, -6.0)
## Drawing scale. The world is drawn at 2×, like every other sprite.
@export_range(0.25, 6.0, 0.25) var sprite_scale: float = 2.0

@export_subgroup("Aiming")
## The pointer while the gun is out. It is set on the local machine only and put
## back the moment the gun goes away — a cursor is not part of the simulation.
@export var crosshair: Texture2D
## Which pixel of that drawing is the point being aimed at. The middle of it.
@export var crosshair_hotspot: Vector2 = Vector2(15.0, 15.0)

# ── Recoil ──────────────────────────────────────────────────────────────────
@export_group("Recoil")
## The shove backwards along the barrel, through Player.shove() — the same one
## entry point a blast and a rival's hit use. It is a movement tool on purpose:
## fire downwards and the kick carries the jump.
@export_range(0.0, 2000.0, 10.0) var recoil: float = 640.0

# ── Feedback ────────────────────────────────────────────────────────────────
@export_group("Feedback")
## Camera kick at the muzzle, faded over `feedback_range` for everyone else. The
## game's scale: 0.35 is a hit taken, 0.45 a shockwave, 0.95 a bomb.
@export_range(0.0, 1.0, 0.05) var shake: float = 0.5
## Green wash over the screen, distance-faded by the caller. Anything much above
## 0.25 reads as a bug rather than a shot.
@export_range(0.0, 1.0, 0.01) var flash: float = 0.16
## How far away the kick and the wash are still felt at all.
@export_range(0.0, 8000.0, 100.0) var feedback_range: float = 2600.0
## Tint for the flash and for every particle the shot throws. Pick it out of the
## drawing — this is the energy green off the indicator.
@export var energy: Color = Color(0.76, 1.0, 0.24, 1.0)

@export_subgroup("Particles")
@export var muzzle_burst: BurstPreset
## Sparks where the beam turns a corner.
@export var bounce_burst: BurstPreset
## The far end, where it finally stops.
@export var impact_burst: BurstPreset

# ── Sound ───────────────────────────────────────────────────────────────────
@export_group("Sound")
## Taking it off her back and putting it back. These are StringNames into the
## SoundBank rather than streams, so giving the railgun its own recordings later
## is three words in this file and no code at all.
@export var draw_sound: StringName = &"upgrade"
@export var stow_sound: StringName = &"ui_click"
## The shot. Played by the firing machine only — it is one avatar's gun.
@export var fire_sound: StringName = &"shockwave"
## Where the beam ends, out in the pit. Positional.
@export var impact_sound: StringName = &"bomb_hit"

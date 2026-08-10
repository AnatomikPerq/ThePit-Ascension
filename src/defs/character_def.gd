@tool
class_name CharacterDef
extends Resource
## Everything that makes one climber different from another. One .tres per
## character: Cyn is data/characters/cyn.tres, Tessa is tessa.tres, and a third
## climber is another file — not another script and not a branch in player.gd.
##
## Player reads this in _ready() and never asks again. Nothing outside
## CharacterDef and the upgrade pool may test *which* character is being played:
## if a difference cannot be expressed as a number or a scene here, it belongs
## here as a new field rather than as an `if id == &"tessa"` somewhere.

## Stable id. It is what travels in the session roster and what the save file
## remembers, so it must not change once a character ships.
@export var id: StringName = &""
@export var display_name: String = ""
## One or two lines on the character-select stand.
@export_multiline var blurb: String = ""
## Drives the stand's highlight and the name colour. Pick it out of the sprite.
@export var accent: Color = Color.WHITE

@export_group("Body")
## Built by tools/build_sprite_frames.gd. Must carry standing / running /
## jumping / falling / attacking / died.
@export var frames: SpriteFrames

@export_group("Feel")
@export_range(1, 10) var max_health: int = 5
## Multiplies Player.JUMP_FORCE. Tessa's jumps are shorter than Cyn's; that is
## the whole of what "немного слабее" means, and it is one number.
@export_range(0.5, 1.5, 0.01) var jump_scale: float = 1.0
## Jumps available with nothing unlocked. 1 = ground jump only (Cyn), 2 = a
## double jump from the start (Tessa). EXTRA_JUMP upgrades add to it.
@export_range(1, 5) var base_jumps: int = 1

@export_group("Attack")
## The hitbox scene the ATTACK upgrade unlocks — Strike.tscn for Cyn's fist,
## SwordStrike.tscn for Tessa's blade. Both run scripts/strike.gd; they differ
## in reach, dwell and art, all of which are exports on that scene.
##
## Empty for a climber with nothing on the attack button. Uzi's is empty and
## deliberately so — her three unlocks are the double jump, the extra heart and
## the railgun, and the left button is hers to be given something later.
@export var attack_scene: PackedScene
@export_range(0.05, 2.0, 0.01) var attack_cooldown: float = 0.45
@export var attack_sound: StringName = &"strike"

@export_group("Shot")
## What the RANGED upgrade unlocks, on the second attack button. Null for a
## character that has no ranged upgrade in its pool — Cyn's is empty and her
## right mouse button does nothing, which is the whole of "Cyn cannot shoot".
@export var ranged_scene: PackedScene
@export_range(0.1, 10.0, 0.05) var ranged_cooldown: float = 2.0
@export var ranged_sound: StringName = &"strike"
## How long the firing pose is held. It only has to outlast the muzzle flash.
@export_range(0.05, 1.0, 0.01) var ranged_pose: float = 0.18
## Where the shot leaves the drawing, relative to the avatar, facing right. It
## is mirrored for the other side. This is a fact about the art, which is why it
## lives here and not as a number in player.gd.
@export var muzzle_offset: Vector2 = Vector2(28, -10)

@export_group("Weapon")
## A weapon the RANGED upgrade unlocks that is a THING RATHER THAN A SHOT.
##
## `ranged_scene` above spawns one projectile per press and is gone; this one is
## mounted on the avatar and stays — Uzi's railgun, which lives on her back, is
## taken out and put away with the same button, aims by mouse, and holds charges
## between shots. The two are alternatives: a character sets one or the other,
## and RANGED unlocks whichever it has.
##
## Anything here answers four questions and Player asks nothing else of it:
## `wants_attack()`, `locks_facing()`, `pose()` and `setup(player, stats)`. That
## is the whole interface, and it is what keeps the avatar from ever knowing
## which climber is holding what.
@export var weapon_scene: PackedScene
## The weapon's own numbers, handed to it on setup. Null for a character with no
## weapon scene.
@export var weapon_stats: Resource

@export_group("Progression")
## The pool the upgrade menu draws from, in the order the buttons appear. Each
## entry can be taken once; when one is left it is granted without asking, and
## when none are the milestone pays score instead.
@export var upgrades: Array[UpgradeDef] = []

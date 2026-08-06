@tool
class_name UpgradeDef
extends Resource
## One thing a climber can be given when they cross an upgrade milestone.
##
## An upgrade is single-use: it leaves the character's pool the moment it is
## taken, so the menu only ever offers what is still missing. That is why the
## title lives here rather than on the button — "DOUBLE JUMP" and "TRIPLE JUMP"
## are the same EXTRA_JUMP effect worded for the character it belongs to.
##
## Adding an upgrade later is a .tres and a row in a character's list. Adding a
## new KIND of upgrade is one more Effect and one more branch in
## World._apply_upgrade — nothing else knows these exist.

enum Effect {
	EXTRA_JUMP, ## one more jump before the ground has to be touched again
	ATTACK, ## unlock the character's own sideways attack
	SHOCKWAVE, ## unlock the radial blast
	MAX_HP, ## one more heart, and a full heal with it
	RANGED, ## unlock the character's own shot
}

## Stable id, for saves and for talking about one in a log. Never shown.
@export var id: StringName = &""
## The line the button leads with, and the text of the UNLOCKED notification.
@export var title: String = "UPGRADE"
## The smaller line under it. Empty is fine.
@export_multiline var subtitle: String = ""
@export var effect: Effect = Effect.EXTRA_JUMP

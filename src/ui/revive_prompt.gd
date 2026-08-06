class_name RevivePrompt
extends Node2D
## The sign over a body: what to press, and what it will cost.
##
## It lives on the avatar rather than on the reviver's HUD because the answer to
## "who do I pick up" is a place in the pit, not a line of text — with four
## bodies on four platforms a HUD notice cannot say which one you are standing
## next to.
##
## Everything about it is local and cosmetic. World decides every frame which
## bodies this machine's own climber could pick up; nothing here crosses the
## wire, and a puppet shows its own sign on its own screen.

## Long enough to notice, short enough that walking past four bodies is not four
## seconds of animation.
const APPEAR_TIME: float = 0.22

@onready var anim: AnimationPlayer = $AnimationPlayer

var _shown: bool = false


func _ready() -> void:
	visible = false


## Called by Player.set_revive_prompt. Idempotent: World asks every frame.
func show_sign(on: bool) -> void:
	if on == _shown:
		return
	_shown = on
	if on:
		visible = true
		anim.play(&"appear")
	else:
		anim.play(&"vanish")

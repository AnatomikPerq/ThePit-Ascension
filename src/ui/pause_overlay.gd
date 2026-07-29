class_name PauseOverlay
extends ColorRect
## Pause menu. Three ways out of a paused run — back into it, restart it, or
## leave for the main menu — as real buttons.
##
## They exist because the hotkeys did not cover the ground: leaving for the
## menu mid-run had no key at all (you had to die first), and in a session R
## did nothing whatsoever. The buttons say who may do what, which a line of
## help text cannot: only the host can restart a shared run.

signal resume_pressed
signal restart_pressed
signal menu_pressed

@onready var help: Label = $VBox/Help
@onready var resume_btn: Button = $VBox/Buttons/ResumeBtn
@onready var restart_btn: Button = $VBox/Buttons/RestartBtn
@onready var menu_btn: Button = $VBox/Buttons/MenuBtn


func _ready() -> void:
	resume_btn.pressed.connect(resume_pressed.emit)
	restart_btn.pressed.connect(restart_pressed.emit)
	menu_btn.pressed.connect(menu_pressed.emit)
	visibility_changed.connect(_on_visibility_changed)


## Re-read the session state every time the overlay comes up rather than once
## at _ready: the same World instance is paused before and after a peer joins,
## and the host is the only one who may restart.
func _on_visibility_changed() -> void:
	if not visible:
		# In a session the tree keeps running behind the overlay, so a button
		# left holding focus would keep eating the arrow keys.
		resume_btn.release_focus()
		restart_btn.release_focus()
		menu_btn.release_focus()
		return
	var may_restart := not Net.active or Net.is_host()
	restart_btn.visible = may_restart
	restart_btn.text = "RESTART FOR EVERYONE" if Net.active else "RESTART"
	menu_btn.text = "LEAVE SESSION" if Net.active else "MAIN MENU"
	help.text = "ESC — resume      R — restart      M — music" if may_restart \
		else "ESC — resume      M — music      (only the host can restart)"
	# Keyboard first: RESUME takes focus, so Enter is always the safe answer.
	resume_btn.grab_focus()

class_name EndScreen
extends ColorRect
## End-of-run screen. One scene serves both outcomes: World.tscn instances it
## twice with the title, colors and background overridden per instance.
##
## The two buttons are the only way out that does not need a hotkey. Which of
## them appear depends on the session: a shared run restarts for everyone or
## not at all, and that is the host's call.

signal restart_pressed
signal menu_pressed

@onready var restart_btn: Button = $Buttons/RestartBtn
@onready var menu_btn: Button = $Buttons/MenuBtn
@onready var hint: Label = $Hint


func _ready() -> void:
	restart_btn.pressed.connect(restart_pressed.emit)
	menu_btn.pressed.connect(menu_pressed.emit)


func show_with(stats: String) -> void:
	$Stats.text = stats
	var may_restart := not Net.active or Net.is_host()
	restart_btn.visible = may_restart
	restart_btn.text = "RESTART FOR EVERYONE" if Net.active else "RESTART"
	menu_btn.text = "LEAVE SESSION" if Net.active else "MAIN MENU"
	hint.text = _hint_text(may_restart)
	visible = true


func _hint_text(may_restart: bool) -> String:
	if not Net.active:
		return "SPACE — restart      ESC — main menu"
	if may_restart:
		return "R — restart for everyone      ESC — leave session"
	return "ESC — leave session      (only the host can restart)"

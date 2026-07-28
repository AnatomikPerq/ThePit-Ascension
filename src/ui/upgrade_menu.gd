class_name UpgradeMenu
extends Panel
## Upgrade choice panel. Four authored buttons; the only logic is turning a
## press into an index. World decides what the index means.

signal chosen(index: int)


func _ready() -> void:
	var buttons: Array[Button] = [
		$DoubleJumpBtn, $StrikeBtn, $ShockwaveBtn, $HealBtn,
	]
	for i in buttons.size():
		buttons[i].pressed.connect(chosen.emit.bind(i))

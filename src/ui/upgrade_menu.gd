class_name UpgradeMenu
extends Panel
## Upgrade choice panel. It is handed the list of things the climber has not
## taken yet and builds one authored button per entry; the only logic here is
## turning a press into an index into that same list. World decides what the
## index means.
##
## The buttons are instanced from a .tscn rather than assembled out of `new()`
## calls, and the list is variable-length rather than four fixed buttons,
## because the two characters do not have the same number of upgrades and the
## pool shrinks as they are taken.

signal chosen(index: int)

const BUTTON_SCENE: PackedScene = preload("res://scenes/ui/UpgradeButton.tscn")

## The hotkeys printed on the first four buttons, matching the upgrade_1..4
## actions. A fifth upgrade would simply have no key — the mouse still works.
const HOTKEYS: Array[String] = ["Z", "X", "C", "V"]

@onready var row: HBoxContainer = $Row
@onready var help: Label = $HelpLabel


## Show a choice. `upgrades` is the caller's live list; the index that comes back
## on `chosen` indexes it.
func open(upgrades: Array[UpgradeDef]) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var keys: Array[String] = []
	for i in upgrades.size():
		var button: UpgradeButton = BUTTON_SCENE.instantiate()
		row.add_child(button)
		var key := HOTKEYS[i] if i < HOTKEYS.size() else ""
		button.fill(upgrades[i], key)
		button.pressed.connect(chosen.emit.bind(i))
		if key != "":
			keys.append(key)
	help.text = "Click to select" if keys.is_empty() \
			else "Click to select or press %s" % ", ".join(keys)
	visible = true

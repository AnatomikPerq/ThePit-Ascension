class_name UpgradeButton
extends Button
## One card in the upgrade menu: the name of the thing, and the key that takes
## it. No description — an upgrade with a name like DOUBLE JUMP does not need a
## sentence under it, and four sentences side by side are four things to read
## while the pit is still moving.

@onready var title_label: Label = $Title
@onready var key_label: Label = $Key


func fill(def: UpgradeDef, hotkey: String) -> void:
	title_label.text = def.title
	key_label.text = hotkey
	key_label.visible = hotkey != ""

class_name UpgradeButton
extends Button
## One card in the upgrade menu: the name of the thing, and the key that takes
## it. No description — an upgrade with a name like DOUBLE JUMP does not need a
## sentence under it, and four sentences side by side are four things to read
## while the pit is still moving.

## Both are laid out by a VBoxContainer rather than anchored by hand. The card
## used to stretch to the panel's full height while holding 150 px of content,
## with the title centred in the space ABOVE the key rather than in the card —
## so it sat off centre in a mostly empty box.
@onready var title_label: Label = $Layout/Title
@onready var key_label: Label = $Layout/Key


func fill(def: UpgradeDef, hotkey: String) -> void:
	title_label.text = def.title
	key_label.text = hotkey
	key_label.visible = hotkey != ""

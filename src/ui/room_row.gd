extends HBoxContainer
## One room in the browser.
##
## Instanced per room rather than authored as a fixed list, for the same reason
## `UpgradeButton` and `CharacterStand` are: the count is not fixed. That is still
## "author it in a scene" — what the rule forbids is `Button.new()` and a
## hand-built StyleBoxFlat, not instancing one.

@onready var name_label: Label = $NameLabel
@onready var detail_label: Label = $DetailLabel
@onready var join_btn: Button = $JoinBtn

var _room_id: int = 0
var _locked: bool = false
var _on_join: Callable


func show_room(info: Dictionary, on_join: Callable) -> void:
	_room_id = int(info.get("id", 0))
	_locked = bool(info.get("locked", false))
	_on_join = on_join

	var running := int(info.get("state", 0)) == Room.State.RUNNING
	name_label.text = "%s%s" % [str(info.get("name", "")).to_upper(),
		"  🔒" if _locked else ""]
	var watching := int(info.get("spectators", 0))
	detail_label.text = "%s · %d/%d%s · %s" % [
		Room.mode_name(int(info.get("mode", 0))),
		int(info.get("players", 0)), int(info.get("max_players", 0)),
		" · %d watching" % watching if watching > 0 else "",
		Room.state_name(int(info.get("state", 0)))]
	# A room mid-climb can still be walked into, to watch. The button says so
	# rather than being disabled, because "join to watch" is a thing people want
	# and a greyed-out button would tell them it is not on offer.
	join_btn.text = "WATCH" if running else "JOIN"
	join_btn.pressed.connect(_pressed)


func _pressed() -> void:
	if _on_join.is_valid():
		_on_join.call(_room_id, _locked)

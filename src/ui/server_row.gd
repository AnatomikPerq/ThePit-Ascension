extends PanelContainer
## One server in the browser.
##
## The badge is three authored nodes rather than one node coloured from here, and
## that is deliberate: a StyleBoxFlat built in a function is exactly what §2 of
## CLAUDE.md is about, and the interface is going to be restyled — three pills
## sitting in the scene file are three things a designer can open and change,
## while a colour computed in GDScript is a thing they have to come and ask about.
##
## The hover text comes from the server's row when the directory sent one, and
## from the badge's own wording when it did not. Either way it is set on the pill
## itself, so the tooltip appears where the player's cursor already is.

## Kind -> the node that shows it. The keys are DirectoryProtocol's wire values.
const BADGE_NODES := {
	DirectoryProtocol.BADGE_OFFICIAL: ^"Row/Text/TitleRow/Official",
	DirectoryProtocol.BADGE_PARTNER: ^"Row/Text/TitleRow/Partner",
	DirectoryProtocol.BADGE_VERIFIED: ^"Row/Text/TitleRow/Verified",
}

@onready var name_label: Label = $Row/Text/TitleRow/NameLabel
@onready var detail_label: Label = $Row/Text/DetailLabel
@onready var players_label: Label = $Row/Players
@onready var save_btn: Button = $Row/SaveBtn
@onready var join_btn: Button = $Row/JoinBtn

var entry: DirectoryEntry


## `on_join` and `on_save` are `func(entry: DirectoryEntry)` and
## `func(entry: DirectoryEntry, wanted: bool)`.
func show_server(shown: DirectoryEntry, on_join: Callable, on_save: Callable) -> void:
	entry = shown
	name_label.text = shown.name.to_upper()
	detail_label.text = _detail(shown)
	players_label.text = "%d / %d" % [shown.players, shown.max_players] \
			if shown.max_players > 0 else "—"
	_show_badge(shown)

	save_btn.button_pressed = shown.favourite
	save_btn.text = "SAVED" if shown.favourite else "SAVE"
	save_btn.toggled.connect(func(on: bool) -> void:
		save_btn.text = "SAVED" if on else "SAVE"
		on_save.call(shown, on))

	join_btn.disabled = not shown.joinable()
	join_btn.text = "CONNECT" if shown.joinable() else "OTHER BUILD"
	join_btn.tooltip_text = "" if shown.joinable() else \
		"This server is on a different version of the game. Update, or ask "\
		+ "whoever runs it to."
	join_btn.pressed.connect(func() -> void: on_join.call(shown))
	if shown.full():
		players_label.modulate = Color(0.95, 0.6, 0.35)


func _show_badge(shown: DirectoryEntry) -> void:
	for kind: String in BADGE_NODES:
		var pill: Control = get_node(BADGE_NODES[kind])
		pill.visible = kind == shown.badge
		if pill.visible:
			pill.tooltip_text = DirectoryProtocol.badge_note(kind, shown.badge_note)


## The line under the name: where it is, where the row came from, and whatever
## the server chose to say about itself. Assembled from the parts that are
## actually there, so a server with no description does not get a stray dot.
static func _detail(shown: DirectoryEntry) -> String:
	var parts := PackedStringArray(["%s:%d" % [shown.address, shown.port]])
	match shown.source:
		DirectoryEntry.Source.LAN:
			parts.append("on this network")
		DirectoryEntry.Source.SAVED:
			parts.append("saved — no reply")
	if shown.region != "":
		parts.append(shown.region)
	if shown.rooms > 0:
		parts.append("%d room%s" % [shown.rooms, "" if shown.rooms == 1 else "s"])
	if shown.auth == "account":
		parts.append("account needed")
	if not shown.tags.is_empty():
		parts.append(", ".join(shown.tags))
	if shown.description != "":
		parts.append(shown.description)
	return "  ·  ".join(parts)

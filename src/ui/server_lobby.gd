extends Control
## The screen you are on while connected to a dedicated server and not climbing:
## the room browser, the room you are in, and the chat that runs down the side of
## both.
##
## One scene for two states rather than two scenes, because the chat belongs to
## the connection and not to either half — swapping scenes on joining a room
## would throw away the conversation you joined for. The browser and the room
## panel are simply shown and hidden.

const ROOM_ROW := preload("res://scenes/ui/server/RoomRow.tscn")

@onready var server_label: Label = $UI/Header/ServerLabel
@onready var account_label: Label = $UI/Header/AccountLabel
@onready var browser: VBoxContainer = $UI/Body/Left/Browser
@onready var room_list: VBoxContainer = $UI/Body/Left/Browser/Scroll/RoomList
@onready var empty_label: Label = $UI/Body/Left/Browser/EmptyLabel
@onready var create_panel: VBoxContainer = $UI/Body/Left/Browser/Create
@onready var create_name: LineEdit = $UI/Body/Left/Browser/Create/NameRow/NameEdit
@onready var create_mode: OptionButton = $UI/Body/Left/Browser/Create/NameRow/ModeSelect
@onready var create_seats: SpinBox = $UI/Body/Left/Browser/Create/OptionsRow/Seats
@onready var create_password: LineEdit = $UI/Body/Left/Browser/Create/OptionsRow/PasswordEdit
@onready var create_btn: Button = $UI/Body/Left/Browser/Create/OptionsRow/CreateBtn

@onready var room_panel: VBoxContainer = $UI/Body/Left/RoomPanel
@onready var room_title: Label = $UI/Body/Left/RoomPanel/RoomTitle
@onready var room_members: Label = $UI/Body/Left/RoomPanel/Members
@onready var character_btn: Button = $UI/Body/Left/RoomPanel/Controls/CharacterBtn
@onready var spectator_btn: Button = $UI/Body/Left/RoomPanel/Controls/SpectatorBtn
@onready var start_btn: Button = $UI/Body/Left/RoomPanel/Controls/StartBtn
@onready var leave_btn: Button = $UI/Body/Left/RoomPanel/Controls/LeaveBtn

@onready var chat_log: RichTextLabel = $UI/Body/Right/ChatLog
@onready var chat_input: LineEdit = $UI/Body/Right/ChatInput
@onready var status_label: Label = $UI/StatusLabel
@onready var admin_btn: Button = $UI/Header/AdminBtn
@onready var character_select: CharacterSelect = $CharacterSelect
@onready var admin_panel: CanvasLayer = $AdminPanel


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.03, 0.06))
	Hub.rooms_changed.connect(_on_rooms)
	Hub.room_changed.connect(_on_room)
	Hub.chat_received.connect(_on_chat)
	Hub.notice.connect(_on_notice)
	Hub.kicked.connect(_on_kicked)
	Net.session_closed.connect(_on_closed)

	create_mode.add_item("CO-OP", NetSession.MODE_COOP)
	create_mode.add_item("RACE", NetSession.MODE_RACE)
	create_btn.pressed.connect(_on_create)
	start_btn.pressed.connect(func() -> void: Hub.ask(&"request_start"))
	leave_btn.pressed.connect(func() -> void: Hub.ask(&"request_leave"))
	character_btn.pressed.connect(character_select.open)
	character_select.closed.connect(_on_character_chosen)
	spectator_btn.toggled.connect(_on_spectator)
	chat_input.text_submitted.connect(_on_chat_submitted)
	admin_btn.pressed.connect(admin_panel.open)
	$UI/Header/LeaveServerBtn.pressed.connect(_on_disconnect)

	# Joined rather than formatted: this screen is also built cold by the UI
	# screenshot harness, with no server and no account, and a fixed "%s · %s"
	# leaves a separator with nothing on one side of it.
	server_label.text = _joined([Hub.server_name, NetProtocol.build_id()])
	account_label.text = _joined([Hub.account_name.to_upper(), Hub.role.to_upper()])
	admin_btn.visible = Hub.may(Permissions.SERVER_ADMIN_PANEL)
	create_panel.visible = Hub.may_create_rooms
	chat_input.editable = Hub.chat_enabled
	if Hub.motd != "":
		_write("[color=#f5c542]%s[/color]" % Hub.motd)
	_on_rooms(Hub.room_listing)
	_on_room(Hub.current_room)
	Hub.ask(&"request_rooms")


func _exit_tree() -> void:
	for pair in [[Hub.rooms_changed, _on_rooms], [Hub.room_changed, _on_room],
			[Hub.chat_received, _on_chat], [Hub.notice, _on_notice],
			[Hub.kicked, _on_kicked], [Net.session_closed, _on_closed]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or character_select.visible or admin_panel.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if not Hub.current_room.is_empty():
			Hub.ask(&"request_leave")
		else:
			_on_disconnect()
	elif event.is_action_pressed(&"admin_panel") and admin_btn.visible:
		get_viewport().set_input_as_handled()
		admin_panel.open()


# ── The browser ─────────────────────────────────────────────────────────────
func _on_rooms(listing: Array) -> void:
	for child in room_list.get_children():
		child.queue_free()
	empty_label.visible = listing.is_empty()
	for info: Variant in listing:
		var row := ROOM_ROW.instantiate()
		room_list.add_child(row)
		row.show_room(info as Dictionary, _join_room)


func _join_room(room_id: int, locked: bool) -> void:
	var password := ""
	if locked:
		password = create_password.text
		if password == "":
			_say("THAT ROOM HAS A PASSWORD — TYPE IT IN THE FIELD BELOW AND TRY AGAIN")
			return
	Audio.play(&"ui_click")
	Hub.ask(&"request_join", [room_id, password, String(_wanted_character())])


func _on_create() -> void:
	var room_name := create_name.text.strip_edges()
	if room_name == "":
		_say("GIVE THE ROOM A NAME")
		return
	Audio.play(&"ui_confirm")
	Hub.ask(&"request_create", [room_name, create_mode.get_selected_id(),
		int(create_seats.value), create_password.text, String(_wanted_character())])


# ── The room ────────────────────────────────────────────────────────────────
func _on_room(detail: Dictionary) -> void:
	var inside := not detail.is_empty()
	browser.visible = not inside
	room_panel.visible = inside
	if not inside:
		return
	room_title.text = "%s  ·  %s  ·  %s" % [
		str(detail.get("name", "")).to_upper(),
		Room.mode_name(int(detail.get("mode", 0))),
		Room.state_name(int(detail.get("state", 0)))]
	var lines: Array[String] = []
	for member: Variant in detail.get("members", []):
		var entry: Dictionary = member
		var pick := str(entry.get("character", ""))
		var def := Game.roster.by_id(StringName(pick))
		lines.append("%s  —  %s" % [str(entry.get("name", "?")).to_upper(),
			def.display_name.to_upper() if def != null else "SPECTATOR"])
	room_members.text = "\n".join(lines)
	start_btn.disabled = int(detail.get("state", 0)) == Room.State.RUNNING
	_refresh_character_buttons()


func _wanted_character() -> StringName:
	return CharacterRoster.SPECTATOR if spectator_btn.button_pressed \
			else Game.selected_character


func _on_character_chosen() -> void:
	if spectator_btn.button_pressed:
		spectator_btn.button_pressed = false # emits toggled, which announces
	else:
		_announce_character()
	_refresh_character_buttons()


func _on_spectator(_on: bool) -> void:
	_announce_character()
	_refresh_character_buttons()


func _announce_character() -> void:
	if not Hub.current_room.is_empty():
		Hub.ask(&"request_character", [String(_wanted_character())])


func _refresh_character_buttons() -> void:
	var watching := spectator_btn.button_pressed
	spectator_btn.text = "SPECTATOR: ON" if watching else "SPECTATOR: OFF"
	character_btn.text = "CHARACTER: %s" % Game.character_def().display_name.to_upper()
	character_btn.disabled = watching


# ── Chat ────────────────────────────────────────────────────────────────────
func _on_chat_submitted(text: String) -> void:
	var line := text.strip_edges()
	chat_input.clear()
	if line == "":
		return
	# A line starting with `/` is a command, exactly as it is on the console —
	# so a moderator does not have to open the panel to kick somebody.
	if line.begins_with("/"):
		Hub.ask(&"run_command", [line.substr(1)])
		return
	Hub.ask(&"send_chat", [line])


func _on_chat(entry: Dictionary) -> void:
	var scope := str(entry.get("scope", "room"))
	var from := str(entry.get("from", "?"))
	var text := str(entry.get("text", "")).replace("[", "[lb]")
	match scope:
		ChatService.SCOPE_SYSTEM:
			_write("[color=#8fb7d6]· %s[/color]" % text)
		ChatService.SCOPE_SERVER:
			_write("[color=#f5c542]%s: %s[/color]" % [from.to_upper(), text])
		_:
			_write("[color=#c8c0b8]%s:[/color] %s" % [from, text])


func _write(bbcode: String) -> void:
	chat_log.append_text("%s\n" % bbcode)


# ── Everything else the server says ─────────────────────────────────────────
func _on_notice(text: String) -> void:
	_say(text)
	_write("[color=#f5c542]· %s[/color]" % text)


## Kicked, dropped, or leaving on purpose: all three land back in the browser
## rather than on the main menu. Whatever went wrong, the next thing the player
## wants is a list of somewhere else to go.
func _on_kicked(reason: String) -> void:
	Net.leave()
	Router.to_multiplayer()
	print_rich("[color=red]%s[/color]" % reason)


func _on_closed(reason: String) -> void:
	_say(reason)
	Router.to_multiplayer()


func _on_disconnect() -> void:
	Net.leave()
	Router.to_multiplayer()


func _say(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


## The non-empty parts, separated. A header that reads "· proto 1" because the
## thing before the separator was blank is the sort of detail nobody reports and
## everybody notices.
func _joined(parts: Array[String]) -> String:
	var kept: Array[String] = []
	for part in parts:
		if part.strip_edges() != "":
			kept.append(part)
	return "  ·  ".join(kept)

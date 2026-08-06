extends CanvasLayer
## The server's administration interface, inside the game.
##
## Seven tabs over one idea: the server sends structured data
## (`ServerAdminFeed`), the panel draws it, and every *action* is sent back as a
## line of the very same command set the operator has at the keyboard. Pressing
## KICK builds `kick somebody` and sends it through `Hub.run_command`, where the
## permission check already lives. So there is no second implementation of
## moderation for the UI to get wrong, no second permission model, and a command
## added to the server is a command the panel's console can run the same day.
##
## What the panel does NOT do is decide what it may show. The server filters
## every feed by the asker's rights before sending it — a client draws what it
## was given and is never trusted to leave anything out.

const ADMIN_ROW := preload("res://scenes/ui/server/AdminRow.tscn")
const SETTING_ROW := preload("res://scenes/ui/server/SettingRow.tscn")

## Tab index -> the feed that fills it. The console tab has none: it is driven by
## what the operator types.
const FEEDS: Array[String] = [
	"overview", "players", "rooms", "settings", "bans", "accounts", "log",
]

@onready var tabs: TabContainer = $Panel/Layout/Tabs
@onready var title: Label = $Panel/Layout/Head/Title
@onready var close_btn: Button = $Panel/Layout/Head/CloseBtn
@onready var refresh_btn: Button = $Panel/Layout/Head/RefreshBtn
@onready var filter_edit: LineEdit = $Panel/Layout/Head/FilterEdit
@onready var console_log: RichTextLabel = $Panel/Layout/Tabs/CONSOLE/Log
@onready var console_input: LineEdit = $Panel/Layout/Tabs/CONSOLE/Input

## Live for as long as the panel is open. Refreshed on a timer as well as on
## demand, because a moderator watching the player list wants it to be true.
@onready var ticker: Timer = $Ticker


func _ready() -> void:
	visible = false
	close_btn.pressed.connect(close)
	refresh_btn.pressed.connect(refresh)
	tabs.tab_changed.connect(func(_index: int) -> void: refresh())
	filter_edit.text_submitted.connect(func(_text: String) -> void: refresh())
	console_input.text_submitted.connect(_on_command)
	ticker.timeout.connect(refresh)
	Hub.admin_answered.connect(_on_data)
	Hub.command_answered.connect(_on_command_result)


func _exit_tree() -> void:
	if Hub.admin_answered.is_connected(_on_data):
		Hub.admin_answered.disconnect(_on_data)
	if Hub.command_answered.is_connected(_on_command_result):
		Hub.command_answered.disconnect(_on_command_result)


func open() -> void:
	if not Hub.may(Permissions.SERVER_ADMIN_PANEL):
		return
	visible = true
	title.text = "%s  ·  %s" % [Hub.server_name.to_upper(), Hub.role.to_upper()]
	ticker.start()
	refresh()


func close() -> void:
	visible = false
	ticker.stop()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"admin_panel"):
		get_viewport().set_input_as_handled()
		close()


func refresh() -> void:
	# A TabContainer emits `tab_changed` while it is being built, so without this
	# the panel instanced into every World would ask the server for data it is
	# not showing, from the moment the run started.
	if not visible:
		return
	var index := tabs.current_tab
	if index < 0 or index >= FEEDS.size():
		return
	Hub.ask(&"request_admin", [FEEDS[index],
		{"filter": filter_edit.text.strip_edges(), "lines": 120}])


# ── Filling the tabs ────────────────────────────────────────────────────────
func _on_data(kind: String, data: Dictionary) -> void:
	match kind:
		"overview":
			_fill_overview(data)
		"players":
			_fill_players(data)
		"rooms":
			_fill_rooms(data)
		"settings":
			_fill_settings(data)
		"bans":
			_fill_bans(data)
		"accounts":
			_fill_accounts(data)
		"log":
			_fill_log(data)


func _rows_of(tab_name: String) -> VBoxContainer:
	var container: VBoxContainer = tabs.get_node("%s/Scroll/Rows" % tab_name)
	for child in container.get_children():
		child.queue_free()
	return container


func _row(into: VBoxContainer, left: String, right: String,
		actions: Array = []) -> Node:
	var row := ADMIN_ROW.instantiate()
	into.add_child(row)
	row.show_row(left, right, actions)
	return row


func _fill_overview(data: Dictionary) -> void:
	var rows := _rows_of("OVERVIEW")
	if data.is_empty():
		_row(rows, "you may not see this", "")
		return
	_row(rows, "SERVER", str(data.get("name", "")))
	_row(rows, "BUILD", str(data.get("build", "")))
	_row(rows, "STATUS", str(data.get("status", "")))
	_row(rows, "PLAYERS", "%d / %d" % [data.get("players", 0), data.get("max_players", 0)])
	_row(rows, "ROOMS", "%d / %d" % [data.get("rooms", 0), data.get("max_rooms", 0)])
	_row(rows, "ACCOUNTS", str(data.get("accounts", 0)))
	_row(rows, "BANS", str(data.get("bans", 0)))
	_row(rows, "AUTHENTICATION", str(data.get("auth", "")))
	_row(rows, "MOVEMENT GUARD", str(data.get("guard", "")))
	var may: Dictionary = data.get("may", {})
	if bool(may.get("stop", false)):
		_row(rows, "SHUT DOWN", "everybody is told why first",
			[["STOP THE SERVER", func() -> void: _send("stop asked from the panel")]])


func _fill_players(data: Dictionary) -> void:
	var rows := _rows_of("PLAYERS")
	var list: Array = data.get("players", [])
	if list.is_empty():
		_row(rows, "nobody is connected", "")
		return
	for entry: Variant in list:
		var row: Dictionary = entry
		var who := str(row.get("name", "?"))
		var where := "lobby" if int(row.get("room", 0)) == 0 \
				else "room %d" % int(row.get("room", 0))
		var detail := "%s · %s%s" % [where, str(row.get("role", "player")),
			"  MUTED" if bool(row.get("muted", false)) else ""]
		if row.has("address"):
			detail += "  ·  %s" % row["address"]
		var made := _row(rows, who, detail, [
			["KICK", func() -> void: _send('kick "%s" removed by a moderator' % who)],
			["MUTE", func() -> void: _send('mute "%s"' % who)],
			["BAN", func() -> void: _send('ban "%s"' % who)],
		])
		if bool(row.get("muted", false)):
			made.tint(Color(0.95, 0.6, 0.35))


func _fill_rooms(data: Dictionary) -> void:
	var rows := _rows_of("ROOMS")
	var list: Array = data.get("rooms", [])
	if list.is_empty():
		_row(rows, "no rooms are open", "")
		return
	for entry: Variant in list:
		var row: Dictionary = entry
		var id := int(row.get("id", 0))
		var made := _row(rows, "#%d %s" % [id, str(row.get("name", ""))],
			"%s · %s · %d/%d%s" % [
				Room.mode_name(int(row.get("mode", 0))),
				Room.state_name(int(row.get("state", 0))),
				int(row.get("players", 0)), int(row.get("max_players", 0)),
				"  LOCKED" if bool(row.get("locked", false)) else ""],
			[
				["START", func() -> void: _send("room start %d" % id)],
				["RESTART", func() -> void: _send("room restart %d" % id)],
				["CLOSE", func() -> void: _send("room close %d closed from the panel" % id)],
			])
		if bool(row.get("running", false)):
			made.tint(Color(0.6, 0.9, 0.5))


func _fill_settings(data: Dictionary) -> void:
	var rows := _rows_of("SETTINGS")
	var list: Array = data.get("settings", [])
	var writable := bool(data.get("writable", false))
	var needle := filter_edit.text.strip_edges().to_lower()
	var shown := 0
	for entry: Variant in list:
		var row: Dictionary = entry
		if needle != "" and not str(row.get("key", "")).to_lower().contains(needle):
			continue
		shown += 1
		var made := SETTING_ROW.instantiate()
		rows.add_child(made)
		made.show_setting(row, writable, _apply_setting)
	if shown == 0:
		_row(rows, "nothing matches '%s'" % needle, "")


func _apply_setting(key: String, value: String) -> void:
	_send('set %s "%s"' % [key, value])


func _fill_bans(data: Dictionary) -> void:
	var rows := _rows_of("BANS")
	var list: Array = data.get("bans", [])
	if list.is_empty():
		_row(rows, "nobody is banned", "")
		return
	for entry: Variant in list:
		var row: Dictionary = entry
		var subject := str(row.get("subject", ""))
		_row(rows, subject, BanList.describe(row),
			[["LIFT", func() -> void: _send('unban "%s"' % subject)]])


func _fill_accounts(data: Dictionary) -> void:
	var rows := _rows_of("ACCOUNTS")
	var list: Array = data.get("accounts", [])
	if list.is_empty():
		_row(rows, "no accounts match", "")
		return
	for entry: Variant in list:
		var row: Dictionary = entry
		var who := str(row.get("name", ""))
		var made := _row(rows, who, "%s · best %d · %s" % [
			str(row.get("role", "player")), int(row.get("best_score", 0)),
			"online" if bool(row.get("online", false)) else "offline"], [
				["OP", func() -> void: _send('op "%s"' % who)],
				["DEOP", func() -> void: _send('deop "%s"' % who)],
				["INFO", func() -> void: _send('account info "%s"' % who)],
			])
		if bool(row.get("online", false)):
			made.tint(Color(0.6, 0.9, 0.5))


func _fill_log(data: Dictionary) -> void:
	var lines: Array = data.get("log", [])
	if lines.is_empty():
		return
	console_log.clear()
	for line: Variant in lines:
		console_log.append_text("%s\n" % str(line).replace("[", "[lb]"))


# ── The console tab ─────────────────────────────────────────────────────────
func _on_command(line: String) -> void:
	console_input.clear()
	if line.strip_edges() == "":
		return
	console_log.append_text("[color=#f5c542]> %s[/color]\n" % line.replace("[", "[lb]"))
	_send(line)


func _send(line: String) -> void:
	Hub.ask(&"run_command", [line])


func _on_command_result(text: String, ok: bool) -> void:
	if text.strip_edges() == "":
		return
	var colour := "#c8c0b8" if ok else "#e06b5a"
	console_log.append_text("[color=%s]%s[/color]\n" % [colour,
		text.replace("[", "[lb]")])
	# Whatever the command did, the tab that was showing is now out of date.
	refresh()

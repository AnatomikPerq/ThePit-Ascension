extends Control
## MULTIPLAYER: the one door out of the main menu to everybody else.
##
## It replaced two buttons on the main menu — MULTIPLAYER and JOIN A SERVER —
## because the distinction they drew was one the player had to already understand
## to choose between them. There is one question ("where do you want to play?")
## and this screen answers it three ways: pick a server from the list, type an
## address, or open your own game for the people next to you.
##
## The list is the body of the screen and the other two are buttons under it,
## which is the ranking on purpose: the list is what somebody opening the game
## for the first time can actually use.
##
## Everything about how servers are FOUND is ServerFinder's — three sources
## merged. This file is the drawing of it, and nothing here knows how many
## sources there are.

const SERVER_ROW := preload("res://scenes/ui/server/ServerRow.tscn")

@onready var finder: ServerFinder = $Finder
@onready var list: VBoxContainer = $UI/Body/Scroll/List
@onready var empty_label: Label = $UI/Body/EmptyLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var refresh_btn: Button = $UI/Toolbar/RefreshBtn
@onready var filter_edit: LineEdit = $UI/Toolbar/FilterEdit
@onready var verified_btn: Button = $UI/Toolbar/VerifiedBtn

var _entries: Array = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.03, 0.06))
	# Arriving here from a session that ended, or from a connection that failed,
	# leaves a socket open. The browser is the one screen that is definitely not
	# in a game, so this is where it gets closed.
	Net.leave()
	finder.changed.connect(_on_entries)
	finder.status_changed.connect(_say)
	refresh_btn.pressed.connect(_on_refresh)
	filter_edit.text_changed.connect(func(_text: String) -> void: _draw_list())
	verified_btn.toggled.connect(func(_on: bool) -> void: _draw_list())
	$UI/Footer/DirectBtn.pressed.connect(func() -> void: Router.to_server_connect())
	$UI/Footer/LanBtn.pressed.connect(Router.to_lobby)
	$UI/Footer/BackBtn.pressed.connect(Router.to_menu)
	_on_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Router.to_menu()


func _on_refresh() -> void:
	Audio.play(&"ui_click")
	_say("LOOKING…")
	finder.refresh()


func _on_entries(found: Array) -> void:
	_entries = found
	_draw_list()


func _draw_list() -> void:
	for child in list.get_children():
		child.queue_free()
	var needle := filter_edit.text.strip_edges().to_lower()
	var verified_only := verified_btn.button_pressed
	var shown := 0
	for item: Variant in _entries:
		var entry: DirectoryEntry = item
		if verified_only and not entry.verified():
			continue
		if needle != "" and not _matches(entry, needle):
			continue
		shown += 1
		var row := SERVER_ROW.instantiate()
		list.add_child(row)
		row.show_server(entry, _join, _save)
	empty_label.visible = shown == 0
	empty_label.text = _empty_text(needle, verified_only)


static func _matches(entry: DirectoryEntry, needle: String) -> bool:
	var haystack := "%s %s %s %s %s" % [entry.name, entry.address, entry.region,
		entry.description, " ".join(entry.tags)]
	return haystack.to_lower().contains(needle)


## What to say when there is nothing to show. Three different situations, and
## telling them apart is the difference between "nobody is playing" and "this
## build has no server list configured", which are not the player's problem in
## the same way at all.
func _empty_text(needle: String, verified_only: bool) -> String:
	if needle != "" or verified_only:
		return "NOTHING MATCHES.\nClear the filter to see everything found."
	if finder.directory_url == "":
		return DirectoryDef.shipped().about
	return "NO SERVERS ANSWERED.\nOpen one of your own below, or connect to an "\
		+ "address somebody gave you."


# ── What a row does ─────────────────────────────────────────────────────────
func _join(entry: DirectoryEntry) -> void:
	Audio.play(&"ui_confirm")
	Router.to_server_connect(entry.address, entry.port, entry.name)


func _save(entry: DirectoryEntry, wanted: bool) -> void:
	entry.favourite = wanted
	if wanted:
		SavedServers.add(entry)
	else:
		SavedServers.forget(entry.key())


func _say(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""

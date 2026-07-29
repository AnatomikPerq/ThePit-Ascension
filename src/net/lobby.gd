extends Control
## Multiplayer lobby. Host opens a port; clients join by address. The host
## picks the mode (co-op or race) and starts the run for everyone; the roster
## locks at that moment — there is no join-in-progress.

@onready var host_port: LineEdit = $UI/HostRow/PortEdit
@onready var join_address: LineEdit = $UI/JoinRow/AddressEdit
@onready var join_port: LineEdit = $UI/JoinRow/PortEdit
@onready var host_btn: Button = $UI/HostRow/HostBtn
@onready var join_btn: Button = $UI/JoinRow/JoinBtn
@onready var status_label: Label = $UI/StatusLabel
@onready var peers_label: Label = $UI/PeersLabel
@onready var mode_select: OptionButton = $UI/StartRow/ModeSelect
@onready var start_btn: Button = $UI/StartRow/StartBtn


func _ready() -> void:
	host_port.text = str(Net.DEFAULT_PORT)
	join_port.text = str(Net.DEFAULT_PORT)
	mode_select.add_item("CO-OP", Net.Mode.COOP)
	mode_select.add_item("RACE", Net.Mode.RACE)

	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	start_btn.pressed.connect(_on_start)
	$UI/BackBtn.pressed.connect(_on_back)
	Net.peers_changed.connect(_refresh)
	Net.session_closed.connect(_on_session_closed)
	_refresh()


func _exit_tree() -> void:
	Net.peers_changed.disconnect(_refresh)
	Net.session_closed.disconnect(_on_session_closed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_on_back()


func _on_host() -> void:
	var err := Net.host(int(host_port.text))
	if err != OK:
		status_label.text = "COULD NOT OPEN PORT %s (error %d)" % [host_port.text, err]
		return
	status_label.text = "HOSTING ON PORT %s — WAITING FOR PLAYERS" % host_port.text
	_refresh()


func _on_join() -> void:
	var err := Net.join(join_address.text.strip_edges(), int(join_port.text))
	if err != OK:
		status_label.text = "COULD NOT START JOINING (error %d)" % err
		return
	status_label.text = "JOINING %s …" % join_address.text
	_refresh()


func _on_start() -> void:
	var world_seed := 0
	while world_seed == 0:
		world_seed = randi()
	Net.start_session(mode_select.get_selected_id() as Net.Mode, world_seed)


func _on_back() -> void:
	Net.leave()
	Router.to_menu()


func _on_session_closed(reason: String) -> void:
	status_label.text = reason
	_refresh()


func _refresh() -> void:
	var connecting := Net.active
	host_btn.disabled = connecting
	join_btn.disabled = connecting
	host_port.editable = not connecting
	join_address.editable = not connecting
	join_port.editable = not connecting

	# Only a connected host can pick the mode and launch.
	var hosting := Net.is_host()
	mode_select.visible = hosting
	start_btn.visible = hosting

	if not Net.active:
		peers_label.text = ""
		return
	var lines: Array[String] = []
	for peer_id in Net.lobby_peers():
		var line := "PLAYER %d" % peer_id
		if peer_id == 1:
			line += "  (HOST)"
		if peer_id == multiplayer.get_unique_id():
			line += "  — YOU"
		lines.append(line)
	peers_label.text = "\n".join(lines)
	if Net.is_host():
		status_label.text = "HOSTING — %d CONNECTED" % lines.size()
	elif multiplayer.has_multiplayer_peer() \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		status_label.text = "CONNECTED — WAITING FOR THE HOST TO START"

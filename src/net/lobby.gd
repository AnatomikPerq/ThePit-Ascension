extends Control
## Multiplayer lobby. Host opens a port; clients join by address. The host
## picks the mode (co-op or race) and starts the run for everyone; the roster
## locks at that moment — there is no join-in-progress.
##
## Each machine also picks who it is here: a climber, or nobody at all. The
## choice is announced to the lobby as it is made, so the list shows what
## everybody will be, and it is locked into the roster with the seed.

@onready var host_port: LineEdit = $UI/HostRow/PortEdit
@onready var join_address: LineEdit = $UI/JoinRow/AddressEdit
@onready var join_port: LineEdit = $UI/JoinRow/PortEdit
@onready var host_btn: Button = $UI/HostRow/HostBtn
@onready var join_btn: Button = $UI/JoinRow/JoinBtn
@onready var status_label: Label = $UI/StatusLabel
@onready var peers_label: Label = $UI/PeersLabel
@onready var mode_select: OptionButton = $UI/StartRow/ModeSelect
@onready var start_btn: Button = $UI/StartRow/StartBtn
@onready var character_btn: Button = $UI/RoleRow/CharacterBtn
## A toggle Button rather than a CheckBox: the pit theme styles buttons and has
## no check glyph, so a CheckBox gave no sign of which way it was set.
@onready var spectator_check: Button = $UI/RoleRow/SpectatorCheck
@onready var character_select: CharacterSelect = $CharacterSelect


func _ready() -> void:
	host_port.text = str(Net.DEFAULT_PORT)
	join_port.text = str(Net.DEFAULT_PORT)
	mode_select.add_item("CO-OP", Net.Mode.COOP)
	mode_select.add_item("RACE", Net.Mode.RACE)

	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	start_btn.pressed.connect(_on_start)
	character_btn.pressed.connect(character_select.open)
	character_select.closed.connect(_on_character_closed)
	spectator_check.toggled.connect(_on_spectator_toggled)
	$UI/BackBtn.pressed.connect(_on_back)
	Net.peers_changed.connect(_refresh)
	Net.choices_changed.connect(_refresh)
	Net.session_closed.connect(_on_session_closed)
	# The climber may have been changed on the main menu since Net last heard
	# about it. Re-read it here rather than at the moment of announcing, so the
	# lobby and the packet can never disagree.
	if Net.local_choice != CharacterRoster.SPECTATOR:
		Net.local_choice = Game.character_def().id
	spectator_check.button_pressed = Net.local_choice == CharacterRoster.SPECTATOR
	_refresh()


func _exit_tree() -> void:
	Net.peers_changed.disconnect(_refresh)
	Net.choices_changed.disconnect(_refresh)
	Net.session_closed.disconnect(_on_session_closed)


func _unhandled_input(event: InputEvent) -> void:
	if character_select.visible:
		return
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_on_back()


# ── Who this machine will be ────────────────────────────────────────────────
## Picking a climber also takes you off the spectator bench: you cannot have
## chosen somebody to play and be watching at the same time.
func _on_character_closed() -> void:
	if spectator_check.button_pressed:
		spectator_check.button_pressed = false # emits toggled, which announces
	else:
		Net.local_choice = Game.selected_character
	_refresh()


func _on_spectator_toggled(on: bool) -> void:
	Net.local_choice = CharacterRoster.SPECTATOR if on else Game.selected_character
	_refresh()


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
	Router.to_multiplayer()


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

	var watching := spectator_check.button_pressed
	spectator_check.text = "SPECTATOR: ON" if watching else "SPECTATOR: OFF"
	character_btn.text = "CHARACTER: %s" % Game.character_def().display_name
	character_btn.disabled = watching

	# Only a connected host can pick the mode and launch.
	var hosting := Net.is_host()
	mode_select.visible = hosting
	start_btn.visible = hosting

	if not Net.active:
		peers_label.text = ""
		return
	var lines: Array[String] = []
	for peer_id in Net.lobby_peers():
		var line := "PLAYER %d  —  %s" % [peer_id, _role_text(peer_id)]
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


func _role_text(peer_id: int) -> String:
	var id := Net.choice_of(peer_id)
	if id == CharacterRoster.SPECTATOR:
		return "SPECTATOR"
	var def := Game.roster.by_id(id)
	return def.display_name if def != null else String(id).to_upper()

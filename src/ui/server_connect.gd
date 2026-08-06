extends Control
## Connecting to a dedicated server: an address, who you are, and how you mean
## to prove it.
##
## The three ways in are three buttons rather than a dropdown, because they are
## three different intentions and the fields they need differ. What the server
## actually allows is not guessed at here — the server says so in its HELLO, and
## the form rearranges itself once it knows. Until then it offers everything and
## lets the server refuse, which is one round trip instead of a second protocol
## for asking.

const LAST_SERVER_PATH := "user://thepit_server.cfg"

@onready var address_edit: LineEdit = $UI/AddressRow/AddressEdit
@onready var port_edit: LineEdit = $UI/AddressRow/PortEdit
@onready var name_edit: LineEdit = $UI/NameRow/NameEdit
@onready var password_edit: LineEdit = $UI/PasswordRow/PasswordEdit
@onready var token_row: HBoxContainer = $UI/TokenRow
@onready var token_edit: LineEdit = $UI/TokenRow/TokenEdit
@onready var guest_btn: Button = $UI/IntentRow/GuestBtn
@onready var login_btn: Button = $UI/IntentRow/LoginBtn
@onready var register_btn: Button = $UI/IntentRow/RegisterBtn
@onready var connect_btn: Button = $UI/ConnectBtn
@onready var status_label: Label = $UI/StatusLabel
@onready var motd_label: Label = $UI/MotdLabel

var _intent: StringName = NetProtocol.INTENT_GUEST

## Set by Router.to_server_connect() when the player picked a row in the browser
## rather than coming here to type. They override the remembered server without
## erasing it — going BACK and picking a different row must not have quietly
## rewritten what was saved.
var prefill_address: String = ""
var prefill_port: int = 0
var prefill_name: String = ""


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.03, 0.06))
	_load_last()
	_apply_prefill()
	guest_btn.pressed.connect(_pick.bind(NetProtocol.INTENT_GUEST))
	login_btn.pressed.connect(_pick.bind(NetProtocol.INTENT_LOGIN))
	register_btn.pressed.connect(_pick.bind(NetProtocol.INTENT_REGISTER))
	connect_btn.pressed.connect(_on_connect)
	$UI/BackBtn.pressed.connect(_on_back)
	Net.link.state_changed.connect(_on_link_state)
	_pick(_intent)


func _exit_tree() -> void:
	if Net.link.state_changed.is_connected(_on_link_state):
		Net.link.state_changed.disconnect(_on_link_state)


func _apply_prefill() -> void:
	if prefill_address == "":
		return
	address_edit.text = prefill_address
	port_edit.text = str(prefill_port if prefill_port > 0 else NetProtocol.DEFAULT_PORT)
	if prefill_name != "":
		$UI/Title.text = prefill_name.to_upper()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()
	elif event.is_action_pressed(&"ui_accept") and not connect_btn.disabled:
		get_viewport().set_input_as_handled()
		_on_connect()


# ── The form ────────────────────────────────────────────────────────────────
func _pick(intent: StringName) -> void:
	_intent = intent
	guest_btn.button_pressed = intent == NetProtocol.INTENT_GUEST
	login_btn.button_pressed = intent == NetProtocol.INTENT_LOGIN
	register_btn.button_pressed = intent == NetProtocol.INTENT_REGISTER
	# A guest has no password to give, so the field is not merely ignored — it is
	# not there, and nobody types one wondering whether it did anything.
	$UI/PasswordRow.visible = intent != NetProtocol.INTENT_GUEST
	token_row.visible = intent == NetProtocol.INTENT_REGISTER and Net.link.token_required
	connect_btn.text = {
		NetProtocol.INTENT_GUEST: "CONNECT AS A GUEST",
		NetProtocol.INTENT_LOGIN: "LOG IN",
		NetProtocol.INTENT_REGISTER: "REGISTER AND CONNECT",
	}[intent]


func _on_connect() -> void:
	var player_name := name_edit.text.strip_edges()
	if player_name.length() < 3:
		_say("PICK A NAME OF AT LEAST THREE CHARACTERS")
		return
	if _intent != NetProtocol.INTENT_GUEST and password_edit.text.length() < 8:
		_say("PASSWORDS ARE AT LEAST EIGHT CHARACTERS")
		return
	Audio.play(&"ui_confirm")
	connect_btn.disabled = true
	_save_last()
	var err := Net.connect_to_server(address_edit.text.strip_edges(),
		int(port_edit.text), _intent, player_name, password_edit.text,
		token_edit.text.strip_edges())
	if err != OK:
		connect_btn.disabled = false
		_say("COULD NOT START CONNECTING (ERROR %d)" % err)


func _on_link_state(state: int, message: String) -> void:
	_say(message)
	motd_label.text = Net.link.motd
	motd_label.visible = Net.link.motd != ""
	match state:
		ServerLink.State.CONNECTED:
			# Remembered only now that it has worked. A browser full of addresses
			# somebody mistyped would be worse than an empty one.
			SavedServers.remember(address_edit.text.strip_edges(),
				int(port_edit.text), Net.link.server_name)
			Router.to_server_lobby()
		ServerLink.State.REFUSED:
			connect_btn.disabled = false
			# The server has now told us what it allows, so the form can stop
			# offering what it does not.
			_apply_server_rules()
		_:
			pass


func _apply_server_rules() -> void:
	if Net.link.server_name == "":
		return # never got as far as a HELLO
	guest_btn.disabled = Net.link.auth_mode == NetProtocol.AUTH_ACCOUNT
	register_btn.disabled = not Net.link.registration_open
	token_row.visible = _intent == NetProtocol.INTENT_REGISTER and Net.link.token_required


func _say(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


func _on_back() -> void:
	Net.leave()
	Router.to_multiplayer()


# ── Remembering the last server ─────────────────────────────────────────────
## Address, port and name only. A password is never written to disk here: this
## file sits in the user directory in plain text, and the whole point of the
## handshake is that the password does not leave the machine — writing it down
## would make that pointless.
func _save_last() -> void:
	var cf := ConfigFile.new()
	cf.set_value("server", "address", address_edit.text.strip_edges())
	cf.set_value("server", "port", int(port_edit.text))
	cf.set_value("server", "name", name_edit.text.strip_edges())
	cf.set_value("server", "intent", String(_intent))
	cf.save(LAST_SERVER_PATH)


func _load_last() -> void:
	var cf := ConfigFile.new()
	if cf.load(LAST_SERVER_PATH) != OK:
		return
	address_edit.text = cf.get_value("server", "address", "127.0.0.1")
	port_edit.text = str(cf.get_value("server", "port", NetProtocol.DEFAULT_PORT))
	name_edit.text = cf.get_value("server", "name", "")
	_intent = StringName(cf.get_value("server", "intent", NetProtocol.INTENT_GUEST))

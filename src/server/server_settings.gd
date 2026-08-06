class_name ServerSettings
extends RefCounted
## Every knob a dedicated server has, in one list, with the value store under it.
##
## Adding a setting is one line in `_declare()`. That single fact is what makes
## the rest of the server small: the console's `set`/`get`/`config` commands, the
## settings tab of the in-game admin panel, the validation, the generated
## `server.cfg` with its comments, and the permission check on who may change
## what are all *derived* from this list. None of them has a hard-coded field
## anywhere, so none of them can fall behind it.
##
## Values live in `server.cfg`, an ordinary INI. It is written back with the
## description of each key as a comment above it, so the file an operator opens
## explains itself without the documentation being open next to it. Unknown keys
## in the file are kept, reported once at boot and never silently dropped — a
## typo should be visible, and a key from a newer build should survive a
## downgrade.
##
## See SettingDef for why the schema is code and the values are a text file.

signal changed(key: String, value: Variant)

const FILE_NAME := "server.cfg"

## Which program these settings are for. Two builds of this project take
## configuration: the game server, and the directory that lists game servers.
## They share the identity, logging and storage sections and share nothing else,
## and declaring both sets in both would leave every operator with a file two
## thirds of which does nothing — which is how a settings file stops being read.
enum Profile {GAME, DIRECTORY}

## key -> SettingDef, in declaration order (Dictionary preserves insertion).
var defs: Dictionary[String, SettingDef] = {}
var profile: int = Profile.GAME
var values: Dictionary[String, Variant] = {}
## Keys found in the file that this build does not know about. Reported at boot
## and written back out untouched.
var unknown: Dictionary[String, Variant] = {}
## Where server.cfg was read from and will be written to.
var path: String = ""


func _init(which: int = Profile.GAME) -> void:
	profile = which
	_declare()
	for key in defs:
		values[key] = defs[key].default_value


# ── The list ────────────────────────────────────────────────────────────────
func _declare() -> void:
	_identity()
	if profile == Profile.DIRECTORY:
		_listing()
		_logging()
		_storage()
		return
	_game_identity()
	_network()
	_auth()
	_rooms()
	_moderation()
	_protection()
	_directory()
	_performance()
	_logging()
	_remote()
	_storage()


func _identity() -> void:
	_add(SettingDef.make("server/name", TYPE_STRING, "The PIT",
		"Shown in the client's server browser and in every log line."))
	_add(SettingDef.make("server/description", TYPE_STRING, "",
		"One or two lines about this server, shown next to its name."))
	_add(SettingDef.make("server/contact", TYPE_STRING, "",
		"How to reach whoever runs this server. Shown to a banned player."))


func _game_identity() -> void:
	_add(SettingDef.make("server/motd", TYPE_STRING,
		"Climb out. Mind the drones.",
		"Message of the day, shown once when a player finishes connecting."))
	_add(SettingDef.make("server/public_address", TYPE_STRING, "",
		"The hostname players actually type, e.g. play.example.com. Used for "
		+ "logs, the status endpoint and the server browser; it does not affect "
		+ "what is listened on. Left empty, a directory falls back to the "
		+ "address your announce arrived from, which is right unless you are "
		+ "behind a tunnel or want players to see a name rather than a number."))
	_add(SettingDef.make("server/tags", TYPE_STRING, "",
		"Comma-separated labels for the server browser, e.g. 'coop,eu,modded'."))
	_add(SettingDef.make("server/region", TYPE_STRING, "",
		"Where this server physically is, e.g. 'EU' or 'Moscow'. Shown in the "
		+ "browser so a player can guess the latency before connecting."))


func _network() -> void:
	_add(SettingDef.make("network/bind_address", TYPE_STRING, "*",
		"Interface to listen on. '*' is every interface; 127.0.0.1 is local only.")
		.needs_restart())
	_add(SettingDef.make("network/port", TYPE_INT, NetProtocol.DEFAULT_PORT,
		"UDP port. This is the one port that has to be reachable from outside.")
		.with_range(1, 65535).needs_restart())
	_add(SettingDef.make("network/max_players", TYPE_INT, 64,
		"Hard ceiling on simultaneous connections, across all rooms.")
		.with_range(1, 512).needs_restart())
	_add(SettingDef.make("network/max_peers_per_ip", TYPE_INT, 3,
		"Connections allowed from one address. 0 removes the limit. The cheapest "
		+ "defence there is against somebody opening a thousand sockets.")
		.with_range(0, 64))
	_add(SettingDef.make("network/joins_per_minute", TYPE_INT, 60,
		"New connections accepted per minute before the rest are refused.")
		.with_range(0, 6000))
	_add(SettingDef.make("network/auth_timeout_seconds", TYPE_FLOAT, 20.0,
		"How long a connection may stay in the handshake before it is dropped.")
		.with_range(3.0, 120.0))
	_add(SettingDef.make("network/relay_between_clients", TYPE_BOOL, false,
		"Whether clients may send packets to each other THROUGH this server. Off "
		+ "means every message a client sends is one this server validated.")
		.needs_restart())
	_add(SettingDef.make("network/max_packet_size", TYPE_INT, 1400,
		"Largest replication packet, in bytes. Above the path MTU it fragments.")
		.with_range(256, 65536))
	_add(SettingDef.make("network/upnp", TYPE_BOOL, false,
		"Ask the router to forward the port on startup. For a server behind a "
		+ "home router; useless and slow in a data centre.").needs_restart())


func _auth() -> void:
	_add(SettingDef.make("auth/mode", TYPE_STRING, "guest",
		"open: anybody, no name check. guest: a name, remembered for the session "
		+ "only. account: a registered name and password.")
		.with_choices(["open", "guest", "account"]))
	_add(SettingDef.make("auth/allow_registration", TYPE_BOOL, true,
		"Whether new accounts may be created from the game. With it off, "
		+ "'account register' on the console is the only way in."))
	_add(SettingDef.make("auth/registration_token", TYPE_STRING, "",
		"When set, registering also requires this token. An invite code.").as_secret())
	_add(SettingDef.make("auth/min_password_length", TYPE_INT, 8,
		"Refused below this. The check is on the client and again here.")
		.with_range(1, 128))
	_add(SettingDef.make("auth/name_min_length", TYPE_INT, 3,
		"").with_range(1, 32))
	_add(SettingDef.make("auth/name_max_length", TYPE_INT, 16,
		"Long names break every list the game prints.").with_range(3, 64))
	_add(SettingDef.make("auth/pbkdf2_iterations", TYPE_INT, NetCrypto.DEFAULT_ITERATIONS,
		"Password hashing cost. Raise it as machines get faster; existing "
		+ "accounts keep the count they were created with and are upgraded on "
		+ "their next login.").with_range(NetCrypto.MIN_ITERATIONS, 1000000))
	_add(SettingDef.make("auth/logins_per_minute", TYPE_INT, 10,
		"Failed logins allowed from one address per minute.").with_range(1, 600))
	_add(SettingDef.make("auth/session_hours", TYPE_FLOAT, 72.0,
		"How long a reconnect token stays valid, so a player who drops out comes "
		+ "back without typing a password.").with_range(0.0, 8760.0))
	_add(SettingDef.make("auth/guest_prefix", TYPE_STRING, "guest_",
		"Prepended to a guest's chosen name, so a guest can never be mistaken "
		+ "for a registered account."))
	_add(SettingDef.make("auth/reserved_names", TYPE_STRING, "server,console,admin,system",
		"Comma-separated names nobody may register or use as a guest."))
	_add(SettingDef.make("auth/first_account_is_owner", TYPE_BOOL, true,
		"The first account ever registered becomes the owner. Saves an operator "
		+ "having to op themselves from the console on a fresh install."))


func _rooms() -> void:
	_add(SettingDef.make("rooms/max_rooms", TYPE_INT, 8,
		"How many rooms may exist at once. Every running room is a full pit "
		+ "being simulated at 120 Hz — see docs/SERVER.md on capacity.")
		.with_range(1, 64))
	_add(SettingDef.make("rooms/players_may_create", TYPE_BOOL, true,
		"Whether an ordinary player may open a room, or only staff."))
	_add(SettingDef.make("rooms/rooms_per_player", TYPE_INT, 1,
		"How many rooms one account may own at a time.").with_range(1, 16))
	_add(SettingDef.make("rooms/default_mode", TYPE_STRING, "coop",
		"The mode a new room starts with.").with_choices(["coop", "race"]))
	_add(SettingDef.make("rooms/default_max_players", TYPE_INT, 8,
		"Seats in a new room.").with_range(1, 32))
	_add(SettingDef.make("rooms/max_players_ceiling", TYPE_INT, 16,
		"The largest a room may be set to, whoever is setting it.")
		.with_range(1, 64))
	_add(SettingDef.make("rooms/allow_passwords", TYPE_BOOL, true,
		"Whether a room may be made private with a password."))
	_add(SettingDef.make("rooms/empty_close_seconds", TYPE_FLOAT, 120.0,
		"A room with nobody in it closes after this. 0 keeps it forever, which "
		+ "is what persistent rooms are for.").with_range(0.0, 86400.0))
	_add(SettingDef.make("rooms/idle_close_seconds", TYPE_FLOAT, 0.0,
		"A room whose players have not moved for this long closes. 0 is off.")
		.with_range(0.0, 86400.0))
	_add(SettingDef.make("rooms/end_to_lobby_seconds", TYPE_FLOAT, 20.0,
		"How long the end screen stays up before the room returns to its lobby.")
		.with_range(0.0, 600.0))
	_add(SettingDef.make("rooms/name_max_length", TYPE_INT, 28,
		"").with_range(4, 64))
	_add(SettingDef.make("rooms/who_may_start", TYPE_STRING, "owner",
		"owner: whoever opened the room. anyone: any player in it. staff: only "
		+ "a moderator or above.").with_choices(["owner", "anyone", "staff"]))
	_add(SettingDef.make("rooms/who_may_restart", TYPE_STRING, "owner",
		"Same choices, for restarting a finished run.")
		.with_choices(["owner", "anyone", "staff"]))
	_add(SettingDef.make("rooms/spectators_count_to_limit", TYPE_BOOL, false,
		"Whether somebody who joined to watch takes one of the seats."))


func _moderation() -> void:
	_add(SettingDef.make("moderation/chat", TYPE_BOOL, true,
		"Chat, in the room lobby and during a run. Turning it off also removes "
		+ "the reason mute exists."))
	_add(SettingDef.make("moderation/chat_max_length", TYPE_INT, 200,
		"Longer messages are cut, not refused.").with_range(16, 2000))
	_add(SettingDef.make("moderation/chat_per_10s", TYPE_INT, 6,
		"Messages one player may send per ten seconds.").with_range(1, 100))
	_add(SettingDef.make("moderation/chat_history", TYPE_INT, 80,
		"How many past messages a player sees on entering a room, and how many "
		+ "are kept for staff to read.").with_range(0, 1000))
	_add(SettingDef.make("moderation/word_filter", TYPE_STRING, "",
		"Comma-separated words to act on. Matching ignores case."))
	_add(SettingDef.make("moderation/word_filter_action", TYPE_STRING, "mask",
		"mask: replace with asterisks. block: drop the message and tell the "
		+ "sender. warn: deliver it and raise a warning against the sender.")
		.with_choices(["mask", "block", "warn"]))
	_add(SettingDef.make("moderation/default_mute_minutes", TYPE_FLOAT, 10.0,
		"Used when a mute is issued without a duration. 0 means until lifted.")
		.with_range(0.0, 525600.0))
	_add(SettingDef.make("moderation/default_ban_minutes", TYPE_FLOAT, 0.0,
		"Used when a ban is issued without a duration. 0 is permanent.")
		.with_range(0.0, 525600.0))
	_add(SettingDef.make("moderation/warnings_before_kick", TYPE_INT, 3,
		"Warnings that add up to an automatic kick. 0 disables it.")
		.with_range(0, 100))
	_add(SettingDef.make("moderation/ban_evasion_by_ip", TYPE_BOOL, true,
		"Whether banning an account also refuses the address it last used. "
		+ "Catches the obvious evasion and punishes shared connections, which "
		+ "is the trade — see docs/SERVER.md."))
	_add(SettingDef.make("moderation/log_chat", TYPE_BOOL, true,
		"Whether chat goes into the server log as well as the room."))
	_add(SettingDef.make("moderation/staff_see_all_rooms", TYPE_BOOL, true,
		"Whether a moderator's admin panel lists players in every room or only "
		+ "the one they are in."))


func _protection() -> void:
	_add(SettingDef.make("protection/enforce_build_match", TYPE_BOOL, true,
		"Refuse a client whose protocol version or content fingerprint differs "
		+ "from this build's. Turning this off is how a desync becomes somebody "
		+ "falling through a platform that is not there. Only ever for testing.")
		)
	_add(SettingDef.make("protection/movement_guard", TYPE_STRING, "log",
		"What to do about an avatar reporting a position it cannot have reached. "
		+ "off / log / warn / kick. Movement is client-authoritative by design "
		+ "(see docs/NETWORKING.md), so this is a tripwire, not a wall.")
		.with_choices(["off", "log", "warn", "kick"]))
	_add(SettingDef.make("protection/max_speed_factor", TYPE_FLOAT, 1.8,
		"Multiple of the fastest legal speed a climber can reach. Below about "
		+ "1.5 a dash down a long shaft trips it.").with_range(1.0, 20.0))
	_add(SettingDef.make("protection/max_step_px", TYPE_FLOAT, 1200.0,
		"Biggest jump in position between two reports that is not a teleport. "
		+ "Lag makes this larger than physics alone would suggest.")
		.with_range(100.0, 100000.0))
	_add(SettingDef.make("protection/bounds_slack_px", TYPE_FLOAT, 3000.0,
		"How far outside the pit an avatar may be before it is a violation.")
		.with_range(0.0, 100000.0))
	_add(SettingDef.make("protection/violations_before_action", TYPE_INT, 8,
		"Violations inside the decay window before the action above is taken.")
		.with_range(1, 1000))
	_add(SettingDef.make("protection/violation_decay_seconds", TYPE_FLOAT, 30.0,
		"How long a violation is remembered.").with_range(1.0, 3600.0))
	_add(SettingDef.make("protection/messages_per_second", TYPE_INT, 90,
		"Client-to-server messages allowed per second, per peer, sustained.")
		.with_range(5, 10000))
	_add(SettingDef.make("protection/message_burst", TYPE_INT, 180,
		"How far a peer may run ahead of that rate before it is refused.")
		.with_range(5, 20000))
	_add(SettingDef.make("protection/kick_on_flood", TYPE_BOOL, true,
		"Whether a peer that keeps exceeding the rate is disconnected rather "
		+ "than merely ignored."))
	_add(SettingDef.make("protection/max_name_length", TYPE_INT, 24,
		"Applies to room names and chat display names alike.").with_range(4, 64))


## How this server is FOUND. Two ways, and they are independent: a directory
## on the internet that a player's browser reads, and a beacon that answers a
## probe on the local network. A server with both off is still perfectly
## playable — players type its address, which is how every server worked before
## the browser existed.
func _directory() -> void:
	_add(SettingDef.make("directory/announce", TYPE_BOOL, false,
		"Tell a directory about this server, so it appears in the in-game "
		+ "browser. Off by default: being listed is a decision, not a default."))
	_add(SettingDef.make("directory/url", TYPE_STRING, "",
		"Base URL of the directory to announce to, e.g. https://list.example.com. "
		+ "Empty uses the one the game ships with."))
	_add(SettingDef.make("directory/interval_seconds", TYPE_FLOAT, 60.0,
		"How often to announce. The directory stops listing a server that has "
		+ "gone quiet, so this is also how quickly a crashed server disappears.")
		.with_range(15.0, 3600.0))
	_add(SettingDef.make("directory/verify_id", TYPE_STRING, "",
		"The public half of a verification key, if the developer issued you one. "
		+ "It is what puts the badge next to this server's name."))
	_add(SettingDef.make("directory/verify_key", TYPE_STRING, "",
		"The secret half. It NEVER leaves this machine: it signs the announce, "
		+ "and the directory checks the signature. Treat it like a password.")
		.as_secret())
	_add(SettingDef.make("directory/lan_beacon", TYPE_BOOL, true,
		"Answer discovery probes on the local network, so players on the same "
		+ "network find this server without typing an address or being listed "
		+ "anywhere. Costs one UDP packet per probe and nothing when idle."))
	_add(SettingDef.make("directory/lan_port", TYPE_INT, DirectoryProtocol.LAN_PORT,
		"The port the beacon listens on. Only one process per machine can hold "
		+ "it — change this on the second server on one box, and note that the "
		+ "browser only probes a few ports either side of the default.")
		.with_range(1, 65535).needs_restart())


## The directory service's own settings. Only declared in that profile — see
## Profile above.
func _listing() -> void:
	_add(SettingDef.make("listing/bind_address", TYPE_STRING, "0.0.0.0",
		"Interface the HTTP endpoint listens on. Set it to 127.0.0.1 when "
		+ "something in front of it (nginx, Caddy) is doing TLS.").needs_restart())
	_add(SettingDef.make("listing/port", TYPE_INT, 24570,
		"TCP port for GET /v1/servers and POST /v1/announce.")
		.with_range(1, 65535).needs_restart())
	_add(SettingDef.make("listing/public_url", TYPE_STRING, "",
		"What this directory tells operators to point their servers at. Printed "
		+ "at boot and by the 'status' command; it changes nothing."))
	_add(SettingDef.make("listing/trust_forwarded", TYPE_BOOL, false,
		"Read the announcing address out of X-Forwarded-For. Turn this on ONLY "
		+ "when a proxy you control is in front: any client can send that "
		+ "header, so trusting it on an exposed port trusts a stranger."))
	_add(SettingDef.make("listing/stale_seconds", TYPE_INT, 150,
		"A server that has not announced for this long stops being listed. It "
		+ "should be comfortably more than an announcing server's interval.")
		.with_range(30, 86400))
	_add(SettingDef.make("listing/forget_seconds", TYPE_INT, 86400,
		"And is dropped from the table entirely after this.")
		.with_range(60, 2592000))
	_add(SettingDef.make("listing/bind_keys_on_first_use", TYPE_BOOL, true,
		"Tie a verification key to the address it is first used from. Without "
		+ "it, whoever holds the secret can badge any server they like — with "
		+ "it, a leaked or handed-on key stops working the moment it is used "
		+ "somewhere else. Undo one binding with 'key bind <id> -'."))
	_add(SettingDef.make("listing/require_key", TYPE_BOOL, false,
		"List only servers holding a verification key. Turns the directory into "
		+ "a curated list rather than an open one."))
	_add(SettingDef.make("listing/max_servers", TYPE_INT, 500,
		"Ceiling on listed servers. A new one past it is refused rather than "
		+ "evicting somebody who was there first.").with_range(1, 100000))
	_add(SettingDef.make("listing/max_per_address", TYPE_INT, 4,
		"How many servers one address may list. The cheapest defence against "
		+ "one machine filling the browser.").with_range(1, 256))
	_add(SettingDef.make("listing/announce_per_minute", TYPE_INT, 20,
		"Announces accepted from one address per minute.").with_range(1, 6000))
	_add(SettingDef.make("listing/blocked", TYPE_STRING, "",
		"Comma-separated addresses that are never listed, whatever they claim."))
	_add(SettingDef.make("listing/max_request_bytes", TYPE_INT, 32768,
		"Largest HTTP request accepted before the connection is dropped.")
		.with_range(1024, 1048576))
	_add(SettingDef.make("listing/max_pending", TYPE_INT, 32,
		"Connections that may be mid-request at once. A socket opened and left "
		+ "silent is the cheapest denial of service there is; this is the limit "
		+ "on how many of them can be waiting.").with_range(1, 1024))
	_add(SettingDef.make("listing/request_timeout_seconds", TYPE_FLOAT, 8.0,
		"And how long one may take before it is closed.").with_range(1.0, 120.0))


func _performance() -> void:
	_add(SettingDef.make("performance/hibernate_empty_rooms", TYPE_BOOL, true,
		"An empty room stops being stepped at all until somebody joins."))
	_add(SettingDef.make("performance/max_fps", TYPE_INT, 60,
		"The server's frame rate. Physics is fixed at 120 Hz whatever this says "
		+ "— the pit's determinism depends on that and it is not tunable.")
		.with_range(10, 600))
	_add(SettingDef.make("performance/frame_warn_ms", TYPE_FLOAT, 14.0,
		"A frame longer than this is logged once per burst. The first sign that "
		+ "the box is carrying more rooms than it can.").with_range(1.0, 1000.0))
	_add(SettingDef.make("performance/status_interval_seconds", TYPE_FLOAT, 300.0,
		"How often a one-line summary goes into the log. 0 is off.")
		.with_range(0.0, 86400.0))


func _logging() -> void:
	_add(SettingDef.make("log/level", TYPE_STRING, "info",
		"trace / debug / info / warn / error.")
		.with_choices(["trace", "debug", "info", "warn", "error"]))
	_add(SettingDef.make("log/to_file", TYPE_BOOL, true,
		"Whether the log is also written to storage/dir/logs."))
	_add(SettingDef.make("log/max_files", TYPE_INT, 10,
		"Rotated log files kept.").with_range(1, 1000))
	_add(SettingDef.make("log/max_size_mb", TYPE_FLOAT, 16.0,
		"Size at which the log rotates.").with_range(0.1, 4096.0))
	_add(SettingDef.make("log/colour", TYPE_BOOL, true,
		"ANSI colour on stdout. Turn it off when piping to a file or a service "
		+ "manager that does not understand escape codes."))


func _remote() -> void:
	_add(SettingDef.make("rcon/enabled", TYPE_BOOL, false,
		"A TCP remote console speaking the same commands as stdin.").needs_restart())
	_add(SettingDef.make("rcon/bind_address", TYPE_STRING, "127.0.0.1",
		"Default is local only ON PURPOSE. Exposing rcon to the internet means "
		+ "one password stands between a stranger and every command there is; "
		+ "put it behind an SSH tunnel instead.").needs_restart())
	_add(SettingDef.make("rcon/port", TYPE_INT, 24566, "")
		.with_range(1, 65535).needs_restart())
	_add(SettingDef.make("rcon/password", TYPE_STRING, "",
		"Empty means rcon refuses every connection, whatever 'enabled' says.")
		.as_secret())
	_add(SettingDef.make("rcon/max_sessions", TYPE_INT, 4, "").with_range(1, 64))
	_add(SettingDef.make("rcon/idle_timeout_seconds", TYPE_FLOAT, 300.0,
		"An authenticated session with nothing to say is closed.")
		.with_range(10.0, 86400.0))
	_add(SettingDef.make("status/enabled", TYPE_BOOL, false,
		"A read-only TCP port that answers one line of JSON: who is up, how many "
		+ "players, which rooms. For uptime monitoring and server browsers.")
		.needs_restart())
	_add(SettingDef.make("status/bind_address", TYPE_STRING, "0.0.0.0", "")
		.needs_restart())
	_add(SettingDef.make("status/port", TYPE_INT, 24567, "")
		.with_range(1, 65535).needs_restart())
	_add(SettingDef.make("status/show_player_names", TYPE_BOOL, false,
		"Whether the status answer names the players. Off by default: who is "
		+ "playing right now is not something an anonymous port should tell."))


func _storage() -> void:
	# The two programs must not share a directory: they write different files
	# under the same names (server.cfg above all) and would overwrite each
	# other's. Different defaults so that running both on one box needs no
	# thought, and --data when somebody wants them somewhere else.
	_add(SettingDef.make("storage/dir", TYPE_STRING,
		"./directory-data" if profile == Profile.DIRECTORY else "./server-data",
		"Where this program's data and logs are kept. Relative paths are "
		+ "resolved against the folder the program lives in, not the working "
		+ "directory.").needs_restart())
	_add(SettingDef.make("storage/save_interval_seconds", TYPE_FLOAT, 30.0,
		"How often changed data is flushed. Every write is atomic, so a crash "
		+ "loses at most this much, never the file.").with_range(1.0, 3600.0))
	_add(SettingDef.make("storage/backups", TYPE_INT, 3,
		"Copies of the account and ban files kept before each rewrite.")
		.with_range(0, 100))


func _add(def: SettingDef) -> void:
	defs[def.key] = def


# ── Reading and writing ─────────────────────────────────────────────────────
func has(key: String) -> bool:
	return defs.has(key)


func get_value(key: String) -> Variant:
	return values.get(key, defs[key].default_value if defs.has(key) else null)


func get_int(key: String) -> int:
	return int(get_value(key))


func get_float(key: String) -> float:
	return float(get_value(key))


func get_bool(key: String) -> bool:
	return bool(get_value(key))


func get_text(key: String) -> String:
	return str(get_value(key))


## Comma-separated setting to a clean list, lower-cased and de-blanked. Four
## settings are lists and none of them should each parse their own.
func get_list(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	for piece in get_text(key).split(",", false):
		var trimmed := piece.strip_edges().to_lower()
		if trimmed != "":
			out.append(trimmed)
	return out


## Set from text, with the setting's own validation. Returns "" on success or
## the reason it was refused. The single entry point for the console, rcon and
## the admin panel — so all three refuse the same things for the same words.
func set_from_text(key: String, text: String) -> String:
	if not defs.has(key):
		return "no such setting: %s" % key
	var parsed: Array = defs[key].parse(text)
	if not parsed[0]:
		return "%s: %s" % [key, parsed[2]]
	values[key] = parsed[1]
	changed.emit(key, parsed[1])
	return ""


## Keys whose section or name contains `needle`, in declaration order.
func search(needle: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lowered := needle.to_lower()
	for key in defs:
		if lowered == "" or key.to_lower().contains(lowered):
			out.append(key)
	return out


func sections() -> PackedStringArray:
	var out := PackedStringArray()
	for key in defs:
		var section := defs[key].section()
		if not out.has(section):
			out.append(section)
	return out


# ── server.cfg ──────────────────────────────────────────────────────────────
## Read the file if it is there. Returns the problems found, as lines to log —
## never throws and never refuses to boot over a bad value, because a server
## that will not start is worse than one running a default it announced.
func load_from(dir_path: String) -> PackedStringArray:
	path = dir_path.path_join(FILE_NAME)
	var problems := PackedStringArray()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return problems # first boot: everything is the default, and save() writes it
	for section in cf.get_sections():
		for leaf in cf.get_section_keys(section):
			var key := "%s/%s" % [section, leaf]
			var raw: Variant = cf.get_value(section, leaf)
			if not defs.has(key):
				unknown[key] = raw
				problems.append("unknown setting kept as-is: %s" % key)
				continue
			var problem := set_from_text(key, str(raw))
			if problem != "":
				problems.append("%s — using the default (%s)"
					% [problem, str(defs[key].default_value)])
				values[key] = defs[key].default_value
	return problems


## Write every setting back, with its description as a comment. Called on first
## boot (so a fresh install leaves behind a documented file) and whenever a
## setting changes, so that what is on disk is what is running.
func save_to(dir_path: String = "") -> Error:
	if dir_path != "":
		path = dir_path.path_join(FILE_NAME)
	if path == "":
		return ERR_UNCONFIGURED
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := _render()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


## Rendered by hand rather than through ConfigFile.save() for one reason: a
## comment. ConfigFile cannot write them, and a settings file that does not say
## what its settings do is a settings file people guess at.
func _render() -> String:
	var lines := PackedStringArray([
		"; %s — dedicated server configuration." % ProjectSettings.get_setting(
			"application/config/name", "The PIT"),
		"; Generated with every value this build knows about; edit and restart,",
		"; or change it live from the console with:  set <key> <value>",
		"; Keys marked (restart) are only read at startup.",
		"",
	])
	var current := ""
	for key in defs:
		var def: SettingDef = defs[key]
		if def.section() != current:
			current = def.section()
			lines.append("[%s]" % current)
			lines.append("")
		if def.description != "":
			for wrapped in _wrap(def.description, 74):
				lines.append("; %s" % wrapped)
		if not def.choices.is_empty():
			lines.append("; one of: %s" % ", ".join(def.choices))
		if def.requires_restart:
			lines.append("; (restart)")
		lines.append("%s = %s" % [def.leaf(), _literal(values[key])])
		lines.append("")
	if not unknown.is_empty():
		lines.append("; Kept from the previous file: this build has no such settings.")
		lines.append("; They may belong to a newer version — they are not deleted.")
		for key in unknown:
			lines.append("; %s = %s" % [key, str(unknown[key])])
	return "\n".join(lines) + "\n"


func _literal(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return '"%s"' % String(value).replace('"', '\\"')
	if typeof(value) == TYPE_BOOL:
		return "true" if value else "false"
	return str(value)


func _wrap(text: String, width: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		if line != "" and line.length() + word.length() + 1 > width:
			out.append(line)
			line = ""
		line += (" " if line != "" else "") + word
	if line != "":
		out.append(line)
	return out

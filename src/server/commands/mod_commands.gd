class_name ModCommands
extends Object
## Who is here, and the verbs for doing something about them.
##
## The commands parse and report; `Moderation` decides. That split is why the
## rank rule ("you cannot act on somebody at or above you") is written once and
## cannot be forgotten by the fourth command that needs it.

static func install(server: PitServer, reg: CommandRegistry) -> void:
	_listing(server, reg)
	_removal(server, reg)
	_silencing(server, reg)
	_bans(server, reg)


static func _listing(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("players", "players",
		"everybody connected, and where they are",
		Permissions.PLAYER_LIST,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			if server.peers.is_empty():
				caller.say("nobody is connected")
				return
			var detailed := caller.may(Permissions.PLAYER_INSPECT)
			for peer_id in server.peers:
				var peer: ServerPeer = server.peers[peer_id]
				var where := "lobby" if peer.room_id == 0 else "room %d" % peer.room_id
				var extra := "  %s" % peer.address if detailed else ""
				caller.row("%s%s" % [peer.name_text(),
					" (%s)" % peer.account.role if peer.account != null
						and peer.account.role != Permissions.ROLE_PLAYER else ""],
					"%s%s%s" % [where, "  MUTED" if peer.account != null
						and peer.account.is_muted() else "", extra], 24)
			caller.say("")
			caller.say("%d connected" % server.peers.size())
	).with_aliases(["list", "who"]).read_only())

	reg.add(ServerCommand.make("player", "player <name>",
		"everything known about one connected player",
		Permissions.PLAYER_INSPECT,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var peer := server.find_peer(args[0])
			if peer == null:
				caller.fail("nobody connected is called '%s' (or the name is "
					% args[0] + "ambiguous — type more of it)")
				return
			_describe(server, caller, peer)
	).with_args(1, 1).read_only())


static func _describe(server: PitServer, caller: CommandCaller, peer: ServerPeer) -> void:
	var account := peer.account
	caller.say(peer.name_text())
	caller.row("peer", str(peer.peer_id))
	caller.row("address", peer.address)
	caller.row("room", "lobby" if peer.room_id == 0 else str(peer.room_id))
	caller.row("connected for", "%ds" % int(Time.get_ticks_msec() / 1000.0
		- peer.connected_at))
	if account == null:
		return
	caller.row("account", "%s%s" % [account.name, "  (guest)" if account.guest else ""])
	caller.row("role", account.role)
	caller.row("muted", "yes" if account.is_muted() else "no")
	caller.row("warnings", str(account.warnings + peer.session_warnings))
	caller.row("movement violations", str(peer.violations))
	if not account.guest:
		caller.row("best score", str(account.best_score))
		caller.row("runs / kills", "%d / %d" % [account.runs, account.kills])
		caller.row("first seen", Time.get_datetime_string_from_unix_time(
			account.created_at, true))
	if account.note != "":
		caller.row("note", account.note)
	var ban := server.bans.check(account.id, peer.address)
	if not ban.is_empty():
		caller.row("BANNED", BanList.describe(ban))


static func _removal(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("kick", "kick <name> [reason...]",
		"disconnect somebody; they may come straight back",
		Permissions.PLAYER_KICK,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var peer := server.find_peer(args[0])
			var problem := server.moderation.kick(caller, peer, " ".join(args.slice(1)))
			if problem != "":
				caller.fail(problem)
			else:
				caller.say("%s was removed" % peer.name_text())
	).with_args(1))

	reg.add(ServerCommand.make("move", "move <name> <room id>",
		"put somebody in another room, password or not",
		Permissions.PLAYER_MOVE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var peer := server.find_peer(args[0])
			var problem := server.moderation.move(caller, peer, args[1].to_int())
			if problem != "":
				caller.fail(problem)
			else:
				caller.say("%s is now in room %s" % [peer.name_text(), args[1]])
	).with_args(2, 2))

	reg.add(ServerCommand.make("warn", "warn <name> <reason...>",
		"a warning; enough of them removes the player",
		Permissions.PLAYER_WARN,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var peer := server.find_peer(args[0])
			var problem := server.moderation.warn(caller, peer, " ".join(args.slice(1)))
			if problem != "":
				caller.fail(problem)
			else:
				caller.say("warned %s" % peer.name_text())
	).with_args(2).with_detail(
		"`moderation/warnings_before_kick` says how many add up to a removal. A "
		+ "guest's warnings last only as long as their connection — run the "
		+ "server in `account` mode if warnings are to mean anything."))


static func _silencing(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("mute", "mute <name> [minutes] [reason...]",
		"stop somebody talking; 0 minutes is until lifted",
		Permissions.PLAYER_MUTE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var peer := server.find_peer(args[0])
			var parsed := _duration(server, args, 1, "moderation/default_mute_minutes")
			var problem := server.moderation.mute(caller, peer, parsed[0], parsed[1])
			if problem != "":
				caller.fail(problem)
			else:
				caller.say("%s is muted %s" % [peer.name_text(),
					"until it is lifted" if parsed[0] <= 0.0
					else "for %g minutes" % parsed[0]])
	).with_args(1))

	reg.add(ServerCommand.make("unmute", "unmute <name>",
		"let somebody speak again",
		Permissions.PLAYER_MUTE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var problem := server.moderation.unmute(caller, server.find_peer(args[0]))
			if problem != "":
				caller.fail(problem)
			else:
				caller.say("unmuted")
	).with_args(1, 1))


static func _bans(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("ban", "ban <name> [minutes] [reason...]",
		"remove and refuse; 0 minutes is permanent",
		Permissions.PLAYER_BAN,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_do_ban(server, caller, args)
	).with_args(1).with_detail(
		"Works on a connected player by name, and on an account that has "
		+ "already left. Whether the ban also refuses the address they last "
		+ "used is `moderation/ban_evasion_by_ip` — it catches the obvious "
		+ "evasion and also catches everybody else behind that address, which "
		+ "is a trade docs/SERVER.md spells out."))

	reg.add(ServerCommand.make("ban address", "ban address <ip> [minutes] [reason...]",
		"refuse an address outright",
		Permissions.PLAYER_BAN,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var parsed := _duration(server, args, 1, "moderation/default_ban_minutes")
			server.bans.add(args[0], BanList.KIND_ADDRESS, parsed[1],
				caller.label, parsed[0])
			server.bans.save()
			caller.say("%s is refused" % args[0])
	).with_args(1))

	reg.add(ServerCommand.make("unban", "unban <name or address>",
		"lift a ban",
		Permissions.PLAYER_UNBAN,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var problem := server.moderation.unban(caller, args[0])
			if problem != "":
				caller.fail(problem)
			else:
				caller.say("%s may connect again" % args[0])
	).with_args(1, 1))

	reg.add(ServerCommand.make("bans", "bans",
		"every ban in force",
		Permissions.PLAYER_UNBAN,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			var all := server.bans.all()
			if all.is_empty():
				caller.say("nobody is banned")
				return
			for entry in all:
				caller.say("  %s" % BanList.describe(entry))
			caller.say("")
			caller.say("%d in force" % all.size())
	).read_only())


static func _do_ban(server: PitServer, caller: CommandCaller,
		args: PackedStringArray) -> void:
	var parsed := _duration(server, args, 1, "moderation/default_ban_minutes")
	var peer := server.find_peer(args[0])
	var problem := ""
	if peer != null:
		problem = server.moderation.ban(caller, peer, parsed[1], parsed[0])
	else:
		problem = server.moderation.ban_absent(caller, args[0], parsed[1], parsed[0])
	if problem != "":
		caller.fail(problem)
		return
	caller.say("%s is banned %s" % [args[0],
		"permanently" if parsed[0] <= 0.0 else "for %g minutes" % parsed[0]])


## `<name> [minutes] [reason...]` is the shape of four commands, and the minutes
## are optional in the middle of it. Returns [minutes, reason].
static func _duration(server: PitServer, args: PackedStringArray, at: int,
		default_key: String) -> Array:
	if args.size() > at and args[at].is_valid_float():
		return [args[at].to_float(), " ".join(args.slice(at + 1))]
	return [server.settings.get_float(default_key), " ".join(args.slice(at))]

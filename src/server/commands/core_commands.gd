class_name CoreCommands
extends Object
## The server's own commands: status, settings, log, shutdown.
##
## Every handler is a closure over the server, which is what lets the same
## command object be run by the operator at the keyboard, over the remote
## console, and from the admin panel inside the game with a permission check in
## front of it. See CommandRegistry.
##
## Help, the settings editor, the log and `stop` are not here: they are in
## CommonCommands, because the directory service has a console too and those four
## must behave identically in both.

static func install(server: PitServer, reg: CommandRegistry) -> void:
	CommonCommands.install_help(reg)
	CommonCommands.install_settings(reg, server.settings, server.storage_dir,
		func() -> void:
			server.accounts.save()
			server.bans.save())
	CommonCommands.install_log(reg, server.logger)
	CommonCommands.install_stop(reg, server.shutdown)
	_status(server, reg)
	_announcements(server, reg)


static func _status(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("status", "status",
		"players, rooms, uptime",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			caller.say(server.status_line())
			caller.row("build", NetProtocol.build_id())
			caller.row("listening", "%s:%d" % [
				server.settings.get_text("network/bind_address"),
				server.settings.get_int("network/port")])
			caller.row("authentication", server.settings.get_text("auth/mode"))
			caller.row("storage", server.storage_dir)
			caller.row("handshakes in progress", str(server.auth.pending_count()))
			caller.row("remote console sessions", str(server.rcon.session_count()))
			caller.row("identity", server.instance_id())
			caller.row("server list", server.directory.last_result)
			caller.row("local network", "answering probes on UDP %d"
				% server.beacon.port if server.beacon.listening() else "not answering")
	).with_aliases(["stat", "info"]).read_only())

	reg.add(ServerCommand.make("announce", "announce",
		"tell the directory about this server now, without waiting",
		Permissions.SERVER_SETTINGS_WRITE,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			if not server.directory.enabled:
				caller.fail("not announcing: %s" % server.directory.last_result)
				return
			server.directory.announce_now()
			caller.say("announcing to %s — 'status' shows what came back"
				% server.directory.base_url)
	).with_detail(
		"An announce goes out on a timer anyway. This is for the minute after "
		+ "changing a setting, when the question is whether it worked."))

	reg.add(ServerCommand.make("version", "version",
		"what build this server is, and what a client must match",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			caller.say(NetProtocol.build_id())
			caller.row("protocol", str(NetProtocol.VERSION))
			caller.row("content fingerprint", NetProtocol.content_hash())
			caller.say("")
			caller.say("A client whose fingerprint differs is refused. That is the "
				+ "check that stops a server left running across a game update "
				+ "from becoming a desync — see docs/SERVER.md.")
	).read_only())


static func _announcements(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("say", "say <message...>",
		"an announcement to everybody on the server",
		Permissions.CHAT_BROADCAST,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var text := " ".join(args)
			server.chat.announce(caller.label if caller.privileged
				else caller.account.name, text)
			caller.say("announced to %d players" % server.peers.size())
	).with_args(1))

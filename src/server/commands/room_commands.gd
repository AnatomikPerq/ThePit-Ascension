class_name RoomCommands
extends Object
## Rooms from the console: open, close, start, restart, and reconfigure.
##
## Two-word names (`room open`, `room close`) so that each carries its own right
## — closing anybody's room is a moderator's business, opening one is not. See
## CommandRegistry._split_command.

static func install(server: PitServer, reg: CommandRegistry) -> void:
	_listing(server, reg)
	_lifecycle(server, reg)
	_configuring(server, reg)


static func _listing(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("rooms", "rooms",
		"every room, and who is in it",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			if server.rooms.count() == 0:
				caller.say("no rooms are open")
				return
			for room_id in server.rooms.rooms:
				var room: Room = server.rooms.rooms[room_id]
				caller.row("#%d %s" % [room.id, room.name],
					"%s · %s · %d/%d%s%s" % [
						Room.mode_name(room.mode), Room.state_name(room.state),
						room.climbers().size(), room.max_players,
						" · %d watching" % room.spectators() if room.spectators() > 0 else "",
						" · locked" if room.locked() else ""], 28)
			caller.say("")
			caller.say("%d of %d rooms" % [server.rooms.count(),
				server.settings.get_int("rooms/max_rooms")])
	).with_aliases(["lobbies"]).read_only())

	reg.add(ServerCommand.make("room", "room <id>",
		"one room in detail",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var room := server.rooms.get_room(args[0].to_int())
			if room == null:
				caller.fail("no room #%s" % args[0])
				return
			_describe(server, caller, room)
	).with_args(1, 1).read_only())


static func _describe(server: PitServer, caller: CommandCaller, room: Room) -> void:
	caller.say("#%d %s" % [room.id, room.name])
	caller.row("mode", Room.mode_name(room.mode))
	caller.row("state", Room.state_name(room.state))
	caller.row("seats", "%d of %d taken" % [room.climbers().size(), room.max_players])
	caller.row("locked", "yes" if room.locked() else "no")
	caller.row("opened by", room.owner_id if room.owner_id != "" else "the server")
	caller.row("world node", room.world_name())
	if room.running():
		caller.row("seed", str(room.run_seed))
	for peer_id in room.members:
		var peer: ServerPeer = server.peers.get(peer_id)
		var pick: StringName = room.choices.get(peer_id, CharacterRoster.SPECTATOR)
		caller.row("  %s" % (peer.name_text() if peer != null else "?"),
			"watching" if pick == CharacterRoster.SPECTATOR else String(pick), 24)


static func _lifecycle(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("room open", "room open <name> [coop|race] [seats]",
		"open a room nobody is in yet",
		Permissions.ROOM_CREATE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var mode := Room.mode_from(args[1] if args.size() > 1
				else server.settings.get_text("rooms/default_mode"))
			var seats := args[2].to_int() if args.size() > 2 \
					else server.settings.get_int("rooms/default_max_players")
			var problem: Array = []
			var room := server.rooms.open(args[0], mode, "", seats, "", problem)
			if room == null:
				caller.fail(str(problem[0]) if not problem.is_empty()
					else "could not open it")
				return
			# A room opened from the console belongs to the server, so it is not
			# tidied away for being empty — which is the whole reason to open one
			# before anybody has arrived.
			room.persistent = true
			server.broadcast_rooms()
			caller.say("opened #%d '%s'" % [room.id, room.name])
	).with_args(1, 3))

	reg.add(ServerCommand.make("room close", "room close <id> [reason...]",
		"close a room and turn everyone in it out",
		Permissions.ROOM_CLOSE_ANY,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var reason := " ".join(args.slice(1)) if args.size() > 1 else "closed by staff"
			if not server.rooms.close(args[0].to_int(), reason):
				caller.fail("no room #%s" % args[0])
				return
			server.broadcast_rooms()
			caller.say("closed #%s" % args[0])
	).with_args(1))

	reg.add(ServerCommand.make("room start", "room start <id>",
		"start that room's climb now",
		Permissions.ROOM_START,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var problem := server.rooms.start(args[0].to_int(), 0)
			if problem != "":
				caller.fail(problem)
				return
			server.broadcast_rooms()
			caller.say("#%s is climbing" % args[0])
	).with_args(1, 1))

	reg.add(ServerCommand.make("room restart", "room restart <id>",
		"fresh pit, same people",
		Permissions.ROOM_START,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var problem := server.rooms.restart(args[0].to_int(), 0)
			if problem != "":
				caller.fail(problem)
				return
			server.broadcast_rooms()
			caller.say("#%s restarted" % args[0])
	).with_args(1, 1))


static func _configuring(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("room set",
		"room set <id> <name|mode|seats|password|persistent> <value>",
		"change one thing about a room",
		Permissions.ROOM_CONFIGURE_ANY,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_configure(server, caller, args)
	).with_args(3).with_detail(
		"name     what it is called\n"
		+ "mode     coop or race — only while it is in its lobby\n"
		+ "seats    how many may climb\n"
		+ "password a password, or \"\" to open it up\n"
		+ "persistent  true keeps it when it empties"))


static func _configure(server: PitServer, caller: CommandCaller,
		args: PackedStringArray) -> void:
	var room := server.rooms.get_room(args[0].to_int())
	if room == null:
		caller.fail("no room #%s" % args[0])
		return
	var field := args[1].to_lower()
	var value := " ".join(args.slice(2))
	var problem := _write_field(server, room, field, value)
	if problem != "":
		caller.fail(problem)
		return
	server.broadcast_rooms()
	caller.say("#%d %s is now %s" % [room.id, field,
		"(set)" if field == "password" else value])


static func _write_field(server: PitServer, room: Room, field: String,
		value: String) -> String:
	match field:
		"name":
			var clean := RoomManager.sanitise_name(value)
			if clean == "":
				return "a room needs a name"
			room.name = clean
		"mode":
			if room.state == Room.State.RUNNING:
				return "not while the run is going"
			room.mode = Room.mode_from(value)
		"seats":
			room.max_players = clampi(value.to_int(), 1,
				server.settings.get_int("rooms/max_players_ceiling"))
		"password":
			room.set_password(value)
		"persistent":
			room.persistent = value.to_lower() in ["true", "yes", "on", "1"]
		_:
			return "no such field: %s" % field
	return ""

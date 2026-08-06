class_name AccountCommands
extends Object
## Accounts, roles and rights — including `op`, which is the command an operator
## reaches for first on a new server.
##
## `op <name>` makes somebody an admin. It is an alias for `account role <name>
## admin` and not a separate mechanism, because a server where "op" and "roles"
## are two ideas is a server where they disagree.

static func install(server: PitServer, reg: CommandRegistry) -> void:
	_listing(server, reg)
	_making(server, reg)
	_rights(server, reg)


static func _listing(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("account list", "account list [filter]",
		"registered accounts, most recently seen first",
		Permissions.ACCOUNT_LIST,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var found := server.accounts.search(args[0] if not args.is_empty() else "")
			if found.is_empty():
				caller.say("no accounts match")
				return
			for account in found:
				caller.row(account.name, "%s · last seen %s%s" % [
					account.role,
					Time.get_datetime_string_from_unix_time(account.last_seen_at, true)
						if account.last_seen_at > 0 else "never",
					"  MUTED" if account.is_muted() else ""], 20)
			caller.say("")
			caller.say("%d of %d accounts" % [found.size(), server.accounts.count()])
	).with_args(0, 1).read_only())

	reg.add(ServerCommand.make("account info", "account info <name>",
		"one account in full",
		Permissions.ACCOUNT_LIST,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var account := server.accounts.find(args[0])
			if account == null:
				caller.fail("no account called '%s'" % args[0])
				return
			_describe(server, caller, account)
	).with_args(1, 1).read_only())

	reg.add(ServerCommand.make("staff", "staff",
		"everybody with a role above player",
		Permissions.ACCOUNT_LIST,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			var found := server.accounts.staff()
			if found.is_empty():
				caller.say("nobody has been given a role yet")
				return
			for account in found:
				caller.row(account.name, account.role, 20)
	).read_only())

	reg.add(ServerCommand.make("top", "top [count]",
		"the best climbs this server has seen",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var limit := args[0].to_int() if not args.is_empty() else 10
			var found := server.accounts.top_scores(clampi(limit, 1, 100))
			if found.is_empty():
				caller.say("nobody has finished a climb here yet")
				return
			for i in found.size():
				caller.row("%2d. %s" % [i + 1, found[i].name],
					"%d  ·  %d kills" % [found[i].best_score, found[i].kills], 22)
	).with_args(0, 1).read_only())


static func _describe(server: PitServer, caller: CommandCaller, account: Account) -> void:
	caller.say(account.name)
	caller.row("role", account.role)
	caller.row("registered", Time.get_datetime_string_from_unix_time(
		account.created_at, true))
	caller.row("last seen", Time.get_datetime_string_from_unix_time(
		account.last_seen_at, true) if account.last_seen_at > 0 else "never")
	caller.row("best score", str(account.best_score))
	caller.row("runs / kills", "%d / %d" % [account.runs, account.kills])
	caller.row("played for", "%d minutes" % int(account.play_seconds / 60.0))
	caller.row("warnings", str(account.warnings))
	caller.row("muted", "yes" if account.is_muted() else "no")
	if not account.grants.is_empty():
		caller.row("granted", ", ".join(account.grants))
	if not account.denials.is_empty():
		caller.row("denied", ", ".join(account.denials))
	if account.note != "":
		caller.row("note", account.note)
	if caller.may(Permissions.PLAYER_INSPECT) and account.last_address != "":
		caller.row("last address", account.last_address)
	var online := server.online_named(account.id)
	caller.row("online", "yes, room %d" % online.room_id if online != null else "no")


static func _making(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("account register", "account register <name> <password>",
		"create an account from here",
		Permissions.ACCOUNT_EDIT,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			if server.accounts.exists(args[0]):
				caller.fail("'%s' already exists" % args[0])
				return
			var minimum := server.settings.get_int("auth/min_password_length")
			if args[1].length() < minimum:
				caller.fail("passwords are at least %d characters" % minimum)
				return
			var first := server.accounts.is_empty() \
					and server.settings.get_bool("auth/first_account_is_owner")
			var account := Account.make(args[0], args[1],
				server.settings.get_int("auth/pbkdf2_iterations"))
			# The same rule the in-game path follows. Without it the boot message
			# that offers this command as the alternative would be telling a lie.
			if first:
				account.role = Permissions.ROLE_OWNER
			server.accounts.add(account)
			server.accounts.save()
			caller.say("registered '%s'%s" % [account.name,
				" — the first account here, so it is the owner" if first else ""])
	).with_args(2, 2).with_detail(
		"The out-of-band way in. Useful when registration from the game is off, "
		+ "and the one route that never sends a derived key over the network — "
		+ "see docs/SERVER.md on what registering in-game does cross."))

	reg.add(ServerCommand.make("account password", "account password <name> <new>",
		"set somebody's password, and kill their reconnect token",
		Permissions.ACCOUNT_EDIT,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var account := server.accounts.find(args[0])
			if account == null:
				caller.fail("no account called '%s'" % args[0])
				return
			if account.rank() >= caller.rank():
				caller.fail("%s outranks you (or matches you)" % account.name)
				return
			account.set_password(args[1], server.settings.get_int("auth/pbkdf2_iterations"))
			server.accounts.save()
			server.logger.info("mod", "%s reset the password of %s"
				% [caller.label, account.name])
			caller.say("done")
	).with_args(2, 2))

	reg.add(ServerCommand.make("account delete", "account delete <name>",
		"remove an account and everything it remembers",
		Permissions.ACCOUNT_DELETE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var account := server.accounts.find(args[0])
			if account == null:
				caller.fail("no account called '%s'" % args[0])
				return
			if account.rank() >= caller.rank():
				caller.fail("%s outranks you (or matches you)" % account.name)
				return
			var online := server.online_named(account.id)
			if online != null:
				server.kick(online.peer_id, "your account was removed")
			server.accounts.remove(args[0])
			server.accounts.save()
			server.logger.info("mod", "%s deleted the account %s"
				% [caller.label, account.name])
			caller.say("'%s' is gone" % account.name)
	).with_args(1, 1))


static func _rights(server: PitServer, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("account role", "account role <name> <role>",
		"player, moderator, admin or owner",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_set_role(server, caller, args[0], args[1].to_lower())
	).with_args(2, 2))

	reg.add(ServerCommand.make("op", "op <name>",
		"make somebody an admin",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_set_role(server, caller, args[0], Permissions.ROLE_ADMIN)
	).with_args(1, 1).with_detail(
		"An alias for `account role <name> admin`. The first account registered "
		+ "on a fresh server is made owner automatically "
		+ "(`auth/first_account_is_owner`), so this is usually for the second "
		+ "person you trust rather than the first."))

	reg.add(ServerCommand.make("deop", "deop <name>",
		"back to an ordinary player",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_set_role(server, caller, args[0], Permissions.ROLE_PLAYER)
	).with_args(1, 1))

	reg.add(ServerCommand.make("account grant", "account grant <name> <right>",
		"one right on top of their role",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_edit_rights(server, caller, args[0], args[1], true)
	).with_args(2, 2).with_detail(
		"Rights are named, not ranked, so somebody can be given `player.kick` "
		+ "and nothing else. `permissions` lists them all."))

	reg.add(ServerCommand.make("account revoke", "account revoke <name> <right>",
		"take a right away, even one their role carries",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_edit_rights(server, caller, args[0], args[1], false)
	).with_args(2, 2))

	reg.add(ServerCommand.make("account note", "account note <name> <text...>",
		"a staff-only note on an account",
		Permissions.PLAYER_INSPECT,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var account := server.accounts.find(args[0])
			if account == null:
				caller.fail("no account called '%s'" % args[0])
				return
			account.note = " ".join(args.slice(1))
			server.accounts.touch()
			caller.say("noted")
	).with_args(2))


static func _set_role(server: PitServer, caller: CommandCaller, name: String,
		role: String) -> void:
	if not Permissions.is_role(role):
		caller.fail("roles are: %s" % ", ".join(Permissions.ROLES))
		return
	var account := server.accounts.find(name)
	if account == null:
		caller.fail("no account called '%s' — they have to register first" % name)
		return
	# Both halves of the rank rule: you cannot demote somebody at your level, and
	# you cannot promote anybody to it either. Otherwise an admin makes a friend
	# an owner and the two of them outrank the person who appointed them.
	if account.rank() >= caller.rank() or Permissions.rank(role) >= caller.rank():
		caller.fail("that is at or above your own rank")
		return
	account.role = role
	server.accounts.save()
	server.logger.info("mod", "%s set %s to %s" % [caller.label, account.name, role])
	var online := server.online_named(account.id)
	if online != null:
		server.hub_notice(online.peer_id, "YOU ARE NOW %s" % role.to_upper())
	caller.say("%s is now %s" % [account.name, role])


static func _edit_rights(server: PitServer, caller: CommandCaller, name: String,
		right: String, granting: bool) -> void:
	var account := server.accounts.find(name)
	if account == null:
		caller.fail("no account called '%s'" % name)
		return
	if account.rank() >= caller.rank():
		caller.fail("%s outranks you (or matches you)" % account.name)
		return
	if not Permissions.catalogue().has(right) and right != Permissions.ALL:
		caller.fail("no such right: %s — 'permissions' lists them" % right)
		return
	if not caller.may(right):
		caller.fail("you cannot hand out a right you do not hold")
		return
	_move_right(account, right, granting)
	server.accounts.save()
	server.logger.info("mod", "%s %s %s for %s" % [caller.label,
		"granted" if granting else "revoked", right, account.name])
	caller.say("%s now %s %s" % [account.name,
		"has" if granting else "does not have", right])


static func _move_right(account: Account, right: String, granting: bool) -> void:
	var grants := Array(account.grants)
	var denials := Array(account.denials)
	grants.erase(right)
	denials.erase(right)
	if granting:
		grants.append(right)
	else:
		denials.append(right)
	account.grants = PackedStringArray(grants)
	account.denials = PackedStringArray(denials)

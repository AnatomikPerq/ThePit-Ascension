class_name DirectoryCommands
extends Object
## What the operator of the directory can type.
##
## Four families: what is listed, which servers are blocked, the verification
## keys, and the four commands every console in this project has (help, the
## settings editor, the log, stop) which come from CommonCommands so that they
## behave identically here and on a game server.
##
## The keys are the interesting half, because issuing one is the ONLY way a badge
## ever appears next to a server's name. `key issue` prints a secret exactly
## once — after that it is in keys.json on this machine and nowhere else the
## operator can conveniently read it, which is on purpose: it should be pasted
## into the host's server.cfg and then forgotten about.

static func install(dir: PitDirectory, reg: CommandRegistry) -> void:
	CommonCommands.install_help(reg)
	CommonCommands.install_settings(reg, dir.settings, dir.storage_dir,
		func() -> void:
			dir.store.save()
			dir.keys.save())
	CommonCommands.install_log(reg, dir.logger)
	CommonCommands.install_stop(reg, dir.shutdown)
	_status(dir, reg)
	_servers(dir, reg)
	_blocking(dir, reg)
	_keys(dir, reg)
	_key_lifecycle(dir, reg)


static func _status(dir: PitDirectory, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("status", "status",
		"what is listed, and how busy this has been",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			caller.say(dir.status_line())
			caller.row("build", NetProtocol.build_id())
			caller.row("listening", "http://%s:%d" % [
				dir.settings.get_text("listing/bind_address"),
				dir.settings.get_int("listing/port")])
			caller.row("announce to", dir.settings.get_text("listing/public_url"))
			caller.row("storage", dir.storage_dir)
			caller.row("verified only",
				"yes" if dir.settings.get_bool("listing/require_key") else "no")
			caller.row("stale after", "%ds" % dir.settings.get_int("listing/stale_seconds"))
	).with_aliases(["stat", "info"]).read_only())

	reg.add(ServerCommand.make("version", "version",
		"what build this directory is",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			caller.say(NetProtocol.build_id())
			caller.row("directory protocol", str(DirectoryProtocol.VERSION))
			caller.row("game protocol", str(NetProtocol.VERSION))
			caller.row("content fingerprint", NetProtocol.content_hash())
			caller.say("")
			caller.say("A directory does NOT have to match the servers it lists. It "
				+ "carries their fingerprints through to the browser, which is how a "
				+ "player is told a server is on another build before connecting.")
	).read_only())


static func _servers(dir: PitDirectory, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("servers", "servers [filter]",
		"every server currently listed",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_print_servers(dir, caller, args[0].to_lower() if not args.is_empty() else "")
	).with_aliases(["list"]).read_only())

	reg.add(ServerCommand.make("forget", "forget <address> [port]",
		"drop one server from the list until it announces again",
		Permissions.SERVER_SETTINGS_WRITE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var port := args[1].to_int() if args.size() > 1 else NetProtocol.DEFAULT_PORT
			if dir.store.remove(args[0], port):
				caller.say("forgotten: %s" % DirectoryEntry.key_for(args[0], port))
			else:
				caller.fail("nothing listed at %s" % DirectoryEntry.key_for(args[0], port))
	).with_args(1, 2))


static func _print_servers(dir: PitDirectory, caller: CommandCaller, needle: String) -> void:
	var now := int(Time.get_unix_time_from_system())
	var rows := dir.store.listing(now, dir.settings.get_int("listing/stale_seconds"))
	var shown := 0
	for row: Variant in rows:
		var entry: Dictionary = row
		var line := "%s:%d" % [entry.get("address", ""), int(entry.get("port", 0))]
		if needle != "" and not (line + str(entry.get("name", ""))).to_lower().contains(needle):
			continue
		shown += 1
		var badge := DirectoryProtocol.badge_label(str(entry.get("badge", "")))
		caller.row(line, "%s  %s  %d/%d  %ds ago" % [
			str(entry.get("name", "")), badge if badge != "" else "—",
			int(entry.get("players", 0)), int(entry.get("max_players", 0)),
			now - int(entry.get("last_seen", now))], 28)
	caller.say("")
	caller.say("%d listed%s · %d remembered in all" % [shown,
		"" if needle == "" else " matching '%s'" % needle, dir.store.count()])


static func _blocking(dir: PitDirectory, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("block", "block <address>",
		"never list anything announcing from that address",
		Permissions.SERVER_SETTINGS_WRITE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_set_blocked(dir, caller, args[0], true)
	).with_args(1, 1))

	reg.add(ServerCommand.make("unblock", "unblock <address>",
		"lift a block",
		Permissions.SERVER_SETTINGS_WRITE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_set_blocked(dir, caller, args[0], false)
	).with_args(1, 1))


static func _set_blocked(dir: PitDirectory, caller: CommandCaller,
		address: String, blocked: bool) -> void:
	var wanted := address.strip_edges().to_lower()
	var current := Array(dir.settings.get_list("listing/blocked"))
	if blocked == current.has(wanted):
		caller.fail("%s is already %s" % [wanted, "blocked" if blocked else "not blocked"])
		return
	if blocked:
		current.append(wanted)
	else:
		current.erase(wanted)
	dir.settings.set_from_text("listing/blocked", ",".join(PackedStringArray(current)))
	if blocked:
		dir.store.remove(wanted, NetProtocol.DEFAULT_PORT)
	caller.say("%s is now %s" % [wanted, "blocked" if blocked else "allowed"])


# ── Verification keys ───────────────────────────────────────────────────────
static func _keys(dir: PitDirectory, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("key issue", "key issue <badge> <label> [note...]",
		"make a verification key to hand to a host",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_issue(dir, caller, args)
	).with_args(2).with_detail(
		"badge is one of: " + ", ".join(DirectoryProtocol.BADGES) + ".\n"
		+ "label is for your own records — who this was given to.\n"
		+ "note is what a player reads when they hover the badge; leave it out "
		+ "for the badge's own wording.\n\n"
		+ "The secret is printed ONCE. Send the two lines it prints to the host; "
		+ "they go straight into their server.cfg. Nothing else has to happen: "
		+ "the badge appears on their next announce."))

	reg.add(ServerCommand.make("key list", "key list",
		"every key ever issued",
		Permissions.ACCOUNT_LIST,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			var all := dir.keys.all()
			if all.is_empty():
				caller.say("no keys issued yet")
				return
			for key in all:
				caller.row(key.id, key.describe(), 20)
			caller.say("")
			caller.say("%d key(s). 'key show <id>' for one." % all.size())
	).read_only())

	reg.add(ServerCommand.make("key show", "key show <id>",
		"one key, and which server is using it",
		Permissions.ACCOUNT_LIST,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_show(dir, caller, args[0])
	).with_args(1, 1).read_only())

	reg.add(ServerCommand.make("key secret", "key secret <id>",
		"print a key's secret again, for a host who lost it",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var key := dir.keys.find(args[0])
			if key == null:
				caller.fail("no such key: %s" % args[0])
				return
			caller.say("directory/verify_id = \"%s\"" % key.id)
			caller.say("directory/verify_key = \"%s\"" % key.secret)
	).with_args(1, 1).with_detail(
		"Deliberately a command of its own rather than part of 'key show': it "
		+ "is written into the audit log when it is used, and a secret should "
		+ "not appear on screen because somebody was listing keys."))


static func _issue(dir: PitDirectory, caller: CommandCaller, args: PackedStringArray) -> void:
	var badge := args[0].to_lower()
	if not DirectoryProtocol.is_badge(badge):
		caller.fail("badge must be one of: %s" % ", ".join(DirectoryProtocol.BADGES))
		return
	var key := VerifyKey.issue(badge, args[1], " ".join(args.slice(2)))
	dir.keys.add(key)
	dir.keys.save()
	caller.say("issued %s for %s" % [DirectoryProtocol.badge_label(badge), args[1]])
	caller.say("")
	caller.say("Send these two lines to the host. They go in the [directory]")
	caller.say("section of their server.cfg, with directory/announce = true:")
	caller.say("")
	caller.say("  verify_id = \"%s\"" % key.id)
	caller.say("  verify_key = \"%s\"" % key.secret)
	caller.say("")
	caller.say("The secret is not printed again by 'key list' or 'key show'.")
	caller.say("Hover text: %s" % key.hover_text())


static func _show(dir: PitDirectory, caller: CommandCaller, id: String) -> void:
	var key := dir.keys.find(id)
	if key == null:
		caller.fail("no such key: %s" % id)
		return
	caller.row("badge", DirectoryProtocol.badge_label(key.badge))
	caller.row("issued to", key.label)
	caller.row("hover text", key.hover_text())
	caller.row("bound to", key.bind_address if key.bind_address != "" else "any address")
	caller.row("used", "%d time(s)" % key.uses)
	caller.row("last used", "never" if key.last_used == 0
		else Time.get_datetime_string_from_unix_time(key.last_used, true))
	if key.revoked:
		caller.row("REVOKED", key.revoked_reason)
	for entry_key in dir.store.entries:
		var entry: DirectoryEntry = dir.store.entries[entry_key]
		if entry.verify_id == key.id:
			caller.row("in use by", "%s (%s)" % [entry.name, entry.key()])


static func _key_lifecycle(dir: PitDirectory, reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("key revoke", "key revoke <id> [reason...]",
		"withdraw a badge, now",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			if not dir.keys.revoke(args[0], " ".join(args.slice(1))):
				caller.fail("no such key, or it is already revoked: %s" % args[0])
				return
			var withdrawn := dir.store.refresh_badges(dir.keys)
			dir.keys.save()
			caller.say("revoked %s — %d listed server(s) lost the badge"
				% [args[0], withdrawn])
	).with_args(1).with_detail(
		"The badge is taken away immediately, from servers already listed as "
		+ "well as from future announces. Revoking rather than deleting keeps "
		+ "the record of what was issued and to whom."))

	reg.add(ServerCommand.make("key delete", "key delete <id>",
		"remove a key from the file entirely",
		Permissions.ACCOUNT_DELETE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			if not dir.keys.forget(args[0]):
				caller.fail("no such key: %s" % args[0])
				return
			dir.store.refresh_badges(dir.keys)
			dir.keys.save()
			caller.say("deleted %s" % args[0])
	).with_args(1, 1))

	reg.add(ServerCommand.make("key bind", "key bind <id> <address|->",
		"tie a key to one address, or untie it with -",
		Permissions.ACCOUNT_ROLE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var address := "" if args[1] == "-" else args[1]
			if not dir.keys.bind(args[0], address):
				caller.fail("no such key: %s" % args[0])
				return
			dir.keys.save()
			caller.say("%s now works %s" % [args[0],
				"for any address" if address == "" else "only for " + address])
	).with_args(2, 2).with_detail(
		"A bound key is refused when it announces a different address, so a "
		+ "leaked one cannot move somebody else's badge onto another machine. "
		+ "Bind it to exactly what the host puts in server/public_address."))

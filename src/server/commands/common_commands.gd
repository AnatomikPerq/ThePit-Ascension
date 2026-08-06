class_name CommonCommands
extends Object
## The commands both console programs have: help, the settings editor, the log,
## and stop.
##
## They are here rather than in CoreCommands because there are now two consoles —
## the dedicated server's and the directory's — and `set network/port 24570`
## should behave identically in both. Written twice they would not: one of them
## would grow the "(restart)" notice, or the validation, or the write-back, and
## the other would not, and nobody would notice until an operator did.
##
## Everything below closes over values rather than over a server, which is what
## lets the same command object serve two programs that have almost nothing else
## in common. See CommandRegistry for why the permission check is not in here.

static func install_help(reg: CommandRegistry) -> void:
	reg.add(ServerCommand.make("help", "help [command]",
		"what you can do here",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			caller.say(reg.help_text(caller,
				" ".join(args) if not args.is_empty() else ""))
	).with_aliases(["?", "commands"]).read_only())

	reg.add(ServerCommand.make("permissions", "permissions",
		"every right there is, and what your role carries",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			caller.say("Rights:")
			for right in Permissions.catalogue():
				caller.row(right, "yes" if caller.may(right) else "—", 30)
			caller.say("")
			caller.say("Roles, weakest first: %s" % ", ".join(Permissions.ROLES))
	).read_only())


## `save_extra` is whatever else that program keeps on disk — accounts and bans
## on a server, the server table and the keys on a directory. Settings are saved
## here either way, so a program cannot forget them.
static func install_settings(reg: CommandRegistry, settings: ServerSettings,
		storage_dir: String, save_extra: Callable) -> void:
	reg.add(ServerCommand.make("get", "get <key>",
		"one setting's value and what it does",
		Permissions.SERVER_SETTINGS_READ,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_describe(settings, caller, args[0])
	).with_args(1, 1).read_only())

	reg.add(ServerCommand.make("set", "set <key> <value>",
		"change a setting, now and in server.cfg",
		Permissions.SERVER_SETTINGS_WRITE,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_apply(settings, caller, args)
	).with_args(2).with_detail(
		"The value is validated against the setting's own type and range, and "
		+ "written back to server.cfg immediately, so a change survives a "
		+ "restart. Settings marked (restart) are read only at startup — the "
		+ "new value is saved but does not take effect until then, and this "
		+ "says so rather than pretending."))

	reg.add(ServerCommand.make("config", "config [filter]",
		"list settings, optionally filtered",
		Permissions.SERVER_SETTINGS_READ,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			_list(settings, caller, args[0] if not args.is_empty() else "")
	).read_only())

	reg.add(ServerCommand.make("save", "save",
		"flush everything this program keeps to disk now",
		Permissions.SERVER_SETTINGS_WRITE,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			if save_extra.is_valid():
				save_extra.call()
			settings.save_to()
			caller.say("written to %s" % storage_dir)
	))


static func _describe(settings: ServerSettings, caller: CommandCaller, key: String) -> void:
	if not settings.has(key):
		caller.fail("no such setting: %s" % key)
		return
	var def: SettingDef = settings.defs[key]
	caller.say("%s = %s" % [key, def.display(settings.get_value(key))])
	caller.say(def.description)
	if not def.choices.is_empty():
		caller.say("one of: %s" % ", ".join(def.choices))
	if def.requires_restart:
		caller.say("(only read at startup)")


static func _apply(settings: ServerSettings, caller: CommandCaller,
		args: PackedStringArray) -> void:
	var key := args[0]
	var value := " ".join(args.slice(1))
	if not settings.has(key):
		caller.fail("no such setting: %s — try 'config %s'" % [key, key.get_slice("/", 0)])
		return
	var problem := settings.set_from_text(key, value)
	if problem != "":
		caller.fail(problem)
		return
	var def: SettingDef = settings.defs[key]
	caller.say("%s = %s" % [key, def.display(settings.get_value(key))])
	if def.requires_restart:
		caller.say("saved, but this one is only read at startup — restart to apply it")


static func _list(settings: ServerSettings, caller: CommandCaller, needle: String) -> void:
	var keys := settings.search(needle)
	if keys.is_empty():
		caller.fail("nothing matches '%s'" % needle)
		return
	for key in keys:
		var def: SettingDef = settings.defs[key]
		caller.row(key, "%s%s" % [
			def.display(settings.get_value(key)),
			"  (restart)" if def.requires_restart else ""], 40)
	caller.say("")
	caller.say("%d of %d settings. 'get <key>' explains one."
		% [keys.size(), settings.defs.size()])


static func install_log(reg: CommandRegistry, logger: ServerLog) -> void:
	reg.add(ServerCommand.make("log", "log [lines] [level]",
		"the last lines this program wrote",
		Permissions.SERVER_LOG,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var count := args[0].to_int() if not args.is_empty() and args[0].is_valid_int() \
					else 30
			var level := ServerLog.level_from(args[1]) if args.size() > 1 \
					else ServerLog.Level.TRACE
			for entry in logger.tail(clampi(count, 1, ServerLog.RING_SIZE), level):
				caller.say(ServerLog.format(entry))
	).with_args(0, 2).read_only())


## `stop` is one line of difference between the two programs — what "shut down
## cleanly" means — so it takes the shutdown itself.
static func install_stop(reg: CommandRegistry, shutdown: Callable) -> void:
	reg.add(ServerCommand.make("stop", "stop [reason...]",
		"shut down cleanly",
		Permissions.SERVER_STOP,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			var reason := " ".join(args) if not args.is_empty() else "asked to"
			caller.say("stopping: %s" % reason)
			shutdown.call(reason)
	).with_aliases(["shutdown", "quit", "exit"]).with_detail(
		"Everything in progress is told why, everything kept is written, and "
		+ "only then does the process exit."))

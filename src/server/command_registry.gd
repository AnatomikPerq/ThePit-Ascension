class_name CommandRegistry
extends RefCounted
## Every command the server understands, and the one place they are dispatched.
##
## The console, the remote console and the admin panel inside the game all call
## `execute()`. They do not each parse, each check permissions, or each decide
## what "unknown command" means — that is the whole reason this exists, and it is
## why an administration feature added once appears in all three.
##
## The order of checks is deliberate: exists, then permitted, then well-formed.
## A player without the right to ban is told they may not, not that they typed it
## wrongly — telling somebody the correct syntax for a thing they cannot do is
## how a permission system leaks what it is protecting.

signal executed(caller_label: String, line: String, ok: bool)

var commands: Dictionary[String, ServerCommand] = {}
## alias -> real name. Kept apart so `help` lists each command once.
var _aliases: Dictionary[String, String] = {}


func add(command: ServerCommand) -> void:
	commands[command.name] = command
	for alias in command.aliases:
		_aliases[alias] = command.name


func resolve(name: String) -> ServerCommand:
	var key := name.to_lower()
	if commands.has(key):
		return commands[key]
	if _aliases.has(key):
		return commands[_aliases[key]]
	return null


## Split a line into the command and its arguments.
##
## Two-word commands are tried first, so `room close 3` finds `room close` and
## not `room`. That is what lets `room close` need a different right from `room
## start` while still reading as one family in `help` — a single `room` command
## dispatching on its first argument would have to do its own permission checks,
## which is exactly the thing this class exists to stop happening in thirty
## places.
func _split_command(parts: PackedStringArray) -> Array:
	if parts.size() >= 2:
		var pair := "%s %s" % [parts[0].to_lower(), parts[1].to_lower()]
		var found := resolve(pair)
		if found != null:
			return [found, pair, parts.slice(2)]
	return [resolve(parts[0].to_lower()), parts[0].to_lower(), parts.slice(1)]


## Run a whole line. Returns the caller, which now holds the output and whether
## it failed — every front-end wants both and neither wants two return values.
func execute(caller: CommandCaller, line: String) -> CommandCaller:
	var parts := ServerConsole.split(line.strip_edges())
	if parts.is_empty():
		return caller
	var resolved := _split_command(parts)
	var command: ServerCommand = resolved[0]
	var name: String = resolved[1]
	var args: PackedStringArray = resolved[2]

	if command == null:
		caller.fail("unknown command: %s — try 'help'%s" % [name, _suggestion(name)])
	elif not caller.may(command.permission):
		caller.fail("you may not do that (needs %s)" % command.permission)
	elif not command.accepts(args.size()):
		caller.fail("usage: %s" % command.usage)
	else:
		command.handler.call(caller, args)

	executed.emit(caller.label, line, not caller.failed)
	return caller


## "did you mean" for a mistyped command, by shared prefix and by containment.
## Cheap, and it is the difference between an operator finding `player list` and
## an operator giving up on a server with sixty commands.
func _suggestion(name: String) -> String:
	var near := PackedStringArray()
	for key in commands:
		if key.begins_with(name.substr(0, 3)) or key.contains(name):
			near.append(key)
	if near.is_empty():
		return ""
	return ". did you mean: %s" % ", ".join(near.slice(0, 4))


## Commands this caller is allowed to run, in name order. `help` and the admin
## panel both show only what the asker can actually use.
func available_to(caller: CommandCaller) -> Array[ServerCommand]:
	var out: Array[ServerCommand] = []
	for key in commands:
		if caller.may(commands[key].permission):
			out.append(commands[key])
	out.sort_custom(func(a: ServerCommand, b: ServerCommand) -> bool: return a.name < b.name)
	return out


## The `help` output, generated. Nothing here is a maintained list, so a command
## added without documentation still documents itself.
func help_text(caller: CommandCaller, topic: String = "") -> String:
	if topic != "":
		return _help_for(caller, topic)
	var lines := PackedStringArray(["Commands you may run:"])
	var group := ""
	for command in available_to(caller):
		var head := command.name.get_slice(" ", 0)
		if head != group:
			group = head
			lines.append("")
		lines.append("  %s %s" % [command.usage.rpad(38), command.summary])
	lines.append("")
	lines.append("'help <command>' for detail. Arguments with spaces go in \"quotes\".")
	return "\n".join(lines)


func _help_for(caller: CommandCaller, topic: String) -> String:
	var command := resolve(topic)
	if command == null:
		# `help room close` as well as `help "room close"`.
		command = resolve(topic.replace("  ", " "))
	if command == null:
		return "no such command: %s" % topic
	if not caller.may(command.permission):
		return "you may not do that (needs %s)" % command.permission
	var lines := PackedStringArray([
		command.usage,
		"",
		command.detail if command.detail != "" else command.summary,
		"",
		"needs: %s" % command.permission,
	])
	if not command.aliases.is_empty():
		lines.append("also: %s" % ", ".join(command.aliases))
	return "\n".join(lines)

class_name ServerCommand
extends RefCounted
## One thing the server can be told to do.
##
## The declaration carries everything the three front-ends need: what it is
## called, what it takes, what right it needs, and one line saying what it does.
## `help` is generated from these, the admin panel's command list is generated
## from these, and the permission check happens in the registry rather than in
## the handler — so a command cannot be added with the check forgotten.

var name: String = ""
var aliases: PackedStringArray = PackedStringArray()
## Argument spelling as a human reads it: `ban <player> [minutes] [reason...]`.
## Printed by `help` and on a wrong-argument error, so it is the documentation.
var usage: String = ""
var summary: String = ""
## Longer text for `help <command>`. Empty falls back to the summary.
var detail: String = ""
var permission: String = Permissions.SERVER_STATUS
var min_args: int = 0
## -1 for "as many as you like" — the commands that take a message or a reason.
var max_args: int = -1
## `func(caller: CommandCaller, args: PackedStringArray) -> void`
var handler: Callable
## Commands that change something, as opposed to reporting it. Logged at INFO
## with who ran them; the read-only ones would drown the log.
var mutating: bool = true


static func make(command_name: String, command_usage: String, text: String,
		right: String, callable: Callable) -> ServerCommand:
	var command := ServerCommand.new()
	command.name = command_name
	command.usage = command_usage
	command.summary = text
	command.permission = right
	command.handler = callable
	return command


func with_aliases(names: Array[String]) -> ServerCommand:
	aliases = PackedStringArray(names)
	return self


func with_args(low: int, high: int = -1) -> ServerCommand:
	min_args = low
	max_args = high
	return self


func with_detail(text: String) -> ServerCommand:
	detail = text
	return self


## Marks a command as reporting only. Keeps it out of the audit log and lets the
## admin panel offer it without a confirmation step.
func read_only() -> ServerCommand:
	mutating = false
	return self


func accepts(count: int) -> bool:
	if count < min_args:
		return false
	return max_args < 0 or count <= max_args

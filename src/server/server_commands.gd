class_name ServerCommands
extends Object
## Installs every built-in command.
##
## Four families, four files, one registry. The split is by subject rather than
## by who may run them, because a permission is a property of each command and
## grouping by rank would put `room close` (staff) next to `ban` (staff) and away
## from `room open` (anybody) — which is not how anybody looks for a command.

static func install(server: PitServer) -> void:
	var reg := server.commands
	CoreCommands.install(server, reg)
	ModCommands.install(server, reg)
	RoomCommands.install(server, reg)
	AccountCommands.install(server, reg)
	server.logger.debug("cmd", "%d commands installed" % reg.commands.size())

class_name CommandCaller
extends RefCounted
## Whoever is running a command, and where the answer goes.
##
## There are three of them and the commands cannot tell which: the operator at
## the keyboard, a remote console over TCP, and a player with the admin panel
## open inside the game. Every command is written against this and therefore
## works from all three the day it is added — which is the point, because an
## administration feature that exists on the console and not in the game is one
## the owner asked for and did not get.
##
## The console and the remote console hold every right. That is not laxity: they
## are already the machine the server runs on and the password in its config, so
## a permission check there would be checking the wrong thing. Everything that
## arrives over the game socket carries an Account, and every right it has is one
## somebody granted it.

## Shown in the audit line every command writes. "console", "rcon 10.0.0.4",
## "player Cyn#7".
var label: String = "console"
## The account behind an in-game caller. Null for the console and for rcon.
var account: Account = null
## The peer this came from over the game socket, 0 otherwise. Moderation uses it
## to refuse acting on yourself.
var peer_id: int = 0
## True for the local keyboard and the remote console.
var privileged: bool = false

## What the command wrote. Collected rather than printed, so that the same
## handler can have its output printed to stdout, written back down a TCP socket,
## or sent to a client as one message.
var lines: PackedStringArray = PackedStringArray()
var failed: bool = false


static func for_console() -> CommandCaller:
	var caller := CommandCaller.new()
	caller.label = "console"
	caller.privileged = true
	return caller


static func for_rcon(address: String) -> CommandCaller:
	var caller := CommandCaller.new()
	caller.label = "rcon %s" % address
	caller.privileged = true
	return caller


static func for_player(player_account: Account, from_peer: int) -> CommandCaller:
	var caller := CommandCaller.new()
	caller.label = "player %s" % player_account.name
	caller.account = player_account
	caller.peer_id = from_peer
	return caller


func may(right: String) -> bool:
	if privileged:
		return true
	return account != null and account.may(right)


## The rank a caller acts with. Moderation refuses to touch anybody at or above
## it, and the console outranks everyone — an operator locked out of their own
## server by an admin they promoted would have no way back in.
func rank() -> int:
	if privileged:
		return Permissions.ROLES.size()
	return account.rank() if account != null else 0


func say(text: String) -> void:
	for line in text.split("\n"):
		lines.append(line)


## Print a table without every command inventing its own column widths.
func row(left: String, right: String, width: int = 26) -> void:
	lines.append("  %s %s" % [left.rpad(width), right])


## End the command with a reason. `failed` is what the remote console reports as
## a non-zero result and what the admin panel colours red.
func fail(reason: String) -> void:
	failed = true
	say(reason)


func output() -> String:
	return "\n".join(lines)
